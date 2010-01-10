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
          File.amp_directories_to(path).each do |p|
            return true if File.directory? File.join(p, ".git")
          end
          false
        end
        
        ################################
        private
        ################################
        def self.find_repo(path)
          res = File.amp_directories_to(path).detect do |p|
            File.directory? File.join(p, ".git")
          end
          res || raise("No repository found for Git")
        end
      end
    end
  end
end
