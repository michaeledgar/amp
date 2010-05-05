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

command :copy do |c|
  c.workflow :git
  c.desc "Copies a file from one location to another, while maintaining history"
  c.opt :force, "Forces the copy, ignoring overwrites", :short => "-f"
  c.opt :"dry-run", "Doesn't actually move files - only prints what would happen", :short => "-n"
  c.synonym :cp
  c.before do |opts, args|
    if args.size < 2
      Amp::UI.say "Usage: amp copy source [other-sources...] destination"
      c.break
    elsif args.size > 2 && !File.directory?(args.last)
      Amp::UI.say "If you want to copy more than 1 file, your destination must" +
                  " be a directory."
      c.break
    end
  end
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    sources = args[0..-2]
    destination = args.last
    sources.each do |source|
      repo.staging_area.copy(source, destination, opts)
    end
    repo.staging_area.save
  end
end