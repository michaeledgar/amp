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
    parse_args = lambda {|os| [:all, :mark, :unmark, :list].map {|i| os[i] } }
    
    # Checks to make sure user input is valid
    all, mark, unmark, list = *parse_args[ opts ]
    
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
    parse_args = lambda {|os| [:all, :mark, :unmark, :list].map {|i| os[i] } }
    
    all, mark, unmark, list = *parse_args[opts]
    merge_state = Amp::Merges::Mercurial::MergeState.new(repo)
    
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
    merge_state.each do |file, status|
      # check to see if our user wants this file
      if match.call(file)
        if list
          Amp::UI.say "#{status.first} #{file}"
        elsif mark
          # the "r" means resolved
          merge_state.mark(file, "r")
          Amp::UI.say "#{file} marked as #{"resolved".blue}"
        elsif unmark
          # the "u" means unresolved
          merge_state.mark(file, "u")
          Amp::UI.say "#{file} marked as #{"unresolved".red}"
        else
          # retry the merge
          working_changeset = repo[nil]
          merge_changeset = working_changeset.parents.last
          
          # backup the current file to a .resolve file (but retain the extension
          # so editors that rely on extensions won't bug out)
          path = repo.working_join file
          File.copy(path, path + ".resolve"  + File.extname(path))
          
          # try to merge the files!
          merge_state.resolve(file, working_changeset, merge_changeset)
          
          # restore the backup to .orig (overwriting the old one)
          File.move(path + ".resolve"  + File.extname(path), path + ".orig" + File.extname(path))
        end
      end
    end
    
  end
end