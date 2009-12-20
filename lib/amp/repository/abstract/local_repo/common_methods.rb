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