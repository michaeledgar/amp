# = Amp
module Amp
  # = Encoding
  module Encoding
    # This class provides methods for encoding and decoding to base85, a storage format used
    # by Mercurial. Base85 is like base64, only with some extra characters to improve compression.
    # This is a direct port of the python file base85.py in the Mercurial distribution.
    class Base85
      # The allowable Base 85 characters (encoding)
      B85chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+-;<=>?@^_`{|}~'
      # The lookup table to go from character -> decimal (decoding)
      B85dec = {}
      # Prepare the decoding table
      B85chars.size.times do |i|
        B85dec[B85chars[i,1]] = i
      end
      
      ##
      # Encodes the given string in Base85, and possibly pad it. This code makes sense to me. Fuck I hate
      # python.
      # 
      # @param [String] str the string to be encoded
      # @param [Boolean] pad whether or not to pad the resulting output
      # @return [String] Base85 encoded string 
      def self.encode str, pad=false
        l = str.size
        r = l % 4
        str += "\0" * (4-r)
        longs = str.size >> 2
        out = []
        words = str.unpack("N#{longs}")
        
        words.each do |word|
          word, r = word.divmod 85
          e = B85chars[r].chr
          word, r = word.divmod 85
          d = B85chars[r].chr
          word, r = word.divmod 85
          c = B85chars[r].chr
          word, r = word.divmod 85
          b = B85chars[r].chr
          word, r = word.divmod 85
          a = B85chars[r].chr
          
          out += [a,b,c,d,e]
        end
        
        out = out.join("")
        return out if pad
        
        olen = l % 4
        olen += 1 if olen > 0
        olen += l / 4 * 5
        
        out[0 .. olen-1]
      end
      
      ##
      # Decodes a base85 encoded string and returns it. This code sort of mystifies me.
      # Slash looking at it I'm not sure why we don't just code it in C. Maybe we will eventually.
      # Fucking python coders.
      # 
      # @param [String] text the base85 encoded string to decode
      # @return [String] the decoded text
      def self.decode text
        l = text.size
        out = []
        i = 0
        while i < text.size
          chunk = text[i .. i+4]
          acc = 0
          chunk.size.times do |j|
            acc = acc * 85 + B85dec[chunk[j].chr]
          end
          out << acc
          i += 5
        end
        
        cl = l % 5
        if cl > 0
          acc *= 85 ** (5 - cl)
          if cl > 1
            acc += 0xffffff >> (cl - 2) * 8
          end
          out[-1] = acc
        end
        
        out = out.pack("N#{out.size}")
        if cl > 0
          out = out[0 .. (-1 * (5-cl) - 1)]
        end
        out
      end
      
    end
  end
end