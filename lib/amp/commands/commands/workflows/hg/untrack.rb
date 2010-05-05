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

command :untrack do |c|
  c.workflow :hg
  c.desc "Stop tracking the file"
  
  c.on_run do |opts, args|
    opts[:"no-unlink"] = true
    opts[:quiet]       = true
    
    puts "Forgetting #{args.size} file#{args.size == 1 ? '' : 's'}"
    Amp::Command['remove'].run opts, args
  end
end
