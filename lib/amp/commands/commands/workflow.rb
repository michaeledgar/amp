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

command :workflow do |c|
  c.workflow :all
  c.maybe_repo
  
  c.desc "Sets the workflow amp uses for commands"
  c.opt :local, "Sets the workflow locally, instead of globally", :short => "-l"
  
  c.before do |opts, args|
    if args.size < 1
      puts "Usage:      amp workflow workflow_name"
      false
    else
      true
    end
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