command :incoming do |c|
  c.workflow :hg
  c.desc "Show new changesets found in source"

  c.help <<-HELP
amp incoming [options]+ source
  
  Show new changesets found in the specified path/URL or the default
  pull location. These are the changesets that would be pulled if a pull
  was requested.
  
  For remote repository, using --bundle or -b avoids downloading the changesets
  twice if the incoming is followed by a pull.
  
  See pull for valid source format details.
HELP

  c.opt :force,          "Run even when remote repository is unrelated", :short => '-f'
  c.opt :"newest-first", "Show newest record first",                     :short => '-n'
  c.opt :bundle,         "File to store the bundles into",               :short => '-b', :type  => :string
  c.opt :rev,            "A specific revision up to which you would like to pull", :short => '-r', :type => :string
  c.opt :patch,          "Show patch",                                   :short => '-p'
  c.opt :limit,          "Limit number of changes displayed",            :short => '-l'
  c.opt :"no-merges",    "Do not show merges",                           :short => '-M'
  c.opt :style,          "Display using template map file",              :short => '-s'
  c.opt :template, "Which template to use while printing", {:short => "-t", :type => :string, :default => "default"}

  c.opt :ssh,            "Specify ssh command to use",                   :short => '-e'
  c.opt :remotecmd,      "Specify hg command to run on the remote side", :short => '-c'

  c.on_run do |opts, args|  
    repo = opts[:repository]
    
    url = args.shift || repo.config['paths', 'default-push'] || repo.config['paths', 'default']
    url = Amp::Support::parse_hg_url url, opts[:rev]
    #source, revs, checkout
    
    remote = Amp::Repositories.pick opts[:global_config], url[:url]
    Amp::UI::status "comparing with #{url[:url].hide_password}"
  
    url[:revs] = url[:revs].map {|r| remote.lookup r } if url[:revs] && url[:revs].any?
    common, incoming, remote_heads = *repo.common_nodes(remote, :heads => url[:revs],
                                                                :force => opts[:force])
    
  
    if incoming.empty?
      File.safe_unlink opts[:bundle]
      Amp::UI::status 'no changes found'
      break
    end
  
    cleanup = nil
    file = opts[:bundle]
  
    if file || !remote.local?
      # create a bundle (uncompressed if the other repo is not local)
    
      url[:revs] = remote_heads if url[:revs].nil? && remote.capable?('changegroupsubset')
      cg = if url[:revs].nil? || !url[:revs].any?
             remote.changegroup incoming, 'incoming'
           else
             remote.changegroup_subset incoming, url[:revs], 'incoming'
           end
      
      bundle_type = (remote.local? && "HG10GZ") || "HG10UN" # ???
      require 'tempfile'
      file = Tempfile.new("hg-incoming-bundle", Dir.pwd)
      Amp::Mercurial::RevlogSupport::ChangeGroup.write_bundle(cg, bundle_type, file)
      cleanup = file.path
      unless remote.local?
        remote = Amp::Repositories::BundleRepository.new(repo.root, opts[:global_config], cleanup)
      end
    end
    opts.merge! :template_type => :log
    remote.changelog.nodes_between(incoming, url[:revs])[:between].each do |n|
      puts remote[n].to_templated_s(opts)
    end

    if remote.respond_to?(:close)
      remote.close
    end
    #File.safe_unlink cleanup if cleanup
  
  end
end
