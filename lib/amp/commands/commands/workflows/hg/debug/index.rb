namespace :debug do
  
  command :index do |c|
    c.workflow :hg
    
    c.desc "Dumps the index of an index file"
    
    c.on_run do |opts, args|
      opener = Amp::Opener.new(Dir.pwd)
      opener.default = :open_file
      args.each do |index_file|
        Amp::UI.say "Index: #{index_file}"
        Amp::UI.say "|---------|------------|------------|----------|-----------|--------------|--------------|--------------|"
        Amp::UI.say "|   rev   |   offset   |   length   |   base   |  linkrev  |   nodeid     |    parent1   |    parent2   |"
        Amp::UI.say "|---------|------------|------------|----------|-----------|--------------|--------------|--------------|"
        revlog = Amp::Mercurial::Revlog.new(opener, index_file)
        idx = 0
        revlog.each do |entry|
          node    = entry.node_id
          parents = revlog.parents_for_node(node) || (["\0" * 20] * 2)
          Amp::UI.say "|#{idx.to_s.ljust(9)}|"+
                 "#{revlog.data_start_for_index(idx).to_s.ljust(12)}|"+
                 "#{revlog[idx].compressed_len.to_s.ljust(12)}|"  +
                 "#{revlog[idx].base_rev.to_s.ljust(10)}|"+
                 "#{revlog[idx].link_rev.to_s.ljust(11)}|"+
                 " #{node.hexlify[0..11]} |"+
                 " #{parents[0].hexlify[0..11]} |"+
                 " #{parents[1].hexlify[0..11]} |"
          idx += 1
        end
        Amp::UI.say "|---------|------------|------------|----------|-----------|--------------|--------------|--------------|"                 
      end
      
    end
  end
end