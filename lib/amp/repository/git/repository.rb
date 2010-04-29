module Amp
  module Repositories    
    module Git
      
      class GitPicker < GenericRepoPicker
        
        def self.pick(config, path='', create=false)
          # hot path so we don't load the HTTP repos!
          unless path[0,4] == "http"
            return LocalRepository.new(find_repo(path), create, config)
          end
          raise "Unknown repository format for Git"
        end
        
        def self.repo_in_dir?(path)
          return true if path[0, 4] == "http"
          until File.directory? File.join(path, ".git")
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
          until File.directory? File.join(path, ".git")
            old_path, path = path, File.dirname(path)
            if path == old_path
              raise "No Repository Found"
            end
          end
          path
        end
      end
    end
  end
end
