module Amp
  module Repositories
    
    ##
    # This class is a generic "repo picker". It will return a Repository object
    # for the given path (if there is one), and is capable of telling you if there
    # is a repository of its type in the given directory.
    #
    # Amp started off with a MercurialPicker - it knows how to find Mercurial repos.
    #
    # When amp runs, it iterates over all subclasses of AbstractRepoPicker, in no
    # guaranteed order (so don't stomp on existing pickers!), calling #repo_in_dir? .
    # If only one picker returns +true+, then that picker is used for opening the
    # repository. If more than one returns +true+, the user's configuration is consulted.
    # If nothing is found then, then the user is prompted. When the final picker has been
    # chosen, its #pick method is called to get the repository for the directory/URL.
    #
    # This is an "abstract" class, in that all the methods will raise a NotImplementedError
    # if you try to call them.
    #
    # You must subclass this class, or your custom repo code will be ignored by Amp's
    # dispatch system.
    class GenericRepoPicker
      @all_pickers = []
      class << self
        include Enumerable
        attr_accessor :all_pickers
        ##
        # Returns whether or not there is a repository in the given directory. This
        # picker should only be responsible for one type of repository - git, svn, hg,
        # etc. The given path could be deep inside a repository, and must look in parent
        # directories for the root of the VCS repository.
        #
        # @param [String] path the path in which to search for a repository
        # @return [Boolean] is there a repository in this directory (or parent directories)?
        def repo_in_dir?(path)
          raise NotImplementedError.new("repo_in_dir? must be implemented in a concrete subclass.")
        end
        alias_method :repo_in_url?, :repo_in_dir?
        
        ##
        # Returns a repository object for the given path. Should respond to the standard repository
        # API to the best of its ability, and raise a CapabilityError if asked to do something it
        # cannot do from the API.
        #
        # @param [AmpConfig] config the configuration of the current environment, loaded from
        #   appropriate configuration files
        # @param [String] path the path/URL in which to open the repository.
        # @param [Boolean] create should a repository be created in the given directory/URL?
        # @return [AbstractLocalRepository] the repository for the given URL
        def pick(config, path = '', create = false)
          raise NotImplementedError.new("repo_in_dir? must be implemented in a concrete subclass.")
        end
        
        ##
        # Iterate over every RepoPicker in the system.
        def each(*args, &block)
          @all_pickers.each(*args, &block)
        end
        
        private
        
        def inherited(subclass)
          all_pickers << subclass
        end
      end
    end
  end
end