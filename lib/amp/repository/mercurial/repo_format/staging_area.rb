module Amp
  module Repositories
    module Mercurial
      class StagingArea < AbstractStagingArea
        attr_reader :dirstate

        def initialize(repo)
          @ignore_all = false
          @repo = repo
          @check_exec = false
        end
        
        ######### API Methods #################################################
        
        ##
        # Adds a list of file paths to the repository for the next commit.
        # 
        # @api
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
        # @api
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
        # Set +file+ as normal and clean. Un-removes any files marked as removed, and
        # un-adds any files marked as added.
        # 
        # @param  [Array<String>] files the name of the files to mark as normal
        # @return [Boolean] success marker
        def normal(*files)
          files.each do |file|
            dirstate.normal(file)
          end
          dirstate.write
        end
        
        ##
        # Copies a file from +source+ to +destination+, while being careful of the
        # specified options. This method will perform all necessary file manipulation
        # and dirstate changes and so forth. Just give 'er a source and a destination.
        #
        # @api
        # @param [String] source the path to the source file
        # @param [String] destination the path to the destination file
        # @param [Hash] opts the options for the copy
        # @option [Boolean] opts :after (false) should the file be deleted?
        # @return [Boolean] success?
        def copy(source, destination, opts)
          # Traverse repository subdirectories
          src    = repo.relative_join source
          target = repo.relative_join destination
          
          # Is there a tracked file at our destination? If so, get its state.
          state = dirstate[target].status
          # abstarget is the full path to the target. Needed for system calls
          # (just to be safe)
          abstarget = repo.working_join target
          
          # If true, we're copying into a directory, so be smart about it.
          if File.directory? abstarget
            abstarget = File.join abstarget, File.basename(src)
            target    = File.join target, File.basename(src)
          end
          abssrc = repo.working_join(src)
          
          
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
                add target
              end
            else
              dirstate_copy src, target
            end
          end
          
          # Clean up if we're doing a move, and not a copy.
          remove(src, :unlink => !(opts[:after])) if opts[:rename]
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
          path = repo.working_join dest
          
          if !File.exist?(path) || File.ftype(path) == 'link'
            UI::warn "#{dest} doesn't exist!"
          elsif not (File.ftype(path) == 'file' || File.ftype(path) == 'link')
            UI::warn "copy failed: #{dest} is neither a file nor a symlink"
          else
            repo.lock_working do
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
        # Marks a modified file to be included in the next commit.
        # If your VCS does this implicitly, this should be defined as a no-op.
        #
        # Mercurial: This is a no-op unless the specified files are not already
        # in the repository, so we should add them to the repo in that case.
        # 
        # @api
        # @param [[String]] filenames a list of files to include for committing
        # @return [Boolean] true for success, false for failure
        def include(*filenames)
          to_add = []
          
          filenames.each do |filename|
            unless dirstate[filename]
              to_add << filename
            end
          end
          
          add to_add if to_add.any?
        end
        
        ##
        # Returns a Symbol.
        # Possible results:
        # :added (subset of :included)
        # :removed
        # :untracked
        # :included
        # :normal
        #
        def file_status(filename)
          dirstate[filename].status
        end
        
        ##
        # Returns whether or not the repository is tracking the given file.
        #
        # @param [String] filename the file to look up
        # @return [Boolean] are we tracking the given file?
        def tracking?(filename)
          dirstate.tracking? filename
        end
        
        ##
        # Returns all files tracked by the repository *for the working directory* - not
        # to be confused with the most recent changeset.
        #
        # @return [Array<String>] all files tracked by the repository at this moment in
        #   time, including just-added files (for example) that haven't been committed yet.
        def all_files
          dirstate.all_files
        end
        
        ######### Optional API Methods ########################################
        
        ##
        # Returns whether the given directory is being ignored. Optional method - defaults to
        # +false+ at all times.
        #
        # @api-optional
        # @param [String] directory the directory to check against ignoring rules
        # @return [Boolean] are we ignoring this directory?
        def ignoring_directory?(directory)
          return true  if @ignore_all
          return false if @ignore_all == false
          dirstate.ignoring_directory? directory
        end

        ##
        # Returns whether the given file is being ignored. Optional method - defaults to
        # +false+ at all times.
        #
        # @api-optional
        # @param [String] file the file to check against ignoring rules
        # @return [Boolean] are we ignoring this file?
        def ignoring_file?(file)
          return true  if @ignore_all
          return false if @ignore_all == false
          dirstate.ignore file
        end
        
        ##
        # Retrives the dirstate from the staging_area. The staging area is reponsible
        # for properly maintaining the dirstate.
        #
        # @return [DirState]
        def dirstate
          return @dirstate if @dirstate ||= nil # the "||= nil" kills undefined ivar warning 
          
          opener = Amp::Opener.new repo.root
          opener.default = :open_hg
          
          @dirstate = DirState.new(repo.root, repo.config, opener)
          @dirstate.read!
        end
        
        ##
        # Calculates the difference (in bytes) between a file and its last tracked state.
        #
        # Supplements the built-in #status method so that its output will include deltas.
        #
        # @apioptional
        # @param [String] file the filename to look up
        # @param [File::Stats] st the current results of File.lstat(file)
        # @return [Fixnum] the number of bytes difference between the file and
        #  its last tracked state.
        def calculate_delta(file, st)
          state, mode, size, time = dirstate.files[file].to_a
          st && size >= 0 ? (size - st.size).abs : 0 # increase the delta, but don't forget to check that it's not nil
        end
        
        ##
        # Does a detailed look at a file, to see if it is clean, modified, or needs to have its
        # content checked precisely.
        #
        # Supplements the built-in #status method so that its output will be more
        # accurate.
        #
        # @param [String] file the filename to look up
        # @param [File::Stats] st the current results of File.lstat(file)
        # @return [Symbol] a symbol representing the current file's status
        def file_precise_status(file, st)
          state, mode, size, time = dirstate.files[file].to_a
          if (size >= 0 && (size != st.size || ((mode ^ st.mode) & 0100 and @check_exec))) || size == -2 || dirstate.copy_map[file]
            return :modified
          elsif time != st.mtime.to_i # DOH - we have to remember that times are stored as fixnums
            return :lookup
          else
            return :clean
          end
        end
        
      end
    end
  end
end