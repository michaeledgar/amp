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

command :forget do |c|
  c.workflow :hg
  c.desc "Remove the file from the staging area"
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    puts "Removing #{args.size} file#{args.size == 1 ? '' : 's'} from the staging area"
    args.each {|f| repo.staging_area.normal f; print '.'}
    repo.staging_area.save
    puts
  end
end
