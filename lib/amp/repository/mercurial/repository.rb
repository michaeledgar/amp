module Amp
  module Repositories
    class RepositoryCapabilityError < StandardError; end
    
    module Mercurial
      
      ##
      # This module is necessary so that we have a hook for autoload.
      # It is quite unfortunate, really, because the one public method
      # that this module provides could easily belong to Mercurial.
      # But it doesn't. C'est la vie.
      class MercurialPicker < GenericRepoPicker
        
        def self.pick(config, path='', create=false)
          # hot path so we don't load the HTTP repos!
          unless path[0,4] == "http"
            return LocalRepository.new(find_repo(path), create, config)
          end
          return HTTPSRepository.new(path, create, config) if path[0,5] == "https"
          return HTTPRepository.new(path, create, config)  if path[0,4] == "http"
        end
        
        def self.repo_in_dir?(path)
          while !(File.directory?(File.join(path, ".hg")))
            old_path, path = path, File.dirname(path)
            if path == old_path
              return false
            end
          end
          true
        end
        
        ################################
        private
        ################################
        def self.find_repo(path)
          while !(File.directory?(File.join(path, ".hg")))
            old_path, path = path, File.dirname(path)
            if path == old_path
              raise "No Repository Found"
            end
          end
          path
        end
      end
      
      ##
      # = Repository
      # This is an abstract class that represents a repository for Mercurial.
      # All repositories must inherit from this class.
      class Repository < AbstractLocalRepository
        
        ##
        # Is this repository capable of the given action/format? Or, if the capability
        # has a value assigned to it (like "revlog" = "version2"), what is it?
        # 
        # @param [String] capability the name of the action/format/what have you that we need to test
        # @return [Boolean, String] whether or not we support the given capability; or, for
        #   capabilities that have a value, the string value.
        def capable?(capability)
          get_capabilities
          @capabilities[capability]
        end
        
        ##
        # No-op, to be implemented by remote repo classes.
        def get_capabilities; end
        
        ##
        # Raises an exception if we don't have a given capability.
        # 
        # @param [String] capability what capability we are requiring
        # @param [String] purpose why we need it - enhances the output
        # @raise [RepositoryCapabilityError] if we don't support it, this is raised
        def require_capability(capability, purpose)
          get_capabilities
          raise RepositoryCapabilityError.new(<<-EOF
          Can't #{purpose}; remote repository doesn't support the #{capability} capability.
          EOF
          ) unless @capabilities[capability]
        end
        
        ##
        # is the repository a local repo?
        # 
        # @return [Boolean] is the repository local?
        def local?
          false
        end
        
        ##
        # can we copy files? Only for local repos.
        # 
        # @return [Boolean] whether we are able to copy files
        def can_copy?
          local?
        end
        
        ##
        # Joins the given path with our URL. Necessary due to the difference between local
        # and remote repos.
        # 
        # @param [String] path the path we are appending
        # @return [String] our URL joined with the requested path
        def add_path(path)
          myurl = self.url
          if myurl.end_with? '/'
            myurl + path
          else
            myurl + '/' + path
          end
        end
      end
    end
  end
end