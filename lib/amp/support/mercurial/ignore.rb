module Amp
  module Mercurial
    module Ignore
      extend self
      
      COMMENT = /((^|[^\\])(\\\\)*)#.*/
      SYNTAXES = {'re' => :regexp, 'regexp' => :regexp, 'glob' => :glob,
                  'relglob' => :relglob, 'relre' => :regexp, 'path' => :glob,
                  'relpath' => :relglob}
      ##
      # Parses the ignore file, +file+ (or ".hgignore")
      # 
      # @param [String] root the root of the repo
      # @param [Array<String>] files absolute paths to files
      def parse_ignore(root, files=[])
        all_patterns = files.select {|file| File.exist?(File.join(root, file))}.map do |file|
          text = File.read File.join(root,file)
          matcher_for_text text
        end # files.map
        
        # here's the proc to do the tests
        regexps_to_proc all_patterns.compact.flatten
      end
      
      ##
      # Parse the lines into valid syntax. Removes empty lines.
      # 
      # @param [String] file and open file
      def parse_lines(text)
        lines = text.split("\n").map do |line|
          line = strip_comment line
          line.rstrip!
          line.empty? ? nil : line
        end
        lines.compact
      end
      
      ##
      # Strips comments from a line of text
      #
      # @param [String] line the line of text to de-commentify
      # @return [String] the same line of text, with comments removed.
      def strip_comment(line)
        if line =~ /#/
          line.sub! COMMENT, "\\1"
          line.gsub! "\\#", "#"
        end
        line
      end
      
      ##
      # Produces an array of regexps which can be used
      # for matching files
      # 
      # @param [String] text the text to parse
      # @return [[Regexp]] the regexps generated from the strings and syntaxes
      def matcher_for_text(text)
        return [] unless text
        syntax = nil
        patterns = parse_lines(text).select {|line| !line.empty?}.map do |line|
          # check for syntax changes
          if line.start_with? "syntax:"
            syntax = SYNTAXES[line[7..-1].strip] || :regexp
            next # move on
          end
          parse_line syntax, line # could be nil, so we need to compact it
        end # parsed_lines(text)
        patterns.compact # kill the nils
      end
      
      ##
      # Much like matcher_for_text, except tailored to single line strings
      # 
      # @see matcher_for_text
      # @param [String] string the string to parse
      # @return [Regexp] the regexps generated from the strings and syntaxes
      def matcher_for_string(string)
        scanpt = string =~ /(\w+):(.+)/
        if scanpt.nil?
          # just a line, no specified syntax
          include_syntax = :regexp
          # no syntax, the whole thing is a pattern
          include_regexp = string   
        else
          include_syntax = $1.to_sym        # the syntax is the first match
          include_regexp = $2.strip # the rest of the string is the pattern
        end
        parse_line include_syntax, include_regexp
      end
      
      ##
      # Turns a single line, given a syntax, into either
      # a valid regexp or nil. If it is nil, it means the
      # syntax was incorrect.
      # 
      # @param [Symbol] syntax the syntax to parse with (:regexp, :glob, :relglob)
      # @param [String] line the line to parse
      # @return [NilClass, Regexp] nil means the syntax was a bad choice
      def parse_line(syntax, line)
        return nil unless syntax
        syntax = syntax.to_sym
        # find more valid syntax stuff
        # we need to make everything here valid regexps
        case syntax
        when :regexp
          # basic regex
          pattern = /#{line}/
        when :glob, :relglob
          # glob: glob (shell style), relative to the root of the repository
          # relglob: glob, except we just match somewhere in the string, not from the root of
          # the repository
          ps = line.split '/**/'
          ps.map! do |l|
            parts = l.split '*' # split it up and we'll escape all the parts
            parts.map! {|p| Regexp.escape p }
            parts.join '[^/]*' # anything but a slash, ie, no change in directories
          end
          joined = ps.join '/(?:.*/)*'
          pattern = (syntax == :glob) ? /^#{joined}/ : /#{joined}/
        else
          pattern = nil
        end
        
        pattern
      end
      
      ##
      # Converts all the ignored regexps into a proc that matches against all of these
      # regexps. That way we can pass around a single proc that checks if a file is ignored.
      #
      # @param [Array<Regexp>] regexps all of the regexes that we need to match against
      # @return [Proc] a proc that, when called with a file's path, will return whether
      #   it matches any of the regexps.
      def regexps_to_proc(*regexps)
        regexps = regexps.flatten.compact # needed because of possible nils
        if regexps.empty?
          proc { false }
        else
          proc { |file| regexps.any? {|p| file =~ p } }
        end
      end
      alias_method :regexp_to_proc, :regexps_to_proc
      
    end
  end
end