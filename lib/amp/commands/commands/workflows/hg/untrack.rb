command :untrack do |c|
  c.workflow :hg
  c.desc "Stop tracking the file"
  
  c.on_run do |opts, args|
    opts[:"no-unlink"] = true
    opts[:quiet]       = true
    
    puts "Forgetting #{args.size} file#{args.size == 1 ? '' : 's'}"
    Amp::Command['remove'].run opts, args
  end
end
