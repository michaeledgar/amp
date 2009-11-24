command :clone do |c|
  c.workflow :hg
  
  c.desc "Clone a repository"
  c.opt :pull, "Whether to do a pull from the destination (the alternative is to stream)", :short => '-p'
  c.opt :stream, "stream raw data uncompressed from repository", :short => '-u'
  c.opt :rev, "revision to clone up to (implies pull=True)", :short => '-r'
  c.opt :"no-update", "Don't do an update after cloning, leaving the directory, if local, empty"
  
  c.help <<-HELP
amp clone [options]+ src dest
  
  Make a copy of an existing repository.
  
  Create a copy of an existing repository in a new directory.  The
  source and destination are URLs, as passed to the repository
  function.  Returns a pair of repository objects, the source and
  newly created destination.
  
  The location of the source is added to the new repository's
  .hg/hgrc file, as the default to be used for future pulls and
  pushes.
  
  If an exception is raised, the partly cloned/updated destination
  repository will be deleted.
  
Where options are:
HELP
  
  c.no_repo
  c.on_run do |opts, args|
    require 'uri'
    
    src, rev, checkout = *c.parse_url(args.shift)               # get the source url, revisions we want, and the checkout
    # puts [src, rev, checkout].inspect
    source = Amp::Repositories.pick opts[:global_config], src # make it an actual repository
    dest   = (dest = args.shift) || File.basename(src)        # get the destination URL
    
    Amp::UI::status "destination directory: #{dest}"
    
    # at this point, source is an {Amp::Repository} and dest is a {String}
    begin
      src  = c.local_path src
      dest = c.local_path dest
      copy = false
      
      raise Amp::Repositories::RepoError.new("destination #{dest} already exists") if File.exist? dest
      
      if source.can_copy? and ['file', nil].include? URI.parse(dest).scheme
        copy = !opts[:pull] && rev.empty?
      end
      
      if ['file', nil].include? URI.parse(dest).scheme # then it's local
        
        if source.local? && copy # then we're copying
          FileUtils.copy_entry src, dest # copy everything, pray it's pristine
          dest_repo = Amp::Repositories::LocalRepository.new dest, false, opts[:global_config]
        else # we have to pull
          # make the directory, cd into it, pull, and maaaaaaybe update
          dest_repo = Amp::Repositories::LocalRepository.new dest, true, opts[:global_config]
          dest_repo.clone source, :revs   => (rev ? rev.map {|r| source.lookup r } : []),
                                  :stream => opts[:stream] # the actual cloning which pulls
        end
        
      else
        
        # we're cloning ourselves to a faraway land
        # which DOESN'T HAPPEN unless source is local
        # remote - remote cloning just isn't supported in mercurial
        if source.local?
          dest_repo = Amp::Repositories.pick opts[:global_config], dest
          source.push dest_repo, :revs => rev.map {|r| source.lookup r }
        else
          raise Amp::RepoError.new("Remote -> Remote cloning is not yet supported")
        end
        
      end
      
      # NOW we write the hgrc file if the dest is local
      if dest_repo.local?
        dest_repo.hg_opener.open('hgrc', 'w') do |f|
          f.puts '[paths]'
          f.puts "default = #{File.expand_path(src).gsub('%', '%%')}"
        end
        
        if opts[:update]
          Amp::UI::status "updating working directory"
          dest_repo.update if opts[:update] # and here we add the files if we want to
        end
      end
      
      [source, dest_repo]
    rescue
      FileUtils.remove_entry dest # kill the dir if we've had any problems
    end
  end
end
