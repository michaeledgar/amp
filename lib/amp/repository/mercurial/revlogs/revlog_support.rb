require 'zlib'

module Amp
  module Mercurial
    module RevlogSupport
      
      class RevlogError < StandardError; end
      class LookupError < StandardError; end
      
      module Support
        extend self
        
        # Old version of the revlog file format
        REVLOG_VERSION_0 = 0
        # Current version of the revlog file format
        REVLOG_VERSION_NG = 1
        # A flag marking that the data is stored with the index
        REVLOG_NG_INLINE_DATA = (1 << 16)
        # Default flags - always start inline (turn off inline if file is huge)
        REVLOG_DEFAULT_FLAGS = REVLOG_NG_INLINE_DATA
        # Default format - the most recent
        REVLOG_DEFAULT_FORMAT = REVLOG_VERSION_NG
        # Default version in general
        REVLOG_DEFAULT_VERSION = REVLOG_DEFAULT_FORMAT | REVLOG_DEFAULT_FLAGS
        
        ##
        # This bears some explanation.
        #
        # Rather than simply having a 4-byte header for the index file format, the
        # Mercurial format takes the first entry in the index, and stores the header
        # in its offset field. (The offset field is a 64-bit unsigned integer which
        # stores the offset into the data or index of the associated record's data)
        # They take advantage of the fact that the first entry's offset will always
        # be 0. As such, its offset field is always going to be zero, so it's safe
        # to store data there.
        #
        # The format is ((flags << 16) | (version)), where +flags+ is a bitmask (up to 48
        # bits) and +version+ is a 16-bit unsigned short.
        #
        # The worst part is, EVERY SINGLE ENTRY has its offset shifted 16 bits to the left,
        # apparently all because of this. It fucking baffles my mind. 
        #
        # So yeah. offset = value >> 16.
        def get_offset(o); o >> 16; end
        # And yeah. version = value && 0xFFFF (last 16 bits)
        def get_version(t); t & 0xFFFF; end
        
        # Combine an offset and a version to spit this baby out
        def offset_version(offset,type)
          (offset << 16) | type
        end
        
        ##
        # generate a hash from the given text and its parent hashes
        # 
        # This hash combines both the current file contents and its history
        # in a manner that makes it easy to distinguish nodes with the same
        # content in the revision graph.
        # 
        # since an entry in a revlog is pretty
        # much [parent1, parent2, text], we use a hash of the previous entry
        # as a reference to that previous entry. To create a reference to this
        # entry, we make a hash of the first parent (which is just its ID), the
        # second parent, and the text.
        # 
        # @return [String] the digest of the two parents and the extra text
        def history_hash(text, p1, p2)
          list = [p1, p2].sort
          s = list[0].sha1
          s.update list[1]
          s.update text
          s.digest
        end
        
        ##
        # returns the possibly-compressed version of the text, in a hash:
        # 
        # @return [Hash] :compression => 'u' or ''
        def compress(text)
          return {:compression => "", :text => text} if text.empty?
          size = text.size
          binary = nil
          if size < 44
          elsif size > 1000000 #big ole file
            deflater = Zlib::Deflate.new
            parts = []
            position = 0
            while position < size
              newposition = position + 2**20
              parts << deflater.deflate(text[position..(newposition-1)], Zlib::NO_FLUSH)
              position = newposition
            end
            parts << deflater.flush
            binary = parts.join if parts.map {|e| e.size}.sum < size # only add it if
                                                   # compression made it smaller
          else #tiny, just compress it
            binary = Zlib::Deflate.deflate text
          end
          
          if binary.nil? || binary.size > size
            return {:compression => "",  :text => text} if text[0,1] == "\0"
            return {:compression => 'u', :text => text}
          end
          {:compression => "", :text => binary}
        end
        
        ##
        # Decompresses the given binary text. The binary text could be
        # uncompressed, in which case, we'll figure that out. Don't worry.
        # 
        # @param [String] binary the text to (possibly) decompress
        # @return [String] the text decompressed
        def decompress(binary)
          return binary if binary.empty?
          case binary[0,1]
          when "\0"
            binary #we're just stored as binary
          when "x"
            Zlib::Inflate.inflate(binary) #we're zlibbed
          when "u"
            binary[1..-1] #we're uncompressed text
          else
            raise LookupError.new("Unknown compression type #{binary[0,1]}")
          end
        end
      end
    end
  end
end