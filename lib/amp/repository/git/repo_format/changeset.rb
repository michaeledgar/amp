require 'time'

module Amp
  module Git
    
    ##
    # A Changeset is a simple way of accessing the repository within a certain
    # revision. For example, if the user specifies revision # 36, or revision
    # 3adf21, then we can look those up, and work within the repository at the
    # moment of that revision.
    class Changeset < Amp::Repositories::AbstractChangeset
      
      attr_accessor :short_name
      attr_accessor :repo
      alias_method :repository, :repo
      
      def initialize(repo, short_name)
        @repo       = repo
        @short_name = short_name
      end
      
      def revision; short_name; end
      
      ##
      # Compares 2 changesets so we can sort them and whatnot
      # 
      # @param [Changeset] other a changeset we will compare against
      # @return [Integer] -1, 0, or 1. Typical comparison.
      def <=>(other)
        date <=> other.date
      end
      
      ##
      # Iterates over every tracked file at this point in time.
      # 
      # @return [Changeset] self, because that's how #each works
      def each(&b)
        all_files.each( &b)
        self
      end
      
      ##
      # the nodes that this node inherits from
      # 
      # @return [Array<Abstract Changeset>]
      def parents
        parse!
        @parents
      end

      ##
      # Retrieve +filename+
      #
      # @return [AbstractVersionedFile]
      def get_file(filename)
        VersionedFile.new @repo, file, :revision => short_name
      end
      alias_method :[], :get_file

      ##
      # When was the changeset made?
      # 
      # @return [Time]
      def date
        parse!
        @date
      end

      ##
      # The user who made the changeset
      # 
      # @return [String] the user who made the changeset
      def user
        parse!
        @user
      end
      
      ##
      # Which branch this changeset belongs to
      # 
      # @return [String] the user who made the changeset
      def branch
        parse!
        raise NotImplementedError.new("branch() must be implemented by subclasses of AbstractChangeset.")
      end

      ##
      # @return [String]
      def description
        parse!
        @description
      end
      
      ##
      # What files have been altered in this changeset?
      # 
      # @return [Array<String>]
      def altered_files
        parse!
        @altered_files
      end
      
      ##
      # Returns a list of all files that are tracked at this current revision.
      #
      # @return [Array<String>] the files tracked at the given revision
      def all_files
        parse!
        @all_files
      end
      
      # Is this changeset a working changeset?
      #
      # @return [Boolean] is the changeset representing the working directory?
      def working?
        false
      end
      
      ##
      #
      def to_templated_s(opts={})
        username    = user
        files       = altered_files
        type        = opts[:template_type] || 'log'
        
        added   = opts[:added]   || []
        removed = opts[:removed] || []
        updated = opts[:updated] || []
        config  = opts
        
        return "" if opts[:no_output]
        
        config = opts
        
        template = opts[:template]
        template = "default-#{type}" if template.nil? || template.to_s == "default"
        
        template = Support::Template['git', template]
        template.render({}, binding)
      end
      
      private
      
      # yeah, i know, you could combine these all into one for a clean sweep.
      # but it's clearer this way
      def parse!
        return if @parsed
        
        # the parents
        log_data = `git log -1 #{short_name}^ 2> /dev/null`
        
        # DETERMINING PARENTS
        dad   = log_data[/^commit (.+)$/, 1]
        dad   = dad ? dad[0..6] : nil
        mom   = nil
        
        if log_data =~ /^Merge: (.+)\.\.\. (.+)\.\.\.$/ # Merge: 1c002dd... 35cfb2b...
          dad = $1 # just have them both use the short name, nbd
          mom = $2
        end
        
        @parents = [dad, mom].compact.map {|r| Changeset.new repo, r }
        
        # the actual changeset
        log_data = `git log -1 #{short_name}  2> /dev/null`
        
        # DETERMINING DATE
        @date = Time.parse log_data[/^Date:\s+(.+)$/, 1]
        
        # DETERMINING USER
        @user = log_data[/^Author:\s+(.+)$/, 1]
        
        # DETERMINING DESCRIPTION
        @description = log_data.split("\n")[4..-1].map {|l| l.strip }.join "\n"
        
        # ALTERED FILES
        @altered_files = `git log -1 #{short_name} --pretty=oneline --name-only  2> /dev/null`.split("\n")[1..-1]
        
        # ALL FILES
        # @all_files is also sorted. Hooray!
        @all_files = `git ls-tree -r #{short_name}`.split("\n").map do |line|
          # 100644 blob cdbeb2a42b714a4db49293c87fec4e180d07d44f    .autotest
          line[/^\d+ \w+ \w+\s+(.+)$/, 1]
        end
        
        @parsed = true
      end
      
    end
    
    class WorkingDirectoryChangeset < Amp::Repositories::AbstractChangeset
      
      attr_accessor :repo
      alias_method :repository, :repo
      
      def initialize(repo, opts={:text => ''})
        @repo = repo
        @text = opts[:text]
        @date = Time.parse opts[:date].to_s
        @user = opts[:user]
        @parents = opts[:parents].map {|p| Changeset.new(@repo, p) } if opts[:parents]
        @status  = opts[:changes]
      end
      
      ##
      # the nodes that this node inherits from
      # 
      # @return [Array<Abstract Changeset>]
      def parents
        @parents || (parse! && @parents)
      end
      
      def revision; nil; end

      ##
      # Retrieve +filename+
      #
      # @return [AbstractVersionedFile]
      def get_file(filename)
        VersionedWorkingFile.new @repo, filename
      end
      alias_method :[], :get_file

      ##
      # When was the changeset made?
      # 
      # @return [Time]
      def date
        Time.now
      end

      ##
      # The user who made the changeset
      # 
      # @return [String] the user who made the changeset
      def user
        @user ||= @repo.config.username
      end
      
      ##
      # Which branch this changeset belongs to
      # 
      # @return [String] the user who made the changeset
      def branch
        @branch ||= `git branch  2> /dev/null`[/\*\s(.+)$/, 1]
      end

      ##
      # @return [String]
      def description
        @text || ''
      end
      
      def status
        @status ||= @repo.status :unknown => true
      end
      
      ##
      # Iterates over every tracked file at this point in time.
      # 
      # @return [Changeset] self, because that's how #each works
      def each(&b)
        all_files.each( &b)
        self
      end
      
      ##
      # Returns a list of all files that are tracked at this current revision.
      #
      # @return [Array<String>] the files tracked at the given revision
      def all_files
        @all_files ||= `git ls-files  2> /dev/null`.split("\n")
      end
      
      # Is this changeset a working changeset?
      #
      # @return [Boolean] is the changeset representing the working directory?
      def working?
        true
      end
      
      ##
      # Recursively walk the directory tree, getting all files that +match+ says
      # are good.
      # 
      # @param [Amp::Match] match how to select the files in the tree
      # @param [Boolean] check_ignored (false) should we check for ignored files?
      # @return [Array<String>] an array of filenames in the tree that match +match+
      def walk(match, check_ignored = false)
        tree = @repo.staging_area.walk true, check_ignored, match
        tree.keys.sort
      end
      
      # What files have been altered in this changeset?
      def altered_files; `git show --name-only #{short_name} 2> /dev/null`.split("\n"); end
      # What files have changed?
      def modified; status[:modified]; end
      # What files have we added?
      def added; status[:added]; end
      # What files have been removed?
      def removed; status[:removed]; end
      # What files have been deleted (but not officially)?
      def deleted; status[:deleted]; end
      # What files are hanging out, but untracked?
      def unknown; status[:unknown]; end
      # What files are pristine since the last revision?
      def clean; status[:normal]; end
      
      # yeah, i know, you could combine these all into one for a clean sweep.
      # but it's clearer this way
      def parse!
        return if @parsed
        
        log_data = `git log -1 HEAD  2> /dev/null`
        
        unless log_data.empty?
          # DETERMINING PARENTS
          commit = log_data[/^commit (.+)$/, 1]
          dad    = commit ? commit[0..6] : nil
          mom    = nil
          
          if log_data =~ /^Merge: (.+)\.\.\. (.+)\.\.\.$/ # Merge: 1c002dd... 35cfb2b...
            dad = $1 # just have them both use the short name, nbd
            mom = $2
          end
          
          @parents = [dad, mom].compact.map {|p| Changeset.new @repo, p }
        else
          @parents = []
        end
        @parsed = true
      end
      
    end
  end
end