command :forget do |c|
  c.workflow :hg
  c.desc "Remove the file from the staging area"
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    puts "Removing #{args.size} file#{args.size == 1 ? '' : 's'} from the staging area"
    args.each {|f| repo.staging_area.normal f; print '.'}
    puts
  end
end
