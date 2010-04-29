command :"what-changed" do |c|
  c.workflow :hg
  
  c.desc "Which commits have touched this file?"
  c.opt :limit, "Limit how many revisions to show", :short => "-l", :type => :integer, :default => -1
  c.opt :template, "Which template to use while printing", :short => "-t", :type => :string, :default => "default"
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    file = repo.versioned_file args.shift
    revs = file.map {|vf| vf.link_rev }
    revs = revs[-opts[:limit]..-1] unless opts[:limit] <= 0
    
    revs.reverse.each do |rev|
      Amp::UI.say repo[rev].to_templated_s(opts)
    end
  end
end
