command :annotate do |c|
  c.desc "Shows who committed each line in a given file."
  c.synonym :blame
  c.opt :rev, "Which revision to annotate", :short => "-r", :type => :integer, :default => nil
  c.opt :"line-number", "Show line number of first appearance", :short => "-l"
  c.opt :changeset, "Show the changeset ID instead of revision number", :short => "-c"
  c.opt :user, "Shows the user who committed instead of the revision", :short => "-u"
  c.opt :date, "Shows the date when the line was committed", :short => "-d"
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    annotate = proc do ||
      revpart = ""
      showrev = !([opts[:changeset], opts[:user], opts[:date]].any?)
      
      revpart += (opts[:verbose] ? file.changeset.user : file.changeset.user.split("@").first[0..15]) if opts[:user]
      revpart += Time.at(file.changeset.date.first).to_s if opts[:date]
      revpart += " " + file.changeset.node_id.hexlify[0..11] if opts[:changeset]
      revpart += file.change_id.to_s if showrev
      
      if line_number
        revpart += ":" + line_number.to_s + ":"
      else
        revpart += ":"
      end
    end
    
    args.each do |arg|
      newopts = {:line_numbers => opts[:"line-number"]}
      results = repo.annotate(arg, opts[:rev], newopts)
      leftparts = results.map do |file, line_number, line|
        revpart = ""
        showrev = !([opts[:changeset], opts[:user], opts[:date]].any?)
        
        revpart += (opts[:verbose] ? file.changeset.user : file.changeset.user.split("@").first[0..15]) if opts[:user]
        revpart += Time.at(file.changeset.date.first).to_s if opts[:date]
        revpart += " " + file.changeset.node_id.hexlify[0..11] if opts[:changeset]
        revpart += file.change_id.to_s if showrev
        
        if line_number
          revpart += ":" + line_number.to_s + ":"
        else
          revpart += ":"
        end
      end
      
      maxleftsize = leftparts.max {|a, b| a.size <=> b.size }.size
      
      results.map! do |file, line_number, line|

        
        (revpart).rjust(maxleftsize) + "  " + line 
      end
      puts results.join
    end
  end
end