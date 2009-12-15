module Amp
  module Bundles
    module Mercurial
      
      ##
      # This module handles revlogs passed to our client (or server)
      # through the bundle file format. Thing is, this revision log
      # spans both a physical filelog, and a bundle (the new revisions),
      # and we might need to get stuff from both. It's kind of like the
      # DelayedOpener/FakeAppender for changelogs.
      module BundleRevlog
        include RevlogSupport::Node
        BUNDLED_INDEX_ENTRY_SIZE = 80
        
        ##
        # Initializes a bundle revlog. Takes, in addition to the normal
        # revlog arguments, a bundle_file. This is any IO we can read
        # from that will give us additional revisions, aside from the
        # revisions stored in the real Revlog. It also takes a link_mapper
        # that will connect things to the changelog revisions (including
        # changelog revisions in the bundle).
        #
        # @param [Opener] opener the opener to use for openinf up the index_file
        # @param [String] index_file the name of the file containing the revlog's
        #  index
        # @param [IO] bundle_file an IO that we can #read from
        # @param [Proc, #call] link_mapper a function that will give us the link-index
        #  to connect revisions to changelog revisions based on node_ids
        def bundle_initialize(opener, index_file, bundle_file, link_mapper = nil)
          @bundle_file = bundle_file
          @base_map = {}
          
          num_revs = self.index_size
          previous = nil
          all_chunk_positions do |chunk, start|
            chunk_size = chunk.size
            
            # each chunk starts with 4 node IDs: the new node's ID, its 2 parent node IDs,
            # and the node ID of the corresponding revision in the changelog. In that order.
            # If we have less than 80 bytes (BUNDLED_INDEX_ENTRY_SIZE), then we're fucked.
            if chunk_size < BUNDLED_INDEX_ENTRY_SIZE
              raise abort("invalid changegroup")
            end
            
            start      += BUNDLED_INDEX_ENTRY_SIZE
            chunk_size -= BUNDLED_INDEX_ENTRY_SIZE
            
            # Get the aforementioned node IDs
            node, parent_1, parent_2, changeset = chunk[0..79].unpack("a20a20a20a20")
            
            # Do we already have this node? Skip it.
            if @index.has_node? node
              previous = node
              next
            end
            
            # make sure we have the new node's parents, or all of our operations will fail!
            # at least, the interesting ones.
            [parent_1, parent_2].each do |parent|
              unless @index.has_node? parent
                raise abort("Unknown parent: #{parent}@#{index_file}")
              end
            end
            
            link_rev = (link_mapper && link_mapper[changeset]) || num_revs
            previous ||= parent_1
            
            @index << [RevlogSupport::Support.offset_version(start, 0), chunk_size, -1, -1, link_rev,
                       revision_index_for_node(parent_1), revision_index_for_node(parent_2),
                       node]
            
            @index.node_map[node] = num_revs
            @base_map[num_revs] = previous
            
            previous = node
            num_revs += 1
          end
        end
        alias_method :bundle_revlog_initialize, :initialize
        ##
        # Returns whether the revision index is in the bundle part of this revlog,
        # or if it's in the actual, stored revlog file.
        #
        # @param [Fixnum] revision the revision index to lookup
        # @return [Boolean] is the revision in the bundle section?
        def bundled_revision?(revision)
          return false if revision < 0
          !!@base_map[revision]
        end
        
        ##
        # Returns the base revision for the revision at the given index, while being
        # cognizant of the bundle-ness of this revlog.
        #
        # @param [Fixnum] revision the revision index to lookup the base-revision of
        # @return [String] the revision node ID of the base for the requested revision
        def bundled_base_revision_for_index(revision)
          @base_map[revision] || base_revision_for_index(revision)
        end
        alias_method :bundled_base, :bundled_base_revision_for_index
        
        ##
        # Gets a chunk of data from the datafile (or, if inline, from the index
        # file). Just give it a revision index and which data file to use. Only difference
        # is that this will check the bundlefile if necessary.
        # 
        # @param [Fixnum] rev the revision index to extract
        # @param [IO] data_file The IO file descriptor for loading data
        # @return [String] the raw data from the index (posssibly compressed)
        def get_chunk(revision, datafile=nil, cache_len = 4096)
          # Warning: in case of bundle, the diff is against bundlebase, not against
          # rev - 1
          # TODO: could use some caching
          unless bundled_revision?(revision)
            return super(revision, datafile)
          end
          @bundle_file.seek data_start_for_index(revision)
          @bundle_file.read self[revision].compressed_len
        end
        
        ##
        # Diffs 2 revisions, based on their indices. They are returned in
        # BinaryDiff format.
        # 
        # @param [Fixnum] rev1 the index of the source revision
        # @param [Fixnum] rev2 the index of the destination revision
        # @return [String] The diff of the 2 revisions.
        def revision_diff(rev1, rev2)
          both_bundled = bundled_revision?(rev1) && bundled_revision?(rev2)
          if both_bundled
            # super-quick path if both are bundled and rev2 == rev1 + 1 diff
            revision_base = self.revision_index_for_node bundled_base_revision_for_index(rev2)
            if revision_base == rev1
              # if rev2 = rev1 + a diff, just get the diff!
              return get_chunk(revision2)
            end
          end
          # normal style
          return super(rev1, rev2)
        end
        
        ##
        # Given a node ID, extracts that revision and decompresses it. What you get
        # back will the pristine revision data! Checks for bundle-ness when we access
        # a node.
        # 
        # @param [String] node the Node ID of the revision to extract.
        # @return [String] the pristine revision data.
        def decompress_revision(node)
          return "" if node == NULL_ID
          
          text = nil
          chain = []
          iter_node = node
          rev = revision_index_for_node(node)
          # walk backwards down the chain. Every single node is going
          # to be a diff, because it's from a bundle.
          while bundled_revision? rev
            if @index.cache && @index.cache[0] == iter_node
              text = @index.cache[2]
              break
            end
            chain << rev
            iter_node = bundled_base_revision_for_index rev
            rev = revision_index_for_node iter_node
          end
          # done walking back, see if we have a stored cache!
          text = super(iter_node) if text.nil? || text.empty?
          
          while chain.any?
            delta = get_chunk(chain.pop)
            text = Diffs::MercurialPatch.apply_patches(text, [delta])
          end
          p1, p2 = parents_for_node node
          
          if node != RevlogSupport::Support.history_hash(text, p1, p2)
            raise RevlogSupport::RevlogError.new("integrity check failed on %s:%d, data:%s" % 
                                                 [(@index.inline? ? @index_file : @data_file), rev(node), text.inspect])
          end
          
          @index.cache = [node, revision_index_for_node(node), text]
          text
        end
        
        ##
        # Give an error to enforce read-only behavior
        def add_revision(text, transaction, link, p1, p2, d=nil, index_file_handle = nil)
          raise NotImplementedError.new
        end
        
        ##
        # Give an error to enforce read-only behavior
        def add_group(revisions, link_mapper, journal)
          raise NotImplementedError.new
        end
        
        
        private
        
        def all_chunk_positions
          results = []
          RevlogSupport::ChangeGroup.each_chunk(@bundle_file) do |chunk|
            if block_given?
              yield(chunk, @bundle_file.tell - chunk.size)
            else
              results << [chunk, @bundle_file.tell - chunk.size]
            end
          end
          results unless block_given?
        end
      end
      
      class BundleChangeLog < ChangeLog
        include BundleRevlog
        def initialize(opener, bundle_file)
          # This is the changelog initializer
          super(opener)
          # This is the bundle initializer
          bundle_initialize(opener, @index_file, bundle_file)
        end
      end
      
      class BundleManifest < Manifest
        include BundleRevlog
        
        def initialize(opener, bundle_file, link_mapper)
          # This is the manifest initializer
          super(opener)
          # This is the bundle initializer
          bundle_initialize(opener, @index_file, bundle_file, link_mapper)
        end
        
      end
      
      class BundleFileLog < FileLog
        include BundleRevlog
        
        def initialize(opener, path, bundle_file, link_mapper)
          # This is the manifest initializer
          super(opener, path)
          # This is the bundle initializer
          bundle_initialize(opener, @index_file, bundle_file, link_mapper)
        end
        
      end
      
    end
  end
end