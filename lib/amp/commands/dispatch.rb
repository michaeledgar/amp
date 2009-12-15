require 'abbrev'
require       "amp/commands/command.rb"
require_dir { "commands/*.rb"              }
require_dir { "commands/commands/*.rb"     }

module Amp
  
  ##
  # = Dispatch
  # This class handles parsing command-line options, finding commands, and running them.
  class Dispatch
    
    ##
    # This method essentially runs the amp executable. It first parses global options (--config)
    # finds the subcommand (eg add, init, clone), parses the subcommand's options, merges the
    # two, and then runs the entire thing.
    def self.run
      # Get the subcommands so we can stop on them
      sub_commands = Amp::Command.all_commands.keys
      # Get the global options (everything before the subcommand)
      global_opts = Trollop::options do
        banner "Amp - some more crystal, sir?"
        version "Amp version #{Amp::VERSION} (#{Amp::VERSION_TITLE})"
        opt :debug_opts,      "Debug the command-line options", :short => "-d", :default => false, :type => :boolean
        opt :verbose,         "Verbose output"
        opt :profile,         "Profile the command being run, running it the given number of times"
        opt :repository,      "The path to the repository to use", :short => "-R", :type => :string, :default => Dir.pwd
        opt :"pure-ruby",     "Use only pure ruby (no C-extensions)"
        opt :testing,         "Running a test. Not for users to use"
        stop_on_unknown
      end
      global_opts = global_opts.first # we don't need the parser here
      
      # This loads the built-in ruby profiler - it's extremely slow. Use with care.
      if global_opts[:profile]
        require 'profile'
      end
      
      # Never load a C extension if we're in pure-ruby mode.
      if global_opts[:"pure-ruby"]
        $USE_RUBY = true
      end
      
      global_config  = Amp::AmpConfig.new
      Amp::UI.config = global_config
      cmd            = ARGV.shift || "default" # get the subcommand
      opts_as_arr    = ARGV.dup
      
      if global_opts[:debug_opts]
        global_config["debug", "messages"] = true
      end
      
      # the options to send to the command
      cmd_opts = {}
      
      # Load the repository
      #path_to_repo = find_repo(".", cmd_opts) unless global_opts[:repository]
      path_to_repo = ""
      
      if path_to_repo.empty?
        local_config = global_config
      else
        local_config = AmpConfig.new(:parent_config => global_config)
        local_config.read_file File.join(path_to_repo, ".hg", "hgrc")
      end
      
      begin
        cmd_opts[:repository] = Repositories.pick(local_config, global_opts[:repository])
      rescue
        unless Command::NO_REPO_ALLOWED[cmd.to_sym] || Command::MAYBE_REPO_ALLOWED[cmd.to_sym]
          raise
        end
      end
      
      if cmd_opts[:repository].respond_to? :config
        cmd_opts[:repository].config && local_config = cmd_opts[:repository].config
      end
      
      workflow = local_config["amp"]["workflow", Symbol, :hg]
      
      if File.exists?(File.expand_path(File.join(File.dirname(__FILE__), "commands/workflows/#{workflow}/")))
        require_dir { "amp/commands/commands/workflows/#{workflow}/**/*.rb" }
      end
      
      user_amprc = File.expand_path("~/.amprc")
      File.exist?(user_amprc) && load(user_amprc)  

      path_to_ampfile = find_ampfile
      load path_to_ampfile if path_to_ampfile
      
      command = pick_command cmd, local_config
      
      unless command
        puts "Invalid command! #{cmd}"
        exit(-1)
      end
      
      # get the sub-command's options
      # if there's a conflict, check to see that the newest value isn't nil
      cmd_opts.merge!(command.collect_options) {|k, v1, v2| v2 || v1 }
      
      cmd_opts[:global_config] = local_config
      if global_opts[:debug_opts]
        require 'yaml'
        puts "Current directory: #{Dir.pwd}"
        puts "Global options: \n#{global_opts.inspect.to_yaml}"
        puts "Subcommand: #{cmd.inspect}"
        puts "Subcommand options: \n#{cmd_opts.to_yaml}"
        puts "Remaining arguments: #{ARGV.inspect}"
        puts "\n"
        puts "Parsed and merged global config files:"
        puts local_config.config.to_s
        puts
      end
      
      # Run that fucker!!!
      begin
        full_backtrace_please do
          command.run cmd_opts, ARGV
        end
      rescue AbortError => e
        puts e.to_s
      end
    end
    
    ##
    # Gets the path to the Ampfile if there is one.
    #
    # @return [String] the path to an Ampfile
    def self.find_ampfile(dir=Dir.pwd)
      rock_bottom = false
      begin
        rock_bottom = true if dir == "/" 
        ["ampfile", "Ampfile", "ampfile.rb", "Ampfile.rb"].each do |pos|
          file = File.join(dir, pos)
          return file if File.exist? file
        end
        dir = File.dirname(dir)
      end until rock_bottom
    end
    
    ##
    # Picks a command from the list of all possible commands, based on a couple
    # simple rules.
    #
    # 1. Look up the command by exact name. If no command is provided, supply "default".
    # 2. Check for "synonyms" - "remove" is synonym'd as "rm". This check occurs inside
    #   the call to Amp::Command[].
    # 3. Check to see if there is only 1 command with our "cmd" as the prefix. For example,
    #   if the user inputs "amp stat", and only one command starts with "stat" (ie "status"),
    #   then return that command. If there is more than 1 match, then exit, showing an error
    #   due to the ambiguity.
    #
    # @param [String] cmd the command to look up
    # @return [Amp::Command] the command object that was found, or nil if none was found.
    def self.pick_command(cmd, config)  
      my_flow = config["amp"]["workflow", Symbol, :hg]
      if c = Amp::Command.all_for_workflow(my_flow).keys.map {|k| k.to_s}.abbrev[cmd]
        Amp::Command.command_for_workflow(c, my_flow)
      else
        prefix_list = Amp::Command.all_for_workflow(my_flow).keys.map {|k| k.to_s}.select {|k| k.start_with? cmd.to_s }
        
        if prefix_list.size > 1
          puts "Ambiguous command: #{cmd}. Could mean: #{prefix_list.join(", ")}"
          exit(-1)
        end
        nil
      end
    end

  end
end
