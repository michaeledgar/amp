module Amp
  module Git
    
    ##
    # This class allows you to access a file at a given revision in the repo's
    # history. You can compare them, sort them, access the changeset, and
    # all sorts of stuff.
    class VersionedFile < Amp::Repositories::AbstractVersionedFile
      
      attr_accessor :revision
      attr_accessor :path
      attr_accessor :repo
      
      def initialize(repo, path, opts={})
        @repo = repo
        @path = path
        @revision = opts[:revision]
      end
      
      ##
      # The changeset to which this versioned file belongs.
      # 
      # @return [AbstractChangeset]
      def changeset
        @changeset ||= Changeset.new @repo, @revision
      end
      
      ##
      # The size of this file
      # 
      # @return [Integer]
      def size
        @size ||= data.size
      end
      
      ##
      # The contents of a file at the given revision
      # 
      # @return [String] the data at the current revision
      def data
        @data ||= `git show #{revision}:#{path} 2> /dev/null`
      end
      
      ##
      # The hash value for sticking this fucker in a hash.
      # 
      # @return [Integer]
      def hash
        "#{size}--#{path}--#{repo.root}--#{revision} 2> /dev/null".hash
      end
      
      ##
      # Has this file been renamed? If so, return some useful info
      def renamed?
        nil
      end
      
      ##
      # Compares to either a bit of text or another versioned file.
      # Returns true if different, false for the same.
      # (much like <=> == 0 for the same)
      # 
      # @param [AbstractVersionedFile, String] item what we're being compared to
      # @return [Boolean] true if different, false if same.
      def cmp(item)
        return data == item if item.is_a? String
        
        not (data      == item.data     &&
             size      == item.size     &&
             revision  == item.revision &&
             repo.root == item.repo.root )
      end
      
      ##
      # Are two versioned files the same? This means same path and revision indexes.
      # 
      # @param [AbstractVersionedFile] vfile what we're being compared to
      # @return [Boolean]
      def ==(vfile)
        !cmp(vfile)
      end
      
      ##
      # Gets the flags for this file ('x', 'l', or '')
      # 
      # @return [String] 'x', 'l', or ''
      def flags
        '' # because git doesn't track them
      end
      
    end
    
    ##
    # This is a VersionedFile, except it's in the working directory, so its data
    # is stored on disk in the actual file. Other than that, it's basically the
    # same in its interface!
    class VersionedWorkingFile < VersionedFile
      
      ##
      # Initializes a new working dir file - slightly different semantics here
      def initialize(repo, path, opts={})
        super(repo, path, opts)
      end
      
      def size
        File.stat(repo.join(path)).size
      end
      
      def data
        File.read repo.working_join(path)
      end
      
      def changeset
        WorkingDirectoryChangeset.new repo
      end
      
    end
  end
end