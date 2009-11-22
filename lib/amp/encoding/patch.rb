# I have seen few files so poorly organized such as patch.py
# What. The. Fuck. This is going to take so long to make.
module Amp
  module Patch
    
    class PatchError < StandardError; end
    class NoHunkError < PatchError; end
    
    class Patch
      
      ##
      # The filename of the patch
      attr_accessor :file_name
      
      ##
      # The opener used to open the patch
      attr_accessor :opener
      
      ##
      # @todo - add comment
      attr_accessor :lines
      
      ##
      # does the patch exist?
      attr_accessor :exists
      alias_method  :exists?, :exists
      
      ##
      # Is the file in the filesystem
      attr_accessor :missing
      alias_method  :missing?, :missing
      
      ##
      # @todo - add comment
      attr_accessor :hash
      
      ##
      # Is this dirty and does it need to be resynced with something?
      attr_accessor :dirty
      alias_method  :dirty?, :dirty
      
      ##
      # @todo - add comment
      attr_accessor :offset
      
      ##
      # has this been printed? (duh)
      attr_accessor :printed
      alias_method  :printed?, :printed
      
      ##
      # @todo - add comment
      attr_accessor :hunks
      
      def initialize(file_name, opener, missing=false)
        @file_name = file_name
        @opener    = opener
        @lines     = []
        @exists    = false
        @hash      = {}
        @dirty     = false
        @offset    = 0
        @rejected  = []
        @printed   = false
        @hunks     = 0
        
        ##
        # If the patch is in the filesystem
        # then we should read it and accurately set its existence
        unless @missing = missing
          begin
            readlines!
            @exists = true
          rescue IOError
          end
        else
          UI::warn "unable to find '#{@file_name}' for patching"
        end
      end
      
      ##
      # Loads up the patch info from +@file_name+
      # into +@lines+
      def readlines!
        @opener.open @file_name do |f|
          @lines = f.readlines
        end
      end
      
      ##
      # Mysteriously and safely disappear...
      #
      # @return [Boolean] success marker
      def unlink; File.safe_unlink @file_name; end
      
      ##
      # Print out the patch to STDOUT, or STDERR if +warn+ is true.
      # 
      # @param [Boolean] warn should we be printing to STDERR?
      def print(warn=false)
        return if printed? # no need to print it twice
        
        @printed = true if warn
        message  = "patching file #{@file_name}"
        warn ? UI::warn message : UI::note message
      end
      
      ##
      # From the Python: looks through the hash and finds candidate lines. The
      # result is a list of line numbers sorted based on distance from linenum.
      # 
      # I wish I knew how to make sense of that sentence.
      # 
      # @todo Look into removing an unnecessary `- number`.
      # @param  [String] line
      # @param  [Integer] number the line number
      # @return [Array] the lines that matchish.
      def find_lines(line, number)
        return [] unless @hash.include? line
        
        # really, we're just getting the lines and sorting them
        # is the `- number` even necessary?
        @hash[line].sort {|a, b| (a - number).abs <=> (b - number).abs }
      end
      
      ##
      # I have no clue what song I am listening to but it is SOOOOO GOOD!!!!!!!!
      # "This time baby, I'll be bullet proof"
      # If I had working internet now, I'd be googling the lyrics.
      # 
      # Oh right, the method. I don't know what this does... YET
      # 
      # @todo Figure out what this does
      def hash_lines
        @hash = Hash.new {|h, k| h[k] = [] }
        (0 ... @lines.size).each do |x|
          s = @lines[x]
          @hash[s] << x
        end
      end
      
      ##
      # our rejects are a little different from patch(1).  This always
      # creates rejects in the same form as the original patch.  A file
      # header is inserted so that you can run the reject through patch again
      # without having to type the filename.
      def write_rejects
        return if @rejects.empty?
        fname = @file_name + '.rej'
        
        UI::warn("#{@rejects.size} out of #{@hunks} hunks FAILED --" +
                 "saving rejects to file #{fname}")
        
        # i have never written code as horrid as this
        # please help me
        lz = []
        base = File.dirname @file_name
        lz << "--- #{base}\n+++ #{base}\n"
        @rejects.each do |r|
          r.hunk.each do |l|
            lz << l
            lz << "\n\ No newline at end of file\n" if l.last.chr != "\n"
          end
        end
        
        write fname, lz, true
      end
      
      ##
      # Write +linez+ to +fname+. We won't be doing any writing if
      # nothing has been changed, but this can be overridden with the
      # force parameter.
      # 
      # @param [String] dest the filename to write to
      # @param [Array<String>] linez an array of the lines to write
      # @param [Boolean] force force a write
      def write(dest=@file_name, linez=@lines, force=false)
        return unless dirty? || force
        
        @opener.open dest, 'w' do |f|
          f.write linez.join("\n")
        end
      end
      
      ##
      # A more restrictive version of {write}
      def write_patch
        write @file_name, @lines, true
      end
      
      ##
      # Closing rites. Write the patch and then write the rejects.
      def close
        write_patch
        write_rejects
      end
      
      ##
      # Apply the current hunk +hunk+. Also, should we reverse the hunk? Consult +reverse+.
      # 
      # @param
      # @param
      def apply(hunk, reverse)
        unless hunk.complete?
          raise PatchError.new("bad hunk #%d %s (%d %d %d %d)" % 
                               [hunk.number, hunk.desc, hunk.a.size,
                                hunk.len_a, hunk.b.size, hunk.len_b])
        end
        
        @hunks += 1               # It's clear we're adding a new hunk.
        
        # Obey reversal rules.
        hunk.reverse                                 if reverse
        
        # Does the file already exist? Better tell someone
        UI::warn "file #{@file_name} already exists" if exists? && hunk.create_file?
        
        # Is this a misfit?
        (@rejects << hunk; return -1)                if missing? || (exists? && hunk.create_file?)
        
        # Deal with GitHunks
        if hunk.is_a? GitHunk
          if hunk.remove_file?
            File.safe_unlink @file_name
          else
            @lines   = hunk.new
            @offset += hunk.new.size
            @dirty   = true
          end
          
          return 0
        end
        
        # fast case first, no offsets, no fuzz
        old = hunk.old
        
        # patch starts counting at 1 unless we are adding the file
        start = hunk.start_a == 0 ? 0 : h.start_a + @offset - 1
        
        orig_start = start
        if DiffHelpers::test_hunk(old, @lines, start) == 0
          if hunk.remove_file?
            File.safe_unlink @file_name
          else
            @lines[start .. (start + hunk.len_a)] = hunk.new
            @offset += hunk.len_b - hunk.len_a
            @dirty   = true
          end
          
          return 0
        end # end if
      end # end def
      
      # Ok, We couldn't match the hunk.  Let's look for offsets and fuzz it
      # as well as use proper punctuation for the 'let us' contraction.
      hash_lines
      
      # if the hunk tried to put something at the bottom of the file
      # then override the start line and use eof here
      search_start = hunk[-1][0].chr != ' ' ? @lines.size : orig_start
      
      0.upto(2) do |fuzz_len|
        [true, false].each do |top_only|
          old = hunk.old fuzz_len, top_only
          # Continue at patch.py:407
          # ...
          # ...
        end
      end # end upto
      
    end # end class Patch
    
    class PatchMeta
    end
    
    class Hunk
    end
    
    class GitHunk
    end
    
    class BinaryHunk
    end
    
    class SymLinkHunk
    end
    
    class LineReader
    end
    
  end
end