command :branches do |c|
  c.workflow :hg
  c.desc "Prints the current branches (active and closed)"
  c.opt :active, "Only show active branches", :short => "-a"
  c.on_run do |opts, args|
    repo = opts[:repository]

    active_branches = repo.heads(nil, :closed => false).map {|n| repo[n].branch}
    branches = repo.branch_tags.map do |tag, node|
      [ active_branches.include?(tag), repo.changelog.rev(node), tag ]
    end
    branches.reverse!
    branches.sort {|a, b| b[1] <=> a[1]}.each do |is_active, node, tag|
      if !opts[:active] || is_active
        hexable = repo.lookup(node)
        if is_active
          branch_status = ""
        elsif !(repo.branch_heads(:branch => tag, :closed => false).include?(hexable))
          notice = " (closed)"
        else
          notice = " (inactive)"
        end
        revision = node.to_s.rjust(31 - tag.size)
        data = [tag, revision, hexable.short_hex, notice]
        Amp::UI.say "#{tag} #{revision}:#{hexable.short_hex}#{notice}"
      end
    end  #end each

  end  # end on_run
end