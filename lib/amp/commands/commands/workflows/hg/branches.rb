command :branches do |c|
  c.workflow :hg
  c.desc "Prints the current branches (active and closed)"
  c.opt :active, "Only show active branches", :short => "-a"
  c.opt :closed, "Show closed branches", :short => "-c"
  c.on_run do |opts, args|
    repo = opts[:repository]

    active_branches = repo.heads(nil, :closed => false).map {|n| repo[n].branch}
    branches = repo.branch_tags.map do |tag, node|
      [ active_branches.include?(tag), repo[node].revision, tag ]
    end
    branches.reverse!
    branches.sort {|a, b| b[1] <=> a[1]}.each do |is_active, node, tag|
      hexable = repo[node].node_id
      is_closed = !is_active && !repo.branch_heads(:branch => tag, :closed => false).include?(hexable)
      if is_active || (opts[:closed] && is_closed) || (!opts[:active] && !is_closed)
        if is_active
          branch_status = ""
        elsif is_closed
          notice = " (closed)"
        else
          notice = " (inactive)"
        end
        revision = node.to_s.rjust(31 - tag.size)
        Amp::UI.say "#{tag} #{revision}:#{hexable.short_hex}#{notice}"
      end
    end  #end each

  end  # end on_run
end