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

command :add do |c|
  c.workflow :hg
  
  c.desc "Add a file to the repository (it will be tracked from here on)"
  c.opt :include, "include names matching the given patterns", :short => "-I", :type => :string
  c.opt :exclude, "exclude names matching the given patterns", :short => "-X", :type => :string
  c.opt :"dry-run", "Doesn't actually add files - just shows output", :short => "-n"
  c.help <<-HELP
amp add [FILE]+ [options]

  add the specified files on the next commit
  This command:
  
      * Schedules files to be version controlled and added to the repository.
  
      * The files will be added to the repository at the next commit. To
        undo an add before that, see [amp revert].
  
      If no names are given, all files are added to the repository.
    
  Where options are:
HELP
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    list = args.map {|p| repo.relative_join(p) }
    
    matcher = Amp::Match.create :files    => list,
                                :includer => opts[:include],
                                :excluder => opts[:exclude]
    names = []
    repo.walk(nil, matcher).each do |file, _|
      if matcher.exact?(file) || !repo.dirstate.include?(file)
        names << file
        if opts[:verbose] || !matcher.exact?(file)
          Amp::UI.status "adding #{file.relative_path repo.root}"
        end
      end
    end
    
    rejected = repo.staging_area.add names unless opts[:"dry-run"]
    
    repo.staging_area.save unless rejected.size == names.size
    
    if names.size == 1
      Amp::UI.say "File #{names.first.blue} has been added at #{Time.now}"
    else
      Amp::UI.say "#{names.size.to_s.blue} files have been added at #{Time.now}"
    end
  end
end