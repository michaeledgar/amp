command :heads do |c|
  c.desc "Prints the heads of the repository."
  c.add_opt :rev, "show only heads which are descendants of rev", {:short => "-r"}
  c.add_opt :active, "show only active heads", {:short => "-a"}
  c.add_opt :template, "Which template to use while printing", {:short => "-t", :type => :string, :default => "default"}
  c.on_run do |options, args|
    repo   = options[:repository]
    start  = options[:rev] ? repo.lookup(options[:rev]) : nil
    closed = options[:active]
    if args.size == 0
      heads = repo.heads(start, :closed => closed)
    else
      #branch shit
    end
    
    options.merge!({:template_type => :log})
    heads.each do |n|
      puts repo[n].to_templated_s(options)
    end
    
  end
end