command :config do |c|
  c.workflow :all
  c.desc "Configure amp interactively."
  c.help <<-HELP
amp config

enter an interactive configuration program to adjust Amp's settings
This command:
    
    * Allows the user to adjust Amp's settings without knowledge of
      how these settings are stored, knowing obscure invisible files
      and their formats
      
    * Does not require that the user call it from within an amp repo-
      sitory, as long as only global settings are changed.
    
HELP
  c.maybe_repo
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    Amp::UI.say "Welcome to the Amp configuration editor. Pull up a seat!"
    while true
      choice = nil
      Amp::UI.choose do |menu|
        menu.prompt = "Would you like to work with local settings (repo-specific), or global ones?"
        menu.choice("Local Settings")  { choice = :local  }
        menu.choice("Global Settings") { choice = :global }
        menu.choice("Exit")            { exit(0) }
      end
      
      case choice
      when :local
        config = opts[:global_config]
      when :global
        config = opts[:global_config]
        while config.parent_config
          config = config.parent_config
        end
      end
      
      choice = nil
      Amp::UI.choose do |menu|
        menu.prompt = "Would you like to view your configuration, or change settings?"
        menu.choice("View Configuration") { choice = :view }
        menu.choice("Change Settings")    { choice = :edit }
        menu.choice("Remove Setting")     { choice = :remove }
        menu.choice("Exit")               { }
      end
      
      all_sections = config.config.sections.keys.map {|n| "[#{n}]"}.join(" ")
      
      case choice
      when :view
        Amp::UI.say config.to_s
      when :edit
        section = Amp::UI.ask("Which section of settings would you like to edit? You may choose "+
                              "an existing section, or create a new one.\nCurrent sections:\n"+
                              all_sections+"\n> ")
        key = Amp::UI.ask("Which setting would you like to change? You may choose an existing "+
                          "setting, or create a new one.\n Current settings: "+
                          config[section].keys.map {|n| "#{n}"}.join(" ")+"\n> ")
        value = Amp::UI.ask("What would you like to set [#{section}:#{key}] to? ")
        config[section,key] = value
        config.save!
      when :remove
        section = Amp::UI.ask("Which section of settings would you like to edit? You may choose "+
                              "an existing section.\nCurrent sections:\n"+
                              all_sections+"\n> ")
        key = Amp::UI.ask("Which setting would you like to change? You may choose an existing "+
                          "setting.\n Current settings: ["+
                          config[section].keys.map {|n| "#{n}"}.join(" ")+"]\n> ")
        config[section].delete key
        config.save!
      end
    end
  end
end

namespace :config do
  command :set do |c|
    c.workflow :all
    c.maybe_repo
    c.opt :global, "Sets the value to the global configuration file", :short => "-g"
    c.desc "Sets a configuration value in Amp's settings"
    c.before do |opts, args|
      if args.size < 2 || args.size > 3 || (args.size == 2 && args.first !~ /\:/)
        puts "Usage:      amp config:set setting-section:setting-name new-setting-value"
        puts "Alt. Usage: amp config:set setting-section setting-name new-setting-value"
        puts
        c.break
      end
      true
    end
    c.on_run do |opts, args|
      config = opts[:global_config]
      if opts[:global]
        while config.parent_config
          config = config.parent_config
        end
      end
      if args.size == 2
        section, key = args.first.split(":")
        value = args[1]
      else
        section, key, value = *args
      end
      
      config[section][key] = value
      config.save!
    end
  end
  command :get do |c|
    c.workflow :all
    c.maybe_repo
    c.opt :global, "Gets the value from the global configuration file", :short => "-g"
    c.desc "Gets a configuration value in Amp's settings"
    c.before do |opts, args|
      if args.size < 1 || args.size > 2 || (args.size == 1 && args.first !~ /\:/)
        puts "Usage:      amp config:get setting-section:setting-name"
        puts "Alt. Usage: amp config:set setting-section setting-name"
        puts
        c.break
      end
      true
    end
    c.on_run do |opts, args|
      config = opts[:global_config]
      if opts[:global]
        while config.parent_config
          config = config.parent_config
        end
      end
      if args.size == 1
        section, key = args.first.split(":")
      else
        section, key = *args
      end
      
      Amp::UI.say config[section][key]
    end
  end
end
