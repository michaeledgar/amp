command :pull do |c|
  c.workflow :hg
  c.desc "Add a file to the repository (it will be tracked from here on)"
  c.opt :update, "update to new tip if changesets were pulled",  :short => "-u"
  c.opt :force,  "run even when remote repository is unrelated", :short => "-f"
  c.opt :rev, "a specific revision up to which you would like to pull", :short => '-r',
                                                                        :type => :string
  c.opt :ssh, "specify ssh command to use", :short => '-e', :type => :string
  c.opt :remotecmd, "specify amp command to run on the remote side", :type => :string
  
  c.desc "pull changes from the specified source"
  c.help <<-HELP
amp pull [options]+ src
  
  Pull changes from a remote repository to a local one.
  
  This finds all changes from the repository at the specified path
  or URL and adds them to the local repository. By default, this
  does not update the copy of the project in the working directory.
  
  Valid URLs are of the form:
  
    local/filesystem/path (or file://local/filesystem/path)
    http://[user[:pass]@]host[:port]/[path]
    https://[user[:pass]@]host[:port]/[path]
    ssh://[user[:pass]@]host[:port]/[path]
  
  Paths in the local filesystem can either point to Mercurial
  repositories or to bundle files (as created by 'amp bundle' or
  'amp incoming --bundle').
  
  An optional identifier after # indicates a particular branch, tag,
  or changeset to pull.
HELP
  
  c.on_run do |opts, args|
    repo   = opts[:repository]
    dest   = args.shift || repo.config["paths", "default-push"] || repo.config["paths", "default"]
    
    if dest =~ /#/
      dest, branch = dest.split('#')
    else
      branch = nil
    end
    
    remote = Amp::Repositories::pick repo.config, dest
    Amp::UI::status "pulling from #{dest.hide_password}"
    
    revs = opts[:rev] && [ remote.lookup(opts[:rev]) ]
    
    mod_heads = repo.pull remote, :heads => revs, :force => opts[:force]
    
    # 
    # Everything here is "post-incoming"
    ####################################
    
    unless mod_heads.zero?
      if opts[:update]
        if mod_heads <= 1 || repo.branch_heads.size == 1 or opts[:rev]
          Amp::Command['update'].run( { :repository => repo } ,
                                      { :rev => opts[:rev]  } )
        else
          Amp::UI::status "not updating, since new heads were added"
        end
      end
    
      if mod_heads > 1
        Amp::UI::status "(run 'amp heads' to see heads, 'amp merge' to merge)"
      else
        Amp::UI::status "(run 'amp update' to get a working copy)"
      end
    end
  end
end
