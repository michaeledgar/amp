module Amp
  module Mercurial
    
    ##
    # A Changeset is a simple way of accessing the repository within a certain
    # revision. For example, if the user specifies revision # 36, or revision
    # 3adf21, then we can look those up, and work within the repository at the
    # moment of that revision.
    class Changeset < Amp::Repositories::AbstractChangeset
      include Mercurial::RevlogSupport::Node
      include Comparable
      include Enumerable
      
      attr_reader :repo
      alias_method :repository, :repo
      
      ##
      # Initializes a new changeset. We need a repository to work with, and also
      # a change_id. this change_id could be a revision index or a node_id for
      # the revision.
      #
      # @param [Repository] repo a repository to work with.
      # @param [Integer, String] change_id an ID or index to lookup to find this
      #   changeset.
      #
      def initialize(repo, change_id='')
        change_id = '.' if change_id == ''
        @repo = repo
        if change_id.kind_of? Integer
          @revision = change_id
          @node_id  = @repo.changelog.node_id_for_index change_id
        else
          @node_id = @repo.lookup change_id
          @revision = @repo.changelog.rev @node_id
        end
        @parents = nil
      end
      
      ##
      # Converts the revision to a number
      def to_i; @revision; end
      
      ##
      # Converts the revision to an easy-to-digest string
      def to_s(opts = {})
        if opts[:template]
          to_templated_s(opts)
        else
          @node_id[0..5].hexlify
        end
      end
      
      ##
      #
      def to_templated_s(opts={})
        
        change_node = node
        revision    = self.revision
        log         = @repo.changelog
        changes     = log.read change_node
        username    = changes[1]
        date        = Time.at changes[2].first
        files       = changes[3]
        description = changes[4]
        extra       = changes[5]
        branch      = extra["branch"]
        cs_tags     = tags
        type        = opts[:template_type].to_s || 'log'
        
        added   = opts[:added] || []
        removed = opts[:removed] || []
        updated = opts[:updated] || []
        config  = opts
        
        parents = useful_parents log, revision
        parents.map! {|p| [p, log.node(p)[0..5].hexlify] }
        
        p1 = useful_parents(log, revision)[0]
        p2 = useful_parents(log, revision)[1]
        
        return "" if opts[:no_output]
        
        config = opts
        
        template = opts[:template]
        template = "default-#{type}" if (template.nil? || template.to_s == "default")
    
        template = Support::Template['mercurial', template]
        template.render({}, binding)
      end
      
      def useful_parents(log, revision)
        parents = log.parent_indices_for_index revision
        if parents[1] == -1
          if parents[0] >= revision - 1
            parents = []
          else
            parents = [parents[0]]
          end
        end
        parents
      end
      
      ##
      # Commits the given changeset to the repository.
      # 
      #  commit_changeset:
      #    foreach file in commit:
      #        commit_file file
      #    end
      #    add_manifest_entry
      #    add_changelog_entry
      # Is this changeset a working changeset?
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
      def commit(opts = {:use_dirstate => true, :update_dirstate => true})
        valid = false # don't update the DirState if this is set!
        
        commit = ((modified || []) + (added || [])).sort
        remove = removed
        xtra = extra.dup
        branchname = xtra["branch"]
        text = description
        
        p1, p2 = parents.map {|p| p.node }
        c1 = repo.changelog.read(p1) # 1 parent's changeset as an array
        c2 = repo.changelog.read(p2) # 2nd parent's changeset as an array
        m1 = repo.manifest.read(c1[0]).dup # 1st parent's manifest
        m2 = repo.manifest.read(c2[0])     # 2nd parent's manifest
        
        if opts[:use_dirstate]
          oldname = c1[5]["branch"]
          tests = [ commit.empty?, remove.empty?, ! opts[:force],
                    p2 == NULL_ID, branchname == oldname ]
          
          if tests.all?
            UI::status "nothing changed"
            return nil
          end
        end
        
        xp1 = p1.hexlify
        xp2 = p2 == NULL_ID ? "" : p2.hexlify
        
        Hook.run_hook :pre_commit
        journal = Amp::Mercurial::Journal.new(:opener => repo.store_opener)
  
        fresh    = {} # new = reserved haha i don't know why someone wrote "haha"
        changed  = []
        link_rev = repo.size
        
        (commit + (remove || [])).each {|file| UI::status file }
        
        # foreach file in commit:
        #     commit_file file
        # end
        commit.each do |file|
          versioned_file = self[file]
          fresh[file]    = versioned_file.commit :manifests     => [m1, m2],
                                                 :link_revision => link_rev,
                                                 :journal       => journal ,
                                                 :changed       => changed
          
          new_flags = versioned_file.flags
          
          # TODO
          # Clean this shit up
          if [ changed.empty? || changed.last != file, 
               m2[file] != fresh[file]
             ].all?
            changed << file if m1.flags[file] != new_flags
          end
          m1.flags[file] = new_flags
          
          repo.staging_area.normal file if opts[:use_dirstate]
        end
        
        #    add_manifest_entry
        man_entry, updated, added = *add_manifest_entry(:manifests  => [m1, m2],
                                                        :changesets => [c1, c2],
                                                        :journal    => journal ,
                                                        :link_rev   => link_rev,
                                                        :fresh      => fresh   ,
                                                        :remove     => remove  ,
                                                        :changed    => changed )

        #    get_commit_text
        text = get_commit_text text, :added   => added,   :updated => updated,
                                     :removed => removed, :user    => user   ,
                                     :empty_ok     => opts[:empty_ok]        ,
                                     :use_dirstate => opts[:use_dirstate]
        
        # atomically write to the changelog
        #    add_changelog_entry
        # for the unenlightened, rents = 'rents = parents
        new_rents = add_changelog_entry :manifest_entry => man_entry,
                                        :files   => (changed + removed),
                                        :text    => text,
                                        :journal => journal,
                                        :parents => [p1, p2],
                                        :user    => user,
                                        :date    => date,
                                        :extra   => xtra
        
        # Write the dirstate if it needs to be updated
        # basically just bring it up to speed
        if opts[:use_dirstate] || opts[:update_dirstate]
          repo.dirstate.parents = new_rents
          removed.each {|f| repo.dirstate.forget(f) } if opts[:use_dirstate]
          repo.dirstate.write
        end
        
        # The journal and dirstates are awesome. Leave them be.
        valid = true
        journal.close
        
        # if an error and we've gotten this far, then the journal is complete
        # and it deserves to stay (if an error is thrown and journal isn't nil,
        # the rescue will destroy it)
        journal = nil
        
        # Run any hooks
        Hook.run_hook :post_commit, :added => added, :modified => updated, :removed => removed, 
                                    :user  => user,  :date     => date,    :text    => text,
                                    :revision => repo.changelog.index_size
        return new_rents
      rescue StandardError => e
        if !valid
          repo.dirstate.invalidate!
        end
        if e.kind_of?(AbortError)
          UI::warn "Abort: #{e}"
        else
          UI::warn "Got exception while committing. #{e}"
          UI::warn e.backtrace.join("\n")
        end
        
        # the journal is a vestigial and incomplete file.
        # destroyzzzzzzzzzzz
        journal.delete if journal
      end
      
      ##
      # Add an entry to the changelog (the final receipt of the commit).
      # 
      # @param [Hash] opts
      # @return [String] the changelog id as to where the revision is in
      #   the changelog
      def add_changelog_entry(opts={})
        repo.changelog.delay_update 
        new_parents = repo.changelog.add opts[:manifest_entry],
                                         opts[:files],
                                         opts[:text],
                                         opts[:journal],
                                         opts[:parents][0],
                                         opts[:parents][1],
                                         opts[:user],
                                         opts[:date],
                                         opts[:extra]
  
        repo.changelog.write_pending
        repo.changelog.finalize opts[:journal]
        new_parents
      end
      
      ##
      # Get the commit text. Ask for it if none is given.
      # 
      # @param [String, NilClass] text (optional) the commit message
      # @param [Hash] opts
      def get_commit_text(text=nil, opts={})
        user = opts.delete :user
        
        unless opts[:empty_ok] || (text && !text.empty?)
          edit_text = to_templated_s :added   => added,   :updated       => modified,
                                     :removed => removed, :template_type => :commit
          text = UI::edit edit_text, user
        end
        
        lines = text.rstrip.split("\n").map {|r| r.rstrip }.reject {|l| l.empty? }
        raise abort("empty commit message") if lines.empty? && opts[:use_dirstate]
        lines.join("\n")
      end
      
      def add_manifest_entry(opts={})
        # changed, m1, m2, c1, c2, fresh, remove, journal, link_rev
        updated, added = [], []
        
        fresh   = opts[:fresh]
        remove  = opts[:remove]
        changed = opts[:changed]
        
        changesets = opts[:changesets]
        manifests  = opts[:manifests]
        
        changed.sort.each do |file|
          if manifests[0][file] || manifests[1][file]
            updated << file
          else
            added << file
          end
        end
        
        manifests[0].merge! fresh
        
        remove.sort!
        remove.reject! {|f| not manifests[0][f] }
        remove.each {|f| manifests[0].delete f }
        
        UI::debug "before adding manifest entry"
        
        # sorry for making this destructive
        # but it's clean and memory efficient
        # GHC's GC goes like 3 times per second, so STFU
        # I don't have that kind of luxury
        fresh.replace fresh.inject([]) {|a, (k, v)| v ? a << k : a }
        man_entry = repo.manifest.add manifests[0], opts[:journal],
                                      opts[:link_rev], changesets[0][0], changesets[1][0], [fresh, remove]
        [man_entry, updated, added]
      end
      
      ##
      # @return [Boolean] is the changeset representing the working directory?
      def working?
        false
      end
      
      ##
      # Gives an easier way to digest this changeset while reminding us it's a
      # changeset
      def inspect
        "#<Changeset #{to_s}>"
      end
      
      ##
      # Hash function for putting these bad boys in hashes
      # 
      # @return [Integer] a hash value.
      def hash
        return @revision.hash if @revision
        return object_id
      end
      
      ##
      # Compares 2 changesets so we can sort them and whatnot
      # 
      # @param [Changeset] other a changeset we will compare against
      # @return [Integer] -1, 0, or 1. Typical comparison.
      def <=>(other)
        return 0 if @revision.nil? || other.revision.nil?
        @revision <=> other.revision
      end
      
      ##
      # Are we a null revision?
      # @return [Boolean] null?
      def nil?
       @revision != NULL_REV
      end
      alias_method :null?, :nil?
      
      # Gets the raw changeset data for this revision. This includes
      # the user who committed it, the description of the commit, and so on.
      # Returns this: [manifest, user, [time, timezone], files, desc, extra]
      def raw_changeset
        @repo.changelog.read(@node_id)
      end
      
      ##
      # Returns the {ManifestEntry} for this revision. This will give
      # us info on any file we want, including flags such as executable
      # or if it's a link. Sizes and so on are also included.
      #
      # @return [ManifestEntry] the manifest at this point in time
      def manifest_entry
        @manifest_entry ||= @repo.manifest.read(raw_changeset[0])
      end
      
      ##
      # Provides access to all the tracked files in the changeset. Needed
      # for API compatibility.
      #
      # @return [Array<String>] all the files tracked in this changeset.
      def all_files
        return manifest_entry.files
      end
      
      ##
      # Returns the change in the manifest at this revision. I don't entirely
      # know what this is yet.
      def manifest_delta
        @manifest_entry_delta ||= @repo.manifest.read_delta(raw_changeset[0])
      end
      
      ##
      # Returns the parents of this changeset as {Changeset}s.
      #
      # @return [[Changeset]] the parents of this changeset.
      def parents
        return @parents if @parents
        
        p = @repo.changelog.parent_indices_for_index @revision
        p = [p[0]] if p[1] == NULL_REV
        
        @parents = p.map {|x| Changeset.new(@repo, x) }
      end
      
      ##
      # Returns the children of this changeset as {Changeset}s.
      #
      # @return [Array<Changeset>] the children of this changeset.
      def children
        @repo.changelog.children(node_id).map do |node|
          Changeset.new(@repo, node)
        end
      end
      
      ##
      # Iterates over each entry in the manifest entry.
      def each(&block)
        manifest_entry.sort.each(&block)
      end
      
      ##
      # Checks whether this changeset included a given file or not.
      # 
      # @param [String] file the file to lookup
      # @return [Boolean] whether the file is in this changeset's manifest
      def include?(file)
        manifest_entry[file] != nil
      end 
      
      ##
      # Gets the file with the given name, as a {VersionedFile}.
      # @param file the path to the file to retrieve
      # @return [VersionedFile] the file at this revision
      #
      def [](file)
        get_file(file)
      end
      
      ##
      # Returns the file's info, namely it's node_id and flags it may
      # have at this point in time, such as "x" for executable.
      # 
      # @param path the path to the file
      # @return [[String, String]] the [node_id, flags] pair for this file
      def file_info(path)
        if manifest_entry # have we loaded our manifest yet? if so, use that sucker
          result = [manifest_entry[path], manifest_entry.flags[path]]
          if result[0].nil?
            return [NULL_ID, '']
          else
            return result
          end
        end
        if manifest_delta || files[path] # check if it's in the delta... i dunno
          if manifest_delta[path]
            return [manifest_delta[path], manifest_delta.flags[path]]
          end
        end
        # Give us, just look it up the long way in the manifest. not fun. slow.
        node, flag = @repo.manifest.find(raw_changeset[0], path)
        if node.nil?
          return [NULL_ID, '']
        end
        return [node, flag]
      end
      
      ##
      # Gets the flags for the file at the given path at this revision.
      # @param path the path to the file in question
      # @return [String] the flags for the file, such as "x", "l", or "".
      #
      def flags(path)
        info = file_info(path)[1]
        return "" if info.nil?
        info
      end
      
      ##
      # Gets the node_id in the manifest_entry for the file at this path, for this
      # specific revision.
      # 
      # @param path the path to the file
      # @return [String] the node's ID in the manifest_entry, which we'll use every
      #   where we need a node_id.
      def file_node(path)
        file_info(path).first[0..19]
      end
      
      ##
      # Creates a versioned file for the file at the given path, for the frame
      # of reference of this revision.
      # @param path the path to the file
      # @param [String] file_id the node_id, to save us some computation
      # @param [FileLog] file_log the file_log to use, again to save us computation
      # @return [VersionedFile] the file at this revision.
      #
      def get_file(path, file_id = nil, file_log = nil)
        file_id = file_node(path) if file_id.nil?
        VersionedFile.new(@repo, path, :file_id => file_id, :changeset => self,
                                       :file_log => file_log)
      end
      #accessors
      # revision index
      def revision; @revision; end
      alias_method :rev, :revision
      # node_id
      def node_id; @node_id; end
      # @see node_id
      alias_method :node, :node_id
      # our node_id in sexy hexy
      def hex; @node_id.hexlify; end
      # the user who committed me!
      def user; raw_changeset[1]; end
      # the date i was committed!
      def date; raw_changeset[2]; end
      def easy_date; Time.at(raw_changeset[2].first); end
      # the files affected in this commit!
      def altered_files; raw_changeset[3]; end
      # pre-API compatibility
      alias_method :files, :altered_files
      
      # the message with this commit
      def description; raw_changeset[4]; end
      # What branch i was committed onto
      def branch 
        extra["branch"] 
      end
      # Any extra stuff I've got in me
      def extra; raw_changeset[5]; end
      # tags
      def tags; @repo.tags_for_node node; end
      
      ##
      # recursively walk
      # 
      # @param [Amp::Matcher] match this is a custom object that knows files
      #   magically. Not your grampa's proc!
      def walk(match) # calls DirState#walk
        # just make it so the keys are there
        results = []
        
        hash = Hash.with_keys match.files
        hash.delete '.'
        
        each do |file|
          hash.each {|f, val| (hash.delete file and break) if f == file }
          
          results << file if match.call file # yield file if match.call file
        end
        
        hash.keys.sort.each do |file|
          if match.bad file, "No such file in revision #{revision}" and match[file]
            results << file # yield file
          end
        end
        results
      end
      
      def ancestor(other_changeset)
        node = @repo.changelog.ancestor(self.node, other_changeset.node)
        return Changeset.new(@repo, node)
      end
      
      def ancestors
        results = []
        @repo.changelog.ancestors(revision)
      end
    end
    
    ##
    # This is a special changeset that specifically works within the
    # working directory. We sort of have to combine the old revision
    # logs with the fact that files might be changed, and not in the
    # revision logs! oh, mercy!
    class WorkingDirectoryChangeset < Changeset
      
      def initialize(repo, opts={:text => ""})
        @repo = repo
        @revision = nil
        @parents = nil
        @node_id  = nil
        @text = opts[:text]
        require 'time' if opts[:date].kind_of?(String)
        @date = opts[:date].kind_of?(String) ? Time.parse(opts[:date]) : opts[:date]
        @user = opts[:user] if opts[:user]
        @parents = opts[:parents].map {|p| Changeset.new(@repo, p)} if opts[:parents]
        @status = opts[:changes] if opts[:changes]
        @manifest = nil
        @extra = opts[:extra] ? opts[:extra].dup : {}
        unless @extra["branch"]
          branch = @repo.dirstate.branch
          # encoding - to UTF-8
          @extra["branch"] = branch
        end
        @extra["branch"] = "default" if @extra["branch"] && @extra["branch"].empty?
        
      end
      
      ##
      # Is this changeset a working changeset?
      #
      # @return [Boolean] is the changeset representing the working directory?
      def working?
        true
      end
      
      ##
      # Converts to a string.
      # I'm my first parent, plus a little extra.
      # "I am my own grandpa"
      # 
      # @return [String]
      def to_s
        parents.first.to_s + "+"
      end
      
      
      ##
      # Do I include a given file? (not sure this is ever used yet)
      def include?(key)
        status = @repo.staging_area.file_status(key)
        ![:unknown, :removed].include?(status)
      end
      
      def all_files
        repo.staging_area.all_files
      end
      
      ##
      # Am I nil? never!
      def nil?; false; end
      
      ##
      # What is the status of the working directory? This little
      # method hides quite a bit of work!
      def status
        @status ||= @repo.status(:unknown => true)
      end
      
      ##
      # Who is the user working on me?
      def user 
        @user ||= @repo.config.username
      end
      
      ##
      # Well, I guess the working directory's date is... right now!
      def date
        @date ||= Time.new
      end
      
      ##
      # Who is the working directory's father? Is it Chef? Mr. Garrison?
      # the 1989 denver broncos?
      #
      # hahaha mike that's hilarious
      def parents
        return @parents if @parents
        p = @repo.dirstate.parents
        p = [p[0]] if p[1] == NULL_ID
        @parents = p.map {|x| Changeset.new(@repo, x) }
        @parents
      end
      
      ##
      # OK, so we've got the last revision's manifest entry, that part's simple and makes sense.
      # except now, we need to get the status of the working directory, and
      # add in all the other files, because they're in the "manifest entry" by being
      # in existence. Oh, and we need to remove any files from the parent's
      # manifest entry that don't exist anymore. Make sense?
      def manifest_entry
        return @manifest_entry if @manifest_entry ||= nil
        
        # Start off with the last revision's manifest_entry, that's safe.
        man = parents()[0].manifest_entry.dup
        # Any copied files since the last revision?
        copied = @repo.dirstate.copy_map
        # Any modified, added, etc files since the last revision?
        modified, added, removed  = status[:modified], status[:added], status[:removed]
        deleted, unknown          = status[:deleted], status[:unknown]
        # Merge these discoveries in!
        {:a => added, :m => modified, :u => unknown}.each do |k, list|
          list.each do |file|
            copy_name = (copied[file] || file)
            man[file] = (man.flags[copy_name] || NULL_ID) + k.to_s
            man.flags[file] = @repo.dirstate.flags(file)
          end
        end
        
        # Delete files from the real manifest entry that don't exist.
        (deleted + removed).each do |file|
          man.delete file if man[file]
        end
        
        man
      end
      
      ##
      # Returns a {VersionedWorkingFile} to represent the file at the given
      # point in time. It represents a file in the working directory, which
      # obvious don't read from the history, but from the actual file in
      # question.
      # 
      # @param path the path to the file
      # @param file_log the log for the file to save some computation
      # @return [Amp::VersionedWorkingFile] the file object we can work with
      def get_file(path, file_log=nil)
        VersionedWorkingFile.new(@repo, path, :working_changeset => self, 
                                              :file_log => file_log)
      end
      
      ##
      # Gets the flags for the file at current state in time
      # 
      # @param [String] path the path to the file
      # @return [String] the flags, such as "x", "l", or ""
      def flags(path)
        if @manifest_entry ||= nil
          return manifest_entry.flags[path] || ""
        end
        pnode = parents[0].raw_changeset[0]
    
        orig = @repo.dirstate.copy_map[path] || path
        node, flag = @repo.manifest.find(pnode, orig)
        return @repo.dirstate.flags(@repo.working_join(path))
      end
      
      def useful_parents(log, revision)
        parents = @parents.map {|p| p.revision}
        if parents[1] == -1
          if parents[0] >= @repo.size - 1
            parents = []
          else
            parents = [parents[0]]
          end
        end
        parents
      end
      
      ##
      # Recursively walk the directory tree, getting all files that +match+ says
      # are good.
      # 
      # @param [Amp::Match] match how to select the files in the tree
      # @param [Boolean] check_ignored (false) should we check for ignored files?
      # @return [Array<String>] an array of filenames in the tree that match +match+
      def walk(match, check_ignored = false)
        tree = @repo.staging_area.walk true, check_ignored, match
        tree.keys.sort
      end
      
      # If there's a description, ok then
      def description; @text; end
      # Files affected in this transaction: modified, added, removed.
      def files; (status[:modified] + status[:added] + status[:removed]).sort; end
      # What files have changed?
      def modified; status[:modified]; end
      # What files have we added?
      def added; status[:added]; end
      # What files have been removed?
      def removed; status[:removed]; end
      # What files have been deleted (but not officially)?
      def deleted; status[:deleted]; end
      # What files are hanging out, but untracked?
      def unknown; status[:unknown]; end
      # What files are pristine since the last revision?
      def clean; status[:normal]; end
      # What branch are we in?
      def branch; @extra["branch"]; end
      # Any other extra data? i'd like to hear it
      def extra; @extra; end
      # No children. Returns the empty array.
      def children; []; end
    end
  end
end