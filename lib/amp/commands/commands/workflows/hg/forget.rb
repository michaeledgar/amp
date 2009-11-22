command :forget do |c|
  c.workflow :hg
  c.desc "Stop tracking a file"
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    puts "Forgetting #{args.size} file#{args.size == 1 ? '' : 's'}"
    repo.forget args
  end
end