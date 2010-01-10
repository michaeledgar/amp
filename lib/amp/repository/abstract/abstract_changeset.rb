module Amp
  module Repositories
    class AbstractChangeset
      include CommonChangesetMethods
      ##
      # the nodes that this node inherits from
      # 
      # @return [Array<Abstract Changeset>]
      def parents
        raise NotImplementedError.new("parents() must be implemented by subclasses of AbstractChangeset.")
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