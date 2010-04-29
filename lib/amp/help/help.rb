module Amp
  ##
  # The module covering all the help subsystems for the Amp binary.
  module Help
    
    ##
    # Module handling the registration and retrieval of entries in the
    # help system.
    #
    # This is a singleton module. Don't mix it in anywhere. That'd be silly.
    module HelpRegistry
      extend self
      
      ##
      # Retrives the entries hash which stores all the help entrys
      #
      # @return [Hash<String => Array<HelpEntry>>] the entry table for the help system
      def entries
        @entries ||= ArrayHash.new
      end
      
      ##
      # Returns a list of HelpEntrys with the given name. Since we allow for
      # the possibility of overlap by name, this returns an array.
      #
      # @param [String, #to_s] entry the name of the entry(ies) to retrieve
      # @return [Array<HelpEntry>] the help entries stored under the given name
      def [](entry)
        entries[entry]
      end
      
      ##
      # Adds an entry to the registry. We take a name and an entry, and store
      # the entry under the list of entries with the given name.
      #
      # @param [String, #to_s] name the name of the help entry. Allowed to
      #   conflict with other entries.
      # @param [HelpEntry] entry the entry to store in the registry
      def register(name, entry)
        entries[name] << entry
      end
      
      ##
      # Unregisters the given entry from the registry. Not sure why you might
      # use this, but it's a capability.
      #
      # @param [String, #to_s] name the name of the entry. Note - you will also
      #   need to provide the entry, because there might be naming conflicts.
      # @param [HelpEntry] entry the entry to remove from the registry.
      def unregister(name, entry)
        entries[name].delete entry
      end
    end
    
    ##
    # The generic HelpEntry class encapsulates a entry in the help system. The
    # entry has text that it provides to the user, as well as a name. The base
    # HelpEntry class does not track its own name, because well, that's not
    # useful! All it needs to know how to do is present its text when asked for it.
    class HelpEntry
      class << self
        ##
        # Singleton method that opens a file and returns a HelpEntry representing it.
        # What makes this method spiffy is that it tries to detect the type of file
        # -- markdown, ERb, et cetera, based on the file's extension, and picks
        # the appropriate class to represent that help entry.
        #
        # The entry is registered under the name of the file - without any extensions -
        # and the file's full contents are provided as the initial text.
        #
        # @param [String] filename the path to the file to load
        # @return [HelpEntry] a help entry representing the file as best as we can.
        def from_file(filename)
          klass = case File.extname(filename).downcase
                  when ".md", ".markdown"
                    MarkdownHelpEntry
                  when ".erb"
                    ErbHelpEntry
                  else
                    HelpEntry
                  end
          without_entry_dir = File.expand_path(File.join(File.dirname(__FILE__), "entries"))
          name = filename[without_entry_dir.size+1..-1].gsub(/\//,":")
          klass.new(name.split(".", 2).first, File.read(filename))
        end
      end
      
      ##
      # Creates a new HelpEntry, and registers it in the Help system, making it
      # immediately available. It is for this reason that all subclasses should
      # call +super+, because that registration is important!
      #
      # @param [String, #to_s] name the name under which to register this help entry
      # @param [String] text ("") the text for the entry.
      def initialize(name, text = "")
        @text = text
        HelpRegistry.register(name, self)
      end
      
      ##
      # Returns the help text to display for this entry.
      #
      # In the generic case, just return the @text variable.
      #
      # @param [Hash] options the options for the process - that way the help commands
      #   can access the user's run-time options and global configuration. For example,
      #   if the user passes in --verbose or --quiet, each help entry could handle that
      #   differently. Who are we to judge?
      # @return [String] the help text for the entry.
      def text(options = {})
        @text
      end
      
      ##
      # Describes the entry briefly, so if the user must pick, they have a decent
      # shot at knowing what this entry is about. Hopefully.
      #
      # In the generic case, use the text and grab the first few words.
      #
      # @return a description of the entry based on its content
      def desc
        %Q{a regular help entry ("#{text.split[0..5].join(" ")} ...")}
      end
    end
    
    ##
    # Represents a help entry that filters its help text through a Markdown parser
    # before returning.
    #
    # This makes it very easy to make very pretty help files, that are smart enough
    # to look good in both HTML form and when printed to a terminal. This uses our
    # additions to the markdown parser to provide an "ANSI" output format.
    class MarkdownHelpEntry < HelpEntry
      ##
      # Returns the help text to display for this entry.
      #
      # For a markdown entry, we run this through Maruku and our special to_ansi
      # output formatter. This will make things like *this* underlined and **these**
      # bolded. Code blocks will be given a colored background, and headings are
      # accentuated.
      #
      # @param [Hash] options the options for the process - that way the help commands
      #   can access the user's run-time options and global configuration. For example,
      #   if the user passes in --verbose or --quiet, each help entry could handle that
      #   differently. Who are we to judge?
      # @return [String] the help text for the entry.
      def text(options = {})
        Maruku.new(super, {}).to_ansi
      end
    end 
    
    ##
    # Represents a help entry that filters its help text through ERB before returning.
    #
    # This is useful because some entries might have programmatic logic to them - 
    # for example, the built in "commands" entry lists all the commands in the
    # user's current workflow. That requires logic, and while we used to simply
    # have that be its own class, we can now stuff it in an ERB file.
    #
    # Note: if you want to use pretty text in an ERB entry, you will have to use
    # ruby code to do so. Use the following shortcuts:
    #
    #     <%= "Ampfiles".bold.underline %> # bolds and underlines
    #     <%= "some.code()".black.on_green %> # changes to black and sets green bg color
    #
    # See our extensions to the String class for more.
    class ErbHelpEntry < HelpEntry
      
      ##
      # Returns the help text to display for this entry.
      #
      # For an ERB entry, we run ERB on the text in the entry, while also exposing the
      # options variable as local, so the ERB can access the user's runtime options.
      #
      # @param [Hash] options the options for the process - that way the help commands
      #   can access the user's run-time options and global configuration. For example,
      #   if the user passes in --verbose or --quiet, each help entry could handle that
      #   differently. Who are we to judge?
      # @return [String] the help text for the entry.
      def text(options = {})
        full_text = super(options)
        
        erb = ERB.new(full_text, 0, "-")
        erb.result binding
      end
    end
    
    ##
    # Represents a command's help entry. All commands have one of these, and in fact,
    # when the command is created, it creates a help entry to go with it.
    #
    # Commands are actually quite complicated, and themselves know how to educate
    # users about their use, so we have surprisingly little logic in this class.
    class CommandHelpEntry < HelpEntry      
      
      ##
      # Creates a new command help entry. Differing arguments, because instead of
      # text, we need the command itself. One might think: why not just pass in
      # the command's help information instead? If you have a command object, you
      # have command.help, no? Well, the reason is two-fold: the help information
      # might be updated later, and there is more to printing a command's help entry
      # than just the command.help() method.
      #
      # @param [String] name the name of the command
      # @param [Amp::Command] command the command being represented.
      def initialize(name, command)
        super(name)
        @command = command
      end
      
      ##
      # Returns the help text to display for this entry.
      #
      # For a command-based entry, simply run its educate method, since commands know
      # how to present their help information.
      #
      # @param [Hash] options the options for the process - that way the help commands
      #   can access the user's run-time options and global configuration. For example,
      #   if the user passes in --verbose or --quiet, each help entry could handle that
      #   differently. Who are we to judge?
      # @return [String] the help text for the entry.
      def text(options = {})
        @command.collect_options
        @command.educate
        ""
      end
      
      ##
      # Describes the entry briefly, so if the user must pick, they have a decent
      # shot at knowing what this entry is about. Hopefully.
      #
      # In the case of a command, grab the command's "desc" information.
      #
      # @return a description of the entry based on its content
      def desc
        %Q{a command help entry ("#{@command.desc}")}
      end
    end
    
    ##
    # The really public-facing part of the Help system - the Help's UI.
    # This lets the outside world get at entries based on their names.
    module HelpUI
      extend self
      
      ##
      # Asks the UI system to print the entry with the given name, with the
      # process's current options.
      #
      # This method is "smart" - it has to check to see what entries are
      # available. If there's more than one with the provided name, it 
      # helps the user pick the appropriate entry.
      #
      # @param [String] name the name of the entry to print
      # @param [Hash] options the process's options
      def print_entry(name, options = {})
        result = HelpRegistry[name.to_s]
        case result.size
        when 0
          raise abort("Could not find help entry \"#{name}\"")
        when 1
          puts result.first.text(options)
        when 2
          UI.choose do |menu|
            result.each do |entry|
              menu.choice("#{name} - #{entry.desc}") { puts entry.text(options) }
            end
          end
        end
      end
    end
    
    ##
    # A method that loads in the default entries for the help system.
    # Normally, I'd just put this code in the module itself, or perhaps
    # at the end of the file, but I'm experimenting with an approach
    # where I try to minimize the bare code, leaving only the invocation
    # of this method to sit in the module.
    def self.load_default_entries
      Dir[File.join(File.dirname(__FILE__), "entries", "**")].each do |file|
        HelpEntry.from_file(file)
      end
    end
    
    # Load the default entries.
    self.load_default_entries
  end
end