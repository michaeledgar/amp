require 'fileutils'

module Amp
  module Repositories
    
    ##
    # A Local Repository is a repository that works on local repo's, such
    # as your working directory. This makes it pretty damn important, and also
    # pretty damn complicated. Have fun!
    class LocalRepository < Repository
      include Amp::RevlogSupport::Node
      include Amp::Repositories::BranchManager
      include Amp::Repositories::TagManager
      include Amp::Repositories::Updatable
      include Amp::Repositories::Verification
      
      # The config is an {AmpConfig} for this repo (and uses .hg/hgrc)
      attr_accessor :config
      
      attr_reader :root
      attr_reader :root_pathname # save some computation here
      attr_reader :hg
      attr_reader :hg_opener
      attr_reader :branch_manager
      attr_reader :store_opener
      attr_reader :store
      
      ##
      # Initializes a new directory to the given path, and with the current
      # configuration.
      # 
      # @param [String] path a path to the Repository.
      # @param [Boolean] create Should we create a new one? Usually for
      #   the "amp init" command.
      # @param [Amp::AmpConfig] config the configuration loaded from the user's
      #   system. Will have some settings overwritten by the repo's hgrc.
      def initialize(path="", create=false, config=nil)
        @capabilities = {}
        @root        = path[-1, 1] == '/' ? path[0..-2] : path # no ending slashes
        @root        = File.expand_path @root
        @hg          = File.join @root, ".hg"
        @file_opener = Amp::Opener.new @root
        @file_opener.default = :open_file     # these two are the same, pretty much
        @hg_opener   = Amp::Opener.new @root
        @hg_opener.default   = :open_hg     # just with different defaults
        @filters     = {}
        @changelog   = nil
        @manifest    = nil
        @dirstate    = nil
        requirements = []
      
        # make a repo if necessary
        unless File.directory? @hg
          if create
          then requirements = init config
          else raise RepoError.new("Repository #{path} not found")
          end
        end
        
        # no point in reading what we _just_ wrote...
        unless create
          # read requires
          # save it if something's up
          @hg_opener.open("requires", 'r') {|f| f.each {|r| requirements << r.strip } } rescue nil
        end
        
        @store = Stores.pick requirements, @hg, Amp::Opener
        @config = Amp::AmpConfig.new :parent_config => config
        @config.read_file File.join(@hg,"hgrc")
      end
      
      def local?; true; end
      
      def relative_join(file, cur_dir=FileUtils.pwd)
        @root_pathname ||= Pathname.new(@root)
        Pathname.new(File.expand_path(File.join(cur_dir, file))).relative_path_from(@root_pathname).to_s
      end
      
      
      def inspect; "#<LocalRepository @root=#{@root.inspect}>"; end
      
      ##
      # Creates this repository's folders and structure.
      # 
      # @param [AmpConfig] config the configuration for this user so
      #   we know what neato features to use (like filename cache) 
      # @return [Array<String>] the requirements that we found are returned,
      #   so further configuration can go down.
      def init(config=@config)
        # make the directory if it's not there
        FileUtils.makedirs @hg
      
        requirements = ["revlogv1"]
        
        # add some requirements
        if config["format"]["usestore", Boolean] || true
          FileUtils.mkdir "#{@hg}/store"
          requirements << "store"
          requirements << "fncache" if config["format"]["usefncache", Boolean, true]
      
          # add the changelog
          make_changelog
        end
        
      
        # write the requires file
        write_requires requirements
      end
      
      ##
      # Has the repository been changed since the last commit?
      # Returns true if there are NO outstanding changes or uncommitted merges.
      # 
      # @return [Boolean] is the repo pristine
      def pristine?        
        dirstate.parents.last == RevlogSupport::Node::NULL_ID &&
        status(:only => [:modified, :added, :removed, :deleted]).all? {|_, v| v.empty? }
      end
      
      ##
      # @see pristine?
      def changed?; !pristine?; end
      
      ##
      # Effectively FileUtils.pwd
      # 
      # @return [String] the current location
      def cwd
        dirstate.cwd
      end
      alias_method :pwd, :cwd
      
      ##
      # Returns the relative path from +src+ to +dest+.
      # 
      # @param [String] src This is a directory! If this is relative,
      #                     it is assumed to be relative to the root.
      # @param [String] dest This MUST be within root! It also is a file.
      # @return [String] the relative path
      def path_to(src, dest)
        dirstate.path_to src, dest
      end
      
      ##
      # Gets the changeset at the given revision.
      # 
      # @param [String, Integer] rev the revision index (Integer) or
      #   node_id (String) that we want to access. if nil, returns
      #   the working directory. if the string is 'tip', it returns the
      #   latest head. Can be either a string or an integer; 
      #   this shit is smart.
      # @return [Changeset] the changeset at the given revision index or node
      #   id. Could be working directory.
      def [](rev)
        if rev.nil?
          return WorkingDirectoryChangeset.new(self)
        end
        rev = rev.to_i if rev.to_i.to_s == rev
        return Changeset.new(self, rev)
      end
      
      ##
      # Iterates over each changeset in the repository, from oldest to newest.
      # 
      # @yield each changeset in the repository is yielded to the caller, in order
      #   from oldest to newest. (Actually, lowest revision # to highest revision #)
      def each(&block)
        0.upto(size - 1) { |i| yield self[i]}
      end
      
      ##
      # Creates a lock at the given path. At first it tries to just make it straight away.
      # If this fails, we then sleep for up to a given amount of time (defaults to 10 minutes!)
      # and continually try to acquire the lock.
      #
      # @raise [LockHeld] if the lock cannot be acquired, this exception is raised
      # @param [String] lockname the name of the lock to create
      # @param [Boolean] wait should we wait for the lock to be released?
      # @param [Proc, #call] release_proc a proc to run when the lock is released
      # @param [Proc, #call] acquire_proc a proc to run when we get the lock
      # @param [String] desc the description of the lock to show if someone stomps on it
      # @return [Lock] a lock at the given location.
      def make_lock(lockname, wait, release_proc, acquire_proc, desc)
        begin
          lock = Lock.new(lockname, :timeout => 0, :release_fxn => release_proc, :desc => desc)
        rescue LockHeld => err
          raise unless wait
          UI.warn("waiting for lock on #{desc} held by #{err.locker}")
          lock = Lock.new(lockname, :timeout => @config["ui","timeout","600"].to_i, 
                                    :release_proc => release_proc, :desc => desc)
        end
        acquire_proc.call if acquire_proc  
        return lock
      end
      
      ##
      # Locks the repository's .hg/store directory. Returns the lock, or if a block is given,
      # runs the block with the lock, and clears the lock afterward.
      #
      # @yield When a block is given, that block is executed under locked
      #  conditions. That code can be guaranteed it is the only code running on the
      #  store in a destructive manner.
      # @param [Boolean] wait (true) wait for the lock to expire?
      # @return [Lock] the lock on the .hg/store directory
      def lock_store(wait = true)
        return @lock_ref if @lock_ref && @lock_ref.weakref_alive?
        
        lock = make_lock(store_join("lock"), wait, nil, nil, "repository #{root}")
        @lock_ref = WeakRef.new(lock)
        if block_given?
          begin
            yield
          ensure
            @lock_ref = nil
            lock.release
          end
        else
          return lock
        end
      end
      
      ##
      # Locks the repository's .hg/store directory. Returns the lock, or if a block is given,
      # runs the block with the lock, and clears the lock afterward.
      #
      # @yield When a block is given, that block is executed under locked
      #  conditions. That code can be guaranteed it is the only code running on the
      #  working directory in a destructive manner.
      # @param [Boolean] wait (true) wait for the lock to expire?
      # @return [Lock] the lock on the .hg/store directory
      def lock_working(wait = true)
        return @working_lock_ref if @working_lock_ref && @working_lock_ref.weakref_alive?
        
        lock = make_lock(join("wlock"), wait, nil, nil, "working directory of #{root}")
        @working_lock_ref = WeakRef.new(lock)
        if block_given?
          begin
            yield
          ensure
            @working_lock_ref = nil
            lock.release
          end
        else
          return lock
        end
      end
      
      ##
      # Takes a block, and runs that block with both the store and the working directory locked.
      #
      # @param [Boolean] wait (true) should we wait for locks, or jsut give up early?
      def lock_working_and_store(wait=true)
        lock_store(wait) do
          lock_working(wait) do
            yield
          end
        end
      end
      
      ##
      # Gets the file-log for the given path, so we can look at an individual
      # file's history, for example.
      # 
      # @param [String] f the path to the file
      # @return [FileLog] a filelog (a type of revision log) for the given file
      def file(f)
        f = f[1..-1] if f[0, 1] == "/"
        FileLog.new @store.opener, f
      end
      
      ##
      # Returns the parent changesets of the specified changeset. Defaults to the
      # working directory, if +change_id+ is unspecified.
      #
      # @param [Integer, String] change_id the ID (or index) of the requested changeset
      # @return [Array<Changeset>] the parent changesets of the requested changeset
      def parents(change_id = nil)
        self[change_id].parents
      end
      
      ##
      # Gets a versioned file for the given path, so we can look at the individual
      # file's history with the file object itself.
      #
      # @param [String] path the path to the file
      # @param [Hash] opts the options for creating the versioned file
      # @option [String] opts change_id (nil) The ID of the changeset in question
      # @option [String, Integer] opts file_id (nil) the revision # or node ID of
      #   into the file_log
      def versioned_file(path, opts={})
        VersionedFile.new(self, path, opts)
      end
      
      ##
      # Gets a versioned file, but using the working directory, so we are looking
      # past the last commit. Important because it uses a different class. Duh.
      #
      # @param [String] path the path to the file
      # @param [Hash] opts the options for creating the versioned file
      # @option [String] opts change_id (nil) The ID of the changeset in question
      # @option [String, Integer] opts file_id (nil) the revision # or node ID of
      #   into the file_log
      def working_file(path, opts={})
        VersionedWorkingFile.new(self, path, opts)
      end
      
      ##
      # Reads from a file, but in the working directory.
      # Uses encoding if we are set up to do so.
      # 
      # @param [String] filename the file to read from the working directory
      # @return [String] the data read from the file, encoded if we are set
      #   up to do so.
      def working_read(filename)
        data = @file_opener.open(filename, "r") {|f| f.read }
        data = @filters["encode"].call(filename, data) if @filters["encode"]
        data
      end
      
      ##
      # Writes to a file, but in the working directory. Uses encoding if we are
      # set up to do so. Also handles symlinks and executables. Ugh.
      #
      # @param [String] path the path to the file to write to
      # @param [String] data the data to write
      # @param [String] flags the flags to set
      def working_write(path, data, flags)
        @file_opener.open(path, "w") do |file|
          file.write(data)
        end
        if flags && flags.include?('x')
          File.amp_set_executable(working_join(path), true)
        end
      end
      
      ##
      # Returns the changelog for this repository. This changelog basically
      # is the history of all commits.
      # 
      # @return [ChangeLog] the commit history object for the entire repo.
      def changelog
        return @changelog if @changelog
        
        @changelog = ChangeLog.new @store.opener
        
        if path = ENV['HG_PENDING']
          if path =~ /^#{root}/
            @changelog.read_pending('00changelog.i.a')
          end
        end
        
        @changelog
      end
      
      ##
      # Returns the merge state for this repository. The merge state keeps track
      # of what files need to be merged for an update to be successfully completed.
      # 
      # @return [MergeState] the repository's merge state.
      def merge_state
        @merge_state ||= Amp::Merges::MergeState.new(self)
      end
      
      ##
      # Returns the manifest for this repository. The manifest keeps track
      # of what files exist at what times, and if they have certain flags
      # (such as executable, or is it a symlink).
      # 
      # @return [Manifest] the manifest for the repository
      def manifest
        return @manifest if @manifest
        
        changelog #load the changelog
        @manifest = Manifest.new @store.opener
      end
      
      ##
      # Returns the dirstate for this repository. The dirstate keeps track
      # of files status, such as removed, added, merged, and so on. It also
      # keeps track of the working directory.
      # 
      # @return [DirState] the dirstate for this local repository.
      def dirstate
        return @dirstate if @dirstate
        
        opener = Amp::Opener.new @root
        opener.default = :open_hg
        
        @dirstate = DirState.new(@root, @config, opener)
        @dirstate.read!
      end
      
      ##
      # Returns the URL of this repository. Uses the "file:" scheme as such.
      #
      # @return [String] the URL pointing to this repo
      def url; "file:#{@root}"; end
      
      ##
      # Opens a file using our opener. Can only access files in .hg/
      def open(*args, &block)
        @hg_opener.open(*args, &block)
      end
      
      ##
      # Joins the path to the repo's root (not .hg, the working dir root)
      # 
      # @param path the path we're joining
      # @return [String] the path joined to the working directory's root
      def working_join(path)
        File.join(@root, path)
      end

      ##
      # Joins the path from this repo's path (.hg), to the file provided.
      # 
      # @param file the file we need the path for
      # @return [String] the repo's root, joined with the file's path
      def join(file)
        File.join(@hg, file)
      end
      
      ##
      # Joins the path, with a bunch of other args, to the store's directory.
      # Used for opening {FileLog}s and whatnot.
      # 
      # @param file the path to the file
      # @return [String] the path to the file from the store. 
      def store_join(file)
        @store.join file
      end
      
      ##
      # Looks up an identifier for a revision in the commit history. This
      # key could be an integer (specifying a revision number), "." for
      # the latest revision, "null" for the null revision, "tip" for
      # the tip of the repository, a node_id (in hex or binary form) for
      # a revision in the changelog. Yeah. It's a flexible method.
      # 
      # @param key the key to lookup in the history of the repo
      # @return [String] a node_id into the changelog for the requested revision
      def lookup(key)
        key = key.to_i if key.to_i.to_s == key.to_s # casting for things like "10"
        case key
        when Fixnum, Bignum, Integer
          changelog.node_id_for_index(key)
        when "." 
          dirstate.parents().first
        when "null", nil
          NULL_ID
        when "tip"
          changelog.tip
        else
          
          n = changelog.id_match(key)
          return n if n
          
          return tags[key] if tags[key]
          return branch_tags[key] if branch_tags[key]
          
          n = changelog.partial_id_match(key)
          return n if n
          
          # bail
          raise RepoError.new("unknown revision #{key}")
        end
      end
      
      ##
      # Finds the nodes between two nodes - this algorithm is ported from the
      # python for mercurial (localrepo.py:1247, for 1.2.1 source). Since this
      # is used by servers, it implements their algorithm... which seems to
      # intentionally not return every node between +top+ and +bottom+.
      # Each one is twice as far from +top+ as the previous.
      #
      # @param [Array<String, String>] An array of node-id pairs, which are arrays
      #   of [+top+, +bottom+], which are:
      #   top [String] the "top" - or most recent - revision's node ID
      #   bottom [String] the "bottom" - or oldest - revision's node ID
      #
      # return [Array<String>] a list of node IDs that are between +top+ and +bottom+
      def between(pairs)
        pairs.map do |top, bottom|
          node, list, counter = top, [], 0
          add_me = 1
          while node != bottom && node != NULL_ID
            if counter == add_me
              list << node
              add_me *= 2
            end
            parent = changelog.parents_for_node(node).first
            node   = parent
            counter += 1
          end
          list
        end
      end
      
      ##
      # Pull new changegroups from +remote+
      # This does not apply the changes, but pulls them onto
      # the local server.
      # 
      # @param [String] remote the path of the remote source (will either be
      #   an HTTP repo or an SSH repo)
      # @param [{Symbol => [String] or Boolean}] this reads two parameters from
      #   opts -- heads and force. heads is the changesets to collect. If this
      #   is empty, it will pull from tip.
      def pull(remote, opts={:heads => nil, :force => nil})
        lock_store do
          # get the common nodes, missing nodes, and the remote heads
          # this is findcommonincoming in the Python code, for those with both open
          common, fetch, remote_heads = *common_nodes(remote, :heads => opts[:heads],
                                                              :force => opts[:force])
          
          UI::status 'requesting all changes'          if fetch == [NULL_ID]
          if fetch.empty?
            UI::status 'no changes found'
            return 0
          end
          
          if (opts[:heads].nil? || opts[:heads].empty?) && remote.capable?('changegroupsubset')
            opts[:heads] = remote_heads
          end
          opts[:heads] ||= []
          cg = if opts[:heads].empty?
                 remote.changegroup fetch, :pull
               else
                 # check for capabilities
                 unless remote.capable? 'changegroupsubset'
                   raise abort('Partial pull cannot be done because' +
                                        'the other repository doesn\'t support' +
                                        'changegroupsubset')
                 end # end unless
                 
                 remote.changegroup_subset fetch, opts[:heads], :pull
               end
          
          add_changegroup cg, :pull, remote.url
        end
      end
      
      ##
      # Add a changegroup to the repo.
      # 
      # Return values:
      # - nothing changed or no source: 0
      # - more heads than before: 1+added_heads (2..n)
      # - fewer heads than before: -1-removed_heads (-2..-n)
      # - number of heads stays the same: 1
      # 
      # Don't the first and last conflict? they stay the same if
      # nothing has changed...
      def add_changegroup(source, type, url, opts={:empty => []})
        run_hook :pre_changegroup, :throw => true, :source => type, :url => url
        changesets = files = revisions = 0
        
        return 0 if source.string.empty?
        
        rev_map = proc {|x| changelog.revision_index_for_node x }
        cs_map  = proc do |x|
          UI::debug "add changeset #{short x}"
          changelog.size
        end
        
        # write changelog data to temp files so concurrent readers will not
        # see inconsistent view
        changelog.delay_update
        old_heads  = changelog.heads.size
        new_heads  = nil # scoping
        changesets = nil # scoping
        cor        = nil # scoping
        cnr        = nil # scoping
        heads      = nil # scoping
        
        Journal::start join('journal') do |journal|
          UI::status 'adding changeset'
          
          # pull of the changeset group
          cor = changelog.size - 1
          unless changelog.add_group(source, cs_map, journal) || opts[:empty].any?
            raise abort("received changelog group is empty")
          end
          
          cnr = changelog.size - 1
          changesets = cnr - cor
          
          # pull off the manifest group
          UI::status 'adding manifests'
          
          # No need to check for empty manifest group here:
          # if the result of the merge of 1 and 2 is the same in 3 and 4,
          # no new manifest will be created and the manifest group will be
          # empty during the pull
          manifest.add_group source, rev_map, journal
          
          # process the files
          UI::status 'adding file changes'
          
          loop do
            f = Amp::RevlogSupport::ChangeGroup.get_chunk source
            break if f.empty?
            
            UI::debug "adding #{f} revisions"
            fl = file f
            o  = fl.index_size
            unless fl.add_group source, rev_map, journal
              raise abort('received file revlog group is empty')
            end
            revisions += fl.index_size - o
            files += 1
          end # end loop
          
          new_heads = changelog.heads.size
          heads     = ""
          
          unless old_heads.zero? || new_heads == old_heads
            heads = " (+#{new_heads - old_heads} heads)"
          end
          
          UI::status("added #{changesets} changesets" +
                     " with #{revisions} changes to #{files} files#{heads}")
          
          if changesets > 0
            changelog.write_pending
            p = proc { changelog.write_pending && root or "" }
            run_hook :pre_txnchangegroup, :throw  => true,
                                          :node   => changelog.node_id_for_index(cor+1).hexlify,
                                          :source => type,
                                          :url    => url
          end
          
          changelog.finalize journal
          
        end # end Journal::start
        
        if changesets > 0
          # forcefully update the on-disk branch cache
          UI::debug 'updating the branch cache'
          branch_tags
          run_hook :post_changegroup, :node => changelog.node_id_for_index(cor+1).hexlify, :source => type, :url => url
          
          ((cor+1)..(cnr+1)).to_a.each do |i|
            run_hook :incoming, :node   => changelog.node_id_for_index(i).hexlify,
                                :source => type,
                                :url    => url
          end # end each
        end # end if
        
        hdz = branch_heads
        # never return 0 here
        ret = if new_heads < old_heads
                new_heads - old_heads - 1
              else
                new_heads - old_heads + 1
              end # end if
        
        # class << ret
        #   def success?; self <= 1 || hdz.size == 1; end
        # end
        
        ret
      end # end def
      
      ##
      # A changegroup, of some sort.
      def changegroup(base_nodes, source)
        changegroup_subset(base_nodes, heads, source)
      end
      
      ##
      # Prints information about the changegroup we are going to receive.
      #
      # @param [Array<String>] nodes the list of node IDs we are receiving
      # @param [Symbol] source how are we receiving the changegroup?
      # @todo add more debug info
      def changegroup_info(nodes, source)
        # print info
        if source == :bundle
          UI.status("#{nodes.size} changesets found")
        end
        # debug stuff
      end
      
      ##
      # Faster version of changegroup_subset. Useful when pushing working dir.
      #
      # Generate a changegruop of all nodes that we have that a recipient
      # doesn't
      #
      # This is much easier than the previous function as we can assume that
      # the recipient has any changegnode we aren't sending them.
      #
      # @param [[String]] common the set of common nodes between remote and self
      # @param [Amp::Repository] source
      def get_changegroup(common, source)
        # Call the hooks
        run_hook :pre_outgoing, :throw => true, :source => source
        
        nodes = changelog.find_missing common
        revset = Hash.with_keys(nodes.map {|n| changelog.rev(n)})

        changegroup_info nodes, source
        
        identity = proc {|x| x }
        
        # ok so this method goes through the generic revlog, and looks for nodes
        # in the changeset(s) we're pushing. Works by the link_rev - basically,
        # the changelog says "hey we're at revision 35", and any changes to any
        # files in any revision logs for that commit will have a link_revision
        # of 35. So we just look for 35!
        gen_node_list = proc do |log|
          log.select {|r| revset[r.link_rev] }.map {|r| r.node_id }
        end
        
        # Ok.... I've tried explaining this 3 times and failed.
        #
        # Goal of this proc: We need to update the changed_files hash to reflect
        # which files (typically file logs) have changed since the last push.
        #
        # How it works: it generates a proc that takes a node_id. That node_id
        # will be looked up in the changelog.i file, which happens to store a
        # list of files that were changed in that commit! So really, this method
        # just takes a node_id, and adds filenamess to the list of changed files.
        changed_file_collector = proc do |changed_fileset|
          proc do |cl_node|
            c = changelog.read cl_node
            c[3].each {|fname| changed_fileset[fname] = true }
          end
        end
        
        lookup_revlink_func = proc do |revlog|
          # given a revision, return the node
          # good thing the python has a description of what this does
          #
          # *snort*
          lookup_revlink = proc do |n|
            changelog.node revlog[n].link_rev
          end
        end
        
        # This constructs a changegroup, or a list of all changed files.
        # If you're here, looking at this code, this bears repeating:
        # - Changelog
        # -- ChangeSet+
        # 
        # A Changelog (history of a branch) is an array of ChangeSets,
        # and a ChangeSet is just a single revision, containing what files
        # were changed, who did it, and the commit message. THIS IS JUST A
        # RECEIPT!!!
        # 
        # The REASON we construct a changegroup here is because this is called
        # when we push, and we push a changelog (usually bundled to conserve
        # space). This is where we make that receipt, called a changegroup.
        # 
        # 'nuff tangent, time to fucking code
        generate_group = proc do
          result = []
          changed_files = {}
          
          coll = changed_file_collector[changed_files]
          # get the changelog's changegroups
          changelog.group(nodes, identity, coll) {|chunk| result << chunk }
          

          node_iter = gen_node_list[manifest]
          look      = lookup_revlink_func[manifest]
          # get the manifest's changegroups
          manifest.group(node_iter, look) {|chunk| result << chunk }
                   
          changed_files.keys.sort.each do |fname|
            file_revlog = file fname
            # warning: useless comment
            if file_revlog.index_size.zero?
              raise abort("empty or missing revlog for #{fname}")
            end
            
            node_list = gen_node_list[file_revlog]
            
            if node_list.any?
              result << RevlogSupport::ChangeGroup.chunk_header(fname.size)
              result << fname
              
              lookup = lookup_revlink_func[file_revlog] # Proc#call
              # more changegroups
              file_revlog.group(node_list, lookup) {|chunk| result << chunk }
            end
          end
          result << RevlogSupport::ChangeGroup.closing_chunk
          
          run_hook :post_outgoing, :node => nodes[0].hexlify, :source => source
          
          result
        end
        
        s = StringIO.new "",(ruby_19? ? "w+:ASCII-8BIT" : "w+")
        generate_group[].each {|chunk| s.write chunk }
        s.rewind
        s
      end
       
      ##
      # This function generates a changegroup consisting of all the nodes
      # that are descendents of any of the bases, and ancestors of any of
      # the heads.
      # 
      # It is fairly complex in determining which filenodes and which
      # manifest nodes need to be included for the changeset to be complete
      # is non-trivial.
      # 
      # Another wrinkle is doing the reverse, figuring out which changeset in
      # the changegroup a particular filenode or manifestnode belongs to.
      # 
      # The caller can specify some nodes that must be included in the
      # changegroup using the extranodes argument.  It should be a dict
      # where the keys are the filenames (or 1 for the manifest), and the
      # values are lists of (node, linknode) tuples, where node is a wanted
      # node and linknode is the changelog node that should be transmitted as
      # the linkrev.
      # 
      # MAD SHOUTZ to Eric Hopper, who actually had the balls to document a
      # good chunk of this code in the Python. He is a really great man, and
      # deserves whatever thanks we can give him. *Peace*
      # 
      # @param [String => [(String, String)]] extra_nodes the key is a filename
      #   and the value is a list of (node, link_node) tuples
      def changegroup_subset(bases, new_heads, source, extra_nodes=nil)
        unless extra_nodes
          if new_heads.sort! == heads.sort!
            common = []
            
            # parents of bases are known from both sides
            bases.each do |base|
              changelog.parents_for_node(base).each do |parent|
                common << parent unless parent.null? # == NULL_ID
              end # end each
            end # end each
            
            # BAIL
            return get_changegroup(common, source)
          end # end if
        end # end unless
        
        run_hook :pre_outgoing, :throw => true, :source => source # call dem hooks
        
        
        # missing changelog list, bases, and heads
        # 
        # Some bases may turn out to be superfluous, and some heads may be as
        # well. #nodes_between will return the minimal set of bases and heads
        # necessary to recreate the changegroup.
        # missing_cl_list, bases, heads = changelog.nodes_between(bases, heads)
        btw = changelog.nodes_between(bases, heads)
        missing_cl_list, bases, heads = btw[:between], btw[:roots], btw[:heads]
        changegroup_info missing_cl_list, source
        
        # Known heads are the list of heads about which it is assumed the recipient
        # of this changegroup will know.
        known_heads = []
        
        # We assume that all parents of bases are known heads.
        bases.each do |base|
          changelog.parents_for_node(base).each do |parent|
            known_heads << parent
          end # end each
        end # end each
        
        if known_heads.any? # unless known_heads.empty?
          # Now that we know what heads are known, we can compute which
          # changesets are known. The recipient must know about all
          # changesets required to reach the known heads from the null
          # changeset.
          has_cl_set = changelog.nodes_between(nil, known_heads)[:between]
          
          # cast to a hash for latter usage
          has_cl_set = Hash.with_keys has_cl_set
        else
          # If there were no known heads, the recipient cannot be assumed to
          # know about any changesets.
          has_cl_set = {}
        end
        
        # We don't know which manifests are missing yet
        missing_mf_set = {}
        # Nor do we know which filenodes are missing.
        missing_fn_set = {}
        
        ########
        # Here are procs for further usage
        
        # A changeset always belongs to itself, so the changenode lookup
        # function for a changenode is +identity+
        identity = proc {|x| x }
        
        # A function generating function. Sets up an enviroment for the 
        # inner function.
        cmp_by_rev_function = proc do |rvlg|
          # Compare two nodes by their revision number in the environment's
          # revision history. Since the revision number both represents the
          # most efficient order to read the nodes in, and represents a
          # topological sorting of the nodes, this function if often useful.
          proc {|a, b| rvlg.rev(a) <=> rvlg.rev(b) }
        end
        
        # If we determine that a particular file or manifest node must be a
        # node that the recipient of the changegroup will already have, we can
        # also assume the recipient will have all the parents. This function
        # prunes them from the set of missing nodes.
        prune_parents = proc do |rvlg, hasses, missing|
          has_list = hasses.keys
          has_list.sort!(&cmp_by_rev_function(rvlg))
          
          has_list.each do |node|
            parent_list = revlog.parent_for_node(node).select {|p| p.not_null? }
          end
          
          while parent_list.any?
            n = parent_list.pop
            unless hasses.include? n
              hasses[n] = 1
              p = revlog.parent_for_node(node).select {|p| p.not_null? }
              parent_list += p
            end
          end
          
          hasses.each do |n|
            missing.slice!(n - 1, 1) # pop(n, None)
          end
        end
        
        # This is a function generating function used to set up an environment
        # for the inner funciont to execute in.
        manifest_and_file_collector = proc do |changed_fileset|
          # This is an information gathering function that gathers
          # information from each changeset node that goes out as part of
          # the changegroup. The information gathered is a list of which
          # manifest nodes are potentially required (the recipient may already
          # have them) and total list of all files which were changed in any
          # changeset in the changegroup.
          # 
          # We also remember the first changenode we saw any manifest
          # referenced by so we can later determine which changenode owns
          # the manifest.
          
          # this is what we're returning
          proc do |cl_node|
            c = changelog.read cl_node
            c[3].each do |f|
              # This is to make sure we only have one instance of each
              # filename string for each filename
              changed_fileset[f] ||= f
            end # end each
            
            missing_mf_set[c[0]] ||= cl_node
          end # end proc
        end # end proc
        
        # Figure out which manifest nodes (of the ones we think might be part
        # of the changegroup) the recipients must know about and remove them
        # from the changegroup.
        prune_manifest = proc do
          has_mnfst_set = {}
          missing_mf_set.values.each do |node|
            # If a 'missing' manifest thinks it belongs to a changenode
            # the recipient is assumed to have, obviously the recipient
            # must have the manifest.
            link_node = changelog.node manifest.link_rev(manifest.revision_index_for_node(node))
            has_mnfst_set[n] = 1 if has_cl_set.include? link_node
          end # end each
          
          prune_parents[manifest, has_mnfst_set, missing_mf_set] # Proc#call
        end # end proc
        
        # Use the information collected in collect_manifests_and_files to say
        # which changenode any manifestnode belongs to.
        lookup_manifest_link = proc {|node| missing_mf_set[node] }
        
        # A function generating function that sets up the initial environment
        # the inner function.
        filenode_collector = proc do |changed_files|
          next_rev = []
          
          # This gathers information from each manifestnode included in the
          # changegroup about which filenodes the manifest node references
          # so we can include those in the changegroup too.
          #
          # It also remembers which changenode each filenode belongs to.  It
          # does this by assuming the a filenode belongs to the changenode
          # the first manifest that references it belongs to.
          collect_missing_filenodes = proc do |node|
            r = manifest.rev node
            
            if r == next_rev[0]
              
              # If the last rev we looked at was the one just previous,
              # we only need to see a diff.
              delta_manifest = manifest.read_delta node
              
              # For each line in the delta
              delta_manifest.each do |f, fnode|
                f = changed_files[f]
                
                # And if the file is in the list of files we care
                # about.
                if f
                  # Get the changenode this manifest belongs to
                  cl_node = missing_mf_set[node]
                  
                  # Create the set of filenodes for the file if
                  # there isn't one already.
                  ndset = missing_fn_set[f] ||= {}
                  
                  # And set the filenode's changelog node to the
                  # manifest's if it hasn't been set already.
                  ndset[fnode] ||= cl_node
                end
              end
            else
              # Otherwise we need a full manifest.
              m = manifest.read node
              
              # For every file in we care about.
              changed_files.each do |f|
                fnode = m[f]
                
                # If it's in the manifest
                if fnode
                  # See comments above.
                  cl_node = msng_mnfst_set[mnfstnode]
                  ndset   = missing_fn_set[f] ||= {}
                  ndset[fnode] ||= cl_node
                end
              end
            end
            
            # Remember the revision we hope to see next.
            next_rev[0] = r + 1
          end # end proc
        end # end proc
        
        # We have a list of filenodes we think need for a file, let's remove
        # all those we know the recipient must have.
        prune_filenodes = proc do |f, f_revlog|
          missing_set = missing_fn_set[f]
          hasset = {}
          
          # If a 'missing' filenode thinks it belongs to a changenode we
          # assume the recipient must have, the the recipient must have
          # that filenode.
          missing_set.each do |n|
            cl_node = changelog.node f_revlog[n].link_rev
            hasset[n] = true if has_cl_set.include? cl_node
          end
          
          prune_parents[f_revlog, hasset, missing_set] # Proc#call
        end # end proc
        
        # Function that returns a function.
        lookup_filenode_link_func = proc do |name|
          missing_set = missing_fn_set[name]
          
          # lookup the changenode the filenode belongs to
          lookup_filenode_link = proc do |node|
            missing_set[node]
          end # end proc
        end # end proc
        
        # add the nodes that were explicitly requested.
        add_extra_nodes = proc do |name, nodes|
          return unless extra_nodes && extra_nodes[name]
          
          extra_nodes[name].each do |node, link_node|
            nodes[node] = link_node unless nodes[node]
          end
          
        end
        
        # Now that we have all theses utility functions to help out and
        # logically divide up the task, generate the group.
        generate_group = proc do
          changed_files = {}
          group = changelog.group(missing_cl_list, identity, &manifest_and_file_collector[changed_files])
          group.each { |chunk| yield chunk }
          prune_manifests.call
          add_extra_nodes[1, msng_mnfst_set]
          msng_mnfst_lst = msng_mnfst_set.keys
          
          msng_mnfst_lst.sort!(&cmp_by_rev_function[manifest])
          
          group = manifest.group(msng_mnfst_lst, lookup_filenode_link,
                                 filenode_collector[changed_files])
          
          group.each {|chunk| yield chunk }
          
          msng_mnfst_lst = nil
          msng_mnfst_set.clear
          
          if extra_nodes
            extra_nodes.each do |fname|
              next if fname.kind_of?(Integer)
              msng_mnfst_set[fname] ||= {}
              changed_files[fname] = true
            end
          end
          
          changed_files.sort.each do |fname|
            file_revlog = file(fname)
            unless file_revlog.size > 0
              raise abort("empty or missing revlog for #{fname}")
            end
            
            if msng_mnfst_set[fname]
              prune_filenodes[fname, file_revlog]
              add_extra_nodes[fname, missing_fn_set[fname]]
              missing_fn_list = missing_fn_set[fname].keys
            else
              missing_fn_list = []
            end
            
            if missing_fn_list.size > 0
              yield ChangeGroup.chunk_header(fname.size)
              yield fname
              missing_fn_list.sort!(&cmp_by_rev_function[file_revlog])
              group = file_revlog.group(missing_fn_list,
                                        lookup_filenode_link_func[fname])
              group.each {|chunk| yield chunk }
            end
            if missing_fn_set[fname]
              missing_fn_set.delete fname
            end
          end
          
          yield ChangeGroup.close_chunk
          
          if missing_cl_list
            run_hook :post_outgoing
          end
        end # end proc
        
        s = StringIO.new "",(ruby_19? ? "w+:ASCII-8BIT" : "w+")
        generate_group.call do |chunk|
          s.write chunk
        end
        s.seek(0, IO::SEEK_SET)
        
      end # end def
      
      ##
      # Revert a file or group of files to +revision+. If +opts[:unlink]+
      # is true, then the files 
      # 
      # @param  [Array<String>] files a list of files to revert
      # @return [Boolean] a success marker
      def revert(files, opts={})
        # get the parents - used in checking if we haven an uncommitted merge
        parent, p2 = dirstate.parents
        
        # get the revision
        rev = opts[:revision] || opts[:rev] || opts[:to]
        
        # check to make sure it's logically possible
        unless rev || p2 == RevlogSupport::Node::NULL_ID
          raise abort("uncommitted merge - please provide a specific revision")
        end
        
        # if we have anything here, then create a matcher
        matcher = if files
                    Amp::Match.create :files    => files         ,
                                      :includer => opts[:include],
                                      :excluder => opts[:exclude]
                  else
                    # else just return nil
                    # we can return nil because when it gets used in :match => matcher,
                    # it will be as though it's not even there
                    nil
                  end
        
        # the changeset we use as a guide
        changeset = self[rev]
        
        # get the files that need to be changed
        stats = status :node_1 => rev, :match => matcher
        
        ###
        # now make the changes
        ###

        ##########
        # MODIFIED and DELETED
        ##########
        # Just write the old data to the files
        (stats[:modified] + stats[:deleted]).each do |path|
          File.open path, 'w' do |file|
            file.write changeset.get_file(path).data
          end
          UI::status "restored\t#{path}"
        end

        ##########
        # REMOVED
        ##########
        # these files are set to be removed, and have thus far been dropped from the filesystem
        # we restore them and we alert the repo
        stats[:removed].each do |path|
          File.open path, 'w' do |file|
            file.write changeset.get_file(path).data
          end

          dirstate.normal path # pretend nothing happened
          UI::status "saved\t#{path}"
        end

        ##########
        # ADDED
        ##########
        # these files have been added SINCE +rev+
        stats[:added].each do |path|
          remove path
          UI::status "destroyed\t#{path}"
        end # pretend these files were never even there
        
        true # success marker
      end
      
      # Return list of roots of the subsets of missing nodes from remote
      # 
      # If base dict is specified, assume that these nodes and their parents
      # exist on the remote side and that no child of a node of base exists
      # in both remote and self.
      # Furthermore base will be updated to include the nodes that exists
      # in self and remote but no children exists in self and remote.
      # If a list of heads is specified, return only nodes which are heads
      # or ancestors of these heads.
      # 
      # All the ancestors of base are in self and in remote.
      # All the descendants of the list returned are missing in self.
      # (and so we know that the rest of the nodes are missing in remote, see
      # outgoing)
      def find_incoming_roots(remote, opts={:base  => nil,   :heads => nil,
                                            :force => false, :base  => nil})
        common_nodes(remote, opts)[1]
      end
      
      ##
      # Find the common nodes, missing nodes, and remote heads.
      # 
      # So in this code, we use  opts[:base] and fetch as hashes
      # instead of arrays. We could very well use arrays, but hashes have
      # O(1) lookup time, and since these could get RFH (Really Fucking
      # Huge), we decided to take the liberty and just use hash for now.
      # 
      # If opts[:base] (Hash) is specified, assume that these nodes and their parents
      # exist on the remote side and that no child of a node of base exists
      # in both remote and self.
      # Furthermore base will be updated to include the nodes that exists
      # in self and remote but no children exists in self and remote.
      # If a list of heads is specified, return only nodes which are heads
      # or ancestors of these heads.
      # 
      # All the ancestors of base are in self and in remote.
      # 
      # @param [Amp::Repository] remote the repository we're pulling from
      # @param [(Array<>, Array<>, Array<>)] the common nodes, missing nodes, and
      #   remote heads
      def common_nodes(remote, opts={:heads => nil, :force => nil, :base => nil})
        # variable prep!
        node_map = changelog.node_map
        search   = []
        unknown  = []
        fetch    = {}
        seen     = {}
        seen_branch = {}
        opts[:base]  ||= {}
        opts[:heads] ||= remote.heads
        
        # if we've got nothing...
        if changelog.tip == NULL_ID
          opts[:base][NULL_ID] = true # 1 is stored in the Python
          
          return [NULL_ID], [NULL_ID], opts[:heads].dup unless opts[:heads] == [NULL_ID]
          return [NULL_ID], [], [] # if we didn't trip ^, we're returning this
        end
        
        # assume we're closer to the tip than the root
        # and start by examining heads
        UI::status 'searching for changes'
        
        opts[:heads].each do |head|
          if !node_map.include?(head)
            unknown << head 
          else
            opts[:base][head] = true # 1 is stored in the Python
          end
        end
        
        opts[:heads] = unknown # the ol' switcheroo
        return opts[:base].keys, [], [] if unknown.empty? # BAIL
        
        # make a hash with keys of unknown
        requests = Hash.with_keys unknown
        count    = 0
        # Search through the remote branches
        # a branch here is a linear part of history, with 4 (four)
        # parts:
        # 
        # head, root, first parent, second parent
        # (a branch always has two parents (or none) by definition)
        # 
        # Here's where we start using the Hashes instead of Arrays
        # trick. Keep an eye out for opts[:base] and opts[:heads]!
        unknown = remote.branches(*unknown)
        until unknown.empty?
          r = []
          
          while node = unknown.shift
            next if seen.include?(node[0])
            UI::debug "examining #{short node[0]}:#{short node[1]}"
            
            if node[0] == NULL_ID
              # Do nothing...
            elsif seen_branch.include? node
              UI::debug 'branch already found'
              next
            elsif node_map.include? node[1]
              UI::debug "found incomplete branch #{short node[0]}:#{short node[1]}"
              search << node[0..1]
              seen_branch[node] = true # 1 in the python
            else
              unless seen.include?(node[1]) || fetch.include?(node[1])
                if node_map.include?(node[2]) and node_map.include?(node[3])
                  UI::debug "found new changset #{short node[1]}"
                  fetch[node[1]] = true # 1 in the python
                end # end if
                
                node[2..3].each do |p|
                  opts[:base][p] = true if node_map.include? p
                end
              end # end unless
              
              node[2..3].each do |p|
                unless requests.include?(p) || node_map.include?(p)
                  r << p
                  requests[p] = true # 1 in the python
                end # end unless
              end # end each
            end # end if
            
            seen[node[0]] = true # 1 in the python
          end # end while
          
          unless r.empty?
            count += 1
            
            UI::debug "request #{count}: #{r.map{|i| short i }}"
            
            (0..(r.size-1)).step(10) do |p|
              remote.branches(r[p..(p+9)]).each do |b|
                UI::debug "received #{short b[0]}:#{short b[1]}"
                unknown << b
              end
            end
          end # end unless
        end # end until
        
        # sorry for the ambiguous variable names
        # the python doesn't name them either, which
        # means I have no clue what these are
        find_proc = proc do |item1, item2|
          fetch[item1]       = true
          opts[:base][item2] = true
        end
        
        # do a binary search on the branches we found
        search, new_count = *binary_search(:find => search,
                                           :repo => remote,
                                           :node_map => node_map,
                                           :on_find => find_proc)
        count += new_count # keep keeping track of the total
        
        # sanity check, because this method is sooooo fucking long
        fetch.keys.each do |f|
          if node_map.include? f
            raise RepoError.new("already have changeset #{short f[0..3]}")
          end
        end
        
        if opts[:base].keys == [NULL_ID]
          if opts[:force]
            UI::warn 'repository is unrelated' 
          else
            raise RepoError.new('repository is unrelated')
          end
        end
        
        UI::debug "found new changesets starting at #{fetch.keys.map{|f| short f }.join ' '}"
        UI::debug "#{count} total queries"
        
        # on with the show!
        [opts[:base].keys, fetch.keys, opts[:heads]]
      end
      
      ##
      # Call the hooks that run under +call+
      # 
      # @param [Symbol] call the location in the system where the hooks
      #   are to be called
      def run_hook(call, opts={:throw => false})
        Hook.run_hook(call, opts)
      end
      
      ##
      # Adds a list of file paths to the repository for the next commit.
      # 
      # @param [String, Array<String>] paths the paths of the files we need to
      #   add to the next commit
      # @return [Array<String>] which files WEREN'T added
      def add(*paths)
        lock_working do
          rejected = []
          paths.flatten!
          
          paths.each do |file|
            path = working_join file
            
            st = File.lstat(path) rescue nil
            
            unless st
              UI.warn "#{file} does not exist!"
              rejected << file
              next
            end
            
            if st.size > 10.mb
              UI.warn "#{file}: files over 10MB may cause memory and" +
                          "performance problems\n" +
                          "(use 'amp revert #{file}' to unadd the file)\n"
            end
            
            
            state = dirstate[file]
            
            
            if File.ftype(path) != 'file' && File.ftype(path) != 'link'
              # fail if it's not a file or link
              UI.warn "#{file} not added: only files and symlinks supported. Type is #{File.ftype path}"
              rejected << path
            elsif state.added? || state.modified? || state.normal?
              # fail if it's being tracked
              UI.warn "#{file} already tracked!"
            elsif state.removed?
              # check back on it if it's being removed
              dirstate.normal_lookup file
            else
              # else add it
              dirstate.add file
              #Amp::Logger.info("added #{file}")
            end
          end
          
          dirstate.write unless rejected.size == paths.size
          return rejected
        end
      end
      
      ##
      # Returns the number of revisions the repository is tracking.
      # 
      # @return [Integer] how many revisions there have been
      def size
        changelog.size
      end
      
      ##
      # Forgets an added file or files from the repository. Doesn't delete the
      # files, it just says "don't add this on the next commit."
      #
      # @param [Array, String] list a file path (or list of file paths) to
      #   "forget".
      # @return [Boolean] success marker
      def forget(list)
        lock_working do
          list = [*list]
          
          successful = list.any? do |f|
            if dirstate[f].status != :added
              UI.warn "#{f} not being added! can't forget it"
              false
            else
              dirstate.forget f
              true
            end
          end
          
          dirstate.write if successful
        end
        
        true
      end
      
      ##
      # Removes the file (or files) from the repository. Marks them as removed
      # in the DirState, and if the :unlink option is provided, the files are
      # deleted from the filesystem.
      #
      # @param list the list of files. Could also just be 1 file as a string.
      #   should be paths.
      # @param opts the options for this removal.
      # @option [Boolean] opts :unlink (false) whether or not to delete the
      #   files from the filesystem after marking them as removed from the
      #   DirState.
      # @return [Boolean] success?
      def remove(list, opts={})
        list = [*list]
        
        # Should we delete the filez?
        if opts[:unlink]
          list.each do |f|
            ignore_missing_files do
              FileUtils.safe_unlink working_join(f)
            end
          end
        end
        
        lock_working do
          # Save ourselves a dirstate write
          successful = list.any? do |f|
            if opts[:unlink] && File.exists?(working_join(f))
              # Uh, why is the file still there? Don't remove it from the dirstate
              UI.warn("#{f} still exists!")
              false # no success
            elsif dirstate[f].added?
              # Is it already added? if so, forgettaboutit
              dirstate.forget f
              #Amp::Logger.info("forgot #{f}")
              true # success!
            elsif !dirstate.tracking?(f)
              # Are we not even tracking this file? dumbass
              UI.warn("#{f} not being tracked!")
              false # no success
            else
              # Woooo we can delete it
              dirstate.remove f
              #Amp::Logger.info("removed #{f}")
              true
            end
          end
          
          # Write 'em out boss
          dirstate.write if successful
        end
        
        true
      end
      
      ##
      # Returns the parents that aren't NULL_ID
      def living_parents
        dirstate.parents.select {|p| p != NULL_ID }
      end
      
      ##
      # There are two ways to push to remote repo:
      #
      # addchangegroup assumes local user can lock remote
      # repo (local filesystem, old ssh servers).
      #
      # unbundle assumes local user cannot lock remote repo (new ssh
      # servers, http servers).
      def push(remote_repo, opts={:force => false, :revs => nil})
        if remote_repo.capable? "unbundle"
          push_unbundle remote_repo, opts
        else
          push_add_changegroup remote_repo, opts
        end
      end
      
      ##
      # Push and add a changegroup
      # @todo -- add default values for +opts+
      def push_add_changegroup(remote, opts={})
        # no locking cuz we rockz
        ret = pre_push remote, opts
        
        if ret[0]
          cg, remote_heads = *ret
          remote.add_changegroup cg, :push, url
        else
          ret[1]
        end
      end
      
      ##
      # Push an unbundled dohickey
      # @todo -- add default values for +opts+
      def push_unbundle(remote, opts={})
        # local repo finds heads on server, finds out what revs it
        # must push. once revs transferred, if server finds it has
        # different heads (someone else won commit/push race), server
        # aborts.
        
        ret = pre_push remote, opts
        
        if ret[0]
          cg, remote_heads = *ret
          remote_heads = ['force'] if opts[:force]
          remote.unbundle cg, remote_heads, :push
        else
          ret[1]
        end
      end
      
      ##
      # Return list of nodes that are roots of subsets not in remote
      # 
      # If base dict is specified, assume that these nodes and their parents
      # exist on the remote side.
      # If a list of heads is specified, return only nodes which are heads
      # or ancestors of these heads, and return a second element which
      # contains all remote heads which get new children.
      def find_outgoing_roots(remote, opts={:base => nil, :heads => nil, :force => false})
        base, heads, force = opts[:base], opts[:heads], opts[:force]
        if base.nil?
          base = {}
          find_incoming_roots remote, :base => base, :heads => heads, :force => force
        end
        
        UI::debug("common changesets up to "+base.keys.map {|k| k.short_hex}.join(" "))
        
        remain = Hash.with_keys changelog.node_map.keys, nil
        
        # prune everything remote has from the tree
        remain.delete NULL_ID
        remove = base.keys
        while remove.any?
          node = remove.shift
          if remain.include? node
            remain.delete node
            changelog.parents_for_node(node).each {|p| remove << p }
          end
        end
        
        # find every node whose parents have been pruned
        subset = []
        # find every remote head that will get new children
        updated_heads = {}
        remain.keys.each do |n|
          p1, p2 = changelog.parents_for_node n
          subset << n unless remain.include?(p1) || remain.include?(p2)
          if heads && heads.any?
            updated_heads[p1] = true if heads.include? p1
            updated_heads[p2] = true if heads.include? p2
          end
        end
        
        # this is the set of all roots we have to push
        if heads && heads.any?
          return subset, updated_heads.keys
        else
          return subset
        end 
      end
      
      ##
      # The branches available in this repository.
      # 
      # @param [Array<String>] nodes the list of nodes. this can be optionally left empty
      # @return [Array<String>] the branches, active and inactive!
      def branches(*nodes)
        branches = []
        nodes = [changelog.tip] if nodes.empty?
        
        # for each node, find its first parent (adam and eve, basically)
        # -- that's our branch!
        nodes.each do |node|
          t = node
          # traverse the tree, staying to the left side
          #            node
          #          /     \
          #   parent1     parent2
          # ....              ....
          # This will get us the first parent. When it's finally NULL_ID,
          # we have a root -- this is the basis for our branch.
          loop do
            parents = changelog.parents_for_node t
            if parents[1] != NULL_ID || parents[0] == NULL_ID
              branches << [node, t, *parents]
              break
            end
            t = parents.first # get the first parent and start again
          end
        end
        
        branches
      end
      
      ##
      # Copies a file from +source+ to +destination+, while being careful of the
      # specified options. This method will perform all necessary file manipulation
      # and dirstate changes and so forth. Just give 'er a source and a destination.
      #
      # @param [String] source the path to the source file
      # @param [String] destination the path to the destination file
      # @param [Hash] opts the options for the copy
      # @option [Boolean] opts :after (false) should the file be deleted?
      # @return [Boolean] success?
      def copy(source, destination, opts)
        # Traverse repository subdirectories
        src    = relative_join source
        target = relative_join destination
        
        # Is there a tracked file at our destination? If so, get its state.
        state = dirstate[target].status
        # abstarget is the full path to the target. Needed for system calls
        # (just to be safe)
        abstarget = working_join target
        
        # If true, we're copying into a directory, so be smart about it.
        if File.directory? abstarget
          abstarget = File.join abstarget, File.basename(src)
          target = File.join target, File.basename(src)
        end
        abssrc = working_join(src)
        
        
        exists = File.exist? abstarget
        # If the file's there, and we aren't forcing the copy, then we should let
        # the user know they might overwrite an existing file in the repo.
        if (!opts[:after] && exists || opts[:after] && [:merged, :normal].include?(state))
          unless opts[:force]
            Amp::UI.warn "#{target} not overwriting, file exists"
            return false
          end
        end
        
        return if opts[:after] && !exists
        unless opts[:"dry-run"]
          # Performs actual file copy from one locatino to another.
          # Overwrites file if it's there.
          begin
            File.safe_unlink(abstarget) if exists
            
            target_dir = File.dirname abstarget
            File.makedirs target_dir unless File.directory? target_dir
            File.copy(abssrc, abstarget)
          rescue Errno::ENOENT
            # This happens if the file has been deleted between the check up above
            # (exists = File.exist? abstarget) and the call to File.safe_unlink.
            Amp::UI.warn("#{target}: deleted in working copy in the last 2 microseconds")
          rescue StandardError => e
            Amp::UI.warn("#{target} - cannot copy: #{e}")
            return false
          end
        end
        
        # Be nice and give the user some output
        if opts[:verbose] || opts[:"dry-run"]
          action = opts[:rename] ? "moving" : "copying"
          Amp::UI.status("#{action} #{src} to #{target}")
        end
        return false if opts[:"dry-run"]
        
        # in case the source of the copy is marked as the destination of a 
        # different copy (that hasn't yet been committed either), we should
        # do some extra handling
        origsrc = dirstate.copy_map[src] || src
        if target == origsrc
          # We're copying back to our original location! D'oh.
          unless [:merged, :normal].include?(state)
            dirstate.maybe_dirty target
          end
        else
          if dirstate[origsrc].added? && origsrc == src
            # we copying an added (but uncommitted) file?
            UI.warn("#{origsrc} has not been committed yet, so no copy data" +
                    "will be stored for #{target}")
            if [:untracked, :removed].include?(dirstate[target].status)
              add [target]
            end
          else
            dirstate_copy src, target
          end
        end
        
        # Clean up if we're doing a move, and not a copy.
        remove([src], :unlink => !(opts[:after])) if opts[:rename]
      end
      
      ##
      # Copy a file from +source+ to +dest+. Really simple, peeps.
      # The reason this shit is even *slightly* complicated because
      # it deals with file types. Otherwise I could write this
      # in, what, 3 lines?
      # 
      # @param [String] source the from
      # @param [String] dest the to
      def dirstate_copy(source, dest)
        path = working_join dest
        
        if !File.exist?(path) || File.ftype(path) == 'link'
          UI::warn "#{dest} doesn't exist!"
        elsif not (File.ftype(path) == 'file' || File.ftype(path) == 'link')
          UI::warn "copy failed: #{dest} is neither a file nor a symlink"
        else
          lock_working do
            # HOME FREE!!!!!!! i love getting out of school before noon :-D
            # add it if it makes sense (like it was previously removed or untracked)
            # and then copy da hoe
            state  = dirstate[dest].status
            dirstate.add dest if [:untracked, :removed].include?(state)
            dirstate.copy source => dest
            dirstate.write
            
            #Amp::Logger.info("copy #{source} -> #{dest}")
          end
        end
      end
      
      ##
      # Undelete a file. For instance, if you remove something and then
      # find out that you NEED that file, you can use this command.
      # 
      # @param [[String]] list the files to be undeleted
      def undelete(list)
        manifests = living_parents.map do |p|
          manifest.read changelog.read(p).first
        end
        
        # now we actually restore the files
        list.each do |file|
          unless dirstate[file].removed?
            UI.warn "#{file} isn't being removed!"
          else
            m = manifests[0] || manifests[1]
            data = file(f).read m[f]
            add_file file, data, m.flags(f) # add_file is wwrite in the python
            dirstate.normal f # we know it's clean, we just restored it
          end
        end
      end
      alias_method :restore, :undelete
      
      ##
      # Write data to a file in the CODE repo, not the .hg
      # 
      # @param [String] file_name
      # @param [String] data (no trailing newlines are appended)
      # @param [[String]] flags we're really just looking for links
      #   and executables, here
      def add_file(file_name, data, flags)
        data = filter "decode", file_name, data
        path = "#{@root}/#{file_name}"
        
        File.unlink path rescue nil
        
        if flags.include? 'l' # if it's a link
          @file_opener.symlink path, data
        else
          @file_opener.open(path, 'w') {|f| f.write data }
          File.set_flag path, false, true if flags.include? 'x'
        end
      end
      
      ##
      # Returns the node_id's of the heads of the repository.
      def heads(start=nil, options={:closed => true})
        heads = changelog.heads(start)
        should_show = lambda do |head|
          return true if options[:closed]
          
          extras = changelog.read(head)[5]
          return !(extras["close"])
        end
        heads = heads.select {|h| should_show[h] }
        heads.map! {|h| [changelog.rev(h), h] }
        heads.sort! {|arr1, arr2| arr2[0] <=> arr1[0] }
        heads.map! {|r, n| n}
      end
      
      ##
      # Walk recursively through the directory tree (or a changeset)
      # finding all files matched by the match function
      # 
      # @param [String, Integer] node selects which changeset to walk
      # @param [Amp::Match] match the matcher decides how to pick the files
      # @param [Array<String>] an array of filenames
      def walk(node=nil, match = Match.create({}) { true })
        self[node].walk(match) # calls Changeset#walk
      end
      
      ##
      # Returns the requested file at the given revision annotated by
      # line number, so you can see who committed which lines in the file's
      # history.
      #
      # @param file The name of the file to annotate
      # @param [Integer, String] rev (nil) The revision to look at for
      #   annotation
      def annotate(file, revision=nil, opts={})
        changeset = self[revision]
        file = changeset.get_file(file)
        return file.annotate(opts[:follow_copies], opts[:line_numbers])
      end
      
      ##
      # This gives the status of the repository, comparing 2 node in
      # its history. Now, with no parameters, it's going to compare the
      # last revision with the working directory, which is the most common
      # usage - that answers "what is the current status of the repository,
      # compared to the last time a commit happened?". However, given any
      # two revisions, it can compare them.
      # 
      # @example @repo.status # => {:unknown => ['code/smthng.rb'], :added => [], ...}
      # @param [Hash] opts the options for this command. there's a bunch.
      # @option [String, Integer] opts :node_1 (".") an identifier for the starting
      #   revision
      # @option [String, Integer] opts :node_2 (nil) an identifier for the ending
      #   revision. Defaults to the working directory.
      # @option [Proc] opts :match (proc { true }) a proc that will match
      #   a file, so we know if we're interested in it.
      # @option [Boolean] opts :ignored (false) do we want to see files we're
      #   ignoring?
      # @option [Boolean] opts :clean (false) do we want to see files that are
      #   totally unchanged?
      # @option [Boolean] opts :unknown (false) do we want to see files we've
      #   never seen before (i.e. files the user forgot to add to the repo)?
      # @return [Hash<Symbol => Array<String>>] no, I'm not kidding. the keys are:
      #   :modified, :added, :removed, :deleted, :unknown, :ignored, :clean. The
      #   keys are the type of change, and the values are arrays of filenames
      #   (local to the root) that are under each key.
      def status(opts={:node_1 => '.'})
        run_hook :status
        
        node1, node2, match = opts[:node_1], opts[:node_2], opts[:match]
        
        match = Match.create({}) { true } unless match
        
        node1 = self[node1] unless node1.kind_of? Changeset # get changeset objects
        node2 = self[node2] unless node2.kind_of? Changeset
        
        write_dirstate = false
        
        # are we working with working directories?
        working = node2.revision == nil
        parent_working = working && node1 == self["."]
        
        # load the working directory's manifest
        node2.manifest if !working && node2.revision < node1.revision
        
        if working
          # get the dirstate's latest status
          status = dirstate.status(opts[:ignored], opts[:clean], opts[:unknown], match)
          
          # this case is run about 99% of the time
          # do we need to do hashes on any files to see if they've changed?
          if parent_working && status[:lookup].any?
            # lookup.any? is a shortcut for !lookup.empty?
            clean, modified, write_dirstate = *fix_files(status[:lookup], node1, node2)
            
            status[:clean]    += clean
            status[:modified] += modified
          end
        else
          status = {:clean => [], :modified => [], :lookup => [], :unknown => [], :ignored => [],
                    :removed => [], :added => [], :deleted => []}
        end
        # if we're working with old revisions...
        unless parent_working
          # get the older revision manifest
          mf1 = node1.manifest.dup
          
          if working
            # get the working directory manifest. note, it's a tweaked
            # manifest to reflect working directory files
            mf2 = self["."].manifest.dup
            
            # mark them as not in the manifest to force checking later
            files_for_later = status[:lookup] + status[:modified] + status[:added]
            files_for_later.each {|file| mf2.mark_for_later file, node2 }
            
            # remove any files we've marked as removed them from the '.' manifest
            status[:removed].each {|file| mf2.delete file }
          else
            # if we aren't working with the working directory, then we'll
            # just use the old revision's information
            status[:removed], status[:unknown], status[:ignored] = [], [], []
            mf2 = node2.manifest.dup
          end
          
          # Every file in the later revision (or working directory)
          mf2.each do |file, node|
            # Does it exist in the old manifest? If so, it wasn't added.
            if mf1[file]
              # the tests to run
              tests = [ mf1.flags[file] != mf2.flags[file]           ,
                        mf1[file] != mf2[file] &&
                          (mf2[file] || node1[file] === node2[file]) ]
              
              # It's in the old manifest, so lets check if its been changed
              # Else, it must be unchanged
              if tests.any?
                status[:modified] << file 
                status[:clean]    << file if opts[:clean]
              end
              
              # Remove that file from the old manifest, since we've checked it
              mf1.delete file
            else
              # if it's not in the old manifest, it's been added
              status[:added] << file
            end
          end
          
          # Anything left in the old manifest is a file we've removed since the
          # first revision.
          status[:removed] = mf1.keys
        end
        
        # We're done!
        status.delete :lookup # because nobody cares about it
        delta = status.delete :delta
        
        status.map {|k, v| [k, v.sort] }.to_hash # sort dem fuckers
        status[:delta] = delta
        status.select {|k, _| opts[:only] ? opts[:only].include?(k) : true }.to_hash
      end
      
      ##
      # Clone a repository.
      # 
      # Here is what this does, pretty much:
      #   % amp init monkey
      #   % cd monkey
      #   % amp pull http://monkey
      # 
      # It's so simple it's not even funny.
      # 
      # @param [Amp::Repository] remote repository to pull from
      # @param [Array<String>] heads list of revs to clone (forces use of pull)
      # @param [Boolean] stream do we stream from the remote source?
      def clone(remote, opts={:revs => [], :stream => false})
        # now, all clients that can request uncompressed clones can
        # read repo formats supported by all servers that can serve
        # them.
        
        # The streaming case:
        # if revlog format changes, client will have to check version
        # and format flags on "stream" capability, and use
        # uncompressed only if compatible.
        if opts[:stream] && opts[:revs].any? && remote.capable?('stream')
          stream_in remote
        else
          pull remote, :revs => opts[:revs]
        end
      end
      
      ##
      # Stream in the data from +remote+.
      # 
      # @param [Amp::Repository] remote repository to pull from
      # @return [Integer] the number of heads in the repository minus 1
      def stream_in(remote)
        remote.stream_out do |f|
          l = f.gets # this should be the server code
          
          unless Integer(l)
            raise ResponseError.new("Unexpected response from server: #{l}")
          end
          
          case l.to_i
          when 1
            raise RepoError.new("operation forbidden by server")
          when 2
            raise RepoError.new("locking the remote repository failed")
          end
          
          UI::status "streaming all changes"
          
          l = f.gets # this is effectively [total_files, total_bytes].join ' '
          total_files, total_bytes = *l.split(' ').map {|i| i.to_i }[0..1]
          UI::status "#{total_files} file#{total_files == 1 ? '' : 's' } to transfer, #{total_bytes.to_human} of data"
          
          start = Time.now
          total_files.times do |i|
            l = f.gets
            name, size = *l.split("\0")[0..1]
            size = size.to_i
            UI::debug "adding #{name} (#{size.to_human})"
            
            @store.opener.open do |store_file|
              chunk = f.read size # will return nil if at EOF
              store_file.write chunk if chunk
            end
          end
          
          elapsed = Time.now - start
          elapsed = 0.001 if elapsed <= 0
          
          UI::status("transferred #{total_bytes.to_human} in #{elapsed}" +
                     "second#{elapsed == 1.0 ? '' : 's' } (#{total_bytes.to_f / elapsed}/sec)")
          
          invalidate!
          heads.size - 1
        end
      end
      
      ##
      # Invalidate the repository: delete things and reset others.
      def invalidate!
        @changelog = nil
        @manifest  = nil
        
        invalidate_tag_cache!
        invalidate_branch_cache!
      end
      
      ##
      # Commits a changeset or set of files to the repository. You will quite often
      # use this method since it's basically the basis of version control systems.
      #
      # @param [Hash] opts the options to this method are all optional, so it's a very
      #   flexible method. Options listed below.
      # @option [Array] opts :files ([]) the specific files to commit - if this is
      #   not provided, the current status of the working directory is used.
      # @option [Hash] opts :extra ({}) any extra data, such as "close" => true
      #   will close the active branch.
      # @option [String] opts :message ("") the message for the commit. An editor
      #   will be opened if this is not provided.
      # @option [Boolean] opts :force (false) Forces the commit, ignoring minor details
      #   like when you try to commit when no files have been changed.
      # @option [Match] opts :match (nil) A match object to specify how to pick files
      #   to commit. These are useful so you don't accidentally commit ignored files,
      #   for example.
      # @option [Boolean] opts :empty_ok (false) Is an empty commit message a-ok?
      # @option [Boolean] opts :force_editor (false) Do we force the editor to be
      #   opened, even if :message is provided?
      # @option [String] opts :user ($USER) the username to associate with the commit.
      #   Defaults to AmpConfig#username.
      # @option [DateTime, Time, Date] opts :date (Time.now) the date to mark with
      #   the commit. Useful if you miss a deadline and want to pretend that you actually
      #   made it!
      # @return [String] the digest referring to this entry in the revlog
      def commit(opts={:message => "", :extra => {}, :files => []})
        opts[:extra] ||= {}
        opts[:force] = true if opts[:extra]["close"]
        opts[:files] ||= []
        opts[:files].uniq!
        
        use_dirstate = opts[:p1] == nil
        changes = {}
        lock_working_and_store do
          if use_dirstate
            p1, p2 = dirstate.parents
            update_dirstate = true
            
            tests = [opts[:force] ,
                     p2 != NULL_ID,
                     opts[:match] ]
            
            raise StandardError("cannot partially commit a merge") if tests.all?
            
            if opts[:files].any?
              changes = {:modified => [], :removed => []}
              
              # split the files up so we can deal with them appropriately
              opts[:files].each do |file|
                state = dirstate[file]
                if state.normal? || state.merged? || state.added?
                  changes[:modified] << file
                elsif state.removed?
                  changes[:removed]  << file
                elsif state.untracked?
                  UI.warn "#{file} not tracked!"
                else
                  UI.err "#{file} has unknown state #{state[0]}"
                end
              end
              
            else
              changes = status(:match => opts[:match])
            end
          else
            p1, p2 = opts[:p1], (opts[:p2] || NULL_ID)
            update_dirstate = dirstate.parents[0] == p1
            changes = {:modified => files}
          end
          
          
          merge_state = Amp::Merges::MergeState.new self # merge state!
          
          changes[:modified].each do |file|
            if merge_state[file] && merge_state[file] == "u"
              raise StandardError.new("unresolved merge conflicts (see `amp resolve`)")
            end
          end
          
          changeset = WorkingDirectoryChangeset.new self, :parents => [p1, p2]      ,
                                                          :text    => opts[:message],
                                                          :user    => opts[:user]   ,
                                                          :date    => opts[:date]   ,
                                                          :extra   => opts[:extra]  ,
                                                          :changes => changes
            
          revision = commit_changeset changeset, :force           => opts[:force]       ,
                                                 :force_editor    => opts[:force_editor],
                                                 :empty_ok        => opts[:empty_ok]    ,
                                                 :use_dirstate    => use_dirstate       ,
                                                 :update_dirstate => update_dirstate
          
          merge_state.reset
          return revision
        end
      end
      
      ##
      # Commits the given changeset to the repository.
      #
      # @param changeset the changeset to commit. Could be working dir, for
      #   example.
      # @param opts the options for committing the changeset.
      # @option [Boolean] opts :force (false) force the commit, even though
      #   nothing has changed.
      # @option [Boolean] opts :force_editor (false) force the user to open
      #   their editor, even though they provided a message already
      # @option [Boolean] opts :empty_ok (false) is it ok if they have no
      #   description of the commit?
      # @option [Boolean] opts :use_dirstate (true) use the DirState for this
      #   commit? Used if you're committing the working directory (typical)
      # @option [Boolean] opts :update_dirstate (true) should we update the
      #   DirState after the commit? Used if you're committing the working
      #   directory.
      # @return [String] the digest referring to this entry in the revlog
      def commit_changeset(changeset, opts = {:use_dirstate => true,
                                              :update_dirstate => true})
        journal = nil
        valid = false #don't update the DirState if this is set!
        
        commit = ((changeset.modified || []) + (changeset.added || [])).sort
        remove = changeset.removed
        extra = changeset.extra.dup
        branchname = extra["branch"]
        user = changeset.user
        text = changeset.description
        
        p1, p2 = changeset.parents.map {|p| p.node}
        c1 = changelog.read(p1) # 1 parent's changeset as an array
        c2 = changelog.read(p2) # 2nd parent's changeset as an array
        m1 = manifest.read(c1[0]).dup # 1st parent's manifest
        m2 = manifest.read(c2[0])     # 2nd parent's manifest
        
        if opts[:use_dirstate]
          oldname = c1[5]["branch"]
          tests = [ commit.empty?, remove.empty?, ! opts[:force],
                    p2 == NULL_ID, branchname = oldname ]
          
          if tests.all?
            UI::status "nothing changed"
            return nil
          end
        end
        
        xp1 = p1.hexlify
        xp2 = (p2 == NULL_ID) ? "" : p2.hexlify
        
        run_hook :pre_commit
        journal = Journal.new

        fresh    = {} # new = reserved haha
        changed  = []
        link_rev = self.size
        
        (commit + (remove || [])).each {|file| UI::status file }
        
        #Amp::Logger.info("<changeset commit>").indent
        
        commit.each do |file|
          # begin
          
          versioned_file = changeset.get_file(file)
          newflags = versioned_file.flags
          
          fresh[file] = commit_file(versioned_file, m1, m2, link_rev,
                                    journal, changed)
          if [ changed.empty? || changed.last != file, 
               m2[file] != fresh[file] ].all?
            changed << file if m1.flags[file] != newflags
          end
          m1.flags[file] = newflags
          
          dirstate.normal file if opts[:use_dirstate]
          #Amp::Logger.section("committing: #{file}") do
            #Amp::Logger.info("flags: #{newflags.inspect}")
            #Amp::Logger.info("total changes: #{changed.inspect}")
          #end
          # rescue
          #            if opts[:use_dirstate]
          #              UI.warn("trouble committing #{file}")
          #              raise
          #            else
          #              remove << file
          #            end
          # end
        end
        
        updated, added = [], []
        changed.sort.each do |file|
          if m1[file] || m2[file]
            updated << file
          else
            added << file
          end
        end
        
        m1.merge!(fresh)
        
        removed = remove.sort.select {|f| m1[f] || m2[f]}
        removed_1 = []
        removed.select {|f| m1[f]}.each do |f|
          m1.delete f
          removed_1 << f
          #Amp::Logger.info("Removed: #{f}")
        end
        
        fresh = fresh.map {|k, v| (v) ? k : nil}.reject {|k| k.nil? }
        man_entry = manifest.add(m1, journal, link_rev, c1[0], c2[0],
                                [fresh, removed_1])
        #Amp::Logger.info("Adding/modifying: #{fresh.inspect}")
        #Amp::Logger.info("Removing: #{removed_1.inspect}")
        #Amp::Logger.section("New Manifest") do
          #manifest.read(:tip).each do |file, _|
            #Amp::Logger.info(file)
          #end
        #end
        if !opts[:empty_ok] && !text
          template_opts = {:added => added, :updated => updated,
                           :removed => removed, :template_type => :commit }
          edit_text = changeset.to_templated_s(template_opts)
          text = UI.edit(edit_text, user)
        end
        
        lines = text.rstrip.split("\n").map {|r| r.rstrip}.reject {|l| l.empty?}
        if lines.empty? && opts[:use_dirstate]
          raise abort("empty commit message")
        end
        text = lines.join("\n")
        
        changelog.delay_update
        n = changelog.add(man_entry, changed + removed_1, text, journal, p1, p2, user,
                          changeset.date, extra)
        #Amp::Logger.section("changelog") do
          #Amp::Logger.info("manifest entry: #{man_entry.inspect}")
          #Amp::Logger.info("files: #{(changed + removed_1).inspect}")
          #Amp::Logger.info("text: #{text.inspect}")
          #Amp::Logger.info("p1: #{p1.inspect}")
          #Amp::Logger.info("p2: #{p2.inspect}")
          #Amp::Logger.info("user: #{user.inspect}")
          #Amp::Logger.info("date: #{changeset.date.inspect}")
          #Amp::Logger.info("extra: #{extra.inspect}")
        #end
        self.changelog.write_pending()
        changelog.finalize(journal)
        #Amp::Logger.outdent.info("</changeset commit>")
        # branchtags
        
        if opts[:use_dirstate] || opts[:update_dirstate]
          dirstate.parents = n
          removed.each {|f| dirstate.forget(f) } if opts[:use_dirstate]
          dirstate.write
        end
        
        valid = true
        journal.close
        run_hook :post_commit, :added => added, :modified => updated,        :removed => removed, 
                               :user  => user,  :date     => changeset.date, :text    => text,
                               :revision => changelog.index_size
        return n
      rescue StandardError => e
        if !valid
          dirstate.invalidate!
        end
        if e.kind_of?(AbortError)
          UI::warn "Abort: #{e}"
        else
          UI::warn "Got exception while committing. #{e}"
          UI::warn e.backtrace.join("\n")
        end
        journal.delete if journal
      end
      
      
      ##
      # Commits a file as part of a larger transaction.
      #
      # @param file the versioned-file to commit
      # @param manifest1 the manifest of the first parent
      # @param manifest2 the manifest of the second parent
      # @param link_revision the revision index we'll be adding this under
      # @param journal the journal for aborting failed commits
      # @param change_list the list of all the files changed during the commit
      #
      def commit_file(file, manifest1, manifest2, link_revision, journal, change_list)
        filename = file.path
        text = file.data
        curfile = self.file filename
        
        fp1 = manifest1[filename] || NULL_ID
        fp2 = manifest2[filename] || NULL_ID

        metadata = {}
        copied = file.renamed
        if copied && copied[0] != filename
          # Mark the new revision of this file as a copy of another
          # file.  This copy data will effectively act as a parent
          # of this new revision.  If this is a merge, the first
          # parent will be the nullid (meaning "look up the copy data")
          # and the second one will be the other parent.  For example:
          #
          # 0 --- 1 --- 3   rev1 changes file foo
          #   \       /     rev2 renames foo to bar and changes it
          #    \- 2 -/      rev3 should have bar with all changes and
          #                      should record that bar descends from
          #                      bar in rev2 and foo in rev1
          #
          # this allows this merge to succeed:
          #
          # 0 --- 1 --- 3   rev4 reverts the content change from rev2
          #   \       /     merging rev3 and rev4 should use bar@rev2
          #    \- 2 --- 4        as the merge base
          
          copied_file = copied[0]
          copied_revision = manifest1[copied_file]
          new_fp = fp2
          
          if manifest2 # branch merge
            if fp2 == NULL_ID || copied_revision == nil # copied on remote side
              if manifest2[copied_file]
                copied_revision = manifest2[copied_file]
                new_fp = fp1
              end
            end
          end

          if copied_revision.nil? || copied_revision.empty?
            self["."].ancestors.each do |a|
              if a[copied_file]
                copied_revision = a[copied_file].file_node
                break
              end
            end
          end
          
          UI::say "#{filename}: copy #{copied_file}:#{copied_revision.hexlify}"
          metadata["copy"] = copied_file
          metadata["copyrev"] = copied_revision.hexlify
          fp1, fp2 = NULL_ID, new_fp
        elsif fp2 != NULL_ID
          fpa = curfile.ancestor(fp1, fp2)
          
          fp1, fp2 = fp2, NULL_ID if fpa == fp1
          fp2 = NULL_ID if fpa != fp2 && fpa == fp2
        end
        
        if fp2 == NULL_ID && !(curfile.cmp(fp1, text)) && metadata.empty?
          return fp1
        end
        
        change_list << filename
        return curfile.add(text, metadata, journal, link_revision, fp1, fp2)
      end
      
      private
      
      ##
      # Make the dummy changelog at .hg/00changelog.i
      def make_changelog
        @hg_opener.open "00changelog.i", "w" do |file|
          file.write "\0\0\0\2" # represents revlogv2
          file.write " dummy changelog to avoid using the old repo type"
        end
      end
      
      ##
      # Write the requirements file. This returns the requirements passed
      # so that it can be the final method call in #init
      def write_requires(requirements)
        @hg_opener.open "requires", "w" do |require_file|
          requirements.each {|r| require_file.puts r }
        end
        requirements
      end
      
      ##
      # Look up the files in +lookup+ to make sure
      # they're either the same or not. Normally, we can
      # just tell if two files are the same by looking at their sizes. But
      # sometimes, we can't! That's where this method comes into play; it
      # hashes the files to verify integrity.
      # 
      # @param [String] lookup files to look up
      # @param node1
      # @param node2
      # @return [[String], [String], Boolean] clean files, modified files, and
      #   whether or not to write the dirstate
      def fix_files(lookup, node1, node2)
        write_dirstate = false # this gets returned
        modified = [] # and this
        fixup    = [] # fixup are files that haven't changed so they're being
                      # marked wrong in the dirstate. this gets returned
        
        lookup.each do |file|
          # this checks to see if the file has been modified after doing
          # hashes/flag checks
          tests = [ node1.include?(file)                   ,
                    node2.flags(file) == node1.flags(file) ,
                    node1[file]      === node2[file]       ]
          
          unless tests.all?
            modified << file
          else
            fixup << file # mark the file as clean
          end
        end
        

        # mark every fixup'd file as clean in the dirstate
        begin
          lock_working do        
            fixup.each do |file|
              write_dirstate = true
              dirstate.normal file
              modified.delete file
            end
          end
        rescue LockError
        end
        dirstate.write if write_dirstate
        
        # the fixups are actually clean
        [fixup, modified, write_dirstate]
      end
      
      ##
      # do a binary search
      # used by common_nodes
      # 
      # Hash info!
      # :find => the stuff we're searching through
      # :on_find => what to do when we've got something new
      # :repo => usually the remote repo where we get new info from
      # :node_map => the nodes in the current changelog
      def binary_search(opts={})
        # I have a lot of stuff to do for scouts
        # but instead i'm doing this
        # hizzah!
        count = 0
        
        until opts[:find].empty?
          new_search = []
          count += 1
          
          #puts opts[:find].inspect #killme
          #puts opts[:find].inspect #killme
          
          zipped = opts[:find].zip opts[:repo].between(opts[:find])
          zipped.each do |(n, list)|
            list << n[1]
            p = n[0]
            f = 1 # ??? why are these vars so NAMELESS

            list.each do |item|
              UI::debug "narrowing #{f}:#{list.size} #{short item}"

              if opts[:node_map].include? item
                if f <= 2
                  opts[:on_find].call(p, item)
                else
                  UI::debug "narrowed branch search to #{short p}:#{short item}"
                  new_search << [p, item]
                end
                break
              end

              p, f = item, f*2
            end
          end

          opts[:find] = new_search
        end

        [opts[:find], count]
      end
      
      ##
      # this is called before every push
      # @todo -- add default values for +opts+
      def pre_push(remote, opts={})
        common = {}
        remote_heads = remote.heads
        inc = common_nodes remote, :base => common, :heads => remote_heads, :force => true
        inc = inc[1]
        update, updated_heads = find_outgoing_roots remote, :base => common, :heads => remote_heads
        
        if opts[:revs]
          btw = changelog.nodes_between(update, opts[:revs])
          missing_cl, bases, heads = btw[:between], btw[:roots], btw[:heads]
        else
          bases, heads = update, changelog.heads
        end
        if bases.empty?
          UI::status 'no changes found'
          return nil, 1
        elsif !opts[:force]
          # check if we're creating new remote heads
          # to be a remote head after push, node must be either
          # - unknown locally
          # - a local outgoing head descended from update
          # - a remote head that's known locally and not
          #   ancestral to an outgoing head
          
          warn = false
          if remote_heads == [NULL_ID]
            warn = false
          elsif (opts[:revs].nil? || opts[:revs].empty?) and heads.size > remote_heads.size
            warn  = true
          else
            new_heads = heads
            remote_heads.each do |r|
              if changelog.node_map.include? r
                desc = changelog.heads r, heads
                l = heads.select {|h| desc.include? h }
                
                new_heads << r if l.empty?
              else  
                new_heads << r
              end
            end
            
            warn = true if new_heads.size > remote_heads.size
          end
          
          if warn
            UI::status 'abort: push creates new remote heads!'
            UI::status '(did you forget to merge? use push -f to forge)'
            return nil, 0
          elsif inc.any?
            UI::note 'unsynced remote changes!'
          end
        end
        
        if opts[:revs].nil?
          # use the fast path, no race possible on push
          cg = get_changegroup common.keys, :push
        else
          cg = changegroup_subset update, revs, :push
        end
        
        [cg, remote_heads]
      end
      
    end # localrepo
  end # repo
end
