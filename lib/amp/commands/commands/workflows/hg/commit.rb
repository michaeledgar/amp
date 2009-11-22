command :commit do |c|
  c.workflow :hg
  
  c.desc "Commit yo shit"
  c.opt :force, "Forces files to be committed", :short => "-f"
  c.opt :include, "Includes the given patterns", :short => "-I", :type => :string
  c.opt :exclude, "Ignores the given patterns", :short => "-E", :type => :string
  c.opt :message, "The commit message", :short => "-m", :type => :string
  c.opt :user,    "The user committing the revision", :short => "-u", :type => :string
  c.opt :date,    "The date of the commit", :short => "-d", :type => :string
  c.synonym :ci
  c.help <<-EOS
amp commit [options]+ [FILE]+

  Commit changes to the given files into the repository.

  If a list of files is omitted, all changes reported by "amp status"
  will be committed.

  If you are committing the result of a merge, do not provide any
  file names or -I/-X filters.

  If no commit message is specified, the configured editor is started to
  prompt you for a message.
  
  amp commit [FILE]+ [options]
  
  Where options are:
EOS
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    files    = args
    included = opts[:include]
    excluded = opts[:exclude]
    extra    = {}
    match    = Amp::Match.create(:files => files, :includer => included, :excluder => excluded) { !files.any? }
    opts.merge! :match => match, :extra => extra
    repo.commit opts
  end
end