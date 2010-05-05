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

command :status do |c|
  c.workflow :hg
  
  c.desc "Prints the status of the working directory (or another revision)"
  c.opt :all,       "Show all files", {:short => "-A"}
  c.opt :modified,  "Show only modified files", {:short => "-m"}
  c.opt :added,     "Show only added files", {:short => "-a"}
  c.opt :deleted,   "Show only deleted files", {:short => "-D"}
  c.opt :removed,   "Show only removed files", {:short => "-R"}
  c.opt :clean,     "Show only files without changes", {:short => "-c"}
  c.opt :unknown,   "Show only untracked files", {:short => "-u"}
  c.opt :ignored,   "Show only ignored files", {:short => "-i"}
  c.opt :rev,       "Selects which revision to use", {:short => "-r", :type => :string, :multi => true}
  c.opt :hg,        "Print the information in hg's style"
  c.opt :"no-color","Don't use color to categorize the output"
  c.opt :yaml,      "Print the information in YAML format (for use with computers)", {:short => '-y'}
  c.synonym :st
  
  c.on_run do |options, args|
    repo = options[:repository]
    node1, node2 = *c.revision_pair(repo, options[:rev])
    cwd = "" # use patterns later
    stop = "\n"
    copy = {}
    colors = {'modified' => :cyan,
              'added'    => :blue,
              'removed'  => :red,
              'deleted'  => :magenta,
              'copied'   => :blue,
              'moved'    => :red,
              'unknown'  => :green,
              'ignored'  => :yellow,
              'clean'    => :white,
             }
    states = ['modified',
              'added'   ,
              'removed' ,
              'deleted' ,
              'unknown' ,
              'ignored' ,
              'clean'   ,
              'copied'  ,
              'moved'   ]
    show = states.select {|k| options[k.to_sym] } # filter the list down
    show = states if options[:all]
    show = states[0..4] if show.empty?
    #show += states[7..8] unless options[:hg]
    
    statopts = {:node_1 => node1, :node_2 => node2 }
    
    show.each {|switch| statopts[switch.to_sym] = true }

    status = repo.status statopts
    
    # this is the proc that does the printing. I have the code in a proc
    # so that the logic is in a short screenful and isn't convoluted.
    stdout_print = proc do
      # PRINTING TIME!!!!!!!!
      if options[:hg]
        status_as_array = [status[:modified],
                           status[:added]   ,
                           status[:removed] ,
                           status[:deleted] ,
                           status[:unknown] ,
                           status[:ignored] ,
                           status[:clean]
                          ]
        changestates = states.zip("MAR!?IC".split(""), status_as_array)
        changestates.each do |state, char, files|
          if show.include? state
            files.each do |f|
              if options[:"no-color"]
                Amp::UI.tell "#{char} #{File.join(cwd, f.to_s)[1..-1]}#{stop}" unless f.nil?
              else
                Amp::UI.tell "#{char.send colors[state]} #{File.join(cwd, f.to_s)[1..-1]}#{stop}" unless f.nil?
              end
            end
          end
        end
      else
        # print it our way
        show.each do |state|
          next if status[state.to_sym].empty?
          num_of_files = status[state.to_sym].size
          
          if options[:"no-color"]
            Amp::UI.say("#{state.upcase}" +
                " => #{num_of_files} file#{num_of_files == 1 ? '' : 's'}")
          else
            Amp::UI.say("#{state.upcase.send colors[state]}" +
                " => #{num_of_files} file#{num_of_files == 1 ? '' : 's'}")
          end
          
          unless [:copied, :moved].include? state.to_sym
            status[state.to_sym].each do |file|
              Amp::UI.say "\t#{File.join(cwd, file)[1..-1]}"
            end
          else
            status[state.to_sym].each do |(src, dst)|
              Amp::UI.say "\t#{File.join(cwd, src)[1..-1]} => #{File.join(cwd, dst)[1..-1]}"
            end
          end
        end
        
        unless show.map {|s| status[s.to_sym] }.all? {|s| s.empty? }
          Amp::UI.say
          Amp::UI.say "#{status[:delta]} bytes were changed" if status[:delta]
        end
      end
    end
    
    yaml_printer = proc do
      require 'yaml'
      puts YAML::dump(status)
    end
    
    # printing logic
    if options[:yaml]
      yaml_printer[]
    else
      stdout_print[]
    end
    
  end
end