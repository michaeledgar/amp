module Amp
  module Repositories
    class AbstractStagingArea

        ##
        # Marks a file to be added to the repository upon the next commit.
        # return value is success/failure
        def add(*filenames)
          raise NotImplementedError.new("add() must be implemented by subclasses of AbstractLocalRepository.")
        end

        ##
        # Marks a file to be removed from the repository upon the next commit.
        # return value is success/failure
        def remove(*filenames)
          raise NotImplementedError.new("remove() must be implemented by subclasses of AbstractLocalRepository.")
        end

        ##
        # Marks a file to be copied from the +from+ location to the +to+ location
        # in the next commit, while retaining history.
        # return value is success/failure
        def copy(from, to)
          raise NotImplementedError.new("copy() must be implemented by subclasses of AbstractLocalRepository.")
        end

        ##
        # Marks a file to be moved from the +from+ location to the +to+ location
        # in the next commit, while retaining history.
        # return value is success/failure
        def move(from, to)
          raise NotImplementedError.new("move() must be implemented by subclasses of AbstractLocalRepository.")
        end

        ##
        # Marks a modified file to be included in the next commit.
        # If your VCS does this implicitly, this should be defined as a no-op.
        # return value is success/failure
        def include(*filenames)
          raise NotImplementedError.new("include() must be implemented by subclasses of AbstractLocalRepository.")
        end
        alias_method :stage, :include

        ##
        # Mark a modified file to not be included in the next commit.
        # If your VCS does not include this idea because staging a file is implicit, this should
        # be defined as a no-op.
        # return value is success/failure
        def exclude(*filenames)
          raise NotImplementedError.new("exclude() must be implemented by subclasses of AbstractLocalRepository.")
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
        def status(filename)
          raise NotImplementedError.new("status() must be implemented by subclasses of AbstractLocalRepository.")
        end
    end
  end
end