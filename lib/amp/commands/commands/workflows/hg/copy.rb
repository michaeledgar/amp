command :copy do |c|
  c.workflow :hg
  c.desc "Copies a file from one location to another, while maintaining history"
  c.opt :force, "Forces the copy, ignoring overwrites", :short => "-f"
  c.opt :"dry-run", "Doesn't actually move files - only prints what would happen", :short => "-n"
  c.opt :verbose, "Prints more output than normal", :short => "-v"
  c.synonym :cp
  c.before do |opts, args|
    if args.size < 2
      Amp::UI.say "Usage: amp copy source [other-sources...] destination"
      c.break
    elsif args.size > 2 && !File.directory?(args.last)
      Amp::UI.say "If you want to copy more than 1 file, your destination must" +
                  " be a directory."
      c.break
    end
    true
  end
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    sources = args[0..-2]
    destination = args.last
    sources.each do |source|
      Amp::UI.say "#{source} => #{destination}"
      repo.copy source, destination, opts
    end
  end
end


