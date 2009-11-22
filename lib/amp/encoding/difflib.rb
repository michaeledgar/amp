module Amp
  ##
  # = Difflib
  # Port of the Python Difflib. Only ports what is necessary. The cool part is that
  # this works for anything that has []! So it'll find matches in an array of lines
  # or just strings.
  module Diffs
    ##
    # Port of the Python SequenceMatcher, leaving out parts that Mercurial doesn't use.
    class SequenceMatcher
      
      ##
      # Initializes the sequence matcher.
      # 
      # @param [String] seq1 The source data
      # @param [String] seq2 The "destination" data
      def initialize(seq1='', seq2='')
        @a = @b = nil
        set_seqs(seq1,seq2)
      end
      ##
      # Initializes the 2 sequences and prepares the rest of the matcher
      # 
      # @param [#each] seq1 The source input sequence. Can be anything responding to #each. 
      # @param [#each] seq2 The destination sequence - what we transform seq1 into.
      def set_seqs(seq1,seq2); set_seq1(seq1); set_seq2(seq2); end
      
      ##
      # Initializes the source sequence and resets the matching blocks.
      # 
      # @param [#each] seq1 The source input sequence.
      def set_seq1(seq1)
        return if @a == seq1
        @a = seq1
        @matching_blocks = nil
      end
      ##
      # Initializes the destination sequence and resets the matching blocks. It also prepares
      # some optimization data.
      # 
      # @param [#each] seq2 The destination input sequence.
      def set_seq2(seq2)
        return if @b == seq2
        @b = seq2
        @matching_blocks = nil
        build_b2j
      end
      
      ##
      # Sets up some optimization stuff. internal use only. I fucking hate python but ok here's what it
      # does... it goes through the destination sequence, setting the indices into the destination where
      # you can find each line. So it'll save the fact that "return nil" appears on lines 3, 14, and 20.
      # at the same time it's looking for "popular" entries, that are ignored to save runtime later. They
      # get removed from the list.
      # The original source respected a "junk" parameter, which was also removed from the list. But
      # Mercurial doesn't use the junk parameter, so I stripped that code.
      def build_b2j
        n = @b.size
        @b2j = {}
        populardict = {}
        n.times do |i|
          elt = @b[i,1]
          if @b2j[elt]
            indices = @b2j[elt]
            if n >= 2000 && (indices.size * 100 > n)
              populardict[elt] = true
              indices.clear
            else
              indices << i
            end
          else
            @b2j[elt] = [i]
          end
        end
        
        populardict.each do |k,v|
          @b2j.delete k
        end
      end
      
      ##
      # Finds the longest match in the 2 sequences between the 2 ranges provided.
      # 
      # @param alo don't look at any part of the source before this
      # @param ahi don't look at any part of the source after this
      # @param blo don't look at any part of the destination before this
      # @param bhi don't look at any part of the destination after this
      # @return [[Integer,Integer,Integer]] The return is of the form 
      #   [start_source, start_destination, length_of_common_sequence].
      #   source[start_source + i] == destination[start_destination + i] for all 0 <= i < length_of_common_sequence
      def find_longest_match(alo, ahi, blo, bhi)
        j2len = {}
        besti, bestj, bestsize = alo, blo, 0
        alo.upto(ahi-1) do |i|
          newj2len = {}
          @b2j[@a[i,1]] && @b2j[@a[i,1]].each do |j|
            next if j < blo
            break if j >= bhi
            k = newj2len[j] = j2len[j-1].to_i + 1
            besti, bestj, bestsize = i-k+1, j-k+1, k if k > bestsize
          end
          j2len = newj2len
        end
        # we ignored popular elements before. they're being added here.
        while besti > alo && bestj > blo && @a[besti-1,1] == @b[bestj-1,1]
          besti, bestj, bestsize = besti-1, bestj-1, bestsize + 1
        end
        # we ignored popular elements before. they're being added here.
        while besti+bestsize < ahi && bestj+bestsize < bhi && @a[besti+bestsize,1] == @b[bestj+bestsize,1]
          bestsize += 1
        end
        return [besti, bestj, bestsize]
      end
      
      ##
      # This will go through and find all the matching blocks in the
      # 2 sequences, picking out the best sequences using find_longest_match.
      # 
      # @return [[Hash]] A list of hashes, each of which represents 1 matching block. 
      def get_matching_blocks
        return @matching_blocks if @matching_blocks
        la, lb = @a.size, @b.size
        
        # This is best done recursively, but if you have a large file it can blow
        # the stack. We ignore popular lines here to speed things up. I guess.
        queue = [[0, la, 0, lb]]
        @matching_blocks = []
        while queue.any?
          alo, ahi, blo, bhi = queue.shift
          i, j, k = x = find_longest_match(alo, ahi, blo, bhi)
          if k > 0
            @matching_blocks << x
            if alo < i && blo < j
              queue << [alo, i, blo, j]
            end
            if i+k < ahi && j+k < bhi
              queue << [i+k, ahi, j+k, bhi]
            end
          end
        end
        # Sort 'em from beginning of the sequences to the end
        @matching_blocks.sort!
        i1 = j1 = k1 = 0
        non_adjacent = []
        # If any "popular" entries were ignored, let's add them to the sequence now.
        @matching_blocks.each do |i2, j2, k2|
          if i1 + k1 == i2 && j1 + k1 == j2
            k1 += k2
          else
            non_adjacent << [i1, j1, k1] if k1 > 0
            i1, j1, k1 = i2, j2, k2
          end
        end
        # Add the last found sequence if there is one
        non_adjacent << [i1, j1, k1] if k1 > 0
        # Add the terminator sequence
        non_adjacent << [la, lb, 0]
        # Make the output ruby-like, we don't need fucking tuples
        @matching_blocks = non_adjacent.map do |i, j, k|
          {:start_a => i, :start_b => j, :length => k}
        end
        @matching_blocks
      end
    end
  end
end