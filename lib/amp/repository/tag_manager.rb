module Amp
  module Repositories
    ##
    # = TagManager
    # This module handles all tag-related (but not branch tag) functionality
    # of the repository. 
    module TagManager
      include Amp::RevlogSupport::Node
      
      TAG_FORBIDDEN_LETTERS = ":\r\n"
      ##
      # Returns a list of all the tags as a hash, mapping each tag to the tip-most
      # changeset it applies to.
      #
      # @return [Hash] a hash, sorted by revision index (i.e. its order in the commit
      #   history), with the keys:
      #   :revision => the revision index of the changeset,
      #   :tag => the name of the tag,
      #   :node => the node-id of the changeset
      def tag_list
        list = []
        tags.each do |tag, node|
          begin
            r = changelog.revision(node)
          rescue
            r = -2
          end
          list << {:revision => r, :tag => tag, :node => node}
        end
        list.sort {|i1, i2| i1[:revision] <=> i2[:revision] }
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
      # Returns the tags for a given revision (by ID).
      #
      # @param [String] node the node-ID, in binary form.
      # @return [Array<String>] a list of tags for the given node.
      def tags_for_node(node)
        return (@tags_for_node_cache[node] || []) if @tags_for_node_cache
        @tags_for_node_cache = {}
        tags.each do |tag, tag_node|
          @tags_for_node_cache[tag_node] ||= [] # make sure there's an array
          @tags_for_node_cache[tag_node] << tag # add the tag to it
        end
        @tags_for_node_cache[node] || []
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
        return @tags_cache if @tags_cache
        
        global_tags, tag_types = {}, {}
        
        file = nil
        # For each current .hgtags file in our history (including multi-heads), read in
        # the tags
        hg_tags_nodes.each do |rev, node, file_node|
          # get the file
          f = (f && f.file(file_node)) || self.versioned_file(".hgtags", :file_id => file_node.file_node)
          # read the tags, as global, because they're versioned.
          read_tags(f.data.split("\n"), f, "global", global_tags, tag_types)
        end
        
        # Now do locally stored tags, that aren't committed/versioned
        begin
          # get the local file, stored in .hg/
          data = @hg_opener.read("localtags")
          # Read the tags as local, because they are not versioned
          read_tags(data.split_newlines,"local_tags","local",global_tags, tag_types)
        rescue Errno::ENOENT
          # do nothing. most people don't have this file.
        end
        # Save our tags for use later. Use ivars.
        @tags_cache = {}
        @tags_type_cache = {}
        # Go through the global tags to store them in the cache
        global_tags.each do |k, nh|
          # the node ID is the first part of the stored data
          n = nh.first
          
          # update the cache
          @tags_cache[k] = n unless n == NULL_ID
          @tags_type_cache[k] = tag_types[k]
        end
        
        # tip = special tag
        @tags_cache["tip"] = self.changelog.tip
        
        # return our tags
        @tags_cache
      end
      
      ##
      # Adds the given tag to a given changeset, and commits to preserve it.
      #
      # @param [String, Array] names a list of tags (or just 1 tag) to apply to
      #   the changeset
      # @param [String, Integer] node the node to apply the tag to
      # @param [Hash] opts the opts for tagging
      # @option [String] opts message ("added tag _tag_ to changeset _node_") 
      #   the commit message to use. 
      # @option [Boolean] opts local (false) is the tag a local one? I.E., will it be
      #   shared across repos?
      # @option [String] opts user ($USER) the username to apply for the commit
      # @option [Time] opts time (Time.now) what should the commit-time be marked as?
      # @option [String] opts parent (nil) The parent revision of the one we
      #   are tagging. or something.
      # @option [Hash] opts extra ({}) the extra data to apply for the commit.
      def apply_tag(names, node, opts={})
        use_dirstate = opts[:parent].nil?
        all_letters  = names.kind_of?(Array) ? names.join : names
        (TAG_FORBIDDEN_LETTERS.size-1).downto 0 do |i|
          if all_letters.include? TAG_FORBIDDEN_LETTERS[i, 1]
            raise abort("#{TAG_FORBIDDEN_LETTERS[i,1]} not allowed in a tag name!")
          end
        end
        
        prev_tags = ""
        # If it's a local tag, we just write the file and bounce. mad easy yo.
        if opts[:local]
          @hg_opener.open("localtags","r+") do |fp|
            prev_tags = fp.read
            write_tags(fp,names, nil, prev_tags)
          end
          return
        end
        
        # ok, it's a global tag. now we have to handle versioning and shit.
        if use_dirstate
          prev_tags = working_read(".hgtags") rescue ""
          file = @file_opener.open(".hgtags","a")
        else
          prev_tags = versioned_file(".hgtags", :change_id => parent).data
          file = @file_opener.open(".hgtags","w")
          
          file.write prev_tags if prev_tags && prev_tags.any?
        end
        
        write_tags(file, node, names, prev_tags)
        file.close
        if use_dirstate && dirstate[".hgtags"].status == :untracked
          self.add([".hgtags"])
        end
        
        tag_node = commit :files => [".hgtags"], 
                          :message => opts[:message], 
                          :user => opts[:user],
                          :date => opts[:date], 
                          :p1 => opts[:parent], 
                          :extra => opts[:extra]
        
        tag_node
      end
      
      private
      
      ##
      # Goes through all the heads in the repository, getting the state of the .hgtags
      # file at each head. We then return a list, with each entry mapping revision index
      # and node ID to the .hgtags file at that head. If two different heads have the same
      # .hgtags file, only 1 is returned with it.
      #
      # @return [[Fixnum, String, VersionedFile]] each head with a different .hgtags file
      #   at that point. That way we have the most recent copy of .hgtags, even if the file
      #   differs on different heads.
      def hg_tags_nodes
        heads = self.heads.reverse
        last = {}
        return_list = []
        heads.each do |node|
          changeset = self[node]
          rev = changeset.revision
          begin
            file_node = changeset.get_file(".hgtags")
          rescue
            next
          end
          return_list << [rev, node, file_node]
          return_list[last[file_node]] = nil if last[file_node] # replace old head
          
          last[file_node] = return_list.size - 1
        end
        return return_list.reject {|item| item.nil?}
      end
      
      ##
      # Writes the tags to the given stream. This method must be aware of previously
      # written tags. Also, any new tags must state what the node to use for writing is.
      #
      # @param [IO, #write] file the output stream to write to. Could be a file, or any IO.
      # @param [String] node a binary node ID for any newly-added tags
      # @param [Array] names A list of all the tag names to write
      # @param [Hash] prev_tags the previously written string (or something)
      def write_tags(file, node, names, prev_tags)
        file.seek(0, IO::SEEK_END)
        if prev_tags && prev_tags.any? && prev_tags[-1,1] != "\n"
          file.write "\n"
        end
        names.each do |name|
          if @tags_type_cache && @tags_type_cache[name]
            old = @tags_cache[name] || NULL_ID
            file.write("#{old.hexlify} #{name}\n")
          end
          file.write("#{node.hexlify} #{name}\n")
        end
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
        file_tags = {}
        
        # Each line is of the format:
        # [char * 40, node ID] [tag]
        # 0123456789012345678901234567890123456789 crazymerge
        lines.each_with_index do |line, count|
          # skip if we have no text to parse
          next if line.nil? || line.empty?
          
          # split once, so we could theoretically have spaces in tag names
          s = line.split(" ", 2)
          # make sure we parsed the tag entry alright
          if s.size != 2
            UI::warn "Can't parse entry, filename #{fn} line #{count}"
            next
          end
          
          # Node comes first, tag comes second
          node, tag = s
          tag.strip! #TODO: encodings, handle local encodings
          
          # Convert to binary so we can look it up in our repo
          bin_node = node.unhexlify
          
          # Is it in our repo? if not, skip to the next tag.
          unless self.changelog.node_map[bin_node]
            UI::warn "Tag #{key} refers to unknown node"
            next
          end
          
          # heads is a list of the nodes that have this same tag
          heads = []
          # have we already seen this tag?
          if file_tags[tag]
            # pull out the old data
            n, heads = file_tags[tag]
            # add our new node to the list for this tag
            heads << n
          end
           # update our tag list
          file_tags[tag] = [bin_node, heads]
        end
        
        # For each tag that we have...
        file_tags.each do |k, nh|
          # Is this a reserved, global tag? Or, just one that's been used already? 
          # like "tip"? if not, we're ok
          unless global_tags[k]
            # update global_tags with our new tag
            global_tags[k] = nh
            # set the tag_types hash as well
            tag_types[k] = tag_type
            next
          end
          # we prefer the global tag if:
          #  it supercedes us OR
          #  mutual supercedes and it has a higher rank
          # otherwise we win because we're tip-most
          an, ah = nh
          bn, bh = global_tags[k]
          if [bn != an, bh[an], (!ah[bn] || bh.size > ah.size)].all?
            an = bn
          end
          ah += bh.select {|n| !ah[n]}
          global_tags[k] = an, ah
          tag_types[k] = tag_type
        end
      end
    end
  end
end