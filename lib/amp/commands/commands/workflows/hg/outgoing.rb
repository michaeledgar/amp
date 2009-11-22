command :outgoing do |c|
  c.workflow :hg
  c.opt :limit, "How much of the logs to show",              :short => '-l', :type => :integer
  c.opt :rev, "Revision to clone up to (implies pull=True)", :short => '-r', :type => :integer
  c.opt :force, "Force getting new heads",                   :short => '-f'
  c.opt :"newest-first", 'Show the newest heads first'
  c.opt :"no-merges", "Don't show merges"
  c.desc "Prints the list of all changesets that can be pushed"
  c.help <<-HELP
amp outgoing [options]+ dest
  show changesets not found in destination
  
  Show changesets not found in the specified destination repository or
  the default push location. These are the changesets that would be pushed
  if a push was requested.
  
  See pull for valid destination format details.
HELP

  c.on_run do |opts, args|
    repo   = opts[:repository]
    
    dest = args.shift
    path = c.expand_path dest || 'default-push', dest || 'default', repo.config
    url  = Amp::Support::parse_hg_url path, opts[:rev]
    # dest, revs, checkout
    if url[:revs] && url[:revs].any? # url[:revs] isn't guaranteed to be an array
      url[:revs] = url[:revs].map {|r| repo.lookup rev }
    end
    
    remote = Amp::Repositories.pick nil, url[:url]
    Amp::UI::status "comparing with #{url[:url].hide_password}"
  
    o = repo.find_outgoing_roots remote, :force => opts[:force]
    (Amp::UI::status "no changes found"; return 1) if o.empty?
  
    o = repo.changelog.nodes_between(o, url[:revs])[:between]
    
    # reverse the order, because the newest are usually last
    # this is noticed if you get bitbucket email notifications
    o.reverse! if opts[:"newest-first"]
  
    # trim the list if it's bigger than our limit
    o = opts[:limit] ? o[0..opts[:limit]-1] : o
    
    Amp::UI::say # give us some space
    
    # print each changeset using the template in templates/
    o.each do |node_id|
      # get the parents of the node so that we can check if it's a merge
      # (merges have two parents)
      parents = repo.changelog.parents(node_id).select {|p| p.not_null? }
    
      # We skip printing this if it's a merge (parents.size == 2)
      # and we're NOT printing merges (opts[:"no-merges"])
      next if opts[:"no-merges"] && parents.size == 2
      opts.merge! :template_type => :log
      Amp::UI::tell repo[node_id].to_templated_s(opts)
    end
  end
end
