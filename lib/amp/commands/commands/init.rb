command :init do |c|
  c.workflow :all
  c.desc "Initializes a new repository in the current directory."
  c.on_run do |options, args|
    path = args.first ? args.first : '.'
    
    Amp::Repositories::Mercurial::LocalRepository.new(path, true, options[:global_config])
    puts "New repository initialized."
  end
end