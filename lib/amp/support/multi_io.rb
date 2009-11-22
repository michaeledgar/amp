module Amp
  module Support
    ##
    # = MultiIO
    # A MultiIO is a class which joins multiple IO classes together. It responds to
    # #read, and its constituent IOs must respond to #read. Since, currently, it only
    # needs to be able to read (and perhaps rewind), that's all it does. It allows one
    # to feed, say, 3 separate input IO objects into a GZipWriter, and have it seamlessly
    # traverse all 3 IOs.
    class MultiIO
      # These are all the base IO objects we are joining together.
      attr_accessor :ios
      # Points to the current IO object in the @ios array.
      attr_accessor :current_io_idx
      # Tracks our current index into the "joined" stream. In other words, if they were
      # all lumped into 1 stream, how many bytes in would we be?
      attr_accessor :current_pos
      
      ##
      # Initializes the MultiIO to contain the given IO objects, in the order in which
      # they are specified as arguments.
      #
      # @param [Array<IO>] ios The IO objects we are concatenating
      def initialize(*ios)
        @ios = ios
        rewind
      end
      
      ##
      # Rewinds all the IO objects to position 0.
      def rewind
        @ios.each {|io| io.seek(0) } 
        @current_pos = 0
        @current_io_idx = 0
      end
      
      ##
      # Gets the current position in the concatenated IO stream.
      #
      # @return [Integer] position in the IO stream (if all were 1 big stream, that is)
      def tell; @current_pos; end
      
      ##
      # Reads from the concatenated IO stream, crossing streams if necessary.
      # (DON'T CROSS THE STREAMS!!!!)
      # 
      # @param [Integer] amt (nil) The number of bytes to read from the overall stream.
      #   If +nil+, reads until the end of the stream.
      # @return [String] the data read in from the stream
      def read(amt=nil)
        if amt==nil # if nil, read it all
          return @ios[@current_io_idx..-1].map {|io| io.read}.join
        end
        results = [] # result strings
        amount_read = 0 # how much have we read? We need this to match the +amt+ param
        cur_spot = current_io.tell # our current position
        while amount_read < amt # until we've read enough to meet the request
          results << current_io.read(amt - amount_read) # read enough to finish
          amount_read += current_io.tell - cur_spot # but we might not have actually read that much
          @current_pos += current_io.tell - cur_spot # update ivar
          # Do we need to go to the next IO stream?
          if amount_read < amt && @current_io_idx < @ios.size - 1
            # go to the next stream
            @current_io_idx += 1 
            # reset it just in case
            current_io.seek(0)
          # are we at the last stream?
          elsif @current_io_idx >= @ios.size - 1
            break
          end
          # if we need to read from another stream, then remember we're at the start of it
          cur_spot = 0
        end
        # join 'em up
        results.join
      end
      
      private
      ##
      # Returns the current IO object - we use it for reading
      #
      # @return [IO] the current IO object (that we should use if we need to read or seek)
      def current_io; @ios[@current_io_idx]; end
      
    end
  end
end