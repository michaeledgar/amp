module Amp
  ##
  # = FileLog
  # A FileLog is the revision log that stores revision history for
  # each individual file tracked by the system. It stores special meta-data
  # for handling files that have been copied over their history.
  #
  class FileLog < Revlog
    ##
    # Initializes the revision log, being sure to encode directories
    # to avoid naming conflicts
    # @param [Opener] opener the opener to use for opening the file
    # @param [String] path the path to the file, excluding "data".
    #
    def initialize(opener, path)
      super(opener, ["data", encode_dir(path + ".i")].join("/"))
    end
    
    ##
    # Encodes the directory to avoid naming conflicts
    # @param [String] path the path to encode for naming conflict issues
    # @return [String] the encoded directory path
    #
    def encode_dir(path)
      path.gsub(".hg/",".hg.hg/").gsub(".i/",".i.hg/").gsub(".d/",".d.hg/")
    end
    
    ##
    # Decodes the directory to avoid naming conflicts
    # @param [String] path the path to decode for naming conflict issues
    # @return [String] the decoded directory path
    #
    def decode_dir(path)
      path.gsub(".d.hg/",".d/").gsub(".i.hg/",".i/").gsub(".hg.hg/",".hg/")
    end
    
    ##
    # Reads the data of the revision, ignoring the meta data for copied files
    # @param [String] node the node_id to read
    # @return [String] the data of the revision
    #
    def read(node)
      t = decompress_revision(node)
      return t unless t.start_with?("\1\n")

      start = t.index("\1\n", 2)
      t[(start+2)..-1]
    end
    
    ##
    # Reads the meta data in the node
    # @param [String] node the node_id to read the meta of
    # @return [Hash] the meta data in this revision. Could be empty hash.
    #
    def read_meta(node)
      t = decompress_revision(node)
      return {} unless t.start_with?("\1\n")
      
      start = t.index("\1\n", 2)
      mt = t[2..(start-1)]
      m = {}
      mt.split("\n").each do |l|
        k, v = l.split(": ", 2)
        m[k] = v
      end
      m
    end
    
    ##
    # Adds a revision to the file's history. Overridden for special metadata
    # 
    # @param [String] text the new text of the file
    # @param [Hash] meta the meta data to use (if we copied)
    # @param [Journal] journal for aborting transaction
    # @param [Integer] link the revision number this is linked to
    # @param [Integer] p1 (nil) the first parent of this new revision
    # @param [Integer] p2 (nil) the second parent of this new revision
    # @param [String] digest referring to the node this makes
    def add(text, meta, journal, link, p1=nil, p2=nil)
      if (meta && meta.any?) || text.start_with?("\1\n")
        mt = ""
        mt = meta.map {|k, v| "#{k}: #{v}\n"} if meta
        text = "\1\n" + mt.join + "\1\n" + text
      end
      add_revision(text, journal, link, p1, p2)
    end
    
    ##
    # Returns whether or not the file at _node_ has been renamed or
    # copied.
    # 
    # @param [String] node the node_id of the revision
    # @return [Boolean] has the file been renamed or copied at this
    #   revision?
    def renamed(node)
      return false if parents_for_node(node).first != NULL_ID
      
      m = read_meta node
      
      if m.any? && m["copy"]
        return [m["copy"], m["copyrev"].unhexlify]
      end
      
      false
    end
    alias_method :renamed?, :renamed
    
    ##
    # Yields a block for every revision, while being sure to follow copies.
    def each(&block)
      if @index[0].parent_one_rev == NULL_REV
        meta_info = renamed(@index[0].node_id)
        if meta_info
          copied_log = FileLog.new(@opener, meta_info.first)
          copied_log.each(&block)
        end
      end
      super(&block)
    end
    
    ##
    # Unified diffs 2 revisions, based on their indices. They are returned in a sexified
    # unified diff format.
    def unified_revision_diff(rev1, old_date, rev2, new_date, path1, path2, opts={})
      opts = Diffs::MercurialDiff::DEFAULT_OPTIONS.merge(opts)
      version_1 = rev1 ? read(self.node_id_for_index(rev1)) : nil
      version_2 = rev2 ? read(self.node_id_for_index(rev2)) : nil
      
      Diffs::MercurialDiff.unified_diff( version_1, old_date, version_2, new_date,
                                      path1, path2, false, opts)
    end
    
    ##
    # Gets the size of the file. Overridden because of the metadata for
    # copied files.
    # 
    # @param [Integer] rev the number of the revision to lookup
    # @return [String] the file's data
    def size(rev)
      node = self.node rev
      if renamed? node
        read(node).size
      else
        self[rev].compressed_len
      end
    end
    
    ##
    # Converts a given node in this revision with the text provided.
    # overridden because it handles renamed files.
    # 
    # @param [String] thenode the node ID to use
    # @param [String] text the text to compare against
    # @return [Boolean] true if they're different, false if not. silly, isn't
    #   it?
    def cmp(thenode, text)
      if renamed? thenode
        t2 = read thenode
        return t2 != text
      end
      super(thenode, text)
    end
  end # class FileLog
  
end # module Amp