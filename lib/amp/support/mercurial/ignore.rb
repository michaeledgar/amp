##################################################################
#                  Licensing Information                         #
#                                                                #
#  The following code is licensed, as standalone code, under     #
#  the Ruby License, unless otherwise directed within the code.  #
#                                                                #
#  For information on the license of this code when distributed  #
#  with and used in conjunction with the other modules in the    #
#  Amp project, please see the root-level LICENSE file.          #
#                                                                #
#  © Michael J. Edgar and Ari Brown, 2009-2010                   #
#                                                                #
##################################################################

module Amp
  module Mercurial
    module Ignore
      extend self
      
      COMMENT = /((^|[^\\])(\\\\)*)#.*/
      SYNTAXES = {'re'      => :regexp,  'regexp' => :regexp, 'glob' => :glob,
                  'relglob' => :relglob, 'relre'  => :regexp, 'path' => :glob,
                  'relpath' => :relglob}
      
      ##
      # Parses the ignore file, +file+ (or ".hgignore")
      # 
      # @param [String] root the root of the repo
      # @param [Array<String>] files absolute paths to files
      def parse_ignore(root, files=[])
        real_files   = files.select {|f| File.exist? File.join(root, f) }
        all_patterns = real_files.inject [] do |collection, file|  
          text = File.read File.join(root, file)
          collection.concat matcher_for_text(text) # i know this is evil
        end # real_files.inject
        
        # here's the proc to do the tests
        regexps_to_proc all_patterns
      end
      
      ##
      # Parse the lines into valid syntax. Removes empty lines.
      # 
      # @param [String] file and open file
      def parse_lines(text)
        lines = text.split("\n").inject [] do |lines, line|
          line = strip_comment line
          line.rstrip!
          line.empty? ? lines : lines << line # I KNOW THIS IS EVIL
        end
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
      # @return [Array<Regexp>] the regexps generated from the strings and syntaxes
      def matcher_for_text(text)
        return [] unless text
        syntax   = nil
        lines    = parse_lines(text).reject {|line| line.empty? }
        
        # take the lines and create a new array of the patterns
        lines.inject [] do |lines, line|
          # check for syntax changes
          if line.start_with? "syntax:"
            syntax = SYNTAXES[line[7..-1].strip] || :regexp
            lines # move on
          else
            # I KNOW THIS IS EVIL
            lines << parse_line(syntax, line) # could be nil, so we need to compact it
          end
        end # lines.inject
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
          include_syntax = :regexp      # just a line, no specified syntax
          include_regexp = string       # no syntax, thus whole thing is pattern
        else
          include_syntax = $1.to_sym    # the syntax is the first match
          include_regexp = $2.strip     # the rest of the string is the pattern
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
          # relglob: glob, except we just match somewhere in the string, not
          # from the root of the repository
          ps = line.split '/**/'
          ps.map! do |l|
            parts = l.split '*' # split it up and we'll escape all the parts
            parts.map! {|p| Regexp.escape p }
            parts.join '[^/]*' # anything but a slash, ie, no change in directories
          end
          joined = ps.join '/(?:.*/)*'
          pattern = syntax == :glob ? /^#{joined}/ : /#{joined}/
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
        # flatten: because if you pass in an array vs. three single args
        # compact: because #parse_line can return nil (and it will travel to here)
        regexps = regexps.flatten.compact
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