command :status do |c|
  c.desc "Prints the status of the working directory (or another revision)"
  c.add_opt :all, "Show all files", {:short => "-A"}
  c.add_opt :modified, "Show only modified files", {:short => "-m"}
  c.add_opt :added,    "Show only added files", {:short => "-a"}
  c.add_opt :deleted,  "Show only deleted files", {:short => "-D"}
  c.add_opt :removed,  "Show only removed files", {:short => "-R"}
  c.add_opt :clean,    "Show only files without changes", {:short => "-c"}
  c.add_opt :unknown,  "Show only untracked files", {:short => "-u"}
  c.add_opt :ignored,  "Show only ignored files", {:short => "-i"}
  c.add_opt :rev,      "Selects which revision to use", {:short => "-r", :type => :string, :multi => true}
  c.add_opt :hg,       "Print the information in hg's style"
  c.add_opt :"no-color","Don't use color to categorize the output"
  c.synonym :st
  
  c.on_run do |options, args|
    repo = options[:repository]
    node1, node2 = c.revision_pair(repo, options[:rev])
    cwd = "" # use patterns later
    stop = "\n"
    copy = {}
    colors = {'modified' => :cyan,
              'added'    => :blue,
              'removed'  => :red,
              'deleted'  => :magenta,
              'unknown'  => :green,
              'ignored'  => :yellow,
              'clean'    => :white
             }
    states = ['modified',
              'added'   ,
              'removed' ,
              'deleted' ,
              'unknown' ,
              'ignored' ,
              'clean'   ]
    show = states.select {|k| options[k.to_sym]} # filter the list down
    
    show = states if options[:all]
    show = states[0..4] if show.empty?
    
    statopts = {:node_1 => node1, :node_2 => node2 }
    
    show.each {|switch| statopts[switch.to_sym] = true }

    status = repo.status statopts
    
    # PRINTING TIME!!!!!!!!
    
    if options[:hg]
      status_as_array = [status[:modified],
                         status[:added],
                         status[:removed],
                         status[:deleted],
                         status[:unknown],
                         status[:ignored],
                         status[:clean]
                        ]
      changestates = states.zip("MAR!?IC".split(""), status_as_array)
      changestates.each do |state, char, files|
        if show.include? state
          files.each do |f|
            if options[:"no-color"]
              Amp::UI.say "#{char} #{File.join(cwd, f.to_s)[1..-1]}#{stop}" unless f.nil?
            else
              Amp::UI.say "#{char.send colors[state]} #{File.join(cwd, f.to_s)[1..-1]}#{stop}" unless f.nil?
            end
          end
        end
      end
    else
      # print it our way
      
      show.each do |state|
        next if status[state.to_sym].empty?
        num_of_files = status[state.to_sym].size
        
        Amp::UI.say("#{state.upcase.send colors[state]}" +
            " => #{num_of_files} file#{num_of_files > 1 ? 's' : ''}")
        
        status[state.to_sym].each do |file|
          Amp::UI.say "\t#{File.join(cwd, file)[1..-1]}"
        end
        
        puts
      end
    end
    
  end
end