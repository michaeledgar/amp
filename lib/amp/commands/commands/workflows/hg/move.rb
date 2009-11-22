command :move do |c|
  c.workflow :hg
  c.desc "Moves a file from one place to another"
  c.opt :force, "Forces the move, ignoring overwrites", :short => "-f"
  c.opt :"dry-run", "Doesn't actually move files - only prints what would happen", :short => "-n"
  
  c.synonym :mv
  c.synonym :rename
  
  c.before do |opts, args|
    if args.size < 2
      Amp::UI.say "Usage: amp move source destination"
      c.break
    elsif args.size > 2 && !File.directory?(args.last)
      Amp::UI.say "If you want to move more than 1 file, your destination must" +
                  " be a directory."
      c.break
    end
    true
  end
  
  c.on_run do |opts, args|
    opts.merge!(:rename => true)
    Amp::Command["copy"].run(opts, args)
  end
end


