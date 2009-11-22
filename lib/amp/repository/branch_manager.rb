module Amp
  module Repositories
    ##
    # = BranchManager
    # Michael Scott for Amp.
    #
    # More seriously, this class handles reading/writing to the branch cache
    # and figuring out what the head revisions are for each branch and such.
    module BranchManager
      include Amp::RevlogSupport::Node
      
      ##
      # Saves the branches with the given "partial" and the last_rev index.
      def save_branch_cache(partial, last_rev)
        tiprev = self.size - 1
        # If our cache is outdated, then update it and re-write it
        if last_rev != tiprev
          # search for new heads
          update_branches!(partial, last_rev+1, tiprev+1)
          # write our data out
          write_branches!(partial, self.changelog.tip, tiprev)
        end
        # return our mappings
        partial
      end
      
      ##
      # Loads the head revisions for each branch. Each branch has at least one, but
      # possible more than one, head.
      #
      # @return [Hash] a map, where the branch names are keys and the values
      #   are the heads of the branch
      def branch_heads
        # Gets the mapping of branch names to branch heads, but uses caching to avoid
        # doing IO and tedious computation over and over. As long as our tip doesn't
        # change, the cache will remain valid.
        
        # Check our current tip
        tip = self.changelog.tip
        # Do we have a cache, and if we do, is the saved cache == tip?
        if !@branch_cache.nil? && @branch_cache_tip == tip
          # if so, cache HIT
          return @branch_cache
        end
        
        # nope? cache miss
        # save the old tip
        oldtip = @branch_cache_tip
        # save the new tip
        @branch_cache_tip = tip
        
        # reset the branch cache
        @branch_cache = @branch_cache.nil? ? {} : @branch_cache.clear # returns same hash, but empty
        # if we didn't have an old cache, or it was invalid, read in the branches again
        if oldtip.nil? || self.changelog.node_map[oldtip].nil?
          partial, last, last_rev = read_branches!
        else
          # Otherwise, dig up the cached hash!
          last_rev = self.changelog.rev(oldtip)
          # Get the last branch cache
          partial = @u_branch_cache
        end
        # Save the branch cache (updating it if we have to)
        save_branch_cache(partial, last_rev)
        
        # Cache our saved hash
        @u_branch_cache = partial
        
        # Copy the partial into the branch_cache
        partial.each { |k, v| @branch_cache[k] = v }
        @branch_cache
      end
      
      # Returns a dict where branch names map to the tipmost head of
      # the branch, open heads come before closed
      def branch_tags
        tags = {}
        branch_heads.each do |branch_node, local_heads|
          head = nil
          local_heads.reverse_each do |h| # get the tip if its a closed
            if !(changelog.read(h)[5].include?("close"))
              head = h
              break
            end
          end
          head = local_heads.last if head.nil?
          tags[branch_node] = head # it's the tip
        end
        return tags
      end
      
      ##
      # Saves the branches, the tip-most node, and the tip-most revision
      # to the branch cache.
      #
      def save_branches(branches, tip, tip_revision)
        write_branches!(branches, tip, tip_revision)
      end
      
      private
      
      ##
      # Reads in the branches from the branch.cache file, stored in the root
      # of the repository's .hg folder. While the repository could figure out
      # what each branch's heads are each time the program is run, that would
      # be quite slow. So we cache them in a file, along with the tip of the
      # repository, so we know if our cache has become inaccurate.
      # The format is very simple:
      #     [tip_node_id] [tip_revision_number]
      #     [branch_head_node_id] [branch_name]
      #     [branch_head_node_id] [branch_name]
      #     [branch_head_node_id] [branch_name]
      #
      # Example:
      #     0abc3135810abc3135810abc3135810abc313581 603
      #     0abc3135810abc3135810abc3135810abc313581 default
      #     1234567890123456789012345678901234567890 other_branch
      #     0987654321098765432109876543210987654321 other_branch
      #
      # In the example, other_branch has 2 heads. This is acceptable. The tip of the
      # repository is node 0abc3135, revision 603, which is the only head of the default
      # branch.
      #
      # @return [[Hash, String, Integer]] The results are returned in the form of:
      #   [partial, tip_node_id, tip_rev_index], where +partial+ is a mapping of
      #   branch names to an array of their heads.
      def read_branches!
        partial, last, last_rev = {}, nil, nil
        lines = nil
        invalid = false
        
        begin
          # read in all the lines. This file should be short, so don't worry about
          # performance concerns of a File.read() call (this call is actually
          # Opener#read, which then calls File.read)
          lines = @hg_opener.read("branchheads.cache").split("\n")
        rescue SystemCallError # IO Errors, i.e. if there is no branch.cache file
          return {}, NULL_ID, NULL_REV
        end
        # use catch, not exceptions (exceptions are more costly)
        valid = catch(:invalid) do
          # Read in the tip node and tip revision #
          last, last_rev = lines.shift.split(" ", 2)
          last, last_rev = last.unhexlify, last_rev.to_i
          
          # if we aren't matching up with the current repo, then invalidate the cache
          if last_rev > self.size || self[last_rev].node != last
            throw :invalid, false
          end
          
          # Go through each next line and read in a head-branch pair
          lines.each do |line|
            # empty = useless line
            next if line.nil? || line.empty?
            # split on " ", only once so we can have a space in a branch name
            node, _label = line.split(" ", 2)
            # and assign to our "partial" i.e. our list of branch-heads
            partial[_label.strip] ||= []
            partial[_label.strip] << node.unhexlify
          end
        end
        
        # if invalid was thrown.... bail
        unless valid
          UI.puts("invalidating branch cache (tip different)")
          partial, last, last_rev = {}, NULL_ID, NULL_REV
        end
        
        # Return our results!
        [partial, last, last_rev]
      end
      
      ##
      # Invalidates the tag cache. Removes all ivars relating to tags.
      def invalidate_branch_cache!
        @branch_cache = nil
        @branch_cache_tip = nil
        @u_branch_cache = nil
      end
      
      ##
      # Goes through from revision +start+ to revision +stop+ and searches for
      # new branch heads for each branch. Annoying, yes. But necessary to keep the
      # cache up to date.
      #
      # @param [Hash] partial the current pairing of branch names to heads. Might
      #   be incomplete, which is why it's called "partial"
      # @param [Integer] start the revision # to start looking new branch heads
      # @param [Integer] stop the last revision in which to look for branch heads
      def update_branches!(partial, start, stop)
        (start..(stop-1)).each do |r|
          # get the changeset
          changeset = self[r]
          # look at its branch
          branch = changeset.branch
          # get that branch's partial list of heads
          
          branch_heads = (partial[branch] ||= [])
          # add this changeset
          branch_heads << changeset.node
          # remove our parents from this branch's list of heads if they're in there,
          # because if they have children, they aren't heads.
          changeset.parents.each do |parent|
            # get the node_id
            parent_node = parent.node
            # remove the parent
            branch_heads.delete parent_node if branch_heads.include? parent_node
          end
        end
      end
      
      ##
      # Writes the branches out to the branch cache. Simple as that. See #read_branches!
      # for the file format.
      #
      # @see read_branches!
      # @param [Hash] branches a mapping of branch names to arrays of their head node IDs
      # @param [String] tip the tip of this repository's node ID
      # @param [Integer] tip_revision the index # of this repository's tip
      def write_branches!(branches, tip, tip_revision)
        @hg_opener.open "branchheads.cache", "w" do |f|
          f << "#{tip.hexlify} #{tip_revision}\n"
          branches.each do |_label, nodes|
            nodes.each {|node| f << "#{node.hexlify} #{_label}\n" }
          end
        end
      rescue SystemCallError
        
      end
    end
    MichaelScott = BranchManager # hehehe
  end
end

