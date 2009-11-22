command :branch do |c|
  c.workflow :hg
  
  c.desc "Set/Show the current branch name"
  c.opt :force, "Forces the branch-name change", :short => "-f"
  c.opt :clean, "Resets the branch setting for this repository", :short => "-c"
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    if opts[:clean]
      _label = repo[nil].parents[0].branch
      repo.dirstate.branch = _label
      Amp::UI.status("Reset working directory to branch #{_label}")
    elsif args.size > 0
      _label = args.first
      if !opts[:force] && repo.branch_tags.include?(_label)
        if !repo.parents.map {|p| p.branch}.include?(_label)
          raise abort("a branch of the same name already exists!"+
                               " (use --force to override)")
        end
      end
      repo.dirstate.branch = _label
      Amp::UI.status("marked working directory as branch #{_label}")
    else
      Amp::UI.say("#{repo.dirstate.branch}")
    end
  end
end