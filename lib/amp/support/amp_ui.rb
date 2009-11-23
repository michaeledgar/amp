require 'singleton'
require 'tempfile'

module Amp
  ##
  # Represents an extremely simple menu that the UI can use to ask for input.
  # Replacement for Highline's "choose" method - and is extremely, extremely basic.
  # In fact, I might strip out some flexibility for now. I just did. It only does
  # numbered lists with no intelligently figuring things out.
  class UIMenu
    # The prompt to ask at the top of the menu
    attr_accessor :prompt
    # How to index results - left in for compatibility and possibly future flexibility
    attr_accessor :index
    
    ##
    # Creates a new UIMenu. Initializes ivars. Does nothing else of use.
    #
    # @return [UIMenu] the new menu
    def initialize
      @choices = []
      @prompt = "Pick an option, please."
      @index = :number
    end
    
    ##
    # Adds a choice to the list of choices to be presented to the user.
    # Choices are ordered in the order in which this method is called.
    # The block is stored and executed if the choice is selected.
    #
    # @param [String] prompt the prompt to display to the user for this
    #   choice
    # @param [Hash] opts options for this choice (unused for now)
    # @param [Proc] &block a block that will be executed later if the choice
    #   is selected
    def choice(prompt, opts={}, &block)
      @choices << {:text => prompt, :action => block}
    end
    
    ##
    # Runs the UIMenu. Will loop until an acceptable choice is selected
    # by the user. Prints the choices in the order in which they were added,
    # in a numbered list. The user must select the number of their desired
    # option. After an acceptable choice is selected, its associated block
    # is executed.
    def run
      input = -1
      while input <= 0 || input > @choices.size do
        UI.say @prompt
        @choices.each_with_index {|item, idx| UI::say "#{idx+1} #{item[:text]}"}
        UI::say
        UI::tell "Your choice: "
        UI::say "[1-#{@choices.size}]"
        input = UI::ask('', Integer)
      end
      choice = @choices[input - 1]
      choice[:action].call
    end
  end
  
  module UI
    extend self
    extend Amp::Merges::MergeUI
    
    class << self
      attr_accessor :config
    end
    ##
    # Prints a warning. Can be disabled using configuration files. These are
    # informational in nature but imply the user did something wrong, or
    # that something is impossible.
    #
    # @param [#to_s] warning the warning to print to standard output
    def warn(warning)
      if !@config || @config["ui","amp-show-warnings",Boolean,true]
        err "warning: #{warning}"
      end
    end
    
    ##
    # Produces a menu for the user. Home-rolled to avoid rubygems dependencies!
    # 
    # @yield yields the menu object, which is configured inside the block, and then
    #   the menu is run
    # @yieldparam menu the menu object. Should be configured inside the given block.
    def choose
      menu = UIMenu.new
      yield menu
      menu.run
    end
    
    ##
    # Gets the user's password, while hiding it from prying eyes.
    # 
    # REQUIRES `stty`
    #
    # @return [String] the user's password.
    def get_pass
      system "stty -echo"
      pass = gets.chomp
      tell "\n"
      system "stty echo"
      pass
    end
    
    ##
    # Prints a status update. Can be disabled using configuration files.
    # These are casual updates to let the user know the progress in an
    # operation.
    # 
    # @param [#to_s] update the message to print to standard output
    # @return [NilClass]
    def status(update='')
      return unless $display
      if !@config || @config["ui", "amp-show-status", Boolean, true]
        say "status: #{update}"
      end
    end
    
    ##
    # Notes the message - ignored unless in debug mode
    #
    # @param [#to_s] note the note to print to standard output
    # @return [NilClass]
    def note(note='')
      return unless $display
      if !@config || @config["ui", "amp-show-notes", Boolean, false]
        say "note: #{note}"
      end
    end
    
    ##
    # Prints +message+ to standard out with a trailing newline
    #
    # @param [#to_s] message the message to be printed.
    # @return [NilClass]
    def say(message='')
      tell "#{message.to_s}\n"
    end
    
    ##
    # Prints +message+ to standard out without a trailing newline.
    #
    # @param [#to_s] message the message to be printed.
    # @return [NilClass]
    def tell(message='')
      $stdout.print message.to_s
    end
    
    ##
    # Prints +message+ to standard error.
    #
    # @param [#to_s] message the message to be errored.
    # @return [NilClass]
    def err(message='')
      $stderr.puts message.to_s
    end
    
    ##
    # Ask +question+ and return the answer, chomped
    # 
    # @param [#to_s] question question to ask
    # @param [Class, #to_s, Symbol] type the type to cast the answer to
    # @return [String] their response without trailing newline
    def ask(question='', type=String)
      type = type.to_s.downcase.to_sym
      
      print question.to_s
      result = gets.chomp unless type == :password
      
      # type conversion
      case type
      when :string
        result
      when :integer, :fixnum, :bignum, :numeric
        result.to_i
      when :array
        result.split(',').map {|e| e.strip }
      when :password
        get_pass
      else
        raise abort("Don't know how to convert to type #{type}")
      end
    end
    
    ##
    # Ask a yes or no question (accepts a variety of inputs)
    # 
    # @param [#to_s] question question to ask
    # @return [Boolean] their agreement
    def yes_or_no(question='')
      result = ask(question.to_s + ' [y/n/r/h] ')
      case result.downcase[0, 1]
      when 'r'
        yes_or_no question # recurse
      when 'h'
        tell <<-EOS
