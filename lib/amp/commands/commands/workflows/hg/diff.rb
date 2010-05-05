##################################################################
#                  Licensing Information                         #
#                                                                #
#  The following code is licensed, as standalone code, under     #
#  the Ruby License, unless otherwise directed within the code.  #
#                                                                #
#  For information on the license of this code when distributed  #
#  with and used in conjunction with the other modules in the    #
#  Amp project, please see the root-level LICENSE file.          #
#                                                                #
#  © Michael J. Edgar and Ari Brown, 2009-2010                   #
#                                                                #
##################################################################

command :diff do |c|
  c.desc "Shows the differences between changesets"
  c.opt :color, "Turns on colored formatting", :short => "-c", :default => false
  c.opt :rev, "Specifies a revision for diffing.", :short => "-r", :multi => true, :type => :integer
  c.on_run do |opts, args|
    repo = opts[:repository]
    revs = opts[:rev] || []
    
    revs << "tip" if revs.size == 0
    revs << nil   if revs.size == 1
    
    revs.map! {|key| repo[key] }
    
    differences = repo.status(:node_1 => revs[0], :node_2 => revs[1])
    files = differences[:added] + differences[:removed] + differences[:deleted] + differences[:modified]
    
    files.each do |filename|
      vf_old, vf_new = revs.map {|rev| rev.get_file filename}
      
      diff = vf_old.unified_diff_with vf_new, :pretty => opts[:color]
      Amp::UI::say diff
    end
    
  end
end