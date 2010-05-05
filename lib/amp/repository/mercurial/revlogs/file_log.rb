#######################################################################
#                  Licensing Information                              #
#                                                                     #
#  The following code is a derivative work of the code from the       #
#  Mercurial project, which is licensed GPLv2. This code therefore    #
#  is also licensed under the terms of the GNU Public License,        #
#  verison 2.                                                         #
#                                                                     #
#  For information on the license of this code when distributed       #
#  with and used in conjunction with the other modules in the         #
#  Amp project, please see the root-level LICENSE file.               #
#                                                                     #
#  © Michael J. Edgar and Ari Brown, 2009-2010                        #
#                                                                     #
#######################################################################

module Amp
  module Mercurial
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
      # Returns whether the given text from a decompressed node has meta-data
      # encoded in it. Not for public use.
      #
      # @param [String] data the data from the file
      # @return [Boolean] is there metadata?
      def has_metadata?(data)
        return data.start_with?("\1\n")
      end
      
      ##
      # Returns the location of the end of the metadata. Metadata prefixes the
      # data in the block.
      #
      # @param [String] text the text to inspect
      # @param [Integer] the location of the end of the metadata
      def normal_data_start(text)
        text.index("\1\n", 2) + 2
      end
      
      ##
      # Returns the location of the end of the metadata. Metadata prefixes the
      # data in the block.
      #
      # @param [String] text the text to inspect
      # @param [Integer] the location of the end of the metadata
      def metadata_end(text)
        text.index("\1\n", 2)
      end
      
      ##
      # Returns the start of the metadata in the text
      #
      # @return [Integer] the location of the start of the metadata
      def metadata_start
        2
      end
      
      ##
      # Reads the data of the revision, ignoring the meta data for copied files
      # @param [String] node the node_id to read
      # @return [String] the data of the revision
      #
      def read(node)
        text = decompress_revision(node)
        return text unless has_metadata?(text)
    
        text[normal_data_start(text)..-1]
      end
      
      ##
      # Reads the meta data in the node
      # @param [String] node the node_id to read the meta of
      # @return [Hash] the meta data in this revision. Could be empty hash.
      #
      def read_meta(node)
        t = decompress_revision(node)
        return {} unless has_metadata?(t)
        
        mt = t[metadata_start..(metadata_end(t) - 1)]
        mt.split("\n").inject({}) do |hash, line|
          k, v = line.split(": ", 2)
          hash[k] = v
          hash
        end
      end
      
      ##
      # Combines the revision data and the metadata into one text blob. Uses
      # Mercurial's encoding method.
      #
      # @param [String] text the data for the revision
      # @param [Hash] meta the metadata to attach
      # @return [String] the compiled data
      def inject_metadata(text, meta)
        if (meta && meta.any?) || text.start_with?("\1\n")
          mt = meta ? meta.map {|k, v| "#{k}: #{v}\n"} : ""
          text = "\1\n" + mt.join + "\1\n" + text
        end
        text
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
      # @return [String] digest referring to the node this makes
      def add(text, meta, journal, link, p1=nil, p2=nil)
        text = inject_metadata(text, meta)
        add_revision(text, journal, link, p1, p2)
      end
      
      ##
      # Returns whether or not the file at _node_ has been renamed or
      # copied in the immediate revision.
      # 
      # @param [String] node the node_id of the revision
      # @return [Array<String, String>] [new_path, flags]
      def renamed?(node)
        return false if parents_for_node(node).first != NULL_ID
        
        m = read_meta node
        if m["copy"]
          [m["copy"], m["copyrev"].unhexlify]
        else
          false
        end
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
  end # module Mercurial
end # module Amp