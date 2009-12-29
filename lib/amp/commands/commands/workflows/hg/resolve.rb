command :resolve do |c|
  c.workflow :hg
  c.desc "Retry file merges, or mark files as successfully hand-merged"
  c.opt :all, "Attempt to resolve (or mark) all unresolved files", :short => "-a"
  c.opt :list, "List unresolved files", :short => "-l"
  c.opt :mark, "Mark file(s) as resolved", :short => "-m"
  c.opt :unmark, "Mark file(s) as unresolved", :short => "-u"
  c.opt :include, "Specify patterns of files to include in the operation", :short => "-I", :type => :string
  c.opt :exclude, "Specify patterns of files to exclude in the operation", :short => "-E", :type => :string
  
  c.before do |opts, args|
    # Checks to make sure user input is valid
    all, mark, unmark, list = [:all, :mark, :unmark, :list].map {|i| opts[i] }
    
    if (list && (mark || unmark)) || (mark && unmark)
      raise abort("too many options specified")
    end
    
    if all && (opts[:include] || opts[:exclude] || args.any?)
      raise abort("can't specify --all and patterns or files")
    end
    
    if !(all || args.any? || opts[:include] || opts[:exclude] || mark || unmark || list)
      raise abort("no files or directories specified; use --all to remerge all files")
    end
    
    true
  end
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    all, mark, unmark, list = [:all, :mark, :unmark, :list].map {|i| opts[i] }
    
    if opts[:all]
      # the block means "default to true" - so basically ignore all other input
      match = Amp::Match.create(:files    => []) { true }
    else
      # the block means "default to false" - rely entirely on user input
      match = Amp::Match.create(:includer => opts[:include],
                                :excluder => opts[:exclude],
                                :files    => args) { false }
    end                        
                          
    # iterate over each entry in the merge state file
    repo.uncommitted_merge_files.each do |file, status|
      # check to see if our user wants this file
      if match.call(file)
        if list
          Amp::UI.say "#{status.first} #{file}"
        elsif mark
          # the "r" means resolved
          repo.mark_resolved(file)
          Amp::UI.say "#{file} marked as #{"resolved".blue}"
        elsif unmark
          # the "u" means unresolved
          repo.mark_conflicted(file)
          Amp::UI.say "#{file} marked as #{"unresolved".red}"
        else
          repo.try_resolve_conflict(file)
        end
      end
    end
    
  end
end