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

command :default do |c|
  c.workflow :hg
  c.desc "run the `info` and `status` commands"
  
  c.on_run do |options, args|
    Amp::Command['info'].run   options, args
    Amp::Command['status'].run options, args
  end
end