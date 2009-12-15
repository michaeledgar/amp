module Amp
  module Mercurial
    class ManifestEntry < DelegateClass(Hash)
      
      ##
      # Initializes the dictionary. It can be empty, by initializing with no
      # arguments, or with more data by assigning them.
      # 
      # It is a hash of Filename => node_id
      # 
      # @param [Hash] mapping the initial settings of the dictionary
      # @param [Hash] flags the flag settings of the dictionary
      def initialize(mapping=nil, flags=nil)
        @source_hash = mapping || {}
        super(@source_hash || {})
        @flags = flags || {}
      end
      
      def inspect
        "#<ManifestEntry " + @source_hash.inspect + "\n" +
        "                " + @flags.inspect + ">"
      end
      
      def flags(file=nil)
        file ? @flags[file] : @flags
      end
      
      def files; keys; end
      
      def delete(*args)
        super(*args)
        flags.delete(*args)
      end
      
      ##
      # Clones the dictionary
      def clone
        self.class.new @source_hash.dup, @flags.dup
      end
      
      # @see clone
      alias_method :dup, :clone
      
      ##
      # Mark a file to be checked later on
      # 
      # @param [String] file the file to be marked for later checking
      # @param []
      def mark_for_later(file, node)
        self[file]  = nil # notice how we DIDN'T use `self.delete file`
        flags[file] = node.flags file
      end
      
    end
    
    
    ##
    # = Manifest
    # A Manifest is a special type of revision log. It stores lists of files
    # that are being tracked, with some flags associated with each one. The
    # manifest is where you can go to find what files a revision changed,
    # and any extra information about the file via its flags.
    class Manifest < Revlog
      
      attr_accessor :manifest_list
      
      ##
      # Parses a bunch of text and interprets it as a manifest entry.
      # It then maps them onto a ManifestEntry that stores the real
      # info.
      # 
      # @param [String] lines the string that contains the information
      #   we need to parse.
      def self.parse(lines)
        mf_dict = ManifestEntry.new
        
        lines.split("\n").each do |line|
          f, n = line.split("\0")
          if n.size > 40
            mf_dict.flags[f] = n[40..-1]
            mf_dict[f] = n[0..39].unhexlify
          else
            mf_dict[f] = n.unhexlify
          end
        end
        
        mf_dict
      end    
      
      def initialize(opener)
        @map_cache = nil
        @list_cache = nil
        super(opener, "00manifest.i")
      end
      
      ##
      # Reads the difference between the given node and the revision
      # before that.
      # 
      # @param [String] node the node_id of the revision to diff
      # @return [ManifestEntry] the dictionary with the info between
      #   the given revision and the one before that
      def read_delta(node)
        r = self.revision_index_for_node node
        return self.class.parse(Diffs::Mercurial::MercurialDiff.patch_text(self.revision_diff(r-1, r)))
      end
      
      ##
      # Parses the manifest's data at a given revision's node_id
      # 
      # @param [String, Symbol] node the node_id of the revision. If a symbol,
      #   it better be :tip or else shit will go down.
      # @return [ManifestEntry] the dictionary mapping the
      #   flags, filenames, digests, etc from the parsed data
      def read(node)
        node = tip if node == :tip
        
        return ManifestEntry.new if node == NULL_ID
        return @map_cache[1] if @map_cache && @map_cache[0] == node
        
        text = decompress_revision node
        
        @list_cache = text
        mapping = self.class.parse(text)
        @map_cache = [node, mapping]
        mapping
      end
      
      ##
      # Digs up the information about how a file changed in the revision
      # specified by the provided node_id.
      # 
      # @param [String] nodes the node_id of the revision we're interested in
      # @param [String] f the path to the file we're interested in
      # @return [[String, String], [nil, nil]] The data stored in the manifest about the
      #   file. The first String is a digest, the second String is the extra
      #   info stored alongside the file. Returns [nil, nil] if the node is not there
      def find(node, f)
        if @map_cache && node == @map_cache[0]
          return [@map_cache[1][f], @map_cache[1].flags[f]]
        end
        mapping = read(node)
        return [mapping[f],  (mapping.flags[f] || "")]
      end
      ##
      # Checks the list for files invalid characters that aren't allowed in
      # filenames.
      # 
      # @raise [RevlogSupport::RevlogError] if the path contains an invalid
      #   character, raise.
      def check_forbidden(list)
        list.each do |f|
          if f =~ /\n/ || f =~ /\r/
            raise RevlogSupport::RevlogError.new("\\r and \\n are disallowed in "+
                                                 "filenames")
          end
        end
      end
      
      def encode_file(file, manifest)
        "#{file}\000#{manifest[file].hexlify}#{manifest.flags[file]}\n"
      end
      
    
      def add(map, journal, link, p1=nil, p2=nil, changed=nil)
        if changed || changed.empty? || @list_cache ||
            @list_cache.empty? || p1.nil? || @map_cache[0] != p1
          check_forbidden map
          @list_cache = map.map {|f,n| f}.sort.map {|f| encode_file f, map }.join
          
          n = add_revision(@list_cache, journal, link, p1, p2)
          @map_cache = [n, map]
          
          return n
        end
        
        check_forbidden changed[0] # added files, check if they're forbidden
        
        mapping = Manifest.parse(@list_cache)
        
        changed[0].each do |x| 
          mapping[x] = map[x].hexlify
          mapping.flags[x] = map.flags[x]
        end
        
        changed[1].each {|x| mapping.delete x }
        @list_cache = mapping.map {|k, v| k}.sort.map {|fn| encode_file(fn, mapping)}.join
        
        n = add_revision(@list_cache, journal, link, p1, p2)
        @map_cache = [n, map]
        
        n
      end
    end
  end
end