[y/n/r/h] means you can type anything starting with a 'y', 'n', 'r', or an 'h' to select those options.

'y'\tyes
'n'\tno
'r'\trepeat
'h'\thelp
EOS
        yes_or_no question
      else
        result.downcase.start_with? 'y'
      end
    end
    alias_method :agree, :yes_or_no
    
    ##
    # Opens the user's editor for the file at the given path, with no extra
    # processing afterward.
    #
    # @param [String, #inspect] path The path to locate the file to open.
    # @return [Boolean] whether or not the editor successfully launched
    def edit_file(path)
      editor = get_editor
      system "#{editor} #{path.inspect}"
    end
    
    ##
    # Prints this message, only if the debug flag is set.
    #
    # @param [String, #to_s] message The debug message to be printed
    def debug(message='')
      if @config && @config["debug","messages", Boolean, false]
        say message
      end
    end
    
    ##
    # Opens the editor for editing. Uses a temporary file to capture the
    # user's input. The user must have either HGEDITOR, AMPEDITOR, VISUAL,
    # EDITOR, or the configuration "ui"->"editor" set. Or, it'll just use
    # vi.
    #
    # @param [String] text the text with which to fill the file
    # @param [String] username the username to set the ENV var as
    # @return [String] the file after being edited
    def edit(text="", username="")
      tempfile = Tempfile.new("amp-editor-")
      path = tempfile.path
      tempfile.write text
      tempfile.close
      
      ENV["AMPUSER"] = username
      edit_file path
      
      text = File.open(path) {|tf| tf.read } || ''
      
      FileUtils.safe_unlink path
      
      text.gsub!(/^AMP:.*\n/,"")
      text
    end
    
    ##
    # Asks the user something.
    # 
    # @deprecated
    # @param [#to_s] message the message to send
    # @param [Class, lambda] type anything to force a type. If you supply
    #   a class, then the answer will be parsed into that class. If you
    #   supply a lambda, the string will be provided, and you do the conversion
    # @param [] default Whatever the default answer is, if they fail to provide
    #   a valid answer.
    # @return [String] their response with whitespace removed, or the default value
    def prompt(message='', type=String, default=nil)
      say message.to_s
      response = STDIN.gets.strip
      response = default if response == ""
      return response
    end
      
    ##
    # Gets the editor for the current system using environment variables or 
    # the configuration files.
    #
    # @return [String] the name of the editor command to execute
    def get_editor
      return ENV["AMPEDITOR"] || ENV["HGEDITOR"] || (@config && @config["ui","editor"]) ||
             ENV["VISUAL"] || ENV["EDITOR"] || "vi"
    end
  end
end