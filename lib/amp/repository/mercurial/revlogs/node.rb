##################################################################
#                  Licensing Information                         #
#                                                                #
#  The following code is licensed, as standalone code, under     #
#  the Ruby License, unless otherwise directed within the code.  #
#                                                                #
#  For information on the license of this code when distributed  #
#  with and used in conjunction with the other modules in the    #
#  Amp project, please see the root-level LICENSE file.          #
#                                                                #
#  © Michael J. Edgar and Ari Brown, 2009-2010                   #
#                                                                #
##################################################################

module Amp
  module Mercurial
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
        
        ##
        # Is string equal to the NULL_ID used in revision logs?
        #
        # @param [String] string the string to check if it's a null revision ID
        # @return [Boolean] is the string a null ID?
        def null?(string)
          string == NULL_ID
        end
        opposite_method :not_null?, :null?
      end
    end
  end
end
