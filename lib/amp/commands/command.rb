require 'amp/commands/command_support.rb'

module Amp
  
  ##
  # Represents a command within the Amp system. Simply instantiating a new
  # command will make it available to the Amp executable. You configure the
  # command by filling out a block in the command's initializer. 
  # @example 
  #   Command.new "add" do |c|
  #     c.workflow :hg
  #     c.opt :include, "Paths to include", 
  #                         :options => {:short => "-I", :multi => true}
  #     c.opt :print_names, :desc => "Print the filenames", 
  #               :options => {:short => "-p"   , 
  #                            :default => false, 
  #                            :type => :boolean}
  #     c.on_run do |options, arguments|
  #       if options[:print_names]
  #         arguments.each do |filename|
  #           puts filename
  #         end
  #       end
  #     end
  #     c.help "This is the help text when the user runs `amp help add`"
  #   end
  #
  class Command
    include CommandSupport
    
    # The current namespace to append to any new commands
    # Not thread-safe at all
    @current_namespaces = []
    
    # All the commands registered in the system
    @all_commands = {}
    
    # Synonyms for commands. Used as a backup.
    @all_synonyms = {}
    
    # Workflows for splitting up commands into groups.
    # The hash will automatically fill slots with empty hashes
    # upon reads if they are empty.
    # 
    # Workflows are doubly linked, in that the cvar +self.class.workflows+ keeps track of
    # what commands belong to it, and the commands themselves keep track of which
    # workflows they belong to.
    @workflows    = Hash.new {|h, k| h[k] = {} }
    
    # These are options that all commands support. Allows the user to put
    # them after the subcommand.
    GLOBAL_OPTIONS = []
    # {:name => :verbose, :desc => "Verbose output", :options => {:short => "-v"}}
    
    class << self
      
      attr_reader :current_namespaces
      
      ##
      # Returns all of the commands registered in the system.
      # 
      # @return [Hash<Symbol => Amp::Command>] the commands, keyed by command name as a string
      attr_reader :all_commands
      
      ##
      # Returns all the synonyms registered in the system.
      #
      # @return [Hash<Symbol => Amp::Command>] the synonyms, keyed by the synonym as a string
      attr_reader :all_synonyms
      attr_reader :workflows
      
      ##
      # Appends the given namespace to the active namespace for new commands.
      #
      # @param [String, #to_s] namespace the new namespace to add
      def use_namespace(namespace)
        current_namespaces.push namespace
      end
      
      ##
      # Removes one namespace from the active namespaces for new commands
      def pop_namespace
        current_namespaces.pop
      end
      
      ##
      # Returns all commands and synonyms registered in the system.
      # The commands are merged into the synonyms so that any synonym with
      # the same name as a command will be overwritten in the hash.
      # 
      # @return [Hash<Symbol => Amp::Command>] the commands and synonyms, 
      #   keyed by command name as a string
      def all
        all_synonyms.merge all_commands
      end
      
      ##
      # Returns all commands and synonyms registered in the system for a
      # given workflow. The ":all" workflow is automatically merged in, as well.
      #
      # @param  [Symbol] workflow the workflow whose commands we need
      # @return [Hash<Symbol => Amp::Command>] the commands and synonyms for the
      #   workflow (and all global commands), keyed by command name as a string
      def all_for_workflow(flow, synonyms=true)
        flow = flow.to_sym
        
        cmds = workflows[flow].merge workflows[:all]
        
        if synonyms
          # because there is no way to view all synonyms with workflow +flow+,
          # we have to work bottom up (hence the doubly linked aspect for commands,
          # which is reduced to singly linked)
          syns = all_synonyms.select {|k, v| v.workflows.include? flow }
          syns = syns.to_hash
        else
          syns = {}
        end
        
        syns.merge cmds
      end
      
      ##
      # Gets a specific command, for a given workflow. This is necessary because it
      # will be expected that 2 different workflows have a command with the same name
      # (such as "move").
      #
      # @param  [String, Symbol] cmd the command to look up
      # @param  [Symbol] the workflow to use for the lookup
      # @return [Amp::Command] the command for the given name and workflow
      def command_for_workflow(cmd, flow)
        all_for_workflow(flow)[cmd.to_sym]
      end
      
      ##
      # Returns all of the commands registered in the system.
      # 
      # @return [Hash<Symbol => Amp::Command>, NilClass] the commands, keyed by
      #   command name as a symbol. returns nil if nothing is found
      def [](arg)
        all[arg.to_sym]
      end
    end

    # Command-specific command-line options
    attr_accessor :options
    # The name of the command (eg 'add', 'init')
    attr_accessor :name
    # Short, 1-line description of the command
    attr_accessor :description
    # The Trollop parser
    attr_accessor :parser
    
    ##
    # Creates a command in the Amp system. Simply instantiating a new
    # command will make it available to the Amp executable. You configure the
    # command by filling out a block in the command's initializer.
    # 
    # @example
    #   Command.new("add") do |c|
    #     c.opt :include, "Paths to include", 
    #               :options => {:short => "-I", :multi => true}
    #     c.opt :print_names, :desc => "Print the filenames", 
    #               :options => {:short => "-p", :default => false, 
    #                            :type => :boolean}
    #     c.on_run do |options, arguments|
    #       puts "silly!"
    #     end
    #   end
    # @param name the name of the command that the user will use to call 
    # the command
    # @param &block a block of code where you can configure the command
    # @yield This block configures the command. Set up options, add an on_run 
    #        handler, and so on.
    # @yieldparam The command itself - it is yielded so you can modify it.
    def initialize(name, require_new = false)
      # so that you can do additions to commands, just like ammending rake tasks
      full_name = (self.class.current_namespaces + [name]).join(":")
      name = full_name.to_sym
      if self.class.all_commands[name]
        yield self.class.all_commands[name] if block_given?
        return self.class.all_commands[name]
      end
      
      @name                = name
      @help                = ""
      @options             = []
      self.class.all_commands[name] = self
      @before = []
      @after  = []

      @workflows = []
      @synonyms  = []
      yield(self) if block_given?
      workflow :all if @workflows.empty?
      @options += GLOBAL_OPTIONS
    end
    
    ##
    # Adds an command-line option to the command.
    # 
    # @param name the name of the command the user will type to run it
    # @param desc the short, one-line description of the command
    # @param options the options that configure the command-line option 
    #                (too meta? sorry!)
    # @option [String] options :short (nil) the short version of the option 
    #                                       (e.g. "-I")
    # @option [String] options :default (nil) the default value of the option.
    # @option [Symbol] options :type (:string) the type of the option. Allows 
    #                                     you to force Integer or URL matches.
    # @option [Boolean] options :multi (false) can this option take multiple 
    #                                          values?
    def opt(name, desc='', options={})
      @options << {:name => name, :desc => desc, :options => options}
    end
    alias_method :add_opt, :opt
    
    ##
    # Override a default value for a command option. Useful for user-provided
    # ampfiles.
    #
    # @example This example will make `amp status` default to mercurial-style
    #  output, instead of amp's colorful, easy-to-read output.
    #     command :status do |c|
    #       default :hg, true
    #       default :"no-color", true
    #     end
    # @param [Symbol, #to_sym] opt the option to modify. Can be symbol or string.
    # @param value the new default value for the option
    def default(opt, value)
      opt = opt.to_sym
      the_opt = @options.select {|o| o[:name] == opt}.first
      if the_opt
        the_opt[:options][:default] = value
      end
    end
    
    ##
    # This method is how you set what the command does when it is run.
    # 
    # @param &block the code to run when the command runs
    # @yield The code to run when the command is executed, after options 
    #        are prepared.
    # @yieldparam options The options that the dispatcher has prepared for 
    #                     the command. Includes global and local.
    # @yieldparam arguments All arguments passed to the command, after 
    #                       the options.
    # @example
    #    Command.new("email_news") do |c|
    #     c.on_run do |options, arguments|
    #       arguments.each do |email_address|
    #         send_some_email(options[:email_subject],email_address)
    #       end
    #     end
    #    end
    def on_run(&block)
      @code = proc(&block) # this way we have the ability to do `return`
    end
    
    ##
    # This method lets you set a synonym (or synonyms) for this command.
    # For example, the "remove" command has the synonym "rm". Example:
    #   command :remove do |c|
    #     c.synonym :rm, :destroy, :nuke
    #   end
    # then you can do
    #   amp nuke badfile.rb
    def synonym(*args)
      args.each do |arg|
        @synonyms << arg
        self.class.all_synonyms[arg.to_sym] = self
      end
    end
    alias_method :synonyms, :synonym
    
    ##
    # Specifies a workflow that may access this command. Workflows are
    # groups of commands, pure and simple. If the user has no specified
    # workflow, the mercurial workflow is used by default.
    def workflow(*args)
      if args.any? # unless args.empty?
        args.each do |arg|
          self.class.workflows[arg][self.name.to_sym] = self # register globally
          @workflows << arg                  # register locally
        end
      else
        @workflows
      end
    end
    alias_method :workflows, :workflow
    
    ##
    # This returns the list of actions to run before the command, in order (first
    # ones are run first). You can modify this array in any way you choose, and
    # it is run _before_ the command is run.
    # 
    # @yield Extra code to run before the command is executed, after options
    #   are prepared.
    # @yieldparam options The options that the dispatcher has prepared 
    #   for the command. Includes global and local.
    # @yieldparam arguments All arguments passed to the command, after the options.
    # @return [Hash] an array of strings and blocks. Strings are assumed to 
    #   be command names and blocks are pieces of code to be run.
    def before(*args, &block)
      args.each do |arg|
        @before << proc {|opts, args| Amp::Command[arg.to_sym].run(opts, args) }
      end
      
      @before << block if block
      @before
    end    
    ##
    # This returns the list of actions to run after the command, in order (first
    # ones are run first). You can modify this array in any way you choose, and
    # it is run _after_ the command is run.
    # 
    # @yield Extra code to run after the command is executed, after options are prepared.
    # @yieldparam options The options that the dispatcher has prepared for the command.
    #   Includes global and local.
    # @yieldparam arguments All arguments passed to the command, after the options.
    # @return [Hash] an array of strings and blocks. Strings are assumed to be command
    #                names and blocks are pieces of code to be run.
    def after(*args, &block)
      args.each do |arg|
        @after << proc {|opts, args| Amp::Command[arg.to_sym].run(opts, args) }
      end
      
      @after << block if block
      @after
    end
    
    ##
    # The one-line description of the command. This is the first line
    # of the help text. If no argument is passed, then the desription
    # is returned. If an argument is passed, it will be set to be the
    # first line of the help text.
    # 
    # @example cmd.desc # => "This command is useless."
    # @param [String, nil] str the help text to set
    def desc(str=nil)
      str ? @help = "#{str}\n\n#{@help}" : @help.split("\n").first
    end
    
    ##
    # Trollop's help info for the command
    def educate
      @parser ? @parser.educate : ''
    end
    alias_method :education, :educate
    
    ##
    # Sets the command to not laod a repository when run. Useful for purely
    # informational commands (such as version) or initializing a new
    # repository.
    def no_repo
      NO_REPO_ALLOWED[@name] = true
    end
    
    # @see no_repo
    def no_repo=(value)
      NO_REPO_ALLOWED[@name] = value
    end
    
    ##
    # Sets the command to not require a repository to run, but try to load one.
    # Used, for example, for the templates command, which sometimes stores
    # information in the local repository.
    def maybe_repo
      MAYBE_REPO_ALLOWED[@name] = true
    end
    
    # @see no_repo
    def maybe_repo=(value)
      MAYBE_REPO_ALLOWED[@name] = value
    end
    
    ##
    # Sets the help text for the command. This can be a very long string,
    # as it is what the user sees when they type `amp help +name+`
    # 
    # @param str the help text to set
    # @example cmd.help %Q{
    #            Big help text!
    #          }
    def help(str=nil)
      str ? @help << str : @help
    end
    
    ##
    # Sets the help text for the command. This can be a very long string,
    # as it is what the user sees when they type `amp help +name+`
    # 
    # @param str the help text to set
    alias :help= :help
    
    ##
    # Parses the commands from the command line using Trollop. You probably
    # shouldn't override this method, but if you have good reason, go for it.
    # 
    # @return [Hash<Symbol => Object>] The parsed command-line options
    def collect_options
      options = @options # hack to get around the fact that
      help    = @help    # Trollop uses instance eval
      
      ret = Trollop::options do
        banner help
        
        # we can't use @options here because Trollop::options uses instance_eval
        # therefore we have to use a local to cheat death^H^H^H^H^Hinstance_eval
        options.each do |option|
          opt option[:name], option[:desc], option[:options]
        end
      end
      
      @parser = ret.pop
      ret.first
    end
    
    def inspect
      "#<Amp::Command #{name}>"
    end
    
    ##
    # Adds a namespace to the name of the command. This extra method is
    # needed because many class variables expect this command based on its name -
    # if we don't update these, then our entire program will expect a
    # command with the old name. Not cool.
    #
    # @param [String] ns the namespace to put in front of the command's name
    def add_namespace(ns)
      to = "#{ns}:#{name}".to_sym
      if self.class.all_commands[name] == self
        self.class.all_commands[to] = self.class.all_commands.delete name
      end
      @workflows.each do |flow|
        if self.class.workflows[flow][name] == self
          self.class.workflows[flow][to] = self.class.workflows[flow].delete name
        end
      end
      @synonyms.each do |syn|
        if self.class.all_synonyms[syn] == self
          self.class.all_synonyms["#{ns}:#{syn}"] = self.class.all_synonyms.delete syn
        end
      end
      @name = to
    end
    
    ##
    # Called by the dispatcher to execute the command. You really don't need to
    # override this. The `$break` global can be set by anything, which
    # will halt the chain.
    # 
    # @param  [Hash<Symbol => Object>] options The global options, merged with the command-specific 
    #                options, as decided by the dispatcher.
    # @param  [Array<String>] arguments The list of arguments, passed after the options. Could 
    #                  be a filename, for example.
    # @return [Amp::Command] the command being run
    def run(options={}, args=[])
      # run the before commands
      @before.each {|cmd| result = cmd.run options, args; return if !result || $break }
      
      @code[options, args] # and of course the actual command...
      
      # top it off with the after commands
      @after.each  {|cmd| result = cmd.run options, args; return if !result || $break }
      
      self
    end
    
    NO_REPO_ALLOWED = {}
    %w(clone init help version debugcomplete debugdata debugindex 
       debugindexdot debugdate debuginstall debugfsinfo).each do |k|
         NO_REPO_ALLOWED[k.to_sym] = true
    end
    
    MAYBE_REPO_ALLOWED = {}
    %w().each do |k|
      MAYBE_REPO_ALLOWED[k.to_sym] = true
    end
    
  end
end

module Amp
  module KernelMethods
    # shortcut
    def command(name, &block)
      Amp::Command.new name, &block
    end
    
    ##
    # Stops the command from running any further - uses the global options.
    def cut!; $break = true; end
    
    # Rake style namespacing
    # After new commands are made, alter their names
    # so that they're "#{namespace}:#{command}"
    # NOTE: THIS IS NOT RAKE-FRIENDLY
    # If you load this into a script with Rake, they will
    # fight to the death and only one will have a proper namespace method!
    def namespace(name)
      # current commands
      Amp::Command.use_namespace name.to_s
      yield
      Amp::Command.pop_namespace
    end
  end
end
