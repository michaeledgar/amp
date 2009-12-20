module Amp
  module Repositories
    class AbstractStagingArea
      
      ##
      # Marks a file to be added to the repository upon the next commit.
      # 
      # @param [[String]] filenames a list of files to add in the next commit
      # @return [Boolean] true for success, false for failure
      def add(*filenames)
        raise NotImplementedError.new("add() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Marks a file to be removed from the repository upon the next commit.
      # 
      # @param [[String]] filenames a list of files to remove in the next commit
      # @return [Boolean] true for success, false for failure
      def remove(*filenames)
        raise NotImplementedError.new("remove() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Marks a file to be copied from the +from+ location to the +to+ location
      # in the next commit, while retaining history.
      # 
      # @param [String] from the source of the file copy
      # @param [String] to the destination of the file copy
      # @return [Boolean] true for success, false for failure
      def copy(from, to)
        raise NotImplementedError.new("copy() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Marks a file to be moved from the +from+ location to the +to+ location
      # in the next commit, while retaining history.
      # 
      # @param [String] from the source of the file move
      # @param [String] to the destination of the file move
      # @return [Boolean] true for success, false for failure
      def move(from, to)
        raise NotImplementedError.new("move() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Marks a modified file to be included in the next commit.
      # If your VCS does this implicitly, this should be defined as a no-op.
      # 
      # @param [[String]] filenames a list of files to include for committing
      # @return [Boolean] true for success, false for failure
      def include(*filenames)
        raise NotImplementedError.new("include() must be implemented by subclasses of AbstractStagingArea.")
      end
      alias_method :stage, :include
      
      ##
      # Mark a modified file to not be included in the next commit.
      # If your VCS does not include this idea because staging a file is implicit, this should
      # be defined as a no-op.
      # 
      # @param [[String]] filenames a list of files to remove from the staging area for committing
      # @return [Boolean] true for success, false for failure
      def exclude(*filenames)
        raise NotImplementedError.new("exclude() must be implemented by subclasses of AbstractStagingArea.")
      end
      alias_method :unstage, :exclude
      
      ##
      # Returns a Symbol.
      # Possible results:
      # :added (subset of :included)
      # :removed
      # :unknown
      # :included
      # :normal
      #
      def file_status(filename)
        raise NotImplementedError.new("status() must be implemented by subclasses of AbstractStagingArea.")
      end
    end
  end
end