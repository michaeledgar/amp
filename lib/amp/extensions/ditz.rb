namespace :ditz do
  
  command :close do |c|
    c.desc "Close a Ditz bug and commit saying that it has been closed"
    
    c.opt :message, "Any notes concerning this bug", :short => '-m', :type => :string, :default => ''
    
    c.on_run do |opts, args|
      repo  = opts[:repository]
      msg   = opts[:message]
      issue = args.shift
      
      system "ditz close #{issue}"
      
      repo.commit :message => "Closed Bug ##{issue}#{msg.empty? ? '' : ": #{msg}"}"
    end
  end
  
  command :add do |c|
    c.desc "Add a Ditz bug and commit saying that it has been opened"
    
    c.opt :message, "Any notes concerning this bug", :short => '-m', :type => :string, :default => ''
    
    c.on_run do |opts, args|
      repo  = opts[:repository]
      msg   = opts[:message]
      
      system "ditz add"
      
      # seydar: *sigh* i hate taking advantage of side effects
      # File.read('.ditz-config') =~ /^issue_dir:(.+)$/
      # bugs = $1.strip
      # adgar: then don't use them!
      bugs = File.read('.ditz-config').match(/^issue_dir:(.+)$/)[1].strip
      
      Amp::Command[:add].run opts, [bugs]
      repo.commit :message => "Added Bugs"
    end
  end
  
end
