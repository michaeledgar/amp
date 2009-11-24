require 'set'

module Amp
  
  ##
  # = Revlog
  # A revlog is a generic file that represents a revision history. This
  # class, while generic, is extremely importantly and highly functional.
  # While the {Amp::Manifest} and {Amp::ChangeLog} classes inherit
  # from Revlog, one can open either file using the base Revlog class.
  #
  # A Revision log is based on two things: an index, which stores some
  # meta-data about each revision in the repository's history, and
  # some data associated with each revision. The data is stored as
  # a (possibly zlib-compressed) diff.
  #
  # There are two versions of revision logs - version 0 and version NG.
  # This information is handled by the {Amp::RevlogSupport:Index} classes.
  #
  # Sometimes the data is stored in a separate file from the index. This
  # is up to the system to decide.
  #
  class Revlog
    include Enumerable
    include RevlogSupport::Node
    
    # the file paths to the index and data files
    attr_reader :index_file, :data_file
    # The actual {Index} object.
    attr_reader :index
    
    ##
    # Initializes the revision log with an opener object (which handles how
    # the interface to opening the files) and the path to the index itself.
    # 
    # @param [Amp::Opener] opener an object that will handle opening the file
    # @param [String] indexfile the path to the index file
    def initialize(opener, indexfile)
      @opener = opener
      @index_file = indexfile
      @data_file  = indexfile[0..-3] + ".d"
      @chunk_cache = nil
      @index = RevlogSupport::Index.parse(opener, indexfile)
      
      # add the null, terminating index entry if it isn't already there
      if @index.index.empty? || @index.is_a?(RevlogSupport::LazyIndex) || 
                               @index.index[-1].node_id.not_null?
        # the use of @index.index is deliberate!
        @index.index << RevlogSupport::IndexEntry.new(0,0,0,-1,-1,-1,-1,NULL_ID)
      end
    end
    alias_method :revlog_initialize, :initialize
    
    ##
    # Actually opens the file.
    def open(path, mode="r")
      @opener.open(path, mode)
    end
    
    ##
    # Returns the requested node as an IndexEntry. Takes either a string or
    # a fixnum index value.
    #
    # @param [String, Fixnum] the index or node ID to look up in the revlog
    # @return [IndexEntry] the requested index entry.
    def [](idx)
      if idx.is_a? String
        return @index[@index.node_map[idx]]
      elsif idx.is_a? Array
        STDERR.puts idx.inspect # KILLME
        idx
      else
        return @index[idx]
      end
    end
    
    ##
    # Returns the unique node_id (a string) for a given revision at _index_.
    # 
    # @param [Fixnum] index the index into the list, from 0-(num_revisions - 1).
    # @return [String] the node's ID
    def node_id_for_index(index)
      unless @index[index]
        raise RevlogSupport::LookupError.new("Couldn't find node for id #{index.inspect}")
      end
      @index[index].node_id
    end
    
    # @see node_id_for_index
    alias_method :node, :node_id_for_index
    
    ##
    # Returns the index number for the given node ID.
    #
    # @param [String] id the node_id to lookup
    # @return [Integer] the index into the revision index where you can find
    #   the requested node.
    def revision_index_for_node(id)
      unless @index.node_map[id]
        raise StandardError.new("Couldn't find node for id #{id.inspect}")
      end
      @index.node_map[id]
    end
    
    ##
    # @see revision_index_for_node
    alias_method :rev, :revision_index_for_node
    
    ##
    # Returns the "link revision" index for the given revision index
    def link_revision_for_index(index)
      self[index].link_rev
    end
    
    ##
    # Returns the node_id's of the parents (1 or 2) of the given node ID.
    def parents_for_node(id)
      #index = revision_index_for_node id
      entry = self[id]
      [ @index[entry.parent_one_rev].node_id , 
        @index[entry.parent_two_rev].node_id ]
    end
    alias_method :parents, :parents_for_node
    
    ##
    # Returns the indicies of the parents (1 or 2) of the node at _index_
    def parent_indices_for_index(index)
      [ self[index].parent_one_rev ,
        self[index].parent_two_rev ]
    end
    
    ##
    # Returns the size of the data for the revision at _index_.
    def data_size_for_index(index)
      self[index].compressed_len
    end
    
    ##
    # Returns the uncompressed size of the data for the revision at _index_.
    def uncompressed_size_for_index(index)
      len = self[index].uncompressed_len
      return len if len >= 0
      
      text = decompress_revision node_id_for_index(index)
      return text.size
    end
    
    ##
    # Returns the offset where the data begins for the revision at _index_.
    def data_start_for_index(index)
      RevlogSupport::Support.get_offset self[index].offset_flags
    end
    
    ##
    # Returns the offset where the data ends for the revision at _index_.
    def data_end_for_index(index)
      data_start_for_index(index) + self[index].compressed_len
    end
    
    ##
    # Returns the "base revision" index for the revision at _index_. 
    def base_revision_for_index(index)
      self[index].base_rev
    end
    
    ##
    # Returns the node ID for the index's tip-most revision
    def tip
      node_id_for_index(@index.size - 2)
    end
    
    ##
    # Returns the number of entries in this revision log.
    def size
      @index.size - 1
    end
    alias_method :index_size, :size
    
    ##
    # Returns true if size is 0
    def empty?
      index_size.zero?
    end
    
    ##
    # Returns each revision as a {Amp::RevlogSupport::IndexEntry}.
    # Don't iterate over the extra revision -1!
    def each(&b); @index[0..-2].each(&b); end
    
    ##
    # Returns all of the indices for all revisions.
    # 
    # @return [Array] all indicies
    def all_indices
      (0..size).to_a
    end
    
    ##
    # Returns a hash of all _ancestral_ nodes that can be reached from
    # the given node ID. Just do [node_id] on the result to check if it's
    # reachable.
    def reachable_nodes_for_node(node, stop=nil)
      reachable = {}
      to_visit = [node]
      reachable[node] = true
      stop_idx = stop ? revision_index_for_node(stop) : 0
      
      until to_visit.empty?
        node = to_visit.shift
        next if node == stop || node.null?
        parents_for_node(node).each do |parent|
          next if revision_index_for_node(parent) < stop_idx
          unless reachable[parent]
            reachable[parent] = true
            to_visit << parent
          end
        end
      end
        
      reachable
    end
    
    ##
    # Allows the user to operate on all the ancestors of the given revisions.
    # One can pass a block, or just call it and get a Set.
    def ancestors(revisions)
      revisions = [revisions] unless revisions.kind_of? Array
      to_visit = revisions.dup
      seen = Set.new([NULL_REV])
      until to_visit.empty?
        parent_indices_for_index(to_visit.shift).each do |parent|
          unless seen.include? parent
            to_visit << parent
            seen     << parent
            yield parent if block_given?
          end
        end
      end
      seen.delete NULL_REV
      seen
    end
    
    ##
    # Allows the user to operate on all the descendants of the given revisions.
    # One can pass a block, or just call it and get a Set. Revisions are passed
    # as indices.
    def descendants(revisions)
      seen = Set.new revisions
      start = revisions.min + 1
      start.upto self.size do |i|
        parent_indices_for_index(i).each do |x|
          if x != NULL_REV && seen.include?(x)
            seen << i
            yield i if block_given?
            break 1
          end
        end
      end
      seen - revisions
    end
    
    ##
    # Returns the topologically sorted list of nodes from the set:
    # missing = (ancestors(heads) \ ancestors(common))
    def find_missing(common=[NULL_ID], heads=self.heads)
      common.map! {|r| revision_index_for_node r}
      heads.map!  {|r| revision_index_for_node r}
      
      has = {}
      ancestors(common) {|a| has[a] = true}
      has[NULL_REV] = true
      common.each {|r| has[r] = true}
      
      missing = {}
      to_visit = heads.reject {|r| has[r]}
      until to_visit.empty?
        r = to_visit.shift
        next if missing.include? r
        missing[r] = true
        parent_indices_for_index(r).each do |p|
          to_visit << p unless has[p]
        end
      end
      
      missing.keys.sort.map {|rev| node_id_for_index rev}
    end
    
    ##
    # Return a tuple containing three elements. Elements 1 and 2 contain
    # a final list bases and heads after all the unreachable ones have been
    # pruned.  Element 0 contains a topologically sorted list of all
    # 
    # nodes that satisfy these constraints:
    # 1. All nodes must be descended from a node in roots (the nodes on
    #    roots are considered descended from themselves).
    # 2. All nodes must also be ancestors of a node in heads (the nodes in
    #    heads are considered to be their own ancestors).
    # 
    # If roots is unspecified, nullid is assumed as the only root.
    # If heads is unspecified, it is taken to be the output of the
    # heads method (i.e. a list of all nodes in the repository that
    # have no children).
    # 
    # @param  [Array<String>] roots
    # @param  [Array<String>] heads
    # @return [{:heads => Array<String>, :roots => Array<String>, :between => Array<String>}]
    def nodes_between(roots=nil, heads=nil)
      no_nodes = {:roots => [], :heads => [], :between => []}
      return no_nodes if roots != nil && roots.empty?
      return no_nodes if heads != nil && heads.empty?
      
      if roots.nil?
        roots = [NULL_ID] # Everybody's a descendent of nullid
        lowest_rev = NULL_REV
      else
        roots = roots.dup
        lowest_rev = roots.map {|r| revision_index_for_node r}.min
      end
      
      if lowest_rev == NULL_REV && heads.nil?
        # We want _all_ the nodes!
        return {:between => all_indices.map {|i| node_id_for_index i },
                :roots => [NULL_ID], :heads => self.heads}
      end
      
      if heads.nil?
        # All nodes are ancestors, so the latest ancestor is the last
        # node.
        highest_rev = self.size - 1
        # Set ancestors to None to signal that every node is an ancestor.
        ancestors = nil
        # Set heads to an empty dictionary for later discovery of heads
        heads = {}
      else
        heads = heads.dup
        ancestors = {}
        
        # Turn heads into a dictionary so we can remove 'fake' heads.
        # Also, later we will be using it to filter out the heads we can't
        # find from roots.
        heads = Hash.with_keys heads, false
        
        # Start at the top and keep marking parents until we're done.
        nodes_to_tag = heads.keys
        highest_rev = nodes_to_tag.map {|r| revision_index_for_node r }.max
        
        until nodes_to_tag.empty?
          # grab a node to tag
          node = nodes_to_tag.pop
          # Never tag nullid
          next if node.null?
          
          # A node's revision number represents its place in a
          # topologically sorted list of nodes.
          r = revision_index_for_node node
          if r >= lowest_rev
            if !ancestors.include?(node)
              # If we are possibly a descendent of one of the roots
              # and we haven't already been marked as an ancestor
              ancestors[node] = true # mark as ancestor
              # Add non-nullid parents to list of nodes to tag.
              nodes_to_tag += parents_for_node(node).reject {|p| p.null? }
            elsif heads.include? node # We've seen it before, is it a fake head?
              # So it is, real heads should not be the ancestors of
              # any other heads.
              heads.delete_at node
            end
          end
        end
        
        return no_nodes if ancestors.empty?
        
        # Now that we have our set of ancestors, we want to remove any
        # roots that are not ancestors.

        # If one of the roots was nullid, everything is included anyway.
        if lowest_rev > NULL_REV
          # But, since we weren't, let's recompute the lowest rev to not
          # include roots that aren't ancestors.

          # Filter out roots that aren't ancestors of heads
          roots = roots.select {|rev| ancestors.include? rev}
          
          return no_nodes if roots.empty? # No more roots?  Return empty list
          
          # Recompute the lowest revision
          lowest_rev = roots.map {|rev| revision_index_for_node rev}.min
        else
          lowest_rev = NULL_REV
          roots = [NULL_ID]
        end
      end
      
      # Transform our roots list into a 'set' (i.e. a dictionary where the
      # values don't matter.
      descendents = Hash.with_keys roots
      
      # Also, keep the original roots so we can filter out roots that aren't
      # 'real' roots (i.e. are descended from other roots).
      roots = descendents.dup
      
      # Our topologically sorted list of output nodes.
      ordered_output = []
      
      # Don't start at nullid since we don't want nullid in our output list,
      # and if nullid shows up in descedents, empty parents will look like
      # they're descendents.
      [lowest_rev, 0].max.upto(highest_rev) do |rev|
        node = node_id_for_index rev
        is_descendent = false
        
        if lowest_rev == NULL_REV # Everybody is a descendent of nullid
          is_descendent = true
        elsif descendents.include? node
          # n is already a descendent
          is_descendent = true
          
          # This check only needs to be done here because all the roots
          # will start being marked is descendents before the loop.
          if roots.include? node
            # If n was a root, check if it's a 'real' root.
            par = parents_for_node node
            # If any of its parents are descendents, it's not a root.
            if descendents.include?(par[0]) || descendents.include?(par[1])
              roots.delete_at node
            end
          end
        else
          # A node is a descendent if either of its parents are
          # descendents. (We seeded the dependents list with the roots
          # up there, remember?)
          par = parents_for_node node
          if descendents.include?(par[0]) || descendents.include?(par[1])
            descendents[node] = true
            is_descendent     = true
          end
        end
        
        if is_descendent && (ancestors.nil? || ancestors.include?(node))
          # Only include nodes that are both descendents and ancestors.
          ordered_output << node
          if !ancestors.nil? && heads.include?(node)
            # We're trying to figure out which heads are reachable
            # from roots.
            # Mark this head as having been reached
            heads[node] = true
          elsif ancestors.nil?
            # Otherwise, we're trying to discover the heads.
            # Assume this is a head because if it isn't, the next step
            # will eventually remove it.
            heads[node] = true
            
            # But, obviously its parents aren't.
            parents_for_node(node).each {|parent| heads.delete parent }
          end
        end
      end
      
      heads = heads.keys.select {|k| heads[k] }
      roots = roots.keys
      {:heads => heads, :roots => roots, :between => ordered_output}
    end
    
    ##
    # Return the list of all nodes that have no children.
    # 
    # if start is specified, only heads that are descendants of
    # start will be returned
    # if stop is specified, it will consider all the revs from stop
    # as if they had no children
    def heads(start=nil, stop=nil)
      if start.nil? && stop.nil?
        count = self.size
        return [NULL_ID] if count == 0
        is_head = [true] * (count + 1)
        count.times do |r|
          e = @index[r]
          is_head[e.parent_one_rev] = is_head[e.parent_two_rev] = false
        end
        return (0..(count-1)).to_a.select {|r| is_head[r]}.map {|r| node_id_for_index r}
      end
      start = NULL_ID if start.nil?
      stop  = [] if stop.nil?
      stop_revs = {}  
      stop.each {|r| stop_revs[revision_index_for_node(r)] = true }
      start_rev = revision_index_for_node start
      reachable = {start_rev => 1}
      heads     = {start_rev => 1}
      (start_rev + 1).upto(self.size - 1) do |r|
        parent_indices_for_index(r).each do |p|
          if reachable[p]
            reachable[r] = 1 unless stop_revs[r]
            heads[r] = 1
          end
          heads.delete p if heads[p] && stop_revs[p].nil?
        end
      end
      
      heads.map {|k,v| node_id_for_index k}
    end
    
    ##
    # Returns the children of the node with ID _node_.
    def children(node)
      c = []
      p = revision_index_for_node node
      (p+1).upto(self.size - 1) do |r|
        prevs = parent_indices_for_index(r).select {|pr| pr != NULL_REV}
        prevs.each {|pr| c << node_id_for_index(r) if pr == p} if prevs.any?
        c << node_id_for_index(r) if p == NULL_REV
      end
      c
    end
    
    ##
    # Tries to find an exact match for a node with ID _id_. If no match is,
    # found, then the id is treated as an index number - if that doesn't work,
    # the revlog will try treating the ID supplied as node_id in hex form.
    def id_match(id)
      return node_id_for_index(id) if id.is_a? Integer
      return id if id.size == 20 && revision_index_for_node(id)
      rev = id.to_i
      rev = self.size + rev if rev < 0
      if id.size == 40
        node = id.unhexlify
        r = revision_index_for_node node
        return node if r
      end
      nil
    end
    
    ##
    # Tries to find a partial match for a node_id in hex form.
    def partial_id_match(id)
      return nil if id.size >= 40
      l = id.size / 2
      bin_id = id[0..(l*2 - 1)].unhexlify
      nl = @index.node_map.keys.select {|k| k[0..(l-1)] == bin_id}
      nl = nl.select {|n| n.hexlify =~ /^#{id}/}
      return nl.first if nl.size == 1
      raise RevlogSupport::LookupError.new("ambiguous ID #{id}") if nl.size > 1
      nil
    end
    
    ##
    # This method will, given an id (or an index) or an ID in hex form,
    # try to find the given node in the index.
    def lookup_id(id)
      n = id_match id
      return n unless n.nil?
      n = partial_id_match id
      return n unless n.nil?
      raise RevlogSupport::LookupError.new("no match found #{id}")
    end
    
    ##
    # Compares a node with the provided text, as a consistency check. Works
    # using <=> semantics.
    def cmp(node, text)
      
      p1, p2 = parents_for_node node
      return RevlogSupport::Support.history_hash(text, p1, p2) != node
    end
    
    ##
    # Loads a block of data into the cache. 
    def load_cache(data_file, start, cache_length)

      if data_file.nil?
        data_file = open(@index_file) if @index.inline?
        data_file = open(@data_file)  unless @index.inline?
      end
      
      # data_file.seek(start, IO::SEEK_SET)
      # sz = data_file.read.length
      # data_file.seek(0, IO::SEEK_SET)
      # $zs = data_file.read.length
      # puts(@index.inline? ? "------- INLINE" : "-------NOT INLINE") #killme
      # puts "------- CACHE_LENGTH = #{cache_length}" # KILLME
      # puts "===" # KILLME
      # puts "We are going to read #{cache_length} bytes starting at #{start}" # KILLME
      # puts "Wait a minute... on Ari's machine, there's only #{sz} bytes to read..." # KILLME
      # puts "Filesize: #{$zs}" # KILLME
      # puts "===" # KILLME
      
      data_file.seek(start, IO::SEEK_SET)
      @chunk_cache = [start, data_file.read(cache_length)]
      data_file
    end
    
    ##
    # Gets a chunk of data from the datafile (or, if inline, from the index
    # file). Just give it a revision index and which data file to use
    # 
    # @param  [Fixnum] rev the revision index to extract
    # @param  [IO] data_file The IO file descriptor for loading data
    # @return [String] the raw data from the index (posssibly compressed)
    def get_chunk(rev, data_file = nil)
      begin
        start, length = self.data_start_for_index(rev), self[rev].compressed_len
      rescue
        Amp::UI.debug "Failed get_chunk: #{@index_file}:#{rev}"
        raise
      end
      
      #puts "The starting point for the data is: #{data_start_for_index(rev)}"   # KILLME
      #puts "We're reading #{length} bytes. Look at data_start_for_index" # KILLME
      
      start += ((rev + 1) * @index.entry_size) if @index.inline?
      
      endpt = start + length
      offset = 0
      if @chunk_cache.nil?
        cache_length = [65536, length].max
        data_file = load_cache data_file, start, cache_length
      else
        cache_start = @chunk_cache[0]
        cache_length = @chunk_cache[1].size
        cache_end = cache_start + cache_length
        if start >= cache_start && endpt <= cache_end
          offset = start - cache_start
        else
          cache_length = [65536, length].max
          data_file = load_cache data_file, start, cache_length
        end
      end
      
      c = @chunk_cache[1]
      return "" if c.nil? || c.empty? || length == 0
      c = c[offset..(offset + length - 1)] if cache_length != length
      
      RevlogSupport::Support.decompress c
    end
    
    ##
    # Unified diffs 2 revisions, based on their indices. They are returned in a sexified
    # unified diff format.
    def unified_revision_diff(rev1, rev2)
      Diffs::MercurialDiff.unified_diff( decompress_revision(self.node_id_for_index(rev1)),
                                      decompress_revision(self.node_id_for_index(rev2)))
    end
    
    ##
    # Diffs 2 revisions, based on their indices. They are returned in
    # BinaryDiff format.
    # 
    # @param [Fixnum] rev1 the index of the source revision
    # @param [Fixnum] rev2 the index of the destination revision
    # @return [String] The diff of the 2 revisions.
    def revision_diff(rev1, rev2)
      return get_chunk(rev2) if (rev1 + 1 == rev2) && 
             self[rev1].base_rev == self[rev2].base_rev
      Diffs::MercurialDiff.text_diff( decompress_revision(node_id_for_index(rev1)),
                                      decompress_revision(node_id_for_index(rev2)))
    end
    
    ##
    # Given a node ID, extracts that revision and decompresses it. What you get
    # back will the pristine revision data!
    # 
    # @param [String] node the Node ID of the revision to extract.
    # @return [String] the pristine revision data.
    def decompress_revision(node)
      return "" if node.nil? || node.null?
      return @index.cache[2] if @index.cache && @index.cache[0] == node
      
      
      text = nil
      rev = revision_index_for_node node
      base = @index[rev].base_rev
      
      if @index[rev].offset_flags & 0xFFFF  > 0
        raise RevlogSupport::RevlogError.new("incompatible revision flag %x" %
                                        (self.index[rev].offset_flags & 0xFFFF))
      end
      data_file = nil
      
      if @index.cache && @index.cache[1].is_a?(Numeric) && @index.cache[1] >= base && @index.cache[1] < rev
        base = @index.cache[1]
        text = @index.cache[2]
        # load the index if we're lazy (base, rev + 1)
      end
      data_file = open(@data_file) if !(@index.inline?) && rev > base + 1
      text = get_chunk(base, data_file) if text.nil?
      bins = ((base + 1)..rev).map {|r| get_chunk(r, data_file)}
      text = Diffs::MercurialPatch.apply_patches(text, bins)
      
      p1, p2 = parents_for_node node
      if node != RevlogSupport::Support.history_hash(text, p1, p2)
        raise RevlogSupport::RevlogError.new("integrity check failed on %s:%d, data:%s" % 
                                             [(@index.inline? ? @index_file : @data_file), rev, text.inspect])
      end
      @index.cache = [node, rev, text]
      text
    end
    
    ############ TODO
    # @todo FINISH THIS METHOD
    # @todo FIXME
    # FINISH THIS METHOD
    # TODO
    # FIXME
    def check_inline_size(tr, fp=nil)
      return unless @index.inline?
      if fp.nil?
        fp = open(@index_file, "r")
        fp.seek(0, IO::SEEK_END)
      end
      size = fp.tell
      return if size < 131072
      
      trinfo = tr.find(@index_file)
      if trinfo.nil?
        raise RevlogSupport::RevlogError.new("#{@index_file} not found in the"+
                                             "transaction")
      end
      trindex = trinfo[:data]
      data_offset = data_start_for_index trindex
      tr.add @data_file, data_offset
      df = open(@data_file, 'w')
      begin
        calc = @index.entry_size
        self.size.times do |r|
          start = data_start_for_index(r) + (r + 1) * calc
          length = self[r].compressed_len
          fp.seek(start)
          d = fp.read length
          df.write d
        end
      ensure
        df.close
      end
      fp.close
      
      ############ TODO
      # FINISH THIS METHOD
      ############ TODO
    end
    
    ##
    # add a revision to the log
    # 
    # @param [String] text the revision data to add
    # @param transaction the transaction object used for rollback
    # @param link the linkrev data to add
    # @param [String] p1 the parent nodeids of the revision
    # @param [String] p2 the parent nodeids of the revision
    # @param d an optional precomputed delta
    # @return [String] the digest ID referring to the node in the log
    def add_revision(text, transaction, link, p1, p2, d=nil, index_file_handle=nil)
      node = RevlogSupport::Support.history_hash(text, p1, p2)
      return node if @index.node_map[node]
      curr = index_size
      prev = curr - 1
      base = self[prev].base_rev
      offset = data_end_for_index prev
      if curr > 0
        if d.nil? || d.empty?
          ptext = decompress_revision node_id_for_index(prev)
          d = Diffs::MercurialDiff.text_diff(ptext, text)
        end
        data = RevlogSupport::Support.compress d
        len = data[:compression].size + data[:text].size
        dist = len + offset - data_start_for_index(base)
      end
      # Compressed diff > size of actual file
      if curr == 0 || dist > text.size * 2
        data = RevlogSupport::Support.compress text
        len = data[:compression].size + data[:text].size
        base = curr
      end
      entry = RevlogSupport::IndexEntry.new(RevlogSupport::Support.offset_version(offset, 0), 
                len, text.size, base, link, rev(p1), rev(p2), node)
      @index << entry
      @index.node_map[node] = curr
      @index.write_entry(@index_file, entry, transaction, data, index_file_handle)
      @index.cache = [node, curr, text]
      node
    end
    
    ##
    # Finds the most-recent common ancestor for the two nodes.
    def ancestor(a, b)
      parent_func = proc do |rev| 
        self.parent_indices_for_index(rev).select {|i| i != NULL_REV }
      end
      c = Graphs::AncestorCalculator.ancestors(revision_index_for_node(a),
                                               revision_index_for_node(b),
                                               parent_func)
      return NULL_ID if c.nil?
      node_id_for_index c
    end
    
    ##
    # Yields chunks of change-group data for writing to disk, given
    # a nodelist, a method to lookup stuff. Given a list of changset
    # revs, return a set of deltas and metadata corresponding to nodes.
    # the first delta is parent(nodes[0]) -> nodes[0] the receiver is
    # guaranteed to have this parent as it has all history before these
    # changesets. parent is parent[0]
    #
    # FIXME -- could be the cause of our failures with #pre_push!
    # @param [[String]] nodelist
    # @param [Proc, #[], #call] lookup
    # @param [Proc, #[], #call] info_collect can be left nil
    def group(nodelist, lookup, info_collect=nil)
      revs = nodelist.map {|n| rev n }

      # if we don't have any revisions touched by these changesets, bail
      if revs.empty?
        yield RevlogSupport::ChangeGroup.closing_chunk
        return
      end
      
      # add the parent of the first rev
      parent1 = parents_for_node(node(revs[0]))[0]
      revs.unshift rev(parent1)
      
      # build deltas
      0.upto(revs.size - 2) do |d|
        a, b = revs[d], revs[d + 1]
        nb = node b
        
        info_collect[nb] if info_collect
        
        p = parents(nb)
        meta = nb + p[0] + p[1] + lookup[nb]
        
        if a == -1
          data = decompress_revision nb
          meta += Diffs::MercurialDiff.trivial_diff_header(d.size)
        else
          
          data = revision_diff(a, b)
        end
        
        yield RevlogSupport::ChangeGroup.chunk_header(meta.size + data.size)
        yield meta
        if data.size > 1048576
          pos = 0
          while pos < data.size
            pos2 = pos + 262144
            yield data[pos..(pos2-1)]
            pos = pos2
          end
        else
          yield data
        end
      end
      yield RevlogSupport::ChangeGroup.closing_chunk
    end
    
    # Adds a changelog to the index
    # 
    # @param [StringIO, #string] revisions something we can iterate over (Usually a StringIO)
    # @param [Proc, #call, #[]] link_mapper
    # @param [Amp::Journal] journal to start a transaction
    def add_group(revisions, link_mapper, journal)
      r = index_size
      t = r - 1
      node = nil
      
      base = prev = RevlogSupport::Node::NULL_REV
      start = endpt = text_len = 0
      endpt = data_end_for_index t if r != 0
      
      index_file_handle = open(@index_file, "a+")
      index_size = r * @index.entry_size
      if @index.inline?
        journal << [@index_file, endpt + index_size, r]
        data_file_handle = nil
      else
        journal << [@index_file, index_size, r]
        journal << [@data_file, endpt]
        data_file_handle = open(@data_file, "a")
      end
      
      begin #errors abound here i guess
        chain = nil
        
        Amp::RevlogSupport::ChangeGroup.each_chunk(revisions) do |chunk|
          node, parent1, parent2, cs = chunk[0..79].unpack("a20a20a20a20")
          link = link_mapper.call(cs)
          
          if @index.node_map[node]
            chain = node
            next
          end
          delta = chunk[80..-1]
          [parent1, parent2].each do |parent|
            unless @index.node_map[parent]
              raise RevlogSupport::LookupError.new("unknown parent #{parent}"+
                                                         " in #{@index_file}")
            end
          end
          
          unless chain
            chain = parent1
            unless @index.node_map[chain]
              raise RevlogSupport::LookupError.new("unknown parent #{chain}"+
                                          " from #{chain} in #{@index_file}")
            end
          end
          
          if chain == prev
            cdelta = RevlogSupport::Support.compress delta
            cdeltalen = cdelta[:compression].size + cdelta[:text].size
            text_len = Diffs::MercurialPatch.patched_size text_len, delta
          end
          
          if chain != prev || (endpt - start + cdeltalen) > text_len * 2
            #flush our writes here so we can read it in revision
            data_file_handle.flush if data_file_handle
            index_file_handle.flush
            text = decompress_revision(chain)
            if text.size == 0
              text = delta[12..-1]
            else
              text = Diffs::MercurialPatch.apply_patches(text, [delta])
            end
            chk = add_revision(text, journal, link, parent1, parent2, 
                                  nil, index_file_handle)
            # if (! data_file_handle) && (! @index.inline?)
            #   data_file_handle = open(@data_file, "a")
            #   index_file_handle = open(@index_file, "a")
            # end
            if chk != node
              raise RevlogSupport::RevlogError.new("consistency error "+
                        "adding group")
            end
            text_len = text.size
          else
            entry = RevlogSupport::IndexEntry.new(RevlogSupport::Support.offset_version(endpt, 0),
                       cdeltalen,text_len, base, link, rev(parent1), rev(parent2), node)
            @index << entry
            @index.node_map[node] = r
            @index.write_entry(@index_file, entry, journal, cdelta, index_file_handle)
          end
          
          
          t, r, chain, prev = r, r + 1, node, node
          base  = self[t].base_rev
          start = data_start_for_index base
          endpt = data_end_for_index t
        end
      rescue Exception => e
        puts e
        puts e.backtrace
      ensure
        if data_file_handle && !(data_file_handle.closed?)
          data_file_handle.close
        end
        index_file_handle.close
      end
      node
    end
    
    ##
    # Strips all revisions after (and including) a given link_index
    def strip(min_link)
      return if size == 0
      
      load_index_map if @index.is_a? RevlogSupport::LazyIndex
      
      rev = 0
      all_indices.each {|_rev| rev = _rev; break if @index[rev].link_rev >= min_link }
      return if rev > all_indices.max
      
      endpt = data_start_for_index rev
      unless @index.inline?
        df = File.open(@data_file, "a")
        df.truncate(endpt)
        endpt = rev * @index.entry_size
      else
        endpt += rev * @index.entry_size
      end
      
      indexf = File.open(@index_file, "a")
      indexf.truncate(endpt)
      
      @cache = @index.cache = nil
      @chunk_cache = nil
      rev.upto(self.size-1) {|x| @index.node_map.delete(self.node(x)) }
      @index.index = @index.index[0..rev-1]
    end
    
    ##
    # Checks to make sure our data and index files are the right size.
    # Returns the differences between expected and actual sizes.
    def checksize
      expected = 0
      expected = [0, data_end_for_index(self.index_size - 1)].max if self.index_size > 0
      
      
      
      
      f = open(@index_file)
      f.seek(0, IO::SEEK_END)
      actual = f.tell
      s = @index.entry_size
      i = [0, actual / s].max
      di = actual - (i * s)
      
      if @index.inline?
        databytes = 0
        self.index_size.times do |r|
          databytes += [0, self[r].compressed_len].max
        end
        dd = 0
        di = actual - (self.index_size * s) - databytes
      else
        f = open(@data_file)
        f.seek(0, IO::SEEK_END)
        actual = f.tell
        dd = actual - expected
        f.close
      end
      
      return {:data_diff => dd, :index_diff => di}
    end
    
    ##
    # Returns all the files this object is concerned with.
    def files
      res = [ @index_file ]
      res << @data_file unless @index.inline?
      res
    end
      
  end
end
