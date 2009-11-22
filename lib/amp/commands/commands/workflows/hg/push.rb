command :push do |c|
  c.workflow :hg
  c.desc "Pushes the latest revisions to the remote repository."
  c.opt :remote, "The remote repository's URL", :short => "-R"
  c.opt :revs, "The revisions to push", :short => "-r", :type => :string
  c.opt :force, "Ignore remote heads", :short => "-f"
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    dest = opts[:remote] || repo.config["paths","default-push"] || repo.config["paths","default"]
    opts[:revs] ||= nil
    remote = Amp::Support.parse_hg_url(dest, opts[:revs])
    dest, revs, checkout = remote[:url], remote[:revs], remote[:head]
    remote_repo = Amp::Repositories.pick(repo.config, dest, false)
    
    revs = revs.map {|rev| repo.lookup rev } if revs
    
    result = repo.push remote_repo, :force => opts[:force], :revs => revs
  end
end
