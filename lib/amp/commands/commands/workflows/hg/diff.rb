command :diff do |c|
  c.desc "Shows the differences between changesets"
  c.opt :"no-color", "Turns off colored formatting", :short => "-c"
  c.opt :rev, "Specifies a revision for diffing.", :short => "-r", :multi => true, :type => :integer
  c.on_run do |opts, args|
    repo = opts[:repository]
    revs = opts[:rev] || []
    
    revs << "tip" if revs.size == 0
    revs << nil   if revs.size == 1
    
    revs.map! {|key| repo[key]}
    
    differences = repo.status(:node_1 => revs[0], :node_2 => revs[1])
    files = differences[:added] + differences[:removed] + differences[:deleted] + differences[:modified]
    
    files.each do |filename|
      vf_old, vf_new     = revs.map {|rev| rev.get_file filename} 
      date_old, date_new = revs.map {|rev| rev.easy_date }
      path_old, path_new = vf_old.path, vf_new.path || "/dev/null"
      rev_old, rev_new   = vf_old.file_rev, vf_new.file_rev
      
      diff = vf_new.file_log.unified_revision_diff rev_old, date_old, rev_new, 
                                                   date_new, path_old, path_new, 
                                                   :pretty => !opts[:"no-color"]
      Amp::UI::say diff
    end
    
  end
end