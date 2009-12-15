module Amp
  module Mercurial
    
    ##
    # This class allows you to access a file at a given revision in the repo's
    # history. You can compare them, sort them, access the changeset, and
    # all sorts of stuff.
    class VersionedFile
      include Mercurial::RevlogSupport::Node
      
      attr_accessor :file_id
      attr_writer   :path
      attr_writer   :change_id
      
      ##
      # Creates a new {VersionedFile}. You need to pass in the repo and the path
      # to the file, as well as one of the following: a revision index/ID, the
      # node_id of the file's revision in the filelog, or a changeset at a given
      # index.
      # 
      # @param [Repository] repo The repo we're working with
      # @param [String] path the path to the file
      # @param [Hash] opts the options to customize how we load this file
      # @option [FileLog] opts :file_log (nil) The FileLog to use for loading data
      # @option [String] opts :change_id (nil) The revision ID/index to use to
      #   figure out which revision we're working with
      # @option [Changeset] opts :changeset (nil) the changeset to use to figure
      #   which revision we're working with
      # @option [String] opts :file_id (nil) perhaps the ID of the revision in
      #   the file_log to use?
      def initialize(repo, path, opts={})
        @repo, @path = repo, path
        raise StandardError.new("specify a revision!") unless opts[:change_id] ||
                                                              opts[:file_id]   ||
                                                              opts[:changeset]
        @file_log  = opts[:file_log]  if opts[:file_log]
        @change_id = opts[:change_id] if opts[:change_id]
        @changeset = opts[:changeset] if opts[:changeset]
        @file_id   = opts[:file_id]   if opts[:file_id]
        
      end
      
      def <=>(other)
        to_i <=> other.to_i
      end
      
      def to_i
        change_id
      end
      
      ##
      # Returns the changeset that this file belongs to
      # 
      # @return [Changeset] the changeset this file belongs to
      def changeset
        @changeset ||= Changeset.new @repo, change_id
      end
      
      ##
      # Dunno why this is here
      #
      def repo_path
        @path
      end
      
      ##
      # The file log that tracks this file
      # 
      # @return [FileLog] The revision log tracking this file
      def file_log
        @file_log ||= @repo.file @path
      end
      
      ##
      # The revision index into the history of the repository. Could also
      # be a node_id
      def change_id
        @change_id ||= @changeset.revision         if @changeset
        @change_id ||= file_log[file_rev].link_rev unless @changeset
        @change_id
      end
      
      def file_node
        @file_node ||= file_log.lookup_id(@file_id) if @file_id
        @file_node ||= changeset.file_node(@path)   unless @file_id
        @file_node ||= NULL_ID
      end
      
      ##
      # Returns the index into the file log's history for this file
      def file_rev
        @file_rev ||= file_log.rev(file_node)
      end
      
      ##
      # Is this a null version?
      def nil?
        file_node.nil?
      end
      
      ##
      # String representation.
      def to_s
        "#{path}@#{node.hexlify[0..11]}"
      end
      
      ##
      # IRB Inspector string representation
      def inspect
        "#<Versioned File: #{to_s}>"
      end
      
      ##
      # Hash value for sticking this fucker in a hash
      def hash
        return (path + file_id.to_s).hash
      end
      
      ##
      # Equality! Compares paths and revision indexes
      def ==(other)
        return false unless @path && @file_id && other.path && other.file_id
        @path == other.path && @file_id == other.file_id
      end
      
      ##
      # Retrieves the file with a different ID
      # 
      # @param file_id a new file ID... still not sure what a file_id is
      def file(file_id)
        self.class.new @repo, @path, :file_id => file_id, :file_log => file_log
      end
      
      # Gets the flags for this file (x and l)
      def flags; changeset.flags(@path); end
      
      # Returns the revision index
      def revision
        return changeset.rev if @changeset || @change_id
        file_log[file_rev].link_rev
      end
      
      # Link-revision index
      def linkrev; file_log[file_rev].link_rev; end
      # Node ID for this file's revision
      def node; changeset.node; end
      # User who committed this revision to this file
      def user; changeset.user; end
      # Date this revision to this file was committed
      def date; changeset.date; end
      # All files in this changeset that this revision of this file was committed
      def files; changeset.files; end
      # The description of the commit that contained this file revision
      def description; changeset.description; end
      # The branch this tracked file belongs to
      def branch; changeset.branch; end
      # THe manifest that this file revision is from
      def manifest; changeset.manifest; end
      # The data in this file
      def data; file_log.read(file_node); end
      # The path to this file
      def path; @path; end
      # The size of this file
      def size; file_log.size(file_rev); end
      
      ##
      # Compares to a bit of text.
      # Returns true if different, false for the same.
      # (much like <=> == 0 for the same)
      def cmp(text)
        file_log.cmp(file_node, text)
      end
      
      ##
      # Just the opposite of #cmp
      # 
      # @param [VersionedFile] other what to compare to
      # @return [Boolean] true if the two are the same
      def ===(other)
        !self.cmp(other.data)
      end
      
      ##
      # Has this file been renamed? If so, return some useful info
      def renamed
        renamed = file_log.renamed(file_node)
        return renamed unless renamed
        
        return renamed if rev == linkrev
        
        name = path
        fnode = file_node
        changeset.parents.each do |p|
          pnode = p.filenode(name)
          next if pnode.nil?
          return nil if fnode == pnode
        end
        renamed
      end
    
      ##
      # What are this revised file's parents? Return them as {VersionedFile}s.
      def parents
        p = @path
        fl = file_log
        pl = file_log.parents(file_node).map {|n| [p, n, fl]}
        
        r = file_log.renamed(file_node)
        pl[0] = [r[0], r[1], nil] if r
        
        pl.select {|parent,n,l| n != NULL_ID}.map do |parent, n, l|
          VersionedFile.new(@repo, parent, :file_id => n, :file_log => l)
        end
      end
      
      ##
      # What are this file's children?
      def children
        c = file_log.children(file_node)
        c.map do |x|
          VersionedFile.new(@repo, @path, :file_id => x, :file_log => file_log)
        end  
      end
      
      def annotate_decorate(text, revision, line_number = false)
        if line_number
          size = text.split("\n").size
          retarr = [nil,text]
          retarr[0] = (1..size).map {|i| [revision, i]}
        else
          retarr = [nil, text]
          retarr[0] = [[revision, false]] * text.split("\n").size
        end
        retarr
      end
      
      def annotate_diff_pair(parent, child)
        Diffs::BinaryDiff.blocks_as_array(parent[1], child[1]).each do |a1,a2,b1,b2|
          child[0][b1..(b2-1)] = parent[0][a1..(a2-1)]
        end
        child
      end
      
      def annotate_get_file(path, file_id)
        log = (path == @path) ? file_log : @repo.get_file(path)
        return VersionedFile.new(@repo, path, :file_id => file_id, :file_log => log)
      end
      
      def annotate_parents_helper(file, follow_copies = false)
        path = file.path
        if file.file_rev.nil?
          parent_list = file.parents.map {|n| [n.path, n.file_rev]}
        else
          parent_list = file.file_log.parent_indices_for_index(file.file_rev)
          parent_list.map! {|n| [path, n]}
        end
        if follow_copies
          r = file.renamed
          pl[0] = [r[0], @repo.get_file(r[0]).revision(r[1])] if r
        end
        return parent_list.select {|p, n| n != NULL_REV}.
                           map {|p, n| annotate_get_file(p, n)}
      end
      
      def annotate(follow_copies = false, line_number = false)
        base = (revision != linkrev) ? file(file_rev) : self
        
        needed = {base => 1}
        counters = {(base.path + base.file_id.to_s) => 1}
        visit = [base]
        files = [base.path]
        
        while visit.any?
          file = visit.shift
          annotate_parents_helper(file).each do |p|
            unless needed.include? p
              needed[p] = 1
              counters[p.path + p.file_id.to_s] = 1
              visit << p
              files << p.path unless files.include? p.path
            end
          end
        end
        
        visit = []
        files.each do |f|
          filenames = needed.keys.select {|k| k.path == f}.map {|n| [n.revision, n]}
          visit += filenames
        end
        
        hist = {}
        lastfile = ""
        visit.sort.each do |rev, file_ann|
          curr = annotate_decorate(file_ann.data, file_ann, line_number)
          annotate_parents_helper(file_ann).each do |p|
            next if p.file_id == NULL_ID
            curr = annotate_diff_pair(hist[p.path + p.file_id.to_s], curr)
            counters[p.path + p.file_id.to_s] -= 1
            hist.delete(p.path + p.file_id.to_s) if counters[p.path + p.file_id.to_s] == 0
          end
          hist[file_ann.path+file_ann.file_id.to_s] = curr
          lastfile = file_ann
        end
        returnarr = []
        hist[lastfile.path+lastfile.file_id.to_s].inspect # force all lazy-loading to stoppeth
        ret = hist[lastfile.path+lastfile.file_id.to_s][0].each_with_index do |obj, i|
          returnarr << obj + [hist[lastfile.path+lastfile.file_id.to_s][1].split_newlines[i]]
        end
        #   hist[lastfile.path+lastfile.file_id.to_s][0][i] + hist[lastfile.path+lastfile.file_id.to_s][1].split_newlines[i]
        # end
        ret = hist[lastfile.path+lastfile.file_id.to_s][0].zip(hist[lastfile.path+lastfile.file_id.to_s][1].split_newlines)
        returnarr
      end
      
      def get_parents_helper(vertex, ancestor_cache, filelog_cache)
        return ancestor_cache[vertex] if ancestor_cache[vertex]
        file, node = vertex
        filelog_cache[file] = @repo.get_file(file) unless filelog_cache[file]
        
        filelog = filelog_cache[file]
        parent_list = filelog.parents(node).select {|p| p != NULL_ID}.map {|p| [file, p]}
        
        has_renamed = filelog.renamed(node)
        
        parent_list << has_renamed if has_renamed
        ancestor_cache[vertex] = parent_list
        parent_list
      end
      
      def ancestor(file_2)
        ancestor_cache = {}
        [self, file_2].each do |c|
          if c.file_rev == NULL_REV || c.file_rev.nil?
            parent_list = c.parents.map {|n| [n.path, n.file_node]}
            ancestor_cache[[c.path, c.file_node]] = parent_list
          end
        end
        
        filelog_cache = {repo_path => file_log, file_2.repo_path => file_2.file_log}
        a, b = [path, file_node], [file_2.path, file_2.file_node]
        parents_proc = proc {|vertex| get_parents_helper(vertex, ancestor_cache, filelog_cache)}
        
        v = Graphs::AncestorCalculator.ancestors(a, b, parents_proc)
        if v
          file, node = v
          return VersionedFile.new(@repo, file, :file_id => node, :file_log => filelog_cache[file])
        end
        return nil
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
        @repo, @path = repo, path
        @change_id = nil
        @file_rev, @file_node = nil, nil
        
        @file_log = opts[:file_log] if opts[:file_log]
        @changeset = opts[:working_changeset]
      end
      
      ##
      # Gets the working directory changeset
      def changeset
        @changeset ||= WorkingDirectoryChangeset.new(@repo)
      end
      
      ##
      # Dunno why this is here
      def repo_path
        @repo.dirstate.copy_map[@path] || @path
      end
      
      ##
      # Gets the file log?
      def file_log
        @repo.file(repo_path)
      end
      
      ##
      # String representation
      def to_s
        "#{path}@#{@changeset}"
      end
      
      ##
      # Returns the file at a different revision
      def file(file_id)
        VersionedFile.new(@repo, repo_path, :file_id => file_id, :file_log => file_log)
      end
      
      ##
      # Get what revision this is
      def revision
        return @changeset.revision if @changeset
        file_log[@file_rev].link_rev
      end
      
      ##
      # Get the contents of this file
      def data
        data = @repo.working_read(@path)
        data
      end
      
      ##
      # Has this file been renamed? If so give some good info.
      def renamed
        rp = repo_path
        return nil if rp == @path
        [rp, (self.changeset.parents[0].manifest[rp] || NULL_ID)]
      end
      
      ##
      # The working directory's parents are the heads, so get this file in
      # the previous revision.
      def parents
        p = @path
        rp = repo_path
        pcl = @changeset.parents
        fl = file_log
        pl = [[rp, pcl[0].manifest[rp] || NULL_ID, fl]]
        if pcl.size > 1
          if rp != p
            fl = nil
          end
          pl << [p, pcl[1].manifest[p] || NULL_ID, fl]
        end
        pl.select {|_, n, __| n != NULL_ID}.map do |parent, n, l|
          VersionedFile.new(@repo, parent, :file_id => n, :file_log => l)
        end
      end
      
      ##
      # Working directory has no children!
      def children; []; end
      
      ##
      # Returns the current size of the file
      #
      def size
        File.stat(@repo.join(@path)).size
      end
      
      ##
      # Returns the date that this file was last modified.
      def date
        t, tz = changeset.date
        begin
          return [FileUtils.lstat(@repo.join(@path)).mtime, tz]
        rescue Errno::ENOENT
          return [t, tz]
        end
      end
      
      ##
      # Compares to the given text. Overridden because this file is
      # stored on disk in the actual working directory.
      # 
      # @param [String] text the text to compare to
      # @return [Boolean] true if the two are different
      def cmp(text)
        @repo.working_read(@path) != text
      end
      
    end
  end
end
