module Amp
  module Repositories
    ##
    # This class contains the functionality of all repositories ever.
    # Methods here rely on certain base methods that are unimplemented,
    # left as an exercise for the reader.

    class AbstractLocalRepository
      ##
      # Returns the staging area for the repository, which provides the ability to add/remove
      # files in the next commit.
      #
      # @return [AbstractStagingArea]
      def staging_area
        raise NotImplementedError.new("staging_area() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Creates a local changeset.
      #
      # @return [Boolean] for success/failure
      def commit(options = {})
        raise NotImplementedError.new("commit() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Pushes changesets to a remote repository.
      #
      # @return [Boolean] for success/failure
      def push(options = {})
        raise NotImplementedError.new("push() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Pulls changesets from a remote repository 
      # Does *not* apply them to the working directory.
      #
      # @return [Boolean] for success/failure
      def pull(options = {})
        raise NotImplementedError.new("pull() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Returns a changeset for the given revision.
      # Must support at least integer indexing as well as a string "node ID", if the repository
      # system has such IDs. Also "tip" should return the tip of the revision tree.
      #
      # @return [AbstractChangeset]
      def [](revision)
        raise NotImplementedError.new("[]() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Returns the number of changesets in the repository.
      #
      # @return [Fixnum]
      def size
        raise NotImplementedError.new("size() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Gets a given file at the given revision, in the form of an AbstractVersionedFile object.
      #
      # @return [AbstractVersionedFile]
      def get_file(file, revision)
        raise NotImplementedError.new("get_file() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # In whatever conflict-resolution system your repository format defines, mark a given file
      # as in conflict. If your format does not manage conflict resolution, re-define this method as
      # a no-op.
      #
      # @return [Boolean]
      def mark_conflicted(*filenames)
        raise NotImplementedError.new("mark_conflicted() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # In whatever conflict-resolution system your repository format defines, mark a given file
      # as no longer in conflict (resolved). If your format does not manage conflict resolution,
      # re-define this method as a no-op.
      #
      # @return [Boolean]
      def mark_resolved(*filenames)
        raise NotImplementedError.new("mark_resolved() must be implemented by subclasses of AbstractLocalRepository.")
      end
    end
  end
end