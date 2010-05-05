#######################################################################
#                  Licensing Information                              #
#                                                                     #
#  The following code is a derivative work of the code from the       #
#  Mercurial project, which is licensed GPLv2. This code therefore    #
#  is also licensed under the terms of the GNU Public License,        #
#  verison 2.                                                         #
#                                                                     #
#  For information on the license of this code when distributed       #
#  with and used in conjunction with the other modules in the         #
#  Amp project, please see the root-level LICENSE file.               #
#                                                                     #
#  © Michael J. Edgar and Ari Brown, 2009-2010                        #
#                                                                     #
#######################################################################

command :annotate do |c|
  c.workflow :hg
  
  c.desc "Shows who committed each line in a given file."
  c.opt :rev, "Which revision to annotate", :short => "-r", :type => :integer, :default => nil
  c.opt :"line-number", "Show line number of first appearance", :short => "-l"
  c.opt :changeset, "Show the changeset ID instead of revision number", :short => "-c"
  c.opt :user, "Shows the user who committed instead of the revision", :short => "-u"
  c.opt :date, "Shows the date when the line was committed", :short => "-d"
  c.opt :number, "Show the revision number of the committed line", :short => "-n"
  c.synonyms :blame, :praise
  
  c.on_run do |opts, args|
    repo = opts[:repository]

    
    args.each do |arg|
      newopts = {:line_numbers => opts[:"line-number"]}
      results = repo.annotate(arg, opts[:rev], newopts)
      revpart = ""
      max_size = 0
      full_results = results.map do |file, line_number, line|
        revpart = ""
        showrev = opts[:number] || !([opts[:changeset], opts[:user], opts[:date]].any?)
        
        # What did this line do? There is no Array#count
        #totalparts = [opts[:user], opts[:date], opts[:changeset], showrev].count {|x| x }
        revpart += (opts[:verbose] ? file.changeset.user : file.changeset.user.split("@").first[0..15]) if opts[:user]
        revpart += " " if opts[:user] and opts[:date] || opts[:changeset] || showrev
        revpart += Time.at(file.changeset.date.first).to_s if opts[:date]
        revpart += " " if opts[:date] and opts[:changeset] || showrev
        revpart += file.changeset.node_id.hexlify[0..11] if opts[:changeset]
        revpart += " " if opts[:changeset] and showrev
        revpart += file.change_id.to_s if showrev
        
        if line_number
          revpart += ":" + line_number.to_s + ":"
        else
          revpart += ":"
        end
        max_size = revpart.size if revpart.size > max_size
        [revpart, file, line_number, line]
      end
      
      
      full_results.map! do |revpart, file, line_number, line|
        (revpart).rjust(max_size) + "  " + line 
      end
      puts full_results.join
    end
  end
end