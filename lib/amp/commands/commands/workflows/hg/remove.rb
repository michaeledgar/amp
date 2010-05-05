#######################################################################
#                  Licensing Information                              #
#                                                                     #
#  The following code is a derivative work of the code from the       #
#  Mercurial project, which is licensed GPLv2. This code therefore    #
#  is also licensed under the terms of the GNU Public License,        #
#  verison 2.                                                         #
#                                                                     #
#  For information on the license of this code when distributed       #
#  with and used in conjunction with the other modules in the         #
#  Amp project, please see the root-level LICENSE file.               #
#                                                                     #
#  © Michael J. Edgar and Ari Brown, 2009-2010                        #
#                                                                     #
#######################################################################

command :remove do |c|
  c.workflow :hg
  c.desc "Removes files from the repository on next commit"
  c.opt :"no-unlink", "Don't unlink the files", :short => "-A", :default => false
  c.opt :force, "Forces removal of files", :short => "-f", :default => false
  c.opt :include, "include names matching the given patterns", :short => "-I", :type => :string
  c.opt :exclude, "exclude names matching the given patterns", :short => "-X", :type => :string
  
  c.synonym :rm, :nuke
  c.on_run do |opts, args|
    repo = opts[:repository]
    list = args
    list = list.map {|p| repo.relative_join(p) }

    match = Amp::Match.create :files => list, :includer => opts[:include], :excluder => opts[:exclude]
    s = repo.status(:match => match, :clean => true)
    modified, added, deleted, clean = s[:modified], s[:added], s[:deleted], s[:clean]
    
    if opts[:force]
      remove, forget = modified + clean, added
    elsif opts[:after]
      remove, forget = deleted, []
      (modified + added + clean).each {|p| Amp::UI.warn "#{p} still exists" }
    else
      remove, forget = deleted + clean, []
      modified.each {|p| Amp::UI.warn "not removing #{p} - file is modified (use -f)"       }
      added.each    {|p| Amp::UI.warn "not removing #{p} - file is marked for add (use -f)" }
    end
    
    if opts[:verbose]
      (remove + forget).sort.each {|f| Amp::UI.status "removing #{f}..." }
    end
    
    repo.staging_area.remove(remove, :unlink => ! opts[:"no-unlink"]) # forgetting occurs here
    repo.forget(forget)
    repo.staging_area.save
    
    remove += forget
    
    if remove.size == 1
      Amp::UI.say "File #{remove.first.red} removed at #{Time.now}"
    else
      Amp::UI.say "#{remove.size.to_s.red} files removed at #{Time.now}"
    end
  end
end
