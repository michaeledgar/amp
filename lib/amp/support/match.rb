module Amp
  
  ##
  # == Match
  # In this project, we came to a fork in the road: port the match class,
  # 200+ lines of strange and convoluted Python, or write our own matcher.
  # We chose to write our own matcher, and it was originally just a proc
  # that would be passed around. After a few days of working with that,
  # we then decided that it would be best to do our own implementation of
  # their Match class, because we needed access to three things from this
  # one object: the explicit files passed, the includes, and the excludes.
  class Match
    extend Ignore
    
    attr_reader :block
    attr_reader :files
    attr_reader :include
    attr_reader :exclude
    
    ##
    # Very similar to #new -- the only difference is that instead of
    # having to pass Regexps as :include or :exclude, you pass in
    # strings, and the strings are parsed and converted into regexps.
    # This is really the same as #initialize.
    # 
    # @see new
    # @param [Hash, [#include?, String, String]] either a hash or 
    #   arrays in the order of: files, include, exclude
    def self.create(*args, &block)
      args  = args.first
      includer, excluder = regexp_for(args[:includer]), regexp_for(args[:excluder])

      new :files   => args[:files],
          :include => includer,
          :exclude => excluder, &block
    end
    
    ##
    # To remove code duplication. This will return a regexp given +arg+
    # If arg is a string, it will turn it into a Regexp. If it's a Regexp,
    # it returns +arg+.
    # 
    # This is called from Match::create, so it needs to be a class method (duh)
    # 
    # @param [Regexp, String] arg
    # @return [Regexp] 
    def self.regexp_for(arg)
      case arg
      when Regexp
        [arg]
      when Array
        matcher_for_text arg.join("\n") if arg.any?
      when String
        [matcher_for_string(arg)]  if arg.any?
      end
    end
    
    ##
    # +args+ can either be a hash (with a block supplied separately)
    # or a list of arguments in the form of:
    #   files, includes, excludes, &block
    # 
    # The block should be used for things that can't be represented as
    # regular expressions. Thus, everything taken from the command line
    # is presented as either an include or an exclude, because blocks
    # are impossible from the console.
    # 
    # @example
    #   Match.new :files => [] do |file|
    #     file =~ /test_(.+).rb$/
    #   end
    # @example Match.new :include => /\.rbc$/
    # @example Match.new([]) {|file| file =~ /test_(.+).rb$/ }
    # @param [Hash, [#include?, Regexp, Regexp] either a hash or 
    #   arrays in the order of: files, include, exclude
    def initialize(*args, &block)
      if (hash = args.first).is_a? Hash
        @files   = hash[:files]   || []
        @include = hash[:include]
        @exclude = hash[:exclude]
        
      else
        files, include_, exclude, block = *args
        
        @files   = files    || []
        @include = include_
        @exclude = exclude
      end
      
      @block = block || proc { false }
    end
    
    ##
    # Is +file+ an exact match?
    # 
    # @param [String] file the file to test
    # @return [Boolean] is it an exact match?
    def exact?(file)
      @files.include?(file)
    end
    
    ##
    # Is this +file+ being excluded? Does it automatically
    # fail?
    # 
    # @param [String] file the file to test
    # @return [Boolean] is it a failure match?
    def failure?(file)
      @exclude && @exclude.any? {|r| file =~ r}
    end
    
    ##
    # Is it an exact match or an approximate match and not
    # a file to be excluded?
    # 
    # If a file is to be both included and excluded, all
    # hell is let loose. You have been warned.
    # 
    # @param [String] file the file to test
    # @return [Boolean] does it pass?
    def call(file)
      if exact? file and failure? file
        raise StandardError.new("File #{file.inspect} is to be both included and excluded")
      end
      # `and` because it's loosely binding
      exact?(file) || included?(file) || approximate?(file) and !failure?(file)
    end
    alias_method :[], :call
    
    ##
    # Is it to be included?
    # 
    # @param [String] file the file to test
    # @return [Boolean] is it to be included?
    def included?(file)
      @include && @include.any? {|r| file =~ r}
    end
    
    ##
    # Is it an approximate match?
    # 
    # @param [String] file the file to test
    # @return [Boolean] is it an approximate match?
    def approximate?(file)
      return false if exact? file
      return false if (@include.nil? && @block.nil?)
      included?(file) || (@block && @block.call(file))
    end
    
  end
end