
module Amp
  module Diffs
    
    ##
    # This handles applying patches in mercurial. yay!!!!
    module MercurialPatch
      
      ##
      # This attempts to apply a series of patches in time proportional to
      # the total size of the patches, rather than patches * len(text). This
      # means rather than shuffling strings around, we shuffle around
      # pointers to fragments with fragment lists.
      #
      # When the fragment lists get too long, we collapse them. To do this
      # efficiently, we do all our operations inside a buffer created by
      # mmap and simply use memmove. This avoids creating a bunch of large
      # temporary string buffers.
      #
      # UPDATE 2AM BEFORE I GO BACK TO SCHOOL
      # I FUCKING HATE PYTHON
      def self.apply_patches(source, patches)
        return source if patches.empty?
        patch_lens = patches.map {|patch| patch.size}
        pl = patch_lens.sum
        bl = source.size + pl
        tl = bl + bl + pl
        b1, b2 = 0, bl
        
        return a if tl == 0 #empty patches. lame.
        
        output = StringIO.new "",(ruby_19? ? "r+:ASCII-8BIT" : "r+")
        output.write source
        
        frags = [[source.size, b1]]
        
        pos = b2 + bl
        output.seek pos
        patches.each {|patch| output.write(patch)}
        patch_lens.each do |plen|
          if frags.size > 128
            b2, b1 = b1, b2
            frags = [self.collect(output,b1,frags)]
          end
          newarr = []
          endpt = pos + plen
          last = 0
          while pos < endpt
            output.seek pos
            p1, p2, l = output.read(12).unpack("NNN")
            self.pull(newarr, frags, p1 - last)
            self.pull([], frags, p2 - p1)
            newarr << [l, pos + 12]
            pos += l + 12
            last = p2
          end
          frags = newarr + frags
        end
  
        t = self.collect output, b2, frags
        output.seek t[1]
        output.read t[0]
      end
      
      
      def self.patched_size(orig, delta)
        outlen, last, bin = 0, 0, 0
        binend = delta.size
        data = 12 # size of the delta instruction values (3 longs)
        while data <= binend
          decode = delta[bin..(bin+11)]
          start, endpt, length = decode.unpack("NNN")
          break if start > endpt
          
          bin = data + length
          data = bin + 12
          outlen += start - last
          last = endpt
          outlen += length
        end
        
        raise "patch cannot be decoded" if bin != binend
        
        outlen += orig - last
        outlen
      end
      
      def self.copy_block(io, destination, source, count)
        io.seek(source)
        buf = io.read(count)
        io.seek(destination)
        io.write(buf)
      end
      
      ##
      # 
      def self.pull(dst, src, l)
        until l == 0
          f = src.shift
          if f[0] > l
            src.unshift [f[0] - l, f[1] + l]
            dst << [l, f[1]]
            return
          end
          dst << f
          l -= f[0]
        end
      end
      
      ##
      # Takes the fragments we've accumulated and applies them all to the IO.
      def self.collect(io, buf, list)
        start = buf
        list.each do |l, p|
          self.copy_block(io, buf, p, l)
          buf += l
        end
        [buf - start, start]
      end
      
    end
  end
end