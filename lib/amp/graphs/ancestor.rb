module Amp
  module Graphs
      
    ##
    # = AncestorGenerator
    # A generator class that will allow us to only calculate one ancestor
    # of a node at a time, so we don't have to process the full list of
    # ancestors for each node twice. Our old, lazy way was, if you have two
    # nodes A and B, and need to find the common ancestor, we would generate
    # *all* nodes in both A, and B's history. If the two have a very close
    # common ancestor (usually the case when doing a branch merge in a rapid
    # development environment), then this is a huge amount of wasted processing.
    # Generators aren't a familiar construct for most ruby developers, and they
    # work via continuations, which are also typically avoided like the plague.
    # Check out 'lib/support/generator.rb' to see how it works.
    #
    #    A   B
    #    |   |
    #    |   |
    #    |   |
    #    |___| <-- target ancestor
    #        |
    #        | <-- don't need to generate this node, so we take one at a time
    #
    class AncestorGenerator < Generator
      
      def initialize(vertex, depth, parent_func)
        @vertex, @depth_hash, @parent_func = vertex, depth, parent_func
      end
      
      ##
      # Internal method that, given a vertex, a depth-hash, and a way to 
      # find parents, will yield all the ancestors of a node, in order
      # of depth.
      # 
      # @param vertex the vertex ID of a node in the graph
      # @param [Hash] depth_hash associates a node_id to its depth in
      #   the graph
      # @param [Proc] parent_func a function that calcualtes the parents
      #   of a node
      # @yield every single ancestor in a row, from lowest depth to the
      #   highest
      # @yieldparam [Hash] a hash, with :node pointing to the ID, and :depth
      #   giving the depth of the node
      def traverse_ancestors
        h = PriorityQueue.new
        h[@vertex] = @depth_hash[@vertex]
        seen = {}
        until h.empty?
          node, depth = h.delete_min
          unless seen[node]
            seen[node] = true
            yield({:node => node, :depth => depth})
            @parent_func.call(node).each do |parent|
              h[parent] = @depth_hash[parent]
            end
          end
        end
      end
      
      ##
      # Yields each depth in succession from lowest depth to highest depth,
      # with each node in that depth as a hash.
      # 
      # @param vertex the base vertex to start from
      # @param depth a hash assigning each node to its depth from the vertex
      # @param [Proc] parent_func a proc that gives the parents of a node
      # @yield each generation - a set of vertices that are a given depth
      #   from the node
      # @yieldparam depth the depth that this generation is from the head
      #   vertex provided
      # @yieldparam generation the generation, as a hash assigning entries
      #   in that generation to _true_.
      #
      def generator_loop
        sg, s = nil, {}
        traverse_ancestors do |hash|
          g, v = hash[:depth], hash[:node]
          if g != sg
            yield_gen [sg, s] if sg
            sg, s = g, {v => true}
          else
            s[v] = true
          end
        end
        yield_gen [sg, s]
        nil
      end
    end
    
    class AncestorCalculator
      
      ##
      # Returns the closest common ancestor between A and B, given a method
      # that says how to find the parent of a node.
      # 
      # @param a the first node
      # @param b the second node (order doesn't matter)
      # @param parent_func a way to determine the parents of a node. Should
      #   eventually be made to a block, perhaps.
      # @return the node_id of the least-common ancestor.
      def self.ancestors(a, b, parent_func)
        return a if a == b
        to_visit = [a, b]
        depth = {}
        until to_visit.empty?
          vertex = to_visit.last
          parent_list = parent_func.call(vertex)
          if parent_list.empty?
            depth[vertex] = 0
            to_visit.pop
          else
            parent_list.each do |parent|
              return parent if parent == a || parent == b
              to_visit << parent unless depth[parent]
            end
            if to_visit.last == vertex
              depth[vertex] = parent_list.map {|p| depth[p]}.min - 1
              to_visit.pop
            end
          end
        end
        
        x = AncestorGenerator.new(a, depth, parent_func)
        y = AncestorGenerator.new(b, depth, parent_func)
        
        gx = x.next
        gy = y.next
        
        while gx && gy
          if gx[0] == gy[0]
            gx[1].each do |k,v|
              return k if gy[1].include? k
            end
            gx = x.next
            gy = y.next
          elsif gx[0] > gy[0]
            gy = y.next
          else
            gx = x.next
          end
        end
        return nil
      end
    end

  end
end