module Amp
  module Merges
    
    class MergeAssertion < StandardError; end
    ##
    # SimpleMerge - basic 3-way merging
    #
    # This class takes 2 texts and a common ancestor text, and tries
    # to produce a text incorporating all the changes from ancestor->local
    # and ancestor->remote. It will produce the annoying >>>>>> ====== <<<<<
    # markers just like mercurial/cvs does.
    #
    # For the record, for any methods that don't have comments in the code, I
    # have an excuse: I don't understand the code.
    #
    # p.s. threeway. hehe. three way.
    class ThreeWayMerger
      
      def assert(val, msg="Assertion failed")
        raise MergeAssertion.new(msg) unless val
      end
      
      # Have there been any conflicts in the merge?
      attr_accessor :conflicts
      
      ##
      # Performs a 3-way merge on the 3 files provided. Saves the merged file over the
      # local file. This basically handles the file juggling while applying the instance
      # methods to do merging.
      #
      # @param [String] local path to the original local file
      # @param [String] base path to a (temporary) base file
      # @param [String] other path to a (temporary) target file
      # @param [Hash] opts additional options for merging
      # @return [Boolean] were there conflicts during the merge?
      def self.three_way_merge(local, base, other, opts={})
        name_a = local
        name_b = other
        labels = opts[:labels] || []
        
        name_a = labels.shift if labels.any?
        name_b = labels.shift if labels.any?
        raise abort("You can only specify 2 labels") if labels.any?
        
        local_text = read_file local
        base_text  = read_file base
        other_text = read_file other
        local = Pathname.new(local).realpath
        unless opts[:print]
          # special temp name for our new merged file
          newname = File.amp_make_tmpname local
          out     = File.open newname, "w"
          
          # add rename method to this object to do atomicity
          def out.rename(local, newname)
            self.close
            File.unlink(local)
            File.move(newname, local)
          end
        else
          out = STDOUT
        end
        
        reprocess = !opts[:no_minimal]
        merger = ThreeWayMerger.new(base_text, local_text, other_text)
        merger.merge_lines(:name_a => name_a, :name_b => name_b, :reprocess => reprocess) do |line|
          out.write line
        end
        
        out.rename(local, newname) unless opts[:print]
        
        if merger.conflicts
          unless opts[:quiet]
            UI.warn("conflicts during merge.")
          end
          return true # yes conflicts
        end
        
        false # no conflicts
      end
      
      ##
      # Initializes the merger object with the 3 necessary texts, as well as
      # subsections to merge (if we don't want to merge the entire texts).
      #
      # @param [String] base_text the common ancestor text, from which we
      #   are merging changes
      # @param [String] a_text one descendent text - typically the local copy
      #   of the file
      # @param [String] b_text the other descendent text - typically a copy
      #   committed by somebody else.
      # @param [String] base_subset (base_text.split_newlines) the subsection
      #   of the common ancestor we are concerned with (if not merging full texts)
      # @param [String] a_subset (a_text.split_newlines) the subsection
      #   of the first text we are concerned with (if not merging full texts)
      # @param [String] b_subset (b_text.split_newlines) the subsection
      #   of the second text we are concerned with (if not merging full texts)
      def initialize(base_text, a_text, b_text, base=nil, a=nil, b=nil)
        @base_text, @a_text, @b_text = base_text, a_text, b_text
        @base = base || @base_text.split_lines_better
        @a    = a    || @a_text.split_lines_better
        @b    = b    || @b_text.split_lines_better
      end
      
      ##
      # Merges the texts in a CVS-like form. The start_marker, mid_markers, and end_marker
      # arguments are used to delimit conflicts. Yields lines - doesn't return anything.
      #
      # @yield the merged lines
      # @yieldparam [String] line 1 line that belongs in the merged file.
      def merge_lines(opts = {})
        defaults = {:name_a => nil, :name_b => nil, :name_base => nil,
                    :start_marker => "<<<<<<<", :mid_marker => "=======", 
                    :end_marker => ">>>>>>>", :base_marker => nil, :reprocess => false}
        opts = defaults.merge(opts)
        
        @conflicts = false # no conflicts yet!
        # Figure out what our newline character is (silly windows)
        newline = "\n"
        if @a.size > 0
          newline = "\r\n" if @a.first.end_with?("\r\n")
          newline = "\r"   if @a.first.end_with?("\r")
        end
        
        if opts[:base_marker] && opts[:reprocess]
          raise ArgumentError.new("Can't reprocess and show base markers!")
        end
        
        # Add revision names to the markers
        opts[:start_marker] += " #{opts[:name_a]}"    if opts[:name_a]
        opts[:end_marker]   += " #{opts[:name_b]}"    if opts[:name_b]
        opts[:base_marker]  += " #{opts[:name_base]}" if opts[:name_base] && opts[:base_marker]
        
        merge_method = opts[:reprocess] ? :reprocessed_merge_regions : :merge_regions
        self.send(merge_method) do |*t|
          status = t[0]
          case status
          when :unchanged
            t[1].upto(t[2]-1) {|i| yield @base[i] } # nothing changed, use base
          when :a, :same
            t[1].upto(t[2]-1) {|i| yield @a[i]    } # local (A) insertion
          when :b
            t[1].upto(t[2]-1) {|i| yield @b[i]    } # remote (B) insertion
          when :conflict
            @conflicts = true # :-( we have conflicts
            
            yield opts[:start_marker] + newline # do the <<<<<<
            t[3].upto(t[4]-1) {|i| yield @a[i]} # and the local copy
            
            if opts[:base_marker]
              yield base_marker + newline       # do the base
              t[1].upto(t[2]-1) {|i| yield @base[i]} # and the base lines
            end
            
            yield opts[:mid_marker] + newline   # do the =====
            t[5].upto(t[6]-1) {|i| yield @b[i]} # and the remote copy
            yield opts[:end_marker] + newline   # and then >>>>>>
          else
            raise ArgumentError.new("invalid region: #{status.inspect}")
          end
        end
        
      end
      
      ##
      # Yield sequence of line groups.  Each one is a tuple:
      # 
      # :unchanged, lines
      #      Lines unchanged from base
      # 
      # :a, lines
      #      Lines taken from a
      # 
      # :same, lines
      #      Lines taken from a (and equal to b)
      # 
      # :b, lines
      #      Lines taken from b
      # 
      # :conflict, base_lines, a_lines, b_lines
      #      Lines from base were changed to either a or b and conflict.
      def merge_groups
        merge_regions do |list|
          case list[0]
          when :unchanged
            yield list[0], @base[list[1]..(list[2]-1)]
          when :a, :same
            yield list[0],    @a[list[1]..(list[2]-1)]
          when :b
            yield list[0],    @b[list[1]..(list[2]-1)]
          when :conflict
            yield list[0], @base[list[1]..(list[2]-1)],
                              @a[list[3]..(list[4]-1)],
                              @b[list[5]..(list[6]-1)]
          else
            raise ArgumentError.new(list[0])
          end
        end
      end
      
      ##
      # Yield sequences of matching and conflicting regions.
      # 
      # This returns tuples, where the first value says what kind we
      # have:
      # 
      # 'unchanged', start, end
      #      Take a region of base[start:end]
      # 
      # 'same', astart, aend
      #      b and a are different from base but give the same result
      # 
      # 'a', start, end
      #      Non-clashing insertion from a[start:end]
      # 
      # Method is as follows:
      # 
      # The two sequences align only on regions which match the base
      # and both descendents.  These are found by doing a two-way diff
      # of each one against the base, and then finding the
      # intersections between those regions.  These "sync regions"
      # are by definition unchanged in both and easily dealt with.
      # 
      # The regions in between can be in any of three cases:
      # conflicted, or changed on only one side.
      #
      # @yield Arrays of regions that require merging
      def merge_regions
        ##     NOTE: we use "z" as an abbreviation for "base" or the "ancestor", because
        #      we can't very well abbreviate "ancestor" as "a" or "base" as "b".
        idx_z = idx_a = idx_b = 0
        
        find_sync_regions.each do |match|
          z_match, z_end = match[:base_start], match[:base_end]
          a_match, a_end = match[:a_start   ], match[:a_end   ]
          b_match, b_end = match[:b_start   ], match[:b_end   ]
          
          match_len = z_end - z_match
          assert match_len >= 0
          assert match_len == (a_end - a_match), "expected #{match_len}, got #{(a_end - a_match)} (#{a_end} - #{a_match})"
          assert match_len == (b_end - b_match)
          
          len_a = a_match - idx_a
          len_b = b_match - idx_b
          len_base = z_match - idx_z
          assert len_a >= 0
          assert len_b >= 0
          assert len_base >= 0
          
          if len_a > 0 || len_b > 0
            equal_a = compare_range(@a, idx_a, a_match, @base, idx_z, z_match)
            equal_b = compare_range(@b, idx_b, b_match, @base, idx_z, z_match)
            same    = compare_range(@a, idx_a, a_match, @b,    idx_b, b_match)
            
            if same
              yield :same, idx_a, a_match
            elsif equal_a && !equal_b
              yield :b, idx_b, b_match
            elsif equal_b && !equal_a
              yield :a, idx_a, a_match
            elsif !equal_a && !equal_b
              yield :conflict, idx_z, z_match, idx_a, a_match, idx_b, b_match
            else
              raise AssertionError.new("can't handle a=b=base but unmatched!")
            end
            
            idx_a = a_match
            idx_b = b_match
          end
          idx_z = z_match
          
          if match_len > 0
            assert idx_a == a_match
            assert idx_b == b_match
            assert idx_z == z_match
            
            yield :unchanged, z_match, z_end
            
            idx_a = a_end
            idx_b = b_end
            idx_z = z_end
          end
        end
      end
      
      ##
      # Take the merge regions yielded by merge_regions, and remove lines where both A and
      # B (local & remote) have made the same changes.
      def reprocessed_merge_regions
        merge_regions do |*region|
          if region[0] != :conflict
            yield *region
            next
          end
          type, idx_z, z_match, idx_a, a_match, idx_b, b_match = region
          a_region = @a[idx_a..(a_match-1)]
          b_region = @b[idx_b..(b_match-1)]
          matches = Amp::Diffs::MercurialDiff.get_matching_blocks(a_region.join, b_region.join)
          
          next_a = idx_a
          next_b = idx_b
          
          matches[0..-2].each do |block|
            region_ia, region_ib, region_len = block[:start_a], block[:start_b], block[:length]
            region_ia += idx_a
            region_ib += idx_b
            
            reg = mismatch_region(next_a, region_ia, next_b, region_ib)
            
            yield *reg if reg
            yield :same, region_ia, region_len + region_ia
            
            next_a = region_ia + region_len
            next_b = region_ib + region_len
            
          end
          reg = mismatch_region(next_a, a_match, next_b, b_match)
          yield *reg if reg
        end
      end
      
      
      
      ##
      # Returns a list of sync'd regions, where both descendents match the base.
      # Generates a list of {:base_start, :base_end, :a_start, :a_end, :b_start, :b_end}
      #
      # @return [Array<Hash>] A list of sync regions, each stored as a hash, with the
      #   keys {:base_start, :base_end, :a_start, :a_end, :b_start, :b_end}. There is
      #   always a zero-length sync region at the end of any file (because the EOF always
      #   matches).
      def find_sync_regions
        idx_a = idx_b = 0
        a_matches = Amp::Diffs::MercurialDiff.get_matching_blocks(@base_text, @a_text)
        b_matches = Amp::Diffs::MercurialDiff.get_matching_blocks(@base_text, @b_text)
        
        len_a, len_b = a_matches.size, b_matches.size
        sync_regions = []
        
        while idx_a < len_a && idx_b < len_b
          next_a, next_b = a_matches[idx_a], b_matches[idx_b]
          
          a_base, a_match, a_len = next_a[:start_a], next_a[:start_b], next_a[:length]
          b_base, b_match, b_len = next_b[:start_a], next_b[:start_b], next_b[:length]
          
          intersection = (a_base..(a_base+a_len)) - (b_base..(b_base+b_len))
          if intersection
            # add the sync region
            sync_regions << synced_region_for_intersection(intersection, a_base, b_base, a_match, b_match)
          end
          if (a_base + a_len) < (b_base + b_len)
            idx_a += 1
          else
            idx_b += 1
          end
        end
        # add the EOF-marker
        inter_base = @base.size
        a_base     = @a.size
        b_base     = @b.size
        sync_regions << {:base_start => inter_base, :base_end => inter_base,
                         :a_start    => a_base,   :a_end    => a_base      ,  
                         :b_start    => b_base,   :b_end    => b_base      }
        
        sync_regions
      end
      
      def synced_region_for_intersection(intersection, a_base, b_base, a_match, b_match)
        inter_base = intersection.begin
        inter_end  = intersection.end
        inter_len  = inter_end - inter_base
        
        # found a match of base[inter_base..inter_end] - this may be less than the region
        # that matches in either one. Let's do some assertions
        #assert inter_len <= a_len
        #assert inter_len <= b_len
        assert a_base    <= inter_base
        assert b_base    <= inter_base
        
        # shift section downward or upward
        a_sub = a_match + (inter_base - a_base)
        b_sub = b_match + (inter_base - b_base)
        # end points = base_len + starts
        a_end = a_sub + inter_len
        b_end = b_sub + inter_len
        
        # make sure the texts are equal of course....
        assert @base[inter_base..(inter_end-1)] == @a[a_sub..(a_end-1)]
        assert @base[inter_base..(inter_end-1)] == @b[b_sub..(b_end-1)]
        
        # return the sync region
        {:base_start => inter_base, :base_end => inter_end,
         :a_start    => a_sub,   :a_end    => a_end       ,  
         :b_start    => b_sub,   :b_end    => b_end       }
      end
      
      private
      
      def mismatch_region(next_a, region_ia, next_b, region_ib)
        if next_a < region_ia || next_b < region_ib
          return :conflict, nil, nil, next_a, region_ia, next_b, region_ib
        end
        nil
      end
      
      ##
      # Reads a file, but raises warnings if it's binary and we shouldn't be
      # working with it.
      #
      # @param [String] filename the path to the file to read
      # @param [Hash] opts the options for handling binary files
      def self.read_file(filename, opts={})
        text = File.read filename
        if text.binary?
          message = "#{filename} appears to be a binary file."
          raise abort(message) unless opts[:text]
          UI.warn(message) unless opts[:quiet]
        end
        text
      end
      
      ##
      # Compares arr_a[a_start...a_end] == arr_b[b_start...b_end], without
      # actually cutting up the array and thus allocating memory.
      #
      # @param [Array<Comparable>] arr_a an array of objects that can be compared to arr_b
      # @param [Integer] a_start the index to begin comparison
      # @param [Integer] a_end the index to end comparison (exclusive - arr_a[a_end] is NOT
      #   compared to arr_b[b_end])
      # @param [Array<Comparable>] arr_b an array of objects that can be compared to arr_a
      # @param [Integer] b_start the index to begin comparison
      # @param [Integer] b_end the index to end comparison (exclusive - arr_a[a_end] is NOT
      #   compared to arr_b[b_end])
      # @return [Boolean] true if arr_a == arr_b, false if arr_a != arr_b
      def compare_range(arr_a, a_start, a_end, arr_b, b_start, b_end)
        return false if (a_end - a_start) != (b_end - b_start)
        idx_a, idx_b = a_start, b_start
        while idx_a < a_end && idx_b < b_end
          return false if arr_a[idx_a] != arr_b[idx_b]
          idx_a += 1
          idx_b += 1
        end
        true
      end
      
    end
  end
end

Threesome = Amp::Merges::ThreeWayMerger