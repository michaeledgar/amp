module Amp
  module Repositories
    module Mercurial
      module Stores
        extend self
        class StoreError < StandardError; end
        # Picks which store to use, given a list of requirements.
        def pick(requirements, path, opener, pathjoiner=nil)
          pathjoiner ||= proc {|*args| File.join(args) }
          if requirements.include? 'store'
            if requirements.include? 'fncache'
              return FilenameCacheStore.new(path, opener, pathjoiner)
            else
              return EncodedStore.new(path, EncodedOpener, pathjoiner)
            end
          else
            return BasicStore.new(path, opener, pathjoiner)
          end
        end
        
        ##
        # = BasicStore
        # This class is the one from which all other stores derive. It implements
        # basic methods #walk, #join, #datafiles, and #copy_list which are the
        # public methods for all stores. All others are basically internal.
        class BasicStore
          BASIC_DATA_FILES = %W(data 00manifest.d 00manifest.i 00changelog.d  00changelog.i)
          
          attr_accessor :path_joiner
          attr_reader :path
          attr_reader :opener
          attr_reader :create_mode
          
          def initialize(path, openerklass, pathjoiner)
            @path_joiner, @path = pathjoiner, path
            @create_mode = calculate_mode path
            @opener = openerklass.new(@path)
            @opener.create_mode = @create_mode
            #@opener.default = :open_hg
          end
          
          ##
          # Joins the file _f_ to the store's base path using the path-joiner.
          # 
          # @param [String] f the filename to join to the store's base path
          # @return the combined base path and file path
          def join(f)
            @path_joiner.call(@path, f)
          end
          
          ##
          # Iterates over every file tracked in the store and yield it.
          # 
          # @yield [file] every file in the store
          # @yieldparam [String] file the filepath to an entry in the store
          def walk
            datafiles do |x|
              yield x
            end
            
            meta = do_walk '', false
            meta.reverse.each do |x|
              yield x
            end
          end
          
          ##
          # Returns all the data files in the store.
          def datafiles
            do_walk('data', true)
          end
          
          ##
          # Basic walker that is not very smart at all. It can recursively search
          # for data files, but it actually uses a queue to do its searching.
          # 
          # @param [String] relpath the base path to search
          # @param [Boolean] recurse (false) whether or not to recursively
          #   search each discovered directory.
          # @return [(String, String, Fixnum)] Each entry is returned in the form
          #   [filepath, filepath, filesize]
          def do_walk(relpath, recurse=false)
            path = join relpath
            stripped_len = path.size + File::SEPARATOR.size - 1
            list = []
            if File.directory?(path)
              to_visit = [path]
              while to_visit.any?
                p = to_visit.shift
                Dir.stat_list(p, true) do |file, kind, stat|
                  fp = join(file)
                  if kind =~ /file/ && ['.d','.i'].include?(file[-2..-1])
                    n = fp[stripped_len..-1]
                    list << [n, n, stat.size]
                  elsif kind =~ /directory/ && recurse
                    to_visit << fp
                  end
                end
              end
            end
            list.sort
          end
          
          ##
          # Calculates the mode for the user on the file at the given path.
          # I guess this saves some wasted chmods.
          # 
          # @param [String] path the path to calculate the mode for
          # @return [Fixnum] the mode to use for chmod. Octal, like 0777
          def calculate_mode(path)
            begin
              mode = File.stat(path).mode
              if (0777 & ~Amp::Support.UMASK) == (0777 & mode)
                mode = nil
              end
            rescue
              mode = nil
            end
            mode
          end
          
          ##
          # Returns the list of basic files that are crucial for the store to
          # function.
          #
          # @return [Array<String>] the list of basic files crucial to this class
          def copy_list
            ['requires'] + BASIC_DATA_FILES
          end
        end
        
        ##
        # = EncodedOpener
        # This opener uses the Stores' encoding function to modify the filename
        # before it is loaded.
        class EncodedOpener < Amp::Opener
          
          ##
          # Overrides the normal opener method to use encoded filenames.
          def open(f, mode="r", &block)
            super(Stores.encode_filename(f), mode, &block)
          end
        end
        
        ##
        # = EncodedStore
        # This version of the store uses encoded file paths to preserve
        # consistency across platforms.
        class EncodedStore < BasicStore
          
          ##
          # over-ride the datafiles block so that it decodes filenames before
          # it returns them.
          # 
          # @see BasicStore
          def datafiles
            do_walk('data', true) do |a, b, size|
              a = decode_filename(a) || nil
              yield [a, b, size] if block_given?
            end
          end
          
          ##
          # Encode the filename before joining
          def join
            @path_joiner.call @path, encode_filename(f)
          end
          
          ##
          # We've got a new required file so let's include it
          def copy_list
            BASIC_DATA_FILES.inject ['requires', '00changelog.i'] do |a, f|
              a + @path_joiner.call('store', f)
            end
          end
        end
        
        ##
        # = FilenameCache
        # This module handles dealing with Filename Caches - namely, parsing
        # them.
        module FilenameCache
          
          ##
          # Parses the filename cache, given an object capable of opening
          # a file relative to the right directory.
          # 
          # @param [Amp::Opener] opener An opener initialized to the repo's
          #   directory.
          def self.parse(opener)
            return unless File.exist? opener.join("fncache")
            opener.open 'fncache', 'r' do |fp|
              # error handling?
              i = 0
              fp.each_line do |line| #this is how we parse it
                if line.size < 2 || line[-1,1] != "\n"
                  raise StoreError.new("invalid fncache entry, line #{i}")
                end
                yield line.chomp
              end
            end
          end
          
          ##
          # = FilenameCacheOpener
          # This opener handles a cache of filenames that we are currently
          # tracking. This way we don't need to recursively walk though
          # the folders every single time. To use this class, you pass in
          # the real Opener object (that responds to #open and returns a file
          # pointer). then just treat it like any other opener. It will handle
          # the behind-the-scenes work itself.
          class FilenameCacheOpener < Amp::Opener
            
            ##
            # Initializes a new FNCacheOpener. Requires a normal object capable
            # of opening files.
            # 
            # @param [Amp::Opener] opener an opener object initialized to the
            #   appropriate root directory.
            def initialize(opener)
              @opener = opener
              @entries = nil
            end
            
            def path; @opener.path; end
            alias_method :root, :path
            
            ##
            # Parses the filename cache and loads it into an ivar.
            def load_filename_cache
              @entries = {}
              FilenameCache.parse @opener do |f|
                @entries[f] = true
              end
            end
            
            ##
            # Opens a file while being sure to write the filename if we haven't
            # seen it before. Just like the normal Opener's open() method.
            # 
            # @param [String] path the path to the file
            # @param [Fixnum] mode the read/write/append mode
            # @param block the block to pass to it (optional)
            def open(path, mode='r', &block)
              
              if mode !~ /r/ && path =~ /data\//
                load_filename_cache if @entries.nil?
                if @entries[path].nil?
                  @opener.open('fncache','ab') {|f| f.puts path }
                  @entries[path] = true
                end
              end
              
              begin
                @opener.open(Stores.hybrid_encode(path), mode, &block)
              rescue Errno::ENOENT
                raise
              rescue
                raise unless mode == 'r'
              end
            rescue
              raise
            end
      
          end
        end
        
        ##
        # = FilenameCacheStore
        # This version of the store uses a "Filename Cache", which is just a file
        # that names all the tracked files in the store. It also uses an even more
        # advanced "hybrid" encoding for filenames that again ensure consistency across
        # platforms. However, this encoding is non-reversible - but since we're just
        # doing file lookups anyway, that's just ducky.
        class FilenameCacheStore < BasicStore
          
          ##
          # Initializes the store. Sets up the cache right away.
          # 
          # @see BasicStore
          def initialize(path, openerklass, pathjoiner)
            @path_joiner = pathjoiner
            @path = pathjoiner.call(path, 'store')
            @create_mode = calculate_mode @path
            @_op = openerklass.new(@path)
            @_op.create_mode = @create_mode
            @_op.default = :open_file
            
            @opener = FilenameCache::FilenameCacheOpener.new(@_op)
          end
          
          ##
          # Properly joins the path, but hybrid-encodes the file's path
          # first.
          def join(f)
            @path_joiner.call(@path, Stores.hybrid_encode(f))
          end
          
          ##
          # Here's how we walk through the files now. Oh, look, we don't need
          # to do annoying directory traversal anymore! But we do have to
          # maintain a consistent fnstore file. I think I can live with that.
          def datafiles
            rewrite = false
            existing = []
            pjoin = @path_joiner
            spath = @path
            result = []
            FilenameCache.parse(@_op) do |f|
              
              ef = Stores.hybrid_encode f
              begin
                st = File.stat(@path_joiner.call(spath, ef))
                yield [f, ef, st.size] if block_given?
                result << [f, ef, st.size] unless block_given?
                existing << f
              rescue Errno::ENOENT
                rewrite = true
              end
            end
            if rewrite
              fp = @_op.open('fncache', 'wb')
              existing.each do |p|
                fp.write(p + "\n")
              end
              fp.close
            end
            result
          end
          
          ##
          # A more advanced list of files we need, properly joined and whatnot.
          def copy_list
            d = BASIC_DATA_FILES + ['dh', 'fncache']
            d.inject ['requires', '00changelog.i'] do |a, f|
              a + @path_joiner.call('store', f)
            end
            result
          end
          
        end
        
        
        #############################################
        ############ Encoding formats ###############
        #############################################
        
        ##
        # Gets the basic character map that maps disallowed letters to
        # allowable substitutes.
        #
        # @param [Boolean] underscore Should underscores be inserted in front of
        #   capital letters before we downcase them? (e.g. if true, "A" => "_a")
        def illegal_character_map(underscore=true)
          e = '_'
          win_reserved = "\\:*?\"<>|".split("").map {|x| x.ord}
          cmap = {}; 0.upto(126) {|x| cmap[x.chr] = x.chr}
          ((0..31).to_a + (126..255).to_a + win_reserved).each do |x|
            cmap[x.chr] = "~%02x" % x
          end
          ((("A".ord)..("Z".ord)).to_a + [e.ord]).each do |x|
            cmap[x.chr] = e + x.chr.downcase if underscore
            cmap[x.chr] = x.chr.downcase     unless underscore
          end
          cmap
        end
        memoize_method :illegal_character_map, true
        
        ##
        # Reversible encoding of the filename
        #
        # @param [String] s a file's path you wish to encode
        # @param [Boolean] underscore should we insert underscores when
        #   downcasing letters? (e.g. if true, "A" => "_a")
        # @return [String] an encoded file path
        def encode_filename(s, underscore=true)
          cmap = illegal_character_map underscore
          s.split("").map {|c| cmap[c]}.join
        end
        
        ##
        # Decodes an encoding performed by encode_filename
        #
        # @param [String] s an encoded file path
        # @param [String] the decoded file path
        def decode_filename(s)
          cmap = illegal_character_map true
          dmap = {}
          cmap.each do |k, v|
            dmap[v] = k
          end
          
          i = 0
          result = []
          while i < s.size
            1.upto(3) do |l|
              if dmap[s[i..(i+l-1)]]
                result << dmap[s[i..(i+l-1)]]
                i += l
                break
              end
            end
          end
          result.join
        end
        
        # can't name a file one of these on windows, apparently
        WINDOWS_RESERVED_FILENAMES = %w(con prn aux nul com1
        com2 com3 com4 com5 com6 com7 com8 com8 lpt1 lpt2
        lpt3 lpt4 lpt5 lpt6 lpt7 lpt8 lpt9)
        
        ##
        # Copypasta
        def auxilliary_encode(path)
          res = []
          path.split('/').each do |n|
            if n.any?
              base = n.split('.')[0]
              if !(base.nil?) && base.any? && WINDOWS_RESERVED_FILENAMES.include?(base)
                ec = "~%02x" % n[2,1].ord
                n = n[0..1] + ec + n[3..-1]
              end
              if ['.',' '].include? n[-1,1]
                n = n[0..-2] + ("~%02x" % n[-1,1].ord)
              end
            end
            res << n
          end
          res.join("/")
        end
        
        ##
        # Normal encoding, but without extra underscores in the filenames.
        def lower_encode(s)
          encode_filename s, false
        end
        
        MAX_PATH_LEN_IN_HGSTORE = 120
        DIR_PREFIX_LEN = 8
        MAX_SHORTENED_DIRS_LEN = 8 * (DIR_PREFIX_LEN + 1) - 4
        
        ##
        # uber encoding that's straight up crazy.
        # Max length of 120 means we have a non-reversible encoding,
        # but since the FilenameCache only cares about name lookups, one-way
        # is really all that matters!
        # 
        # @param [String] path the path to encode
        # @return [String] an encoded path, with a maximum length of 120.
        def hybrid_encode(path)
          return path unless path =~ /data\//
          ndpath = path["data/".size..-1]
          res = "data/" + auxilliary_encode(encode_filename(ndpath))
          if res.size > MAX_PATH_LEN_IN_HGSTORE
            digest = path.sha1.hexdigest
            aep = auxilliary_encode(lower_encode(ndpath))
            root, ext = File.amp_split_extension aep
            parts = aep.split('/')
            basename = File.basename aep
            sdirs = []
            parts[0..-2].each do |p|
              d = p[0..(DIR_PREFIX_LEN-1)]
              
              d = d[0..-2] + "_" if " .".include?(d[-1,1])
              
              t = sdirs.join("/") + "/" + d
              break if t.size > MAX_SHORTENED_DIRS_LEN
      
              sdirs << d
            end
            dirs = sdirs.join("/")
            dirs += "/" if dirs.size > 0
            
            res = "dh/" + dirs + digest + ext
            space_left = MAX_PATH_LEN_IN_HGSTORE - res.size
            if space_left > 0
              filler = basename[0..(space_left-1)]
              res = "dh/" + dirs + filler + digest + ext
            end
          end
          return res
              
        end
      end
    end
  end
end