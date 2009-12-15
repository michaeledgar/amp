module Amp
  module Repositories
    module Mercurial
      
      ##
      # An entry in the dirstate. Similar to IndexEntry for revlogs. Simple struct, that's
      # all.
      class DirStateEntry < Struct.new(:status, :mode, :size, :mtime)
        
        ##
        # shortcuts!
        def removed?;     self.status == :removed; end
        def added?;       self.status == :added; end
        def untracked?;   self.status == :untracked; end
        def modified?;    self.status == :modified; end
        def merged?;      self.status == :merged; end
        def normal?;      self.status == :normal; end
        def forgotten?;   self.status == :forgotten; end
      
        ##
        # Do I represent a dirty object?
        #
        # @return [Boolean] does this array represent a dirty object in a DirState?
        def dirty?
          self[-2] == -2 && self[-1] == -1 && self.normal?
        end
    
        ##
        # Do I possibly represent a dirty object?
        #
        # @return [Boolean] does this array possibly represent a dirty object in a DirState?
        def maybe_dirty?
          self[-2] == -1 && self[-1] == -1 && self.normal?
        end
      end
    
      ##
      # = DirState
      # This class handles parsing and manipulating the "dirstate" file, which is stored
      # in the .hg folder. This file handles which files are marked for addition, removal,
      # copies, and so on. The structure of each entry is below.
      #
      #
      # class DirStateEntry < BitStruct
      #   default_options :endian => :network
      #   
      #   char    :status     ,  8, "the state of the file"
      #   signed  :mode       , 32, "mode"
      #   signed  :size       , 32, "size"
      #   signed  :mtime      , 32, "mtime"
      #   signed  :fname_size , 32, "filename size"
      #
      # end
      class DirState
        include Amp::Mercurial::Ignore
        include Amp::Mercurial::RevlogSupport::Node
      
        UNKNOWN = DirStateEntry.new(:untracked, 0, 0, 0)
        FORMAT  = "cNNNN"
      
        class FileNotInRootError < StandardError; end
        class AbsolutePathNeededError < StandardError; end
      
        # The parents of the current state. If there's been an uncommitted merge,
        # it will be two. Otherwise it will just be one parent and +NULL_ID+
        attr_reader :parents
      
        # The number of directories in each base ["dir" => #_of_dirs]
        attr_reader :dirs
      
        # The files mapped to their stats (state, mode, size, mtime)
        # [state, mode, size, mtime]
        attr_reader :files
      
        # A map of files to be copied, because we want to preserve their history
        # "source" => "dest"
        attr_reader :copy_map
      
        # I still don't know what this does
        attr_reader :folds
      
        # The conglomerate config object of global configs and the repo
        # specific config.
        attr_reader :config
      
        # The root of the repository
        attr_reader :root
      
        # The opener to access files. The only files that will be touched lie
        # in the .hg/ directory, so the default MUST be +:open_hg+.
        attr_reader :opener
      
        ##
        # Creates a DirState object. This is used to represent, in memory (and
        # occasionally on file) how the repository is being changed.
        # It's really simple, and it is really the basis for _using_ the repo
        # (contrary to how Revlog is the basis for _saving_ the repo).
        # 
        # @param [String] root the absolute path to the root of the repository
        # @param [Amp::AmpConfig] config the config file of hgrc
        # @param [Amp::Opener] opener the opener to open files with
        def initialize(root, config, opener)
          unless root[0, 1] == "/"
            raise AbsolutePathNeededError, "#{root} is not an absolute path!" 
          end
        
          # root must be an aboslute path with no ending slash
          @root  = root[-1, 1] == "/" ? root[0..-2] : root # the root of the repo
          @config = config # the config file where we get defaults
          @opener = opener # opener to retrieve files (default: open_hg)
          @dirty = false # has something changed, and do we need to write?
          @dirty_parents = false
          @parents = [NULL_ID, NULL_ID] # the parent revisions
          @dirs  = {} # number of directories in each base ["dir" => #_of_dirs]
          @files = {} # the files mapped to their statistics
          @copy_map = {} # src => dest
          @ignore = [] # dirs and files to ignore
          @folds = []
          @check_exec = nil
          generate_ignore
        end
      
        ##
        # Retrieve a file's status from +@files+. If it's not there
        # then return :untracked
        # 
        # @param [String] key the path of the file
        # @return [Symbol] status of the file, either :removed, :added, :untracked,
        #   :merged, :normal, :forgotten, or :untracked
        def [](key)
          lookup = @files[key]
          lookup || DirStateEntry.new(:untracked)
        end
      
        ##
        # Determine if +path+ is a link or an executable.
        # 
        # @param [String] path the path to the file
        # @return [String] either 'l' for a link and 'x' for an executable. Returns
        #   '' if neither
        def flags(path)
          return 'l' if File.ftype(path) == 'link'
          return 'x' if File.executable? path
          ''
        end
      
        ##
        # just a lil' reader to find if the repo is dirty or not
        # by dirty i mean "no longer in sync with the cache"
        # 
        # @return [Boolean] is the dirstate no longer in sync with the cache located
        #   at .hg/branch.cache
        def dirty?
          @dirty
        end
      
        ##
        # The directories and path matches that we're ignoringzorz. It will call
        # the ignorer generated by .hgignore, but only if @ignore_all is nil (really
        # only if @ignore_all isn't a Boolean value, but we set it to nil)
        # 
        # @param [String] file the path to the file that will be checked by
        #   the .hgignore file
        # @return [Boolean] whether we're ignoring the path or not
        def ignore(file)
          return true  if @ignore_all == true
          return false if @ignore_all == false
          @ignore_matches ||= parse_ignore @root, @ignore
          @ignore_matches.call file
        end
      
        ##
        # Gets the current branch.
        #
        # @return [String] the current branch in the working directory
        def branch
          text      = @opener.read('branch').strip
          @branch ||= text.empty? ? "default" : text
        rescue
          @branch   = "default"
        end
      
        ##
        # Set the branch to +branch+.
        # 
        # @param [#to_s] brnch the branch to switch to
        # @return [String] +brnch+.to_s
        def branch=(brnch)
          @branch = brnch.to_s
        
          @opener.open 'branch', 'w' do |f|
            f.puts brnch.to_s
          end
          @branch
        end
      
        ##
        # Set the parents to +p+
        # 
        # @param [Array<String>] p the parents as binary strings
        # @return [Array<String>] the parents, as will be used by the dirstate
        def parents=(p)
          @parents = if p.is_a? Array
                       p.size == 1 ? p + [NULL_ID] : p[0..1]
                     else
                       [p, NULL_ID]
                     end
        
          @dirty_parents = true
          @dirty         = true
          @parents # return this
        end
        alias_method :parent, :parents
      
        ##
        # Set the file as "to be added".
        # 
        # @param [String] file the path of the file to add
        # @return [Boolean] a success marker
        def add(file)
          add_path file, true
        
          @dirty = true
          @files[file] = DirStateEntry.new(:added, 0, -1, -1)
          @copy_map.delete file
          true # success
        end
      
        ##
        # Set the file as "normal", meaning no changes. This is the same
        # as dirstate.normal in dirstate.py, for those referencing both.
        # 
        # @param [String] file the path of the file to clean
        # @return [Boolean] a success marker
        def normal(file)
          @dirty = true
          add_path file, true
        
          f = File.lstat "#{@root}/#{file}"
          @files[file] = DirStateEntry.new(:normal, f.mode, f.size, f.mtime.to_i)
          @copy_map.delete file
          true # success
        end
        alias_method :clean, :normal
      
        ##
        # Set the file as normal, but possibly dirty. It's like when you
        # meet a cool girl, and she seems really innocent and it's a chance
        # for you to maybe change yourself and make a new friend, but then
        # she *might* actually be a total slut. Better milk that grapevine
        # to find out the truth. Oddly specific, huh.
        # 
        # THUS IS THE HISTORY OF THIS METHOD!
        #
        # And then one day you go to the movies with some other girl, and the
        # original crazy slutty girl is the cashier next to you. Unsure of
        # what to do, you don't do anything. Next thing you know, she's trying
        # to get your attention to say hey. WTF? Anyone know what's up with this
        # girl?
        # 
        # After milking that grapevine, you find out that she's not a great person.
        # There's nothing interesting there and you should just move on.
        # 
        # *sigh* girls.
        # 
        # @param [String] file the path of the file to mark
        # @return [Boolean] a success marker
        def maybe_dirty(file)
          if @files[file] && @parents.last != NULL_ID
            # if there's a merge happening and the file was either modified
            # or dirty before being removed, restore that state.
            # I'm quoting the python with that one.
            # I guess what it's saying is that if a file is being removed
            # by a merge, but it was altered somehow beforehand on the local
            # repo, then play it safe and bring back the dead. Divine intervention
            # on the side of the local repo.
          
            # info here is a standard array of info
            # [action, mode, size, mtime]
            info = @files[file]
          
            if info.removed? and [-1, -2].member? info.size
              source = @copy_map[file]
            
              # do the appropriate action
              case info.size
              when -1 # either merge it
                merge file
              when -2 # or mark it as dirty
                dirty file
              end
            
              copy source => file if source
              return
            end
          
            # next step... the base case!
            return true if info.modified? || info.maybe_dirty? and info.size == -2
          end
        
          @dirty = true # make the repo dirty
          add_path file # add the file
        
          @files[file] = DirStateEntry.new(:normal, 0, -1, -1) # give it info
          @copy_map.delete file # we're not copying it since we're adding it
          true # success
        end
      
        ##
        # Checks whether the dirstate is tracking the given file.
        # 
        # @param f the file to check for
        # @return [Boolean] whether or not the file is being tracked.
        def include?(path)
          not @files[path].nil?
        end
        alias_method :tracking?, :include?
      
        ##
        # Mark the file as "dirty"
        # 
        # @param [String] file the path of the file to mark
        # @return [Boolean] a success marker
        def dirty(file)
          @dirty = true
          add_path file
        
          @files[file] = DirStateEntry.new(:normal, 0, -2, -1)
          @copy_map.delete file
          true # success
        end
      
        ##
        # Set the file as "to be removed"
        # 
        # @param [String] file the path of the file to remove
        # @return [Boolean] a success marker
        def remove(file)
          @dirty = true
          drop_path file
        
          size = 0
          if @parents.last.null? && (info = @files[file])
            if info.merged?
             size = -1
            elsif info.normal? && info.size == -2
             size = -2
            end
          end
          @files[file] = DirStateEntry.new(:removed, 0, size, 0)
          @copy_map.delete file if size.zero?
          true # success
        end
      
        ##
        # Prepare the file to be merged
        # 
        # @param [String] file the path of the file to merge
        # @return [Boolean] a success marker
        def merge(file)
          @dirty = true
          add_path file
        
          stats = File.lstat "#{@root}/#{file}"
          add_path file
          @files[file] = DirStateEntry.new(:merged, stats.mode, stats.size, stats.mtime.to_i)
          @copy_map.delete file
          true # success
        end
      
        ##
        # Forget the file, erase it from the repo
        # 
        # @param [String] file the path of the file to forget
        # @return [Boolean] a success marker
        def forget(file)
          @dirty = true
          drop_path file
          @files.delete file
          true # success
        end
      
        ##
        # Invalidates the dirstate, making it completely unusable until it is
        # re-read. Should only be used in error situations.
        def invalidate!
          %w(@files @copy_map @folds @branch @parents @dirs @ignore).each do |ivar|
            instance_variable_set(ivar, nil)
          end
          @dirty = false
        end
      
        ##
        # Refresh the directory's state, making everything empty.
        # Called by #rebuild.
        # 
        # This is not the same as #initialize, so we can't just run
        # `send :initialize` and call it a day :-(
        # 
        # @return [Boolean] a success marker
        def clear
          @files    = {}
          @dirs     = {}
          @copy_map = {}
          @parents  = [NULL_ID, NULL_ID]
          @dirty    = true
        
          true # success
        end
      
        ##
        # Rebuild the directory's state. Needs Manifest, as that's
        # what the files really are.
        # 
        # @param [String] parent the binary format of the parent
        # @param [ManifestEntry] files the files in a specific revision
        # @return [Boolean] a success marker
        def rebuild(parent, files)
          clear
        
          # alter each file according to its flags
          files.each do |f|
            mode = files.flags(f).include?('x') ? 0777 : 0666
            @files[f] = DirStateEntry.new(:normal, mode, -1, 0)
          end
        
          @parents = [parent, NULL_ID]
          @dirty_parents = true
          true # success
        end
      
        ##
        # Save the data to .hg/dirstate.
        # Uses mode: "w", so it overwrites everything
        # 
        # @todo watch memory usage - +si+ could grow unrestrictedly which would
        #   bog down the entire program
        # @return [Boolean] a success marker
        def write
          return true unless @dirty
          begin
            @opener.open "dirstate", 'w' do |state|
              gran = @config['dirstate']['granularity'] || 1 # self._ui.config('dirstate', 'granularity', 1)
            
              limit = 2147483647 # sorry for the literal use...
              limit = state.mtime - gran if gran > 0
            
              si = StringIO.new "", (ruby_19? ? "w+:ASCII-8BIT" : "w+")
              si.write @parents.join
            
              @files.each do |file, info|
                file = file.dup # so we don't corrupt vars
                info = info.dup.to_a # UNLIKE PYTHON
                info[0]   = info[0].to_hg_int
              
                # I should probably do mah physics hw. nah, i'll do it
                # tomorrow during my break
                # good news - i did pretty well on my physics test by using
                # brian ford's name instead of my own.
                file = "#{file}\0#{@copy_map[file]}" if @copy_map[file]
                info = [info[0], 0, (-1).to_signed(32), (-1).to_signed(32)] if info[3].to_i > limit.to_i and info[0] == :normal
                info << file.size # the final element to make it pass, which is the length of the filename
                info = info.pack FORMAT # pack them their lunch
                si.write info # and send them off
                si.write file # to school
              end
            
              state.write si.string
              @dirty         = false
              @dirty_parents = false
            
              true # success
            end
          rescue IOError
            false
          end
        end
      
        ##
        # Copies the files in h (represented as "source" => "dest").
        #
        # @param [Hash<String => String>] h the keys are sources and the values 
        #   are dests
        # @return [Boolean] a success marker
        def copy(h={})
          h.each do |source, dest|
            next if source == dest
            return true unless source
          
            @dirty = true
          
            if   @copy_map[dest]
            then @copy_map.delete dest
            else @copy_map[dest] = source
            end
          end
        
          true # success
        end
      
        ##
        # The current directory from where the command is being called, with
        # the path shortened if it's within the repo.
        # 
        # @return [String] effectively Dir.pwd
        def cwd
          path = Dir.pwd
          return '' if path == @root
        
          # return a more local path if possible...
          return path[@root.length..-1] if path.start_with? @root
          path # else we're outside the repo
        end
        alias_method :pwd, :cwd
      
        ##
        # Returns the relative path from +src+ to +dest+.
        # 
        # @param [String] src This is a directory! If this is relative,
        #                     it is assumed to be relative to the root.
        # @param [String] dest This MUST be within root! It also is a file.
        # @return [String] the relative path
        def path_to(src, dest)
          # first, make both paths absolute, for ease of use.
          # @root is guarenteed to be absolute, so we're leethax here
          src  = File.join @root, src
          dest = File.join @root, dest
        
          # lil' bit of error checking...
          [src, dest].map do |f|
            unless File.exist? f # does both files and directories...
              raise FileNotInRootError, "#{f} is not in the root, #{@root}"
            end
          end
        
          # now we find the differences
          # these both are now arrays!!!
          src  = src.split '/'
          dest = dest.split '/' 
        
          while src.first == dest.first
            src.shift and dest.shift
          end
        
          # now, src and dest are just where they differ
          path = ['..'] * src.size # we want to go back this many directories
          path += dest
          path.join '/' # tadah!
        end
      
        ##
        # Walk recursively through the directory tree, finding all
        # files matched by the regexp in match.
        # 
        # Step 1: find all explicit files
        # Step 2: visit subdirectories
        # Step 3: report unseen items in the @files hash
        # 
        # @param [Boolean] unknown
        # @param [Boolean] ignored
        # @return [Hash<String => [NilClass, File::Stat]>] nil for directories and
        #   stuff, File::Stat for files and links
        def walk(unknown, ignored, match)
          files = match.files
        
          bad_type = proc do |file|
            UI::warn "#{file}: unsupported file type (type is #{File.ftype file})"
          end
        
          if ignored
            @ignore_all = false
          elsif not unknown
            @ignore_all = true
          end
        
          work = [@root]
        
          files = match.files ? match.files.uniq : [] # because [].uniq! is a major fuckup
        
          # why do we overwrite the entire array if it includes the current dir?
          # we even kill posisbly good things
          files = [''] if files.empty? || files.include?('.') # strange thing to do
          results = {'.hg' => true}
        
          # Step 1: find all explicit files
          files.sort.each do |file|
            next if results[file] || file == ""
          
            begin
              stats = File.lstat File.join(@root, file)
              kind  = File.ftype File.join(@root, file)
            
              # we'll take it! but only if it's a directory, which means we have
              # more work to do...
              if kind == 'directory'
                # add it to the list of dirs we have to search in
                work << File.join(@root, file) unless ignoring_directory? file
              elsif kind == 'file' || kind == 'link'
                # ARGH WE FOUND ZE BOOTY
                results[file] = stats
              else
                # user you are a fuckup in life please exit the world
                bad_type[file]
                results[file] = nil if @files[file]
              end
            rescue => e
              keep = false
              prefix = file + '/'
            
              @files.each do |f, _|
                if f == file || f.start_with?(prefix)
                  keep = true
                  break
                end
              end
            
              unless keep
                bad_type[file]
                results[file] = nil if (@files[file] || !ignore(file)) && match.call(file)
              end
            end
          end
        
          # step 2: visit subdirectories in `work`
          until work.empty?
            dir = work.shift
            skip = nil
          
            if dir == '.'
              dir = ''
            else
              skip = '.hg'
            end
          
          
            dirs = Dir.glob("#{dir}/*", File::FNM_DOTMATCH) - ["#{dir}/.", "#{dir}/.."]
            entries = dirs.inject({}) do |h, f|
              h.merge f => [File.ftype(f), File.lstat(f)]
            end
          
          
            entries.each do |f, arr|
              tf = f[(@root.size+1)..-1]
              kind = arr[0]
              stats = arr[1]
              unless results[tf]
                if kind == 'directory'
                  work << f unless  ignore tf
                  results[tf] = nil if @files[tf] && match.call(tf)
                elsif kind == 'file' || kind == 'link'
                  if @files[tf]
                    results[tf] = stats if match.call tf
                  elsif match.call(tf) && !ignore(tf)
                    results[tf] = stats
                  end
                elsif @files[tf] && match.call(tf)
                  results[tf] = nil
                end
              end
            end
          end
        
          # step 3: report unseen items in @files
          visit = @files.keys.select {|f| !results[f] && match.call(f) }.sort
        
          # zip it to a hash of {file_name => file_stats}
          hash  = visit.inject({}) do |h, f|
            h.merge!(f => File.stat(File.join(@root,f))) rescue h.merge!(f => nil)
          end
        
          hash.each do |file, stat|
            unless stat.nil?
              # because filestats can't be gathered if it's, say, a directory
              stat = nil unless ['file', 'link'].include? File.ftype(File.join(@root, file))
            end
            results[file] = stat
          end
        
          results.delete ".hg"
          @ignore_all = nil # reset this
          results
        end
      
        ##
        # what's the current state of life, man!
        # Splits up all the files into modified, clean,
        # added, deleted, unknown, ignored, or lookup-needed.
        # 
        # @return [Hash<Symbol => Array<String>>] a hash of the filestatuses and their files
        def status(ignored, clean, unknown, match = Match.new { true })
          list_ignored, list_clean, list_unknown = ignored, clean, unknown
          lookup, modified, added, unknown, ignored = [], [], [], [], []
          removed, deleted, clean = [], [], []
          delta = 0
        
          walk(list_unknown, list_ignored, match).each do |file, st|
            next if file.nil?
          
            unless @files[file]
              if list_ignored && ignoring_directory?(file)
                ignored << file
              elsif list_unknown
                unknown << file unless ignore(file)
              end
            
              next # on to the next one, don't do the rest
            end
          
            # here's where we split up the files
            state, mode, size, time = *@files[file].to_a
            delta += (size - st.size).abs if st && size >= 0 # increase the delta, but don't forget to check that it's not nil
            if !st && [:normal, :modified, :added].include?(state)
              # add it to the deleted folder if it should be here but isn't
              deleted << file
            elsif state == :normal
              if (size >= 0 && (size != st.size || ((mode ^ st.mode) & 0100 and @check_exec))) || size == -2 || @copy_map[file]
                modified << file
              elsif time != st.mtime.to_i # DOH - we have to remember that times are stored as fixnums
                lookup << file
              elsif list_clean
                clean << file
              end
            
            elsif state == :merged
              modified << file
            elsif state == :added
              added << file
            elsif state == :removed
              removed << file
            end
          end
        
          r = { :modified => modified.sort , # those that have clearly been modified
                :added    => added.sort    , # those that are marked for adding
                :removed  => removed.sort  , # those that are marked for removal
                :deleted  => deleted.sort  , # those that should be here but aren't
                :unknown  => unknown.sort  , # those that aren't being tracked
                :ignored  => ignored.sort  , # those that are being deliberately ignored
                :clean    => clean.sort    , # those that haven't changed
                :lookup   => lookup.sort   , # those that need to be content-checked to see if they've changed
                :delta    => delta           # how many bytes have been added or removed from files (not bytes that have been changed)
              }
        end
      
      
        ##
        # Reads the data in the .hg folder and fills in the vars
        # 
        # @return [Amp::DirState] self -- chainable!
        def read!
          @parents, @files, @copy_map = parse('dirstate')
          self # chainable
        end
      
        private
        ##
        # Generates the @ignore array
        # The array is full of paths relative to the root, which
        # makes things easier for the proc-generation phase.
        # 
        # @return [NilClass]
        def generate_ignore
          @ignore = @config['ui'].map do |k, v|
            @ignore << "#{v}" if k == "ignore"
          end
        
          @ignore << ".hgignore"
          @ignore.compact
        
          nil
        end
      
        ##
        # Perform various checks on the file before upping the content count
        # for all of its parent directories. It checks for:
        #   * filenames containing "\n" or "\r" (newlines and carriage returns)
        #   * filenames with the same names as directories
        #   * clashing filenames
        # 
        # It only increments the dirs' file count if the file is untracked or
        # being removed.
        # 
        # @param [String] f Should be formatted like ["action", mode, size, mtime]
        # @param [Boolean] check whether to perform any of the checks
        # @return [NilClass]
        def add_path(f, check=false)
          old_state = @files[f] || DirStateEntry.new # it's an array of info, remember
        
          if check || old_state.removed?
            raise "Bad Filename" if f.match(/\r|\n/)
            raise "Directory #{f} already exists" if @dirs[f]
          
            # make sure we don't have any files with the same name as a directory
            directories_to(f).each do |d|
              break if @dirs[d]
            
              if @files[d] && !@files[d].removed?
                raise "File #{d} clashes with #{f}! Fix their names" 
              end
            end
          end
        
          # only inc the dirs if the file is untracked or being removed.
          if [:untracked, :removed].include? old_state.status
            # inc the number of dirs in each dir
            inc_directories_to f
          end
        
          nil
        end
      
        ##
        # Conditional wrapper around +dec_directories_to+. It will dec the
        # directories if the file in question (+f+) is either untracked or
        # being removed.
        # 
        # @param [String] f Should be formatted like ["action", mode, size, mtime]
        # @return [NilClass]
        def drop_path(f)
          unless [:untracked, :removed].include? f[0]
            dec_directories_to(f)
          end
        
          nil
        end
      
        ##
        # All directories leading up to this path
        # 
        # @example directories_to "/Users/ari/src/monkey.txt" # => 
        #                           ["/Users/ari/src", "/Users/ari", "/Users"]
        # @param [String] path the path to the file we're examining
        # @return [Array] the directories leading up to this path
        def directories_to(path)
          File.amp_directories_to path
        end
      
        ##
        # Increment all directories' dir-count leading up to this path.
        # The dir-count is the path's value in @dirs.
        # This is used when adding a file.
        # 
        # @param [String] path the path we're disecting
        # @return [NilClass]
        def inc_directories_to(path)
          p = directories_to(path).first
          @dirs[p] ||= 0
          @dirs[p] += 1
          nil
        end
      
        ##
        # Decrement all directories' dir-count leading up to this path.
        # The dir-count is the path's value in @dirs.
        # This is used when removing a file.
        # 
        # @param [String] path the path we're disecting
        # @return [NilClass]
        def dec_directories_to(path)
          p = directories_to(path).first
          # if the dir has 0, kill the dir. we don't need it anymore
          if @dirs[p] && @dirs[p].zero?
            @dirs.delete p
          elsif @dirs[p]
            @dirs[p] -= 1 # we only need to inc the latest dir
          end
        
          nil
        end
      
        ##
        # I wish I knew what this did or when it was called.
        # 
        # @todo figure out what this does
        # @param [String] path the path to a file
        # @return [String] All I know is that this returns a string
        def normalize(path)
          fold_path = @folds[path]
          fold_path = path unless fold_path # if fold_path is true, then this line returns nil
          fold_path # so we need an extra line here to make sure it returns a good value
        end
      
        ##
        # Are we ignoring the directory?
        # 
        # @param [String] dir the directory we're checking, either aboslute or relative
        # @return [Boolean] are we ignoring the dir?
        def ignoring_directory?(dir)
          return true  if @ignore_all
          return false if @ignore_all == false
          return false if dir == '.'  # base cases
          return true  if ignore dir  # base cases
        
          !!directories_to(dir).any? {|d| ignore d }
        end
        alias_method :ignoring_dir?, :ignoring_directory?
      
        ##
        # Parses the dirstate file in .hg
        # 
        # @param [String] file path to the file to parse
        # @return [((String, String), Hash<String => (Integer, Integer, Integer)>, Hash<String => String>)]
        #   a tuple of (parents, files, copies). Parents is a tuple of the parents,
        #   files is a hash of filename => [mode, size, mtime], and copies is a hash of src => dest
        def parse(file)
          # the main data we need to return
          files  = {}
          copies = {}
          parents = []
          @opener.open file, "r" do |s|
          
            # the parents are the first 40 bytes
            parent  = s.read(20)  || NULL_ID
            parent_ = s.read(20)  || NULL_ID
            parents = [parent, parent_] 
          
            # 1 character + 4 32-bit ints = 17 bytes
            e_size = 17
          
            # this loop is just cycling through and reading every entry
            while !s.eof?
              # read 1 entry
              info = s.read(e_size).unpack FORMAT
            
              # byte swap and shizzle
              info = [info[0].to_dirstate_symbol, info[1], info[2].to_signed(32), info[3].to_signed(32), info[4]]
              # ^^^^ we have to sign them because otherwise they'll be hugely wrong
            
              # read in the filename
              f = s.read(info[4])
                
              # if it has an \0, then we've moved/copied it
              if f.match(/\0/)
                source, dest = f.split "\0"
                copies[source] = dest
                f = source
              end
                
              # and put in the info for the file itself
              files[f] = DirStateEntry.new(*info[0..3])
            end
          end
    
          [parents, files, copies]
        rescue Errno::ENOENT
          # no file? easy peasy
          [[NULL_ID, NULL_ID], {}, {}]
        end
      end
    end
  end
end