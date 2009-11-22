command :serve do |c|
  c.workflow :hg
  
  c.desc "Starts an HTTP server (with an associated website) serving the repository"
  c.opt :path,    "The path section of the URL (e.g. /repository/served/)",    :short => "-P", :type => :string
  c.opt :port,    "Which port to run the server on",                           :short => "-p", :type => :integer
  c.opt :basic,   "HTTP Basic Authentication (vs. Digest)",                    :short => "-b", :default => false
  c.opt :private, "Should the server not be publicly readable?",               :short => "-X", :default => false
  c.opt :storage, "Store the users in [TYPE] manner. Can be 'sequel' or 'memory'", :short => "-s", :type => :string,
                                                                               :default => 'memory'
  c.opt :users,   "File from which to read the users (YAML format)",           :short => '-u', :type => :string
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    http_path = opts[:path] || "/"
    auth = opts[:basic] ? :basic : :digest
    
    server = Amp::Servers::FancyHTTPServer
    server.set_authentication auth
    server.amp_repository http_path, repo, {:title => repo.root }
    server.set :port, opts[:port] if opts[:port]
    
    server.set_storage opts[:storage]
    
    file  = YAML::load_file(opts[:users] || File.join(repo.hg, 'users')) rescue {:users => []}
    
    perms = file[:users].map do |u|
      [ u[:permission]                                                   ,
        server << {:username => u[:username], :password => u[:password]} ]
    end
    
    perms.map {|(p, u)| server.set_permission p, repo, u }
    server.set_private repo, opts[:private]
    
    server.run!
    
  end
end
