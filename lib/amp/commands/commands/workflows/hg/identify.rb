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
    working_changeset = repo[nil]
    parent_changeset = working_changeset.parents.first
    
    Amp::UI.tell parent_changeset.node_id.short_hex + " " if opts[:id]
    Amp::UI.tell parent_changeset.revision.to_s + " " if opts[:num]
    Amp::UI.tell parent_changeset.branch + " " if opts[:branch]
    Amp::UI.tell parent_changeset.tags.join(" ") + " " if opts[:tags]
    
    Amp::UI.say
    
  end
end