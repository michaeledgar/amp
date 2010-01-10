command :help do |c|
  c.workflow :all
  c.desc "Prints the help for the program."
  
  c.on_run do |options, args|
    output = ""
    
    cmd_name = args.empty? ? "__default__" : args.first
    Amp::Help::HelpUI.print_entry(cmd_name, options)
  end
end