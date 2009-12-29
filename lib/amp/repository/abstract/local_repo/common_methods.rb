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
      # Iterates over each changeset in the repository, from oldest to newest.
      # 
      # @yield each changeset in the repository is yielded to the caller, in order
      #   from oldest to newest. (Actually, lowest revision # to highest revision #)
      def each(&block)
        0.upto(size - 1) { |i| yield self[i]}
      end
    end
    
  end
end