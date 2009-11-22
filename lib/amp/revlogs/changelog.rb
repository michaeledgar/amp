module Amp
  
  ##
  # This is used for faking data writing, until we're totally done
  # accumulating data.
  class FakeFileAppender
    
    ##
    # Initializes the fake file with the pointer to the real deal,
    # and also the current data
    def initialize(fp, buffer, size)
      @data = buffer
      @fp = fp
      @offset = fp.tell
      @size = size
    end
    
    ##
    # Returns the endpoint of the data in the (fake) file
    def endpt
      @size + @data.join.size
    end
    
    ##
    # Returns the current offset of the (fake) file
    def tell
      @offset
    end
    
    ##
    # Nothing, since we don't flush, we just sit here
    def flush; end
    
    ##
    # Closes the real file pointer for this fake file
    def close
      @fp.close
    end
    
    ##
    # Seeks to the position requested. We're faking this, but it's a little
    # tougher, because if we break the fake file down like this:
    #
    # [   actual file  size = 10  |  pending data size = 10 ]
    #
    # If the user seeks to 15, we need to make sure we don't try to seek to
    # 15 in the file, as that would cause errors.
    def seek(offset, whence)
      if whence == IO::SEEK_SET
        @offset = offset
      elsif whence == IO::SEEK_CUR
        @offset += offset
      elsif whence == IO::SEEK_END
        @offset = self.endpt + offset
      end
      if @offset < @size
        @fp.seek @offset
      end
    end
    
    ##
    # Reads from the fake file, for _count_ bytes. This is a little sketchy
    # because we might be reading some real data and some fake data, or all
    # real, or all fake.
    # 
    # @param  [Integer] count how much to read. -1 will read it all.
    # @return [String]  the contents
    def read(count=-1)
      ret = ""
      
      if @offset < @size
        s = @fp.read(count)
        ret = s
        @offset += s.size
        if count > 0
          count -= s.size
        end
      end
      
      unless count.zero?
        doff = @offset - @size
        @data.unshift @data.join
        @data.delete_range(1..-1)
        s = @data[0][doff..(doff+count-1)]
        @offset += s.size
        ret += s
      end
      
      ret
    end
    
    ##
    # Writes to the fake file. Notice - this will only work because we only
    # append to the file - we don't write in the middle anywhere, or this
    # scheme would fail.
    # 
    # @param [#to_s] s data to write
    def write(s)
      @data << s.to_s
      @offset += s.size
    end
  end
  
  class DelayedOpener
    attr_accessor :default
    
    ##
    # Initializes the delayed opener, needing the real deal, and the owner
    # of the delayed opener.
    # 
    # @param [Opener] realopener the actual opener. Since the DelayedOpener
    #   doesn't know how to open files, we'll need this!
    # @param [ChangeLog] owner the owner of the delayed opener. This reference
    #   is needed because we need to check on the state of the delayed_buffer
    #   and what not.
    def initialize(realopener, owner)
      @real_opener, @owner = realopener, owner
    end
    
    ##
    # Specialized opener that will fake writing when asked to. We need to
    # know who our owner is and we need a real opener so we can actually
    # open files. The DelayedOpener doesn't know how to do real IO.
    def open(name, mode="r")
      fp = @real_opener.open(name, mode)
      return fp if name != @owner.index_file
      
      # Are we holding off on writing? if so, set up the file where we
      # writing pending data.
      
      if @owner.delay_count == 0
        @owner.delay_name = File.amp_name(fp)
        mode.gsub!(/a/, 'w') if @owner.empty?
        return @real_opener.open(name+".a", mode) # See what I did there?
      end
      
      # FakeFileAppender = fake file so we don't do any real writing yet
      size = File.stat(@real_opener.join(name)).size
      ffa = FakeFileAppender.new(fp, @owner.delay_buffer, size)
      
      return ffa
    end
  end
  
  ##
  # A ChangeLog is a special revision log that stores the actual commit data,
  # including usernames, dates, messages, all kinds of stuff.
  #
  # This version of the revision log is special though, because sometimes
  # we have to hold off on writing until all other updates are done, for
  # example during merges that might fail. So we have to actually have
  # a real Opener and a fake one, which will save the data in memory.
  # When you call #finalize, the fake file will replace the real deal.
  class ChangeLog < Amp::Revlog
    attr_accessor :delay_count, :delay_name, :index_file, :delay_buffer, :node_map
    
    ##
    # Initializes the revision log. Just pass in an Opener. Amp::Opener.new(path)
    # will do just fine.
    # 
    # @param [Amp::Opener] opener an object that knows how to open
    #   and return files based on a root directory.
    def initialize(opener)
      super(opener, "00changelog.i")
      @node_map = @index.node_map
    end
    alias_method :changelog_initialize, :initialize
    
    ##
    # Tells the changelog to stop writing updates directly to the file,
    # and start saving any new info to memory/other files. Used when the
    # changelog has to be the last file saved.
    def delay_update
      @_real_opener = @opener
      @opener = DelayedOpener.new(@_real_opener, self) # Our fake Opener
      @delay_count = self.size
      @delay_buffer = []
      @delay_name = nil
    end
    
    ##
    # Finalizes the changelog by swapping out the fake file if it has to.
    # If there's any other data left in the buffer, it will be written
    # as well.
    def finalize(journal)
      if @delay_name
        src = @_real_opener.join(@index_file+".a")
        dest = @_real_opener.join(@index_file)
        @opener = @_real_opener # switch back to normal mode....
        return File.amp_force_rename(src, dest)
      end
      
      if @delay_buffer && @delay_buffer.any?
        @fp = open(@index_file, "a")
        @fp.write @delay_buffer.join
        @fp.close
        @delay_buffer = []
      end
      # check_inline_size journal
    end
    
    ##
    # Reads while we're blocking this changelog's output.
    # @param file the file to read in as a revision log
    def read_pending(file)
      r = Revlog.new(@opener, file)
      @index = r.index
      @node_map = r.index.node_map
      @chunk_cache = r.chunk_cache
    end
    
    ##
    # Writes our data, while being aware of the delay buffer when we're holding
    # off on finalizing the changelog.
    def write_pending
      if @delay_buffer && @delay_buffer.size > 0
        fp1 = @_real_opener.open(@index_file)
        fp2 = @_real_opener.open(@index_file + ".a", "w+")
        puts "trying to open #{@index_file + ".a"}..."
        fp2.write fp1.read
        fp2.write @delay_buffer.join
        fp2.close
        fp1.close
        @delay_buffer = []
        @delay_name = @index_file
      end
      return true if @delay_name && @delay_name.any?
      false
    end
    
    ##
    # Does a check on our size, but knows enough to quit if we're still in
    # delayed-writing mode.
    # @param [Amp::Journal] journal the journal to use to keep track of our transaction
    # @param [File] fp the file pointer to use to check our size
    def check_inline_size(journal, fp=nil)
      return if @opener.is_a? DelayedOpener
      super(journal, fp)
    end
    
    ##
    # Decodes the extra data stored with the commit, such as requirements
    # or just about anything else we need to save
    # @param [String] text the data in the revision, decompressed
    # @return [Hash] key-value pairs, joining each file with its extra data
    def decode_extra(text)
      extra = {}
      text.split("\0").select {|l| l.any? }.
                       map {|l| l.remove_slashes.split(":",2) }.
                       each {|k,v| extra[k]=v }
      extra
    end
    
    ##
    # Encodes the extra data in a format we can use for writing.
    # @param [Hash] data the extra data to format
    # @return [String] the encoded data
    def encode_extra(data)
      " " + data.sort.map {|k| "#{k}:#{data[k]}".add_slashes }.join("\0")
    end
    
    ##
    # Reads the revision at the given node_id. It returns it in a format
    # that tells us everything about the revision - the manifest, the user
    # who committed it, timestamps, the relevant filenames, the description
    # message, and any extra data.
    # 
    # @todo Text encodings, I hate you. but i must do them
    # @param [Fixnum] node the node ID to lookup into the revision log
    # @return [[String, String, [Float, Integer], [String], String, Hash]]
    #   The format is [Manifest, Username, [Time, Timezone], [Filenames],
    #   Message, ExtraData].
    def read(node)
      text = decompress_revision node
      if text.nil? || text.empty?
        return [NULL_ID, "", [0,0], [], "", {"branch" => "default"}]
      end
      #p text
      last = text.index("\n\n")
      desc = text[last+2..-1] #TODO: encoding
      l = text[0..last].split("\n")
      manifest = l[0].unhexlify
      user = l[1] #TODO: encoding
      extra_data = l[2].split(' ', 3)
      if extra_data.size != 3
        time = extra_data.shift.to_f
        timezone = extra_data.shift.to_i
        extra = {}
      else
        time, timezone, extra = extra_data
        time, timezone = time.to_f, timezone.to_i
        extra = decode_extra text
      end
      extra["branch"] = "default" unless extra["branch"]
      
      files = l[3..-1]
      
      #puts(">> Ari's tipmost changeset: "+[manifest, user, [time, timezone], files, desc, extra].inspect) #killme
      
      [manifest, user, [time, timezone], files, desc, extra]
    end
    
    ##
    # Adds the given commit to the changelog.
    # 
    # @todo Handle text encodings
    # @param [Amp::Manifest] Manifest a hex-version of a node_id or something?
    # @param [String] files the files relevant to the commit, to be included
    # @param [String] desc the commit message from the user
    # @param [Amp::Journal] journal the transaction journal to write to for rollbacks if
    #   something goes horribly wrong
    # @param [String] p1 the first parent of this node
    # @param [String] p2 the second parent of this node
    # @param [Strng] user the username of the committer
    # @param [Time] date the date of the commit
    # @param [Hash] extra any extra data
    def add(manifest, files, desc, journal, p1=nil, p2=nil, user=nil, date=nil, extra={})
      user = user.strip
      raise RevlogSupport::RevlogError.new("no \\n in username") if user=~ /\n/
      user, desc = user, desc #TODO: encoding!
      
      date = Time.now unless date
      parsed_date = "#{date.to_i} #{-1 * date.utc_offset}"
      
      if extra && ["default", "", nil].include?(extra["branch"])
        extra.delete "branch"
      end
      if extra
        extra = (extra.any?) ? encode_extra(extra) : ""
        parsed_date = "#{parsed_date}#{extra}"
      end
      
      l = [manifest.hexlify, user, parsed_date] + files.sort + ["", desc]
      text = l.join "\n"
      add_revision text, journal, self.size, p1, p2
    end
  end
end
