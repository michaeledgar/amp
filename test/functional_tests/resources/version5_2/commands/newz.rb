command :newz do |c|
  c.desc "Prints the newz at a given revision (defaults to working directory)"
  c.add_opt :rev, "Specifies the revision to check", {:short => "-r", :type => :integer}
  c.on_run do |options, arguments|
    revision = options[:rev]
    repo = options[:repository]
    
    repo[revision].each do |k, v|
      puts "#{k}"
    end
  end
end