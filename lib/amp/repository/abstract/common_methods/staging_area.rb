module Amp
  module Repositories
    
    ##
    # = CommonStagingAreaMethods
    #
    # These methods are common to all staging areas, and this module is mixed into
    # the AbstractStagingArea class. This guarantees that all staging areas will
    # have these methods.
    #
    # No methods should be placed into this module unless it relies on methods in the
    # general API for staging areas.
    module CommonStagingAreaMethods
      
      ##
      # Returns whether or not the repository is tracking the given file.
      #
      # @api
      # @param [String] filename the file to look up
      # @return [Boolean] are we tracking the given file?
      def tracking?(filename)
        file_status(filename) != :untracked
      end
      
      ##
      # Helper method that filters out a list of explicit filenames that do not
      # belong in the repository. It then stores the File stats of the files
      # it keeps, and returns any explicitly named directories.
      #
      # @param [Array<String>] files the files to examine
      # @param [Amp::Match] match the matcher object
      # @return [Array<Hash, Array<String>>] returns an array: [file_stats, directories]
      def examine_named_files(files, match)
        results, work = {vcs_dir => true}, [] # ignore the .hg
        files.reject {|f| results[f] || f == ""}.sort.each do |file|
          path  = File.join(repo.root, file)
          
          if File.exist?(path)
            # we'll take it! but only if it's a directory, which means we have
            # more work to do...
            if File.directory?(path)
              # add it to the list of dirs we have to search in
              work << File.join(repo.root, file) unless ignoring_directory? file
            elsif File.file?(path) || File.symlink?(path)
              # ARGH WE FOUND ZE BOOTY
              results[file] = File.lstat path
            else
              # user you are a fuckup in life please exit the world
              UI::warn "#{file}: unsupported file type (type is #{File.ftype file})"
              results[file] = nil if tracking? file
            end
          else
            prefix = file + '/'
            
            unless all_files.find { |f, _| f == file || f.start_with?(prefix) }
              bad_type[file]
              results[file] = nil if (tracking?(file) || !ignoring_file?(file)) && match.call(file)
            end
          end
        end
        [results, work]
      end
      
      ##
      # Helper method that runs match's patterns on every non-ignored file in
      # the repository's directory.
      #
      # @param [Hash] found_files the already found files (we don't want to search them
      #   again)
      # @param [Array<String>] dirs the directories to search
      # @param [Amp::Match] match the matcher object that runs patterns against
      #   filenames
      # @return [Hash] the updated found_files hash
      def find_with_patterns(found_files, dirs, match)
        results = found_files
        Find.find(*dirs) do |f|
          tf = f[(repo.root.size+1)..-1]
          Find.prune if results[tf]
          
          stats = File.lstat f
          match_result = match.call tf
          tracked = tracking? tf
          
          if File.directory? f
            Find.prune if ignoring_file? tf
            results[tf] = nil if tracked && match_result
          elsif File.file?(f) || File.symlink?(f)
            if match_result && (tracked || !ignoring_file?(tf))
              results[tf] = stats
            end
          elsif tracked && match_result
            results[tf] = nil
          end
        end
        results
      end
      
      ##
      # Walk recursively through the directory tree, finding all
      # files matched by the regexp in match.
      # 
      # Step 1: find all explicit files
      # Step 2: visit subdirectories
      # Step 3: report unseen items in the @files hash
      # 
      # @todo this is still tied to hg
      # @param [Boolean] unknown
      # @param [Boolean] ignored
      # @return [Hash<String => [NilClass, File::Stat]>] nil for directories and
      #   stuff, File::Stat for files and links
      def walk(unknown, ignored, match = Amp::Match.new { true })
        if ignored
          @ignore_all = false
        elsif not unknown
          @ignore_all = true
        end
        
        files = (match.files || []).uniq
        
        # why do we overwrite the entire array if it includes the current dir?
        # we even kill posisbly good things
        files = [''] if files.include?('.') # strange thing to do
        
        # Step 1: find all explicit files
        results, found_directories = examine_named_files files, match
        work = [repo.root] + found_directories
        
        # Run the patterns
        results = find_with_patterns(results, work, match)
        
        # step 3: report unseen items in @files
        visit = all_files.select {|f| !results[f] && match.call(f) }.sort
        
        visit.each do |file|
          path = File.join(repo.root, file)
          keep = File.exist?(path) && (File.file?(path) || File.symlink(path))
          results[file] = keep ? File.lstat(path) : nil
        end
        
        results.delete vcs_dir
        @ignore_all = nil # reset this
        results
      end
      
      ##
      # what's the current state of life, man!
      # Splits up all the files into modified, clean,
      # added, deleted, unknown, ignored, or lookup-needed.
      # 
      # @param [Boolean] ignored do we collect the ignore files?
      # @param [Boolean] clean do we collect the clean files?
      # @param [Boolean] unknown do we collect the unknown files?
      # @param [Amp::Match] match the matcher
      # @return [Hash<Symbol => Array<String>>] a hash of the filestatuses and their files
      def status(ignored, clean, unknown, match = Match.new { true })
        list_ignored, list_clean, list_unknown = ignored, clean, unknown
        lookup, modified, added, unknown, ignored = [], [], [], [], []
        moved, copied, removed, deleted, clean = [], [], [], [], []
        delta = 0
      
        walk(list_unknown, list_ignored, match).each do |file, st|
          next if file.nil?
          
          unless tracking?(file)
            if list_ignored && ignoring_directory?(file)
              ignored << file
            elsif list_unknown
              unknown << file unless ignoring_file?(file)
            end
          
            next # on to the next one, don't do the rest
          end
        
          # here's where we split up the files
          state = file_status file
          
          delta += calculate_delta(file, st)
          if !st && [:normal, :modified, :added].include?(state)
            # add it to the deleted folder if it should be here but isn't
            deleted << file
          elsif state == :normal
            case file_precise_status(file, st)
            when :modified
              modified << file
            when :lookup
              lookup << file
            when :clean
              clean << file if list_clean
            end
          
          elsif state == :merged
            modified << file
          elsif state == :added
            added << file
          elsif state == :removed
            removed << file
          end
        end
        
        # # This code creates the copied and moved arrays
        # # 
        # # ugh this should be optimized
        # # as in, built into the code above ^^^^^
        # dirstate.copy_map.each do |dst, src|
        #   # assume that if +src+ is in +removed+ then +dst+ is in +added+
        #   # we know that this part will be COPIES
        #   if removed.include? src
        #     removed.delete src
        #     added.delete   dst
        #     copied << [src, dst]
        #   elsif added.include? dst # these are the MOVES
        #     added.delete dst
        #     moved << [src, dst]
        #   end
        # end
      
        r = { :modified => modified.sort , # those that have clearly been modified
              :added    => added.sort    , # those that are marked for adding
              :removed  => removed.sort  , # those that are marked for removal
              :deleted  => deleted.sort  , # those that should be here but aren't
              :unknown  => unknown.sort  , # those that aren't being tracked
              :ignored  => ignored.sort  , # those that are being deliberately ignored
              :clean    => clean.sort    , # those that haven't changed
              :lookup   => lookup.sort   , # those that need to be content-checked to see if they've changed
              #:copied   => copied.sort_by {|a| a[0] }, # those that have been copied
              #:moved    => moved.sort_by  {|a| a[0] }, # those that have been moved
              :delta    => delta           # how many bytes have been added or removed from files (not bytes that have been changed)
            }
      end
    end
  end
end