command :merge do |c|
  c.workflow :hg
  
  c.desc "merge working directory with another revision"
  c.opt :force, "force a merge with outstanding changes", :short => "-f"
  c.opt :rev, "revision to merge", :type => :integer, :short => "-r"
  
  c.before do |opts, args|
    repo = opts[:repository]
    if !opts[:rev]
      branch = repo[nil].branch
      bheads = repo.branch_heads[branch]
      if bheads.size > 2
        raise abort("branch #{branch} has #{bheads.size} - please merge " +
                             " with an explicit revision")
        c.break
      end
      parent = repo.dirstate.parents.first
      if bheads.size == 1
        if repo.heads.size > 1
          raise abort("branch #{branch} has one head - please merge with " +
                               "an explicit revision")
          c.break
        end
        message = "there is nothing to merge"
        if parent != repo.lookup(repo[nil].branch)
          message = "#{message} - use \"amp update\" instead"
        end
        raise abort(message)
      end
      unless bheads.include? parent
        raise abort("working dir not at a head revision - use \"amp update\" or "+
                             "merge with an explicit revision" + bheads.inspect)
      end
      opts[:node] = (parent == bheads.first) ? bheads.last : bheads.first
    end
    
    true
  end
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    node = opts[:node]
    stats = repo.update(node, true, opts[:force], false)
    c.print_update_stats stats
    if stats[:unresolved]
      Amp::UI.status("use 'amp resolve' to retry unresolved file merges or use "+
                     "'amp update --clean' to abandon changes")
    elsif true # check for a reminder setting to disable this remidner
      Amp::UI.status("(branch merge, don't forget to commit)")
    end
  end
end