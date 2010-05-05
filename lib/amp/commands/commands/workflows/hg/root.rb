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

command :root do |c|
  c.workflow :hg
  c.desc "Prints the current repository's root path."
  c.help <<-EOF
amp root
  
  Prints the path to the current repository's root.
EOF
  c.on_run do |opts, args|
    puts opts[:repository].root
  end
end