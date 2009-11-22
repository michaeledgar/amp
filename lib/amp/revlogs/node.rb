module Amp
  module RevlogSupport
    module Node
      # the null node ID - just 20 null bytes
      NULL_ID = "\0" * 20
      # -1 is the null revision (the last one in the index)
      NULL_REV = -1
      
      ##
      # Returns the node in a short hexadecimal format - only 6 bytes => 12 hex bytes
      #
      # @return [String] the node, in hex, and chopped a bit
      def short(node)
        node.short_hex
      end
    end
  end
end
