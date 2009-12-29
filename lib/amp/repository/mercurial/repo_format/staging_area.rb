module Amp
  module Repositories
    module Mercurial
      class StagingArea < AbstractStagingArea
        
        attr_reader :repo
        attr_reader :dirstate

        def initialize(repo)
          @repo = repo
        end
        
        ##
        # Adds a list of file paths to the repository for the next commit.
        # 
        # @param [String, Array<String>] paths the paths of the files we need to
        #   add to the next commit
        # @return [Array<String>] which files WEREN'T added
        def add(*files)
          rejected = []
          files.flatten!
          
          repo.lock_working do
            files.each do |file|
              path = repo.working_join file
              stat = File.exist?(path) && File.lstat(path)
              
              if !stat
                UI.warn "#{file} does not exist!"
                rejected << file
              elsif File.ftype(path) != 'file' && File.ftype(path) != 'link'
                UI.warn "#{file} not added: only files and symlinks supported. Type is #{File.ftype path}"
                rejected << path
              else
                if stat.size > 10.mb
                  UI.warn "#{file}: files over 10MB may cause memory and performance problems\n" +
                              "(use 'amp revert #{file}' to unadd the file)\n"
                end
                dirstate.add file
              end
            end
            dirstate.write unless rejected.size == files.size
          end
          rejected
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
        def remove(*args)
          list = args.last.is_a?(Hash) ? args[0..-2].flatten : args[0..-1].flatten
          opts = args.last.is_a?(Hash) ? args.last : {}
          # Should we delete the filez?
          if opts[:unlink]
              FileUtils.safe_unlink list.map {|f| repo.working_join(f)}
          end
          
          repo.lock_working do
            # Save ourselves a dirstate write
            successful = list.any? do |f|
              if opts[:unlink] && File.exists?(repo.working_join(f))
                # Uh, why is the file still there? Don't remove it from the dirstate
                UI.warn("#{f} still exists!")
                false # no success
              else
                dirstate.remove f
              end
            end
            
            # Write 'em out boss
            dirstate.write if successful
          end
          
          true
        end
        
        ##
        # Retrives the dirstate from the staging_area. The staging area is reponsible
        # for properly maintaining the dirstate.
        #
        # @return [DirState]
        def dirstate
          return @dirstate if @dirstate
          
          opener = Amp::Opener.new repo.root
          opener.default = :open_hg
          
          @dirstate = DirState.new(repo.root, repo.config, opener)
          @dirstate.read!
        end
        
      end
    end
  end
end