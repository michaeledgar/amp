module Amp
  module Repositories
    class AbstractChangeset

      ##
      # Returns Array of AbstractChangesets ( [AbstractChangeset] )
      def parents
        raise NotImplementedError.new("parents() must be implemented by subclasses of AbstractChangeset.")
      end

      ##
      # Returns AbstractVersionedFile
      def get_file(filename)
        raise NotImplementedError.new("get_file() must be implemented by subclasses of AbstractChangeset.")
      end
      alias_method :[], :get_file

      ##
      # Returns Date object
      def date
        raise NotImplementedError.new("date() must be implemented by subclasses of AbstractChangeset.")
      end

      ##
      # Returns String
      def user
        raise NotImplementedError.new("user() must be implemented by subclasses of AbstractChangeset.")
      end

      ##
      # Returns String
      def description
        raise NotImplementedError.new("description() must be implemented by subclasses of AbstractChangeset.")
      end

      ##
      # Returns Array of String ( [String] )
      def changed_files
        raise NotImplementedError.new("changed_files() must be implemented by subclasses of AbstractChangeset.")
      end
    end
  end
end