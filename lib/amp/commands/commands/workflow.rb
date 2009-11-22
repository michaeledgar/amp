command :workflow do |c|
  c.workflow :all
  c.maybe_repo
  
  c.desc "Sets the workflow amp uses for commands"
  c.opt :local, "Sets the workflow locally, instead of globally", :short => "-l"
  
  c.before do |opts, args|
    if args.size < 1
      puts "Usage:      amp workflow workflow_name"
      c.break
    end
    
    true
  end
  
  c.on_run do |opts, args|
    config = opts[:global_config]
    unless opts[:local]
      while config.parent_config
        config = config.parent_config
      end
    end
    
    config["amp"]["workflow"] = args.shift
    config.save!
  end
end