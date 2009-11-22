module Amp
  module Diffs
    ##
    # = MercurialDiff
    # Mercurial has it's own implementation of the unified diff, because windows
    # boxes don't have diff -u. Plus code is faster than the shell.
    # Lame. That's ok, it's pretty easy to do. And we can also add flags and 
    # change default settings.
    #
    # Mainly, you're only going to use MercurialDiff.unified_diff(). It's usage
    # is described below.
    module MercurialDiff
      extend self
      ##
      # These are the default options you can modify. Grab them, clone them,
      # change them. Notice: You have to *clone* this when you use it, or
      # you will be changing the default options!
      DEFAULT_OPTIONS = {:context => 3, :text => false, :show_func => false,
                         :git => false, :no_dates => false, :ignore_ws => false,
                         :ignore_ws_amount => false, :ignore_blank_lines => false,
                         :pretty => false}
      
      ##
      # Clear up whitespace in the text if we have any options relating
      # to getting rid of whitespace.
      # 
      # @param [String] text the text to modify
      # @param [Hash] options the options to use when deciding how to clean text
      # @option [Boolean] options :ignore_ws (false) do we ignore all whitespace?
      #   this has the net effect of removing all whitespace.
      # @option [Boolean] options :ignore_ws_amount (false) when this option is
      #   true, we only remove "excessive" whitespace - more than 1 space or tab.
      #   we then substitute it all with 1 space.
      # @option [Boolean] options :ignore_blank_lines (false) when this option
      #   is true, we remove all extra blank lines.
      def whitespace_clean(text, options=DEFAULT_OPTIONS)
        if options[:ignore_ws]
          text.gsub!(/[ \t]+/, "") #warnings made me use parens
        elsif options[:ignore_ws_amount]
          text.gsub!(/[ \t]+/, ' ')
          text.gsub!(/[ \t]+\n/, "\n")
        end
        text.gsub!(/\n+/, '') if options[:ignore_blank_lines]
        text
      end
      
      ##
      # Given a line, returns a string that represents "adding that line" in a diff,
      # based on the options.
      #
      # @param [String] input the input line
      # @return [String] the output line, in a format indicating it is "added"
      def add_line(input, options)
        options[:pretty] ? "+#{input.chomp}".green+"\n" : "+#{input}"
      end
      
      ##
      # Given a line, returns a string that represents "removing that line" in a diff,
      # based on the options.
      #
      # @param [String] input the input line
      # @return [String] the output line, in a format indicating it is "removed"
      def remove_line(input, options)
        options[:pretty] ? "-#{input.chomp}".red+"\n" : "-#{input}"
      end
      
      ##
      # Creates a header or something? Not sure what this is used for, no code
      # references it. I think it's for git or something. eh.
      def diff_line(revisions, a, b, options=DEFAULT_OPTIONS)
        options = DEFAULT_OPTIONS.merge options
        parts = ['diff']
        
        parts << '--git' if options[:git]
        parts << revisions.map {|r| "-r #{r}"}.join(' ') if revisions && !options[:git]
        if options[:git]
          parts << "a/#{a}"
          parts << "b/#{b}"
        else
          parts << a
        end
        parts.join(' ') + "\n"
      end
      
      ##
      # Creates a date tag appropriate for diffs. Not all diff types use
      # dates though (namely git, apparently), so the options matter.
      # 
      # @param [Time] date the time that we want to make a spiffy date line for
      # @param [String] fn1 the filename of the file being stamped. Only
      #   used if the addtab option is on.
      # @param [Boolean] addtab (false) whether or not to add a tab in the
      #   line or not. Only used if we're in git mode or no-date mode.
      # @param options the options to use while creating the date line.
      # @option [Boolean] options :git (false) are we creating a git diff?
      #   this will deactivate dates.
      # @option options [Boolean] :nodates (false) should we never print dates?
      def date_tag(date, fn1, addtab = true, options = DEFAULT_OPTIONS)
        return "\t#{date.to_diff}\n" if !(options[:git]) && !(options[:nodates])
        return "\t\n" if addtab && fn1 =~ / /
        return "\n"
      end
      
      ##
      # Returns a unified diff based on the 2 blocks of text, their modification
      # times, their filenames, and the options. 
      #
      # This is a self-contained replacement for diffs.
      # 
      # @param a the original text
      # @param [Time] ad the modification timestamp for the old file
      # @param b the new text
      # @param [Time] bd the modification timestamp for the new file
      # @param fn1 the old filename
      # @param fn2 the new filename
      # @param r not sure what this does
      # @param options the options we will be using. There's a lot of settings,
      #   see the descriptions for {whitespace_clean} and {date_tag}.
      def unified_diff(a, ad, b, bd, fn1, fn2, r=nil, options=DEFAULT_OPTIONS)
        return "" if (a.nil? || a.empty?) && (b.nil? || b.empty?)
        epoch = Time.at(0)
        if !options[:text] && (!a.nil? && a.binary? || !b.nil? && b.binary?)
          return "" if a.any? && b.any? && a.size == b.size && a == b #DERR
          l = ["Binary file #{fn1} has changed\n"]
        elsif a.nil? || a.empty?
          b = b.split_lines_better
          header = []
          if options[:pretty]
            l1 = a.nil? ? "Added file " : "Changed file "
            l1 += "#{fn2} at #{date_tag(bd,fn1,true,options)}"
            l1 = l1.cyan
            header << l1
          else
            if a.nil?
              header << "--- /dev/null#{date_tag(epoch, fn1, false, options)}"
            else
              header << "--- #{"a/" + fn1}#{date_tag(ad,fn1,true,options)}"
            end
            header << "+++ #{"b/" + fn2}#{date_tag(bd,fn1,true,options)}"
            header << "@@ -0,0 +1,#{b.size} @@\n"
          end
          l = header + (b.map {|line| add_line(line, options)})
        elsif b.nil? || b.empty?
          a = b.split_lines_better
          header = []
          if options[:pretty]
            l1 = b.nil? ? "Removed file " : "Changed file "
            l1 += "#{fn2} at #{date_tag(bd,fn1,true,options)}"
            l1 = l1.cyan
            header << l1
          else
            header << "--- #{"a/" + fn1}#{date_tag(ad,fn1,true,options)}"
            if b.nil?
              header << "+++ /dev/null#{date_tag(epoch, fn1, false, options)}"
            else
              header << "+++ #{"b/" + fn2}#{date_tag(bd,fn1,true,options)}"
            end
            header << "@@ -1,#{a.size} +0,0 @@\n"
          end
          l = header + (a.map {|line| remove_line(line, options)})
        else
          al = a.split_lines_better
          bl = b.split_lines_better
          l = bunidiff(a, b, al, bl, "a/"+fn1, "b/"+fn2, options)
          return "" if l.nil? || l.empty?
          if options[:pretty]
            l.shift
            if fn1 == fn2
              l[0] = "Changed file #{fn1.cyan} at #{date_tag(bd,fn1,true,options).lstrip}"
            else
              l[0] = "Moved file from #{fn1.cyan} to #{fn2.cyan}"
            end
          else
            l[0] = "#{l[0][0 .. -3]}#{date_tag(ad,fn1,true,options)}"
            l[1] = "#{l[1][0 .. -3]}#{date_tag(bd,fn1,true,options)}"
          end
        end
        
        l.size.times do |ln|
          if l[ln][-1,1] != "\n"
            l[ln] << "\n\\ No newline at end of file\n"
          end
        end
        
        if r
          l.unshift diff_line(r, fn1, fn2, options)
        end
        
        l.join
      end
      
      ##
      # Starts a block ending context for a change - part of the unified diff
      # format.
      def context_end(l, len, options)
        ret = l + options[:context]
        ret = len if ret > len
        ret
      end
      
      ##
      # Starts a block starting context for a change - part of the unified diff
      # format.
      def context_start(l, options)
        ret = l - options[:context]
        return 0 if ret < 0
        ret
      end
      
      ##
      # Given a hunk of changes, yield each line we need to write to the diff.
      # 
      # @param [Hash] hunk specifies a block of lines that changed between
      #   the two files.
      # @param header the header for the block, if we have one.
      # @param l1 the original lines - used for context (unified diff format)
      # @param delta the lines that have changed thus far
      # @param options settings for the unified diff action. unused mostly here.
      def yield_hunk(hunk, header, l1, delta, options)
        header.each {|x| yield x} if header && header.any?
        delta = hunk[:delta]
        astart, a2, bstart, b2 = hunk[:start_a], hunk[:end_a], hunk[:start_b], hunk[:end_b]
        aend = context_end(a2,l1.size,options)
        alen = aend - astart
        blen = b2 - bstart + aend - a2
        
        # i seriously don't know what this does.
        func = ""
        if options[:show_func]
          (astart - 1).downto(0) do |x|
            t = l1[x].rstrip
            if t =~ /\w/
              func = ' ' + t[0 .. 39]
              break
            end
          end
        end
        
        # yield the header
        if options[:pretty]
          yield "From original lines #{astart + 1}-#{alen+astart+1}".yellow + "\n"
        else
          yield "@@ -%d,%d +%d,%d @@%s\n" % [astart + 1, alen,
                                            bstart + 1, blen, func]
        end
                                           
        # then yield each line of changes
        delta.each {|x| yield x}
        # then yield some context or something?
        a2.upto(aend-1) {|x| yield ' ' + l1[x] }
      end
      
      ##
      # Helper method for creating unified diffs.
      # 
      # @param [String] t1 original text
      # @param [String] t2 new text
      # @param [String] l1 the original text broke into lines?
      # @param [String] l2 the new etxt broken into lines?
      # @param [String] header1 the original file's header
      # @param [String] header2 the new file's header
      # @param opts options for the method
      def bunidiff(t1,t2, l1, l2, header1, header2, opts=DEFAULT_OPTIONS)
        header = [ "--- #{header1}\t\n", "+++ #{header2}\t\n" ]

        diff = BinaryDiff.blocks(t1,t2)
        hunk = nil
        return_hunks = []
        saved_delta = []
        delta = []
        diff.size.times do |i|
          s = (i > 0) ? diff[i-1] : {:start_a => 0, :end_a => 0, :start_b => 0, :end_b => 0}
          saved_delta += delta unless delta.empty?
          delta = []
          s1 = diff[i]
          a1 = s[:end_a]
          a2 = s1[:start_a]
          b1 = s[:end_b]
          b2 = s1[:start_b]
          
          old = (a2 == 0) ? [] : l1[a1..(a2-1)]
          newb = (b2 == 0) ? [] : l2[b1..(b2-1)] #stands for new "b"
          
          next if old.empty? && newb.empty?
          if opts[:ignore_ws] || opts[:ignore_blank_lines] || opts[:ignore_ws_amount]
            next if whitespace_clean(old.join,opts) == whitespace_clean(newb.join,opts)
          end
          
          astart = context_start(a1,opts)
          bstart = context_start(b1,opts)
          prev = nil
          if hunk
            if astart < hunk[:end_a] + opts[:context] + 1
              prev = hunk
              astart = hunk[:end_a]
              bstart = hunk[:end_b]
            else
              yield_hunk(hunk, header, l1, delta, opts) {|x| return_hunks << x}

              header = nil
            end
          end
          # move this inside previous nested if statements
          if prev
            hunk[:end_a] = a2
            hunk[:end_b] = b2
            delta = hunk[:delta]
          else
            hunk = {:start_a => astart, :end_a => a2, :start_b => bstart, :end_b => b2, :delta => delta}
          end
          
          hunk[:delta] += l1[astart..(a1-1)].map {|x| ' ' + x } if a1 > 0
          hunk[:delta] += old.map  {|x| remove_line(x, opts) }
          hunk[:delta] += newb.map {|x| add_line(x, opts) } 

        end
        saved_delta += delta
  
        yield_hunk(hunk, header, l1, saved_delta, opts) {|x| return_hunks << x} if hunk
        return_hunks
      end
      
      ##
      # Unpacks a binary-compressed patch.
      # 
      # @param [String] binary the packed binary text to unpack
      def patch_text(binary)
        pos = 0
        t = []
        while pos < binary.size
          p1, p2, l = binary[pos..(pos+11)].unpack("NNN")
          pos += 12
          t << binary[pos..(pos + l - 1)]
          pos += l
        end
        t.join
      end
      
      ##
      # Applies the patch _bin_ to the text _a_.
      # 
      # @param [String] a the text to patch
      # @param [String] bin the binary patch to apply
      def patch(a, bin)
        MercurialPatch.apply_patches(a, [bin])
      end
      
      ##
      # Gets the matching blocks between the two texts.
      # 
      # @param [String] a the original text
      # @param [String] b the final text
      # @return [[Hash]] The blocks of changes between the two
      def get_matching_blocks(a, b)
        an = a.split_lines_better
        bn = b.split_lines_better
        
        SequenceMatcher.new(an, bn).get_matching_blocks
      end
      
      ## 
      # Returns the obvious header for when we create a new file
      # 
      # @param [Fixnum] length the length of the file
      # @return [String] the obvious header
      def trivial_diff_header(length)
        [0, 0, length].pack("NNN")
      end
      
      ##
      # Returns a text diff between a and b. This returns the packed, binary
      # kind of diff.
      def text_diff a,b
        BinaryDiff.bdiff a,b
      end
    end
  end
end