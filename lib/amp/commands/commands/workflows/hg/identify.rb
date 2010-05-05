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

command :identify do |c|
  c.workflow :hg
  c.desc "Identifies the current (or another) revision"
  c.opt :num, "show local revision number", :short => "-n"
  c.opt :id,  "show global revision ID", :short => "-i"
  c.opt :branch, "show branch", :short => "-b"
  c.opt :tags, "show tags", :short => "-t"
  c.opt :rev, "specifies which revision to report upon", :type => :string, :short => "-r"
  c.on_run do |opts, args|
    repo = opts[:repository]
    default_mode = !(opts[:num] || opts[:id] || opts[:branch] || opts[:tags])
    
    changeset = repo[opts[:rev] || nil]
    
    Amp::UI.tell changeset.to_s + " " if opts[:id] || default_mode
    Amp::UI.tell changeset.revision.to_s + " " if opts[:num]
    if opts[:branch]
      Amp::UI.tell changeset.branch + " "
    elsif default_mode && changeset.branch != "default"
      Amp::UI.tell "(#{changeset.branch})" + " "
    end
    Amp::UI.tell changeset.tags.join(" ") + " " if opts[:tags] || default_mode
    
    Amp::UI.say
    
  end
end