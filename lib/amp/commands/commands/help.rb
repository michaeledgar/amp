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

command :help do |c|
  c.workflow :all
  c.desc "Prints the help for the program."
  
  c.on_run do |options, args|
    output = ""
    
    cmd_name = args.empty? ? "__default__" : args.first
    Amp::Help::HelpUI.print_entry(cmd_name, options)
  end
end