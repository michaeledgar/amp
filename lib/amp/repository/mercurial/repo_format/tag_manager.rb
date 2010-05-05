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
  module Repositories
    module Mercurial
      
      ##
      # = TagManager
      # This module handles all tag-related (but not branch tag) functionality
      # of the repository. 
      module TagManager
        include Amp::Mercurial::RevlogSupport::Node
        
        TAG_FORBIDDEN_LETTERS = ":\r\n"
        ##
        # Returns a list of all the tags as a hash, mapping each tag to the tip-most
        # changeset it applies to.
        #
        # @return [Hash] a hash, sorted by revision index (i.e. its order in the commit
        #   history), with the keys:
        #   :revision => the revision index of the changeset, or :unknown if unknown
        #   :tag => the name of the tag,
        #   :node => the node-id of the changeset
        def tag_list
          tags.map do |tag, node|
            r = changelog.rev(node) rescue :unknown
            {:revision => r, :tag => tag, :node => node, :type => tag_type(tag)}
          end.sort {|i1, i2| i1[:revision] <=> i2[:revision] }
        end
        
        ##
        # Returns the tag-type of the given tag. This could be "local", which means it is
        # not shared among repositories.
        #
        # @param [String] tag_name the name of the tag to lookup, such as "tip"
        # @return [String] the type of the requested tag, such as "local".
        def tag_type(tag_name)
          tags #load the tags
          @tags_type_cache[tag_name]
        end
        
        ##
        # Returns the tags for a given revision (by ID). We normally store the tag<->node
        # relationship with tags as the key, but if for some reason we need the other way
        # around, we look it up this way.
        #
        # @param [String] node the node-ID, in binary form.
        # @return [Array<String>] a list of tags for the given node.
        def tags_for_node(node)
          if @tags_for_node_cache ||= nil
            return @tags_for_node_cache[node] || []
          end
          # build the reverse cache
          build_reverse_tag_lookup_cache
          # Now that we're cached, try again
          tags_for_node(node)
        end
        
        ##
        # Builds the tags-for-node cache. Tags are stored as tag -> node normally,
        # since that's the most common case (looking up the node for a tag), but
        # we need it backwards, too. So this builds that in an in-memory hash.
        def build_reverse_tag_lookup_cache
          @tags_for_node_cache = ArrayHash.new
          tags.inject(@tags_for_node_cache) do |hash, (tag, tag_node)|
            hash[tag_node] << tag
            hash
          end
        end
        
        ##
        # Invalidates the tag cache. Removes all ivars relating to tags.
        def invalidate_tag_cache!
          @tags_for_node_cache = nil
          @tags_cache = nil
          @tags_type_cache = nil
        end
        
        ##
        # Loads all of the tags from the tag-cache file stored as .hgtags. Returns
        # a hash, mapping tag names to node-IDs.
        #
        # @return [Hash] a hash mapping tags to node-IDs.
        def tags
          return @tags_cache if (@tags_cache ||= nil)
          
          global_tags, tag_types = {}, {}
          
          f = nil
          # For each current .hgtags file in our history (including multi-heads), read in
          # the tags
          hg_tags_nodes.each do |rev, node, file_node|
            # get the file
            f = (f && f.file(file_node.file_node)) || self.versioned_file(".hgtags", :file_id => file_node.file_node)
            # read the tags, as global, because they're versioned.
            read_tags(f.data.split("\n"), f, "global", global_tags, tag_types)
          end
          
          # Now do locally stored tags, that aren't committed/versioned
          begin
            # get the local file, stored in .hg/
            data = @hg_opener.read("localtags")
            # Read the tags as local, because they are not versioned
            read_tags(data.split_newlines, "local_tags", "local", global_tags, tag_types)
          rescue Errno::ENOENT
            # do nothing. most people don't have this file.
          end
          # Save our tags for use later. Use ivars.
          @tags_cache, @tags_type_cache = {}, {}
          
          # Go through the global tags to store them in the cache
          global_tags.each do |k, nh|
            # update the cache
            @tags_cache[k] = nh.first unless nh.first == NULL_ID
            @tags_type_cache[k] = tag_types[k]
          end
          
          # tip = special tag
          @tags_cache["tip"] = self.changelog.tip
          
          # return our tags
          @tags_cache
        end
        
        ##
        # Verifies the provided tag names. If any contain a disallowed character,
        # raise an abort.
        #
        # @raises AbortError raises if a name contains a disallowed character
        # @param [Array<String>, String] names the tag names to check. Or just one name.
        def verify_tag_names(names)
          all_letters  = names.kind_of?(Array) ? names.join : names
          (TAG_FORBIDDEN_LETTERS.size-1).downto 0 do |i|
            if all_letters.include? TAG_FORBIDDEN_LETTERS[i, 1]
              raise abort("#{TAG_FORBIDDEN_LETTERS[i,1]} not allowed in a tag name!")
            end
          end
        end
        
        ##
        # Adds the given tag to a given changeset, and commits to preserve it.
        #
        # @param [String, Array] names a list of tags (or just 1 tag) to apply to
        #   the changeset
        # @param [String, Integer] node the node to apply the tag to
        # @param [Hash] opts the opts for tagging
        # @option opts [String] message ("added tag _tag_ to changeset _node_") 
        #   the commit message to use. 
        # @option opts [Boolean] local (false) is the tag a local one? I.E., will it be
        #   shared across repos?
        # @option opts [String] user ($USER) the username to apply for the commit
        # @option opts [Time] time (Time.now) what should the commit-time be marked as?
        # @option opts [String] parent (nil) The parent revision of the one we
        #   are tagging. or something.
        # @option opts [Hash] extra ({}) the extra data to apply for the commit.
        def apply_tag(names, node, opts={})
          use_dirstate = opts[:parent].nil?
          verify_tag_names(names)
          
          # If it's a local tag, we just write the file and bounce. mad easy yo.
          if opts[:local]
            write_hgtags_file(@hg_opener, "localtags", "r+", node, names)
            return
          end
          
          # ok, it's a global tag. now we have to handle versioning and shit.
          if use_dirstate
            write_hgtags_file(@file_opener, ".hgtags", "a", node, names)
          else
            prev_tags = versioned_file(".hgtags", :change_id => parent).data || ""
            write_hgtags_file(@file_opener, ".hgtags", "w", node, names, prev_tags)
          end
          
          staging_area.add(".hgtags") if use_dirstate
          
          tag_node = commit :modified => [".hgtags"], 
                            :message => opts[:message], 
                            :user => opts[:user],
                            :date => opts[:date],
                            :parents => [opts[:parent]], 
                            :extra => opts[:extra]
          
          tag_node
        end
        
        private
        
        ##
        # Writes out a file containing hgtags. Could be the "localtags" file for storing
        # local tags, or could be the .hgtags. That's specified with a parameter.
        #
        # @param [Amp::Opener] the opener to use
        # @param [String] filename the file to write to
        # @param [String] mode the mode to use for writing
        # @param [String] node the node to use for the new tags
        # @param [Array<String>] names the tag names to write
        # @param [String] preamble (nil) the preamble to write if necessary.
        def write_hgtags_file(opener, filename, mode, node, names, preamble = nil)
          opener.open(filename, mode) do |file|
            file << preamble if preamble
            write_tags(file, node, names)
          end
        end
        
        ##
        # Goes through all the heads in the repository, getting the state of the .hgtags
        # file at each head. We then return a list, with each entry mapping revision index
        # and node ID to the .hgtags file at that head. If two different heads have the same
        # .hgtags file, only 1 is returned with it.
        #
        # @return [(Fixnum, String, VersionedFile)] each head with a different .hgtags file
        #   at that point. That way we have the most recent copy of .hgtags, even if the file
        #   differs on different heads.
        def hg_tags_nodes
          return_list = {}
          self.heads.reverse.each do |node|
            changeset = self[node]
            rev = changeset.revision
            file_node = changeset.get_file(".hgtags") rescue next
            return_list[file_node] = [rev, node, file_node]
          end
          return return_list.values
        end
        
        ##
        # Writes the tags to the given stream. This method must be aware of previously
        # written tags. Also, any new tags must state what the node to use for writing is.
        #
        # @param [IO, #write] file the output stream to write to. Could be a file, or any IO.
        # @param [String] node a binary node ID for any newly-added tags
        # @param [Array] names A list of all the tag names to write
        def write_tags(file, node, names)
          file.seek(0, IO::SEEK_END)
          # Make sure file currently ends in a newline.
          if file.tell == 0 || file.seek(-1, IO::SEEK_CUR) && file.read(1) != "\n"
            file.write "\n"
          end
          # Write each line.
          names.each do |name|
            if @tags_type_cache && @tags_type_cache[name]
              old = @tags_cache[name] || NULL_ID
              file.write("#{old.hexlify} #{name}\n")
            end
            file.write("#{node.hexlify} #{name}\n")
          end
        end
        
        ##
        # Parses the lines of a .hgtags file. Calculates a list of heads for each
        # tag.
        #
        # @param [Array<String>] lines the lines of the file
        # @param [String] filename the name of the file (for error reporting)
        def parse_tag_heads(lines, filename)
          file_tags = {}
          # Each line is of the format:
          # [char * 40, node ID] [tag]
          # 0123456789012345678901234567890123456789 crazymerge
          lines.each_with_index do |line, count|
            # skip if we have no text to parse
            next if line.nil? || line.empty?
            
            # split once, so we could theoretically have spaces in tag names
            node, tag = line.split(" ", 2)
            # make sure we parsed the tag entry alright
            unless node && tag
              UI::warn "Can't parse entry, filename #{filename} line #{count}"
              next
            end

            # convert out of file-stored format
            bin_node, tag = node.unhexlify, tag.strip
            
            # Is it in our repo? if not, skip to the next tag.
            unless self.changelog.node_map[bin_node]
              UI::warn "Tag #{tag} refers to unknown node"
              next
            end
            
            # have we already seen this tag?
            if file_tags[tag]
              # pull out the old data
              heads = file_tags[tag][1] << file_tags[tag][0]
            else
              heads = []
            end
             # update our tag list
            file_tags[tag] = [bin_node, heads]
          end
          file_tags
        end
        
        ##
        # Reads in an .hgtags file and parses it, while respecting global tags.
        # This is where things get kinda messy, because otherwise we'd just be parsing
        # a simple text file. Anyway, global_tags are tags like "tip" -> the current tip
        # - they're programmatically assigned tags.
        #
        # @param [Array<String>] lines the file, split into lines
        # @param [String] fn the file that we are parsing, only for debug purposes
        # @param [String] tag_type what kind of tag are we looking at? usually "local"
        #   or "global" or nothing. For example, a local-only tag isn't committed - these
        #   need to be treated differently.
        # @param [Hash] global_tags maps nodes to global tags, such as "tip".
        # @param [Hash] tag_types maps nodes to what type of tag they are
        # @return [Hash] the list of tags we have read in.
        #
        # @todo encodings, handle local encodings
        def read_tags(lines, fn, tag_type, global_tags, tag_types)
          # This is our tag list we'll be building.
          file_tags = parse_tag_heads(lines, fn)
          
          # For each tag that we have...
          file_tags.each do |tag, nh|
            # Is this a reserved, global tag? Or, just one that's been used already? 
            # like "tip"? if not, we're ok
            unless global_tags[tag]
              # register the tag list in the global list.
              global_tags[tag] = nh
              # set the tag_types hash as well
              tag_types[tag] = tag_type
              next
            end
            # We have a tag that is already used.
            # a_node/a_heads - the list we got from the file
            a_node, a_heads = nh
            # b_node/b_heads - the already-figured-out tag heads
            b_node, b_heads = global_tags[tag]
            # should we use the already-figured-out tag heads instead?
            if b_node != a_node && b_heads.include?(a_node) && 
              (!a_heads.include?(bn) || b_heads.size > a_heads.size)
              a_node = b_node
            end
            # Union the two head lists into a_heads
            a_heads |= b_heads
            # Save our results
            global_tags[tag] = a_node, a_heads
            tag_types[tag] = tag_type
          end
        end
      end
    end
  end
end