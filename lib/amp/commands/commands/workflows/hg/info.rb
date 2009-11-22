command :info do |c|
  c.workflow :hg
  c.desc "Print information about one or more changesets"
  c.opt :template, "Which template to use while printing", {:short => "-t", :type => :string, :default => "default"}
  
  c.on_run do |opts, args|
    #arguments are the revisions
    repo = opts[:repository]
    
    args.empty? && args = ['tip']
    opts.merge! :template_type => :log
    
    args.each do |arg|
      index = arg
      puts repo[index].to_templated_s(opts)
    end
  end
end