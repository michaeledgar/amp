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
    opts[:id] = opts[:num] = true unless opts[:num] || opts[:id] || opts[:branch] || opts[:tags]
    
    changeset = repo[opts[:rev] || nil]
    
    Amp::UI.tell changeset.node_id.short_hex + " " if opts[:id]
    Amp::UI.tell changeset.revision.to_s + " " if opts[:num]
    Amp::UI.tell changeset.branch + " " if opts[:branch]
    Amp::UI.tell changeset.tags.join(" ") + " " if opts[:tags]
    
    Amp::UI.say
    
  end
end