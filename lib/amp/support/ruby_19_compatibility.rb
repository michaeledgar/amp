module Kernel
  def ruby_19?; (RUBY_VERSION >= "1.9"); end
end

if RUBY_VERSION < "1.9"
  class String
    require 'enumerator' unless method_defined?(:to_enum)

    # DON'T USE String#each. Use String#each_line
    def lines
      return to_enum(:lines) if !block_given?
      self.split(/^/).each do |l|
        yield l
      end
    end unless method_defined?(:lines)
    
    ##
    # Returns the numeric, ascii value of the first character
    # in the string.
    #
    # @return [Fixnum] the ascii value of the first character in the string
    def ord
      self[0]
    end unless method_defined?(:ord)
  end
  class Object
    def tap
      yield self
      self
    end unless method_defined?(:tap)
  end
else
  # 1.9 +
  # Autoload bug in 1.9 means we have to directly require these. FML.
  require 'continuation'
  require 'zlib'
  require 'stringio'
  require 'fileutils'
  class String
    # String doesn't include Enumerable in Ruby 1.9, so we lose #any?.
    # Luckily it's quite easy to implement.
    #
    # @return [Boolean] does the string have anything in it?
    def any?
      size > 0
    end
  end
  
  class File
    ##
    # This is in ftools in Ruby 1.8.x, but now it's in FileUtils. So
    # this is essentially an alias to it. Silly ftools, trix are for kids.
    def self.copy(*args)
      FileUtils.copy(*args)
    end
    ##
    # This is in ftools in Ruby 1.8.x, but now it's in FileUtils. So
    # this is essentially an alias to it. Silly ftools, trix are for kids.
    def self.move(*args)
      FileUtils.move(*args)
    end
    ##
    # This is in ftools in Ruby 1.8.x, but now it's in FileUtils. So
    # this is essentially an alias to it. Silly ftools, trix are for kids.
    def self.makedirs(*args)
      FileUtils.makedirs(*args)
    end
  end
end
