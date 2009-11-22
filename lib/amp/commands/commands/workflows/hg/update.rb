command :update do |c|
  c.workflow :hg
  
  c.desc "Updates the current repository to the specified (or tip-most) revision"
  c.opt :rev, "The revision # to use for updating.", { :short => "-r", :type => :string }
  c.opt :node, "The node ID to use for updating.", { :short => "-n", :type => :string }
  c.opt :clean, "Remove uncommitted changes from the working directory.", { :short => "-C" }
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    if opts[:rev] && opts[:node]
      raise ArgumentError.new("Please only specify either --rev or --node.")
    end
    
    rev = opts[:rev] ? opts[:rev] : opts[:node]
    
    # TODO: add --date option
    if opts[:clean]
      stats = repo.clean(rev)
    else
      stats = repo.update(rev)
    end
    
    c.print_update_stats stats
  end
end