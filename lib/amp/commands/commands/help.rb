command :help do |c|
  c.workflow :all
  c.desc "Prints the help for the program."
  
  c.on_run do |options, args|
    output = ""
    
    if args.empty?
      output << "These are the following commands available:\n"
      
      Amp::Command.all_for_workflow(options[:global_config]["amp", "workflow"], false).sort {|k1, k2| k1.to_s <=> k2.to_s}.each do |k, v| 
        output << "\t#{k.to_s.ljust(30, " ")}#{v.desc}" + "\n"
      end
      
      output << 'Run "amp help [command]" for more information.'
      
      Amp::UI.say output
    else
      
      unless cmd = Amp::Command.all_for_workflow(options[:global_config]["amp","workflow"])[args.first.to_sym]
        Amp::UI.say "The command #{args.first} was not found."
      else
        cmd.collect_options
        cmd.educate
      end
      
    end
  end
end