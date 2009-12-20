module Amp
  module Repositories
    class AbstractVersionedFile
      # data at the given revision
      # @return [String] the data at the current revision
      def data
        raise NotImplementedError.new("data() must be implemented by subclasses of AbstractVersionedFile.")
      end
    end
  end
end