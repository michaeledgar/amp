namespace :debug do
  command :dirstate do |c|
    c.workflow :hg
    
    c.desc "Shows the current state of the working directory, as amp sees it."
    c.opt :"no-dates", "Do not show modification dates", :short => "-D"
    
    c.on_run do |opts, args|
      repo = opts[:repository]
      showdates = !opts[:"no-dates"]
      time = ""
      
      repo.dirstate.files.sort.each do |file, ent|
        if showdates
          # fuck locales for now....
          timetouse = ent.mtime == -1 ? 0 : ent.mtime
          time = Time.at(timetouse).strftime("%Y-%m-%d %H:%M:%S")
        end
        if ent.mode & 020000 != 0
          mode = 'lnk'
        else
          mode = (ent.mode & 0777).to_s(8)
        end
        Amp::UI.say "#{ent.status}\t#{mode.to_s.rjust(3)} #{ent.size.to_s.rjust(10)} #{time} #{file}"
      end
      
      repo.dirstate.copy_map.each do |key, value|
        Amp::UI.say "copy: #{value} -> #{key}"
      end
    end
  end
end