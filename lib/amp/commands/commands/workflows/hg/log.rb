command :log do |c|
  c.workflow :hg
  c.desc "Prints the commit history."
  c.add_opt :verbose, "Verbose output", {:short => "-v"}
  c.add_opt :limit, "Limit how many revisions to show", {:short => "-l", :type => :integer, :default => -1}
  c.add_opt :template, "Which template to use while printing", {:short => "-t", :type => :string, :default => "default"}
  c.add_opt :no_output, "Doesn't print output (useful for benchmarking)"
  c.on_run do |options, args|
    repo = options[:repository]
    limit = options[:limit]
    limit = repo.size if limit == -1
    
    start = repo.size - 1
    stop  = start - limit + 1
    
    options.merge! :template_type => :log
    start.downto stop do |x|
      puts repo[x].to_templated_s(options) unless options[:no_output]
    end
  end
end
