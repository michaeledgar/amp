module Amp
  ##
  # Binary diffs
  module Diffs
    
    ##
    # Methods for producing a binary diff file for 2 input strings. Direct port
    # from pure/bdiff.py in the mercurial source.
    module BinaryDiff
      
      ##
      # Produces a binary diff file from the input strings, str1 and str2. Works by
      # getting the list of matching blocks (using {SequenceMatcher}) and filling in
      # the gaps between them. Basically.
      # 
      # @param [String] str1 the source string/file
      # @param [String] str2 the destination string/file
      # @return [String] A binary string representing the diff between the two strings/files
      def bdiff(str1, str2)
        # break 'em up into lines
        a = []
        str1.each_line {|l| a << l}
        b = []
        str2.each_line {|l| b << l}

        if a.nil? || a.empty?
          s = b.join
          return [0,0,s.size].pack("NNN") + s
        end
        
        bin = []
        byte_offsets = [0]
        a.each {|line| byte_offsets << (byte_offsets.last + line.size) }
        # Get all the sections of a and b that actually match each other.
        matched_blocks = SequenceMatcher.new(a, b).get_matching_blocks
        la = lb = 0
        matched_blocks.each do |block|
          am, bm, size = block[:start_a], block[:start_b], block[:length]
          
          # At this point, a[la..am-1] does NOT equal b[lb..bm-1]. We know this
          # because the block we just got is a *matching* block. It tells us where
          # the two strings are the *same*. So a[la..am-1] is the source text, and
          # b[lb..bm-1] is the destination text of our diff. Thus, we say "replace
          # the text in a from (la..am) with the following text we got from b".
          # Since the array byte_offsets[] contains the actual byte offsets of each line,
          # our diff is stored as [start_a_text_to_replace, end_a_text_to_replace,
          # size_of_replacement_text, replacement_text]. 
          s = b[lb .. (bm-1)].join unless lb == bm && lb == 0
          s = ""                   if     lb == bm && lb == 0
          bin << [byte_offsets[la], byte_offsets[am], s.size].pack("NNN") + s if am > la || s.any?
          la = am + size
          lb = bm + size
        end
        bin.join
      end
      module_function :bdiff
      
      ##
      # Breaks the 2 input strings into blocks that match each other. Uses
      # {SequenceMatcher} and just manipulates the output a little.
      # 
      # @param [String] str1 the source string
      # @param [String] str2 the destination string
      # @return [[Hash]] The matching blocks, with keys :start_a, :start_b, :end_a, :end_b
      def blocks(str1, str2)
        an = str1.split_lines_better
        bn = str2.split_lines_better
        
        matches = Diffs::SequenceMatcher.new(an, bn).get_matching_blocks
        matches.map do |match|
          {:start_a => match[:start_a], :end_a => match[:start_a] + match[:length],
           :start_b => match[:start_b], :end_b => match[:start_b] + match[:length] }
        end
      end
      module_function :blocks
      
      def self.blocks_as_array(str1, str2)
        blocks(str1,str2).map {|h| [h[:start_a], h[:end_a], h[:start_b], h[:end_b]]}
      end
    end
  end
end