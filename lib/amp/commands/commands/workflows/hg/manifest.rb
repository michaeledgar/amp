command :manifest do |c|
  c.workflow :hg
  c.desc "Prints the manifest at a given revision (defaults to working directory)"
  c.add_opt :rev, "Specifies the revision to check", {:short => "-r", :type => :integer}
  c.on_run do |options, arguments|
    revision = options[:rev] || "tip"
    repo = options[:repository]
        
    repo[revision].each do |k, _|
      puts "#{k}"
    end
  end
end