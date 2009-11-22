command :tip do |c|
  c.workflow :hg
  
  c.desc "Prints the information about the repository's tip"
  c.opt :template, "Which template to use while printing", :short => "-t", :type => :string, :default => "default"
  
  c.on_run do |options, args|
    repo = options[:repository]
    options.merge! :template_type => :log
    puts repo[repo.size - 1].to_templated_s(options)

  end
end