##
# Ruby versions of slow functions we've implemented in C
class Integer
  
  ##
  # Used for byte-swapping a 64-bit double long.
  # Unfortuantely, this will invoke bignum logic, which is ridiculously slow.
  # That's why we have a C extension.
  # 
  # If the system is little endian, we work some magic. If the system is big
  # endian, we just return self.
  #
  # @return [Integer] the number swapped as if it were a 64-bit integer
  def byte_swap_64
    if Amp::Support::SYSTEM[:endian] == :little
      ((self >> 56))                        | ((self & 0x00FF000000000000) >> 40) |
        ((self & 0x0000FF0000000000) >> 24) | ((self & 0x000000FF00000000) >> 8 ) |
        ((self & 0x00000000FF000000) << 8 ) | ((self & 0x0000000000FF0000) << 24) |
        ((self & 0x000000000000FF00) << 40) | ((self & 0x00000000000000FF) << 56)
    else
      self
    end
  end
  
  ##
  # Returns the number as if it were a signed 16-bit integer. Since unpack() always returns
  # unsigned integers, we have to sign them here.
  #
  # @return [Integer] the number overflowed if it would overflow as a 16-bit integer
  def to_signed_16
    return self if self < 32785
    return self - 65536
  end
  
  ##
  # Returns the number as if it were a signed 32-bit integer. Since unpack() always returns
  # unsigned integers, we have to sign them here.
  #
  # @return [Integer] the number overflowed if it would overflow as a 32-bit integer
  def to_signed_32
    return self if self < 2147483648
    return self - 4294967296
  end
  
  ##
  # Converts to a useful symbol for dir_state. States are represented as a character
  # in the DirState file, such as "n" for "normal". We will read them in as a number,
  # then convert those numbers to a nice symbol!
  #
  # @example "n".ord.to_dirstate_symbol #=> :normal
  # @return [Symbol] a symbol representing the dirstate state this number stands for
  def to_dirstate_symbol
    case self
    when 110 # "n".ord
      :normal
    when 63  # "?".ord
      :untracked
    when 97  # "a".ord
      :added
    when 109 # "m".ord
      :merged
    when 114 # "r".ord
      :removed
    else
      raise "No known hg value for #{self}"
    end
  end
end

class String

  if RUBY_VERSION < "1.9"
    ##
    # Converts a string of hex into the binary values it represents. This is used for
    # when we store a node ID in a human-readable format, and need to convert it back.
    #
    # @example "DEADBEEF".unhexlify #=> "\336\255\276\357"
    # @return [String] the string decoded from hex form
    def unhexlify
      str = "\000" * (size/2)
      c = 0
      (0..size-2).step(2) do |i|
        hex = self[i,2].to_i(16)
        str[c] = hex
        c += 1
      end
      str
    end
  else
    def unhexlify
      str = "\000" * (size/2)
      c = 0
      (0..size-2).step(2) do |i|
        hex = self[i,2].to_i(16)
        str[c] = hex.chr
        c += 1
      end
      str
    end
  end
end


