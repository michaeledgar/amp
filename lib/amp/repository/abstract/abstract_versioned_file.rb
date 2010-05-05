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
    class AbstractVersionedFile
      include CommonVersionedFileMethods
      
      ##
      # The changeset to which this versioned file belongs.
      # 
      # @return [AbstractChangeset]
      def changeset
        raise NotImplementedError.new("changeset() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # The repo to which this {VersionedFile} belongs
      # 
      # @return [AbstractLocalRepository]
      def repo
        raise NotImplementedError.new("repo() must be implemented by subclasses of AbstractVersionedFile.")
      end
      alias_method :repository, :repo
      
      ##
      # The path to this file
      # 
      # @return [String]
      def path
        raise NotImplementedError.new("path() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # The revision of the file. This can be vague, so let me explain:
      # This is the revision of the repo from which this VersionedFile is.
      # If this is unclear, please submit a patch fixing it.
      # 
      # @return [Integer]
      def revision
        raise NotImplementedError.new("revision() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # The size of this file
      # 
      # @return [Integer]
      def size
        raise NotImplementedError.new("size() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # The contents of a file at the given revision
      # 
      # @return [String] the data at the current revision
      def data
        raise NotImplementedError.new("data() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # The hash value for sticking this fucker in a hash.
      # 
      # @return [Integer]
      def hash
        raise NotImplementedError.new("hash() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # Has this file been renamed? If so, return some useful info
      def renamed?
        raise NotImplementedError.new("renamed() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # Compares to either a bit of text or another versioned file.
      # Returns true if different, false for the same.
      # (much like <=> == 0 for the same)
      # 
      # @param [AbstractVersionedFile, String] item what we're being compared to
      # @return [Boolean] true if different, false if same.
      def cmp(item)
        raise NotImplementedError.new("cmp() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # Are two versioned files the same? This means same path and revision indexes.
      # 
      # @param [AbstractVersionedFile] vfile what we're being compared to
      # @return [Boolean]
      def ==(vfile)
        raise NotImplementedError.new("==() must be implemented by subclasses of AbstractVersionedFile.")
      end
      
      ##
      # Gets the flags for this file ('x', 'l', or '')
      # 
      # @return [String] 'x', 'l', or ''
      def flags
        raise NotImplementedError.new("flags() must be implemented by subclasses of AbstractVersionedFile.")
      end
    end
  end
end