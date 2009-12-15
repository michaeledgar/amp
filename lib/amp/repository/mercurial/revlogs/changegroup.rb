require 'tempfile'
module Amp
  module Mercurial
    module RevlogSupport
      
      ##
      # This class handles changegroups - most specifically, packaging up a bunch
      # of revisions into a single bundled file.
      #
      module ChangeGroup
        BUNDLE_HEADERS = {
            "" => "",
            "HG10UN" => "HG10UN",
            "HG10BZ" => "HG10",
            "HG10GZ" => "HG10GZ"
        }
        FORMAT_PRIORITIES = BUNDLE_TYPES = ["HG10GZ", "HG10BZ", "HG10UN"]
        class ChangeGroupError < StandardError; end
        
        ##
        # Loads a single chunk of data from a changegroup. Each chunk is stored in the
        # changegroup as:
        #   (uint32_t) length    <-- less than 4 if we should terminate
        #   (length * char) body
        # Example:
        #      00 00 00 05 h e l l o
        #
        # @param [IO, #read] source the source stream with all the data that we'll be
        #   working on.
        # @return [String] the data read in. Will be either nil or the empty string if
        #   no data was read.
        def self.get_chunk(source)
          data = source.read 4
          return "" if data.nil? || data.empty?
          l = data.unpack("N")[0]
          return "" if l <= 4
          data = source.read(l - 4)
          if data.size < l - 4
            raise ChangeGroupError.new("premature EOF when reading changegroup:" +
                                       "(got #{data.size} bytes, expected #{l-4})")
          end
          return data
        end
        
        ##
        # Loads each chunk, in a row, until we run out of chunks in the changegroup.
        # Yields the data to the caller. This will run until we hit a terminating chunk.
        #
        # @param [IO, #read] source The stream from which we will read the data in sequence
        # @yield Each chunk of data will be yielded to be processed
        # @yieldparam [String] chunk the chunk that is yielded
        def self.each_chunk(source)
          begin
            c = self.get_chunk(source) # get a chunk
            yield c unless c.empty?    # yield if not empty
          end until c.empty?           # keep going if we have more!
        end
        
        ##
        # If we have data of size +size+, then return the encoded header for the chunk
        #
        # @param [Integer] size the size of the chunk we wish to encode
        # @return [String] the encoded header for the chunk
        def self.chunk_header(size)
          [size + 4].pack("N")
        end
        
        ##
        # The terminating chunk that indicates the end of a chunk sequence
        #
        # @return [String] the encoded terminating chunk
        def self.closing_chunk
          "\000\000\000\000" # [0].pack("N")
        end
        
        ##
        # Returns a compressing stream based on the header for a changegroup bundle.
        # The bundle header will specify that the contents should be either uncompressed,
        # BZip compressed, or GZip compressed. This will return a stream that responds
        # to #<< and #flush, where #flush will return the unread, decompressed data,
        # and #<< will input uncompressed data.
        #
        # @param [String] header the header for the changegroup bundle. Can be either
        #   HG10UN, HG10GZ, or HG10BZ, or HG10.
        # @return [IO, #<<, #flush] an IO stream that accepts uncompressed data via #<< or
        #   #write, and returns compressed data by #flush.
        def self.compressor_by_type(header)
          case header
          when "HG10UN", ""
            # new StringIO
            result = StringIO.new "",(ruby_19? ? "w+:ASCII-8BIT" : "w+")
            # have to fix the fact that StringIO doesn't conform to the other streams,
            # and give it a #flush method. Kind of hackish.
            class << result
              def flush
                ret = self.string.dup  # get the current read-in string
                self.string.replace "" # erase our contents
                self.rewind            # rewind the IO
                self.tell
                ret                    # return the string
              end
            end
            #return the altered StringIO
            result
          when "HG10GZ"
            # lazy-load Zlib
            require 'zlib'
            # Return a deflating stream (compressor)
            Zlib::Deflate.new
          when "HG10BZ", "HG10"
            # lazy load BZip
            need { '../../../ext/amp/bz2/bz2' }
            # Return a compressing BZip stream
            BZ2::Writer.new
          end
        end
        
        ##
        # Returns a stream that will decompress the IO pointed to by file_handle, 
        # when #read is called upon it. Note: file_handle doesn't have to be a file!
        #
        # @param [String] header the header of the stream. Specifies which compression
        #  to handle
        # @param [IO, #read] file_handle the input stream that will provide the compressed
        #  data.
        # @return [IO, #read] an IO object that we can #read to get uncompressed data
        def self.unbundle(header, file_handle)
          # uncompressed? just return the input IO!
          return file_handle if header == "HG10UN"
          # if we have no header, we're uncompressed
          if !header.start_with?("HG")
            # append the header to it. meh
            headerio = StringIO.new(header, (ruby_19? ? "w+:ASCII-8BIT" : "w+"))
            Amp::Support::MultiIO.new(headerio, file_handle)
            # WOW we have legacy support already
          elsif header == "HG10GZ"
            # Get a gzip reader
            Zlib::GzipReader.new(file_handle)
          elsif header == "HG10BZ"
            # get a BZip reader, but it has to decompress "BZ" first. Meh.
            headerio = StringIO.new("BZ", (ruby_19? ? "w+:ASCII-8BIT" : "w+"))
            input = Amp::Support::MultiIO.new(headerio, file_handle)
            BZ2::Reader.new(input)
          end
        end
            
        ##
        # Writes a set of changegroups to a bundle. If no IO is specified, a new StringIO
        # is created, and the bundle is written to that (i.e., memory). the IO used is returned.
        #
        # @param [IO, #read, #seek] changegroup A stream that will feed in an uncompressed
        #   changegroup
        # @param [String] bundletype A specified compression type - either "HG10UN", "HG10GZ",
        #   or "HG10BZ". The empty string defaults to "HG10UN".
        # @param [IO, #write] fh (StringIO.new) An output stream to write to, such as a File
        #   or a socket. If not specified, a StringIO is created and returned.
        # @return [IO, #write] the output IO stream is returned, even if a new one is not
        #   created on the fly.
        def self.write_bundle(changegroup, bundletype, fh = StringIO.new("", (ruby_19? ? "w+:ASCII-8BIT" : "w+")))
          # rewind the changegroup to start at the beginning
          changegroup.rewind
          # pick out our header
          header     = BUNDLE_HEADERS[bundletype]
          # get a compressing stream
          compressor = compressor_by_type header
          # output the header (uncompressed)
          fh.write header
          
          # These 2 variables are for checking to see if #changegroup has been fully
          # read in or not. 
          empty = false
          count = 0
          
          # Do at least 2 changegroups (changelog + manifest), then go until we're empty
          while !empty || count <= 2
            # Set empty to true for this particular file (each iteration of this loop
            # represents compressing 1 file's changesets into changegroups in the bundle)
            empty = true
            # Add 1 to the number of files we've comrpessed
            count += 1
            # For each chunk in the changegroup (i.e. each changeset)
            inner_count = 0
            self.each_chunk(changegroup) do |chunk|
              inner_count += 1
              empty = false
              # Compress the chunk header
              compressor << chunk_header(chunk.size)
              # Write the chunk header
              fh.write(compressor.flush)
              
              # compress the actual chunk 1 megabyte at a time
              step_amt = 1048576
              (0..chunk.size).step(step_amt) do |pos|
                compressor << chunk[pos..(pos+step_amt-1)]
                fh.write(compressor.flush)
                fh.flush
              end
            end
            # Compress the terminating chunk - this indicates that there are no more changesets
            # for the current file
            compressor << closing_chunk
            # Write the terminating chunk out!
            fh.write compressor.flush
            fh.flush
          end
          
          # Write anything left over in that there compressor
          fh.write compressor.flush
          # Kill the compressor
          compressor.close
          # Return the IO we wrote to (in case we instantiated it)
          return fh
        end
      end
    end
  end
end