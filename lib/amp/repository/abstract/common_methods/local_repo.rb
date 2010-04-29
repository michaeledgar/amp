module Amp
  module Repositories
    
    ##
    # = CommonLocalRepoMethods
    #
    # These methods are common to all repositories, and this module is mixed into
    # the AbstractLocalRepository class. This guarantees that all repositories will
    # have these methods.
    #
    # No methods should be placed into this module unless it relies on methods in the
    # general API for repositories.
    module CommonLocalRepoMethods
      
      attr_accessor :config
      
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
        @root         = File.expand_path path.chomp("/")
        @config       = config
      end
      
      ##
      # Initializes a new repository in the given directory. We recommend
      # calling this at some point in your repository subclass as it will 
      # do amp-specific initialization, though you will need to do all the
      # hard stuff yourself.
      def init(config=@config)
        FileUtils.makedirs root
        working_write "Ampfile", <<-EOF
# Any ruby code here will be executed before Amp loads a repository and
# dispatches a command.
#
# Example command:
#
# command "echo" do |c|
#    c.opt :"no-newline", "Don't print a trailing newline character", :short => "-n"
#    c.on_run do |opts, args|
#        print args.join(" ")
#        print "\\n" unless opts[:"no-newline"]
#    end
# end
EOF
        
      end
      
      ##
      # Joins the path to the repo's root (not .hg, the working dir root)
      # 
      # @param path the path we're joining
      # @return [String] the path joined to the working directory's root
      def working_join(path)
        File.join(root, path)
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
        staging_area.add(*paths)
      end
      
      ##
      # Removes the file (or files) from the repository. Marks them as removed
      # in the DirState, and if the :unlink option is provided, the files are
      # deleted from the filesystem.
      #
      # @param list the list of files. Could also just be 1 file as a string.
      #   should be paths.
      # @param opts the options for this removal. Must be last argument or will mess
      #   things up.
      # @option [Boolean] opts :unlink (false) whether or not to delete the
      #   files from the filesystem after marking them as removed from the
      #   DirState.
      # @return [Boolean] success?
      def remove(*args)
        staging_area.remove(*args)
      end
      
      def relative_join(file, cur_dir=FileUtils.pwd)
        @root_pathname ||= Pathname.new(root)
        Pathname.new(File.expand_path(File.join(cur_dir, file))).relative_path_from(@root_pathname).to_s
      end
      
      ##
      # Walk recursively through the directory tree (or a changeset)
      # finding all files matched by the match function
      # 
      # @param [String, Integer] node selects which changeset to walk
      # @param [Amp::Match] match the matcher decides how to pick the files
      # @param [Array<String>] an array of filenames
      def walk(node=nil, match = Match.create({}) { true })
        self[node].walk match # calls Changeset#walk
      end
      
      ##
      # Iterates over each changeset in the repository, from oldest to newest.
      # 
      # @yield each changeset in the repository is yielded to the caller, in order
      #   from oldest to newest. (Actually, lowest revision # to highest revision #)
      def each(&block)
        0.upto(size - 1) { |i| yield self[i] }
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
      # @option [Boolean] opts :delta (false) do we want to see the overall delta?
      # @return [Hash<Symbol => Array<String>>] no, I'm not kidding. the keys are:
      #   :modified, :added, :removed, :deleted, :unknown, :ignored, :clean, and :delta. The
      #   keys are the type of change, and the values are arrays of filenames
      #   (local to the root) that are under each key.
      def status(opts={:node_1 => '.'})
        run_hook :status
        
        opts[:delta] ||= true
        node1, node2, match = opts[:node_1], opts[:node_2], opts[:match]
        
        match = Match.create({}) { true } unless match
        
        node1 = self[node1] unless node1.kind_of? Repositories::AbstractChangeset # get changeset objects
        node2 = self[node2] unless node2.kind_of? Repositories::AbstractChangeset
        
        # are we working with working directories?
        working = node2.working?
        comparing_to_tip = working && node2.parents.include?(node1)
        
        status = Hash.new {|h, k| h[k] = k == :delta ? 0 : [] }
        
        if working
          # get the dirstate's latest status
          status.merge! staging_area.status(opts[:ignored], opts[:clean], opts[:unknown], match)
          
          # this case is run about 99% of the time
          # do we need to do hashes on any files to see if they've changed?
          if comparing_to_tip && status[:lookup].any?
            clean, modified = fix_files(status[:lookup], node1, node2)
            
            status[:clean].concat clean
            status[:modified].concat modified
          end
        end
        # if we're working with old revisions...
        unless comparing_to_tip
          # get the older revision manifest            
          node1_file_list = node1.all_files.dup
          node2_file_list = node2.all_files.dup
          if working
            # remove any files we've marked as removed them from the '.' manifest
            status[:removed].each {|file| node2_file_list.delete file }
          end
          
          # Every file in the later revision (or working directory)
          node2.all_files.each do |file|
            # Does it exist in the old manifest? If so, it wasn't added.
            if node1.include? file
              # It's in the old manifest, so lets check if its been changed
              # Else, it must be unchanged
              if file_modified? file, :node1 => node1, :node2 => node2 # tests.any?
                status[:modified] << file
              elsif opts[:clean]
                status[:clean]    << file
              end
              # Remove that file from the old manifest, since we've checked it
              node1_file_list.delete file
            else
              # if it's not in the old manifest, it's been added
              status[:added] << file
            end
          end
          
          # Anything left in the old manifest is a file we've removed since the
          # first revision.
          status[:removed] = node1_file_list
        end
        
        # We're done!
        status.delete :lookup # because nobody cares about it
        delta = status.delete :delta
        
        status.each {|k, v| v.sort! } # sort dem fuckers
        status[:delta] = delta if opts[:delta]
        status.each {|k, _| status.delete k if opts[:only] && !opts[:only].include?(k) }
        status
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
      # @return [[String], [String]] clean files and modified files
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
            staging_area.normal *fixup  
            fixup.each do |file|
              modified.delete file
            end
          end
        rescue LockError
        end
        
        # the fixups are actually clean
        [fixup, modified]
      end
    end
    
  end
end