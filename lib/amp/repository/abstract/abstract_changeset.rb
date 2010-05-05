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
  module Repositories
    class AbstractChangeset
      include CommonChangesetMethods
      include Enumerable
      include Comparable
      
      ##
      # the nodes that this node inherits from
      # 
      # @return [Array<Abstract Changeset>]
      def parents
        raise NotImplementedError.new("parents() must be implemented by subclasses of AbstractChangeset.")
      end
      
      ##
      # Iterates over every tracked file in this changeset.
      # 
      # @return [AbstractChangeset] self
      def each
        raise NotImplementedError.new("each() must be implemented by subclasses of AbstractChangeset.")
      end
      
      ##
      # How does this changeset compare to +other+? Used in sorting.
      # 
      # @param [AbstractChangeset] other
      # @return [Integer] -1, 0, or 1
      def <=>(other)
        raise NotImplementedError.new("<=>() must be implemented by subclasses of AbstractChangeset.")
      end

      ##
      # Retrieve +filename+
      #
      # @return [AbstractVersionedFile]
      def get_file(filename)
        raise NotImplementedError.new("get_file() must be implemented by subclasses of AbstractChangeset.")
      end
      alias_method :[], :get_file

      ##
      # When was the changeset made?
      # 
      # @return [Time]
      def date
        raise NotImplementedError.new("date() must be implemented by subclasses of AbstractChangeset.")
      end

      ##
      # The user who made the changeset
      # 
      # @return [String] the user who made the changeset
      def user
        raise NotImplementedError.new("user() must be implemented by subclasses of AbstractChangeset.")
      end
      
      ##
      # Which branch this changeset belongs to
      # 
      # @return [String] the user who made the changeset
      def branch
        raise NotImplementedError.new("branch() must be implemented by subclasses of AbstractChangeset.")
      end

      ##
      # @return [String]
      def description
        raise NotImplementedError.new("description() must be implemented by subclasses of AbstractChangeset.")
      end
      
      ##
      # What files have been altered in this changeset?
      # 
      # @return [Array<String>]
      def altered_files
        raise NotImplementedError.new("altered_files() must be implemented by subclasses of AbstractChangeset.")
      end
      
      ##
      # Returns a list of all files that are tracked at this current revision.
      #
      # @return [Array<String>] the files tracked at the given revision
      def all_files
        raise NotImplementedError.new("all_files() must be implemented by subclasses of AbstractChangeset.")
      end
      
      # Is this changeset a working changeset?
      #
      # @return [Boolean] is the changeset representing the working directory?
      def working?
        raise NotImplementedError.new("working() must be implemented by subclasses of AbstractChangeset.")
      end
      
    end
  end
end