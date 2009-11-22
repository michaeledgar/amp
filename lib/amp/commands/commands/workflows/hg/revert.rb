command :revert do |c|
  c.workflow :hg
  c.desc "Add a file to the repository (it will be tracked from here on)"
  c.opt :include, "include names matching the given patterns", :short => "-I", :type => :string
  c.opt :exclude, "exclude names matching the given patterns", :short => "-X", :type => :string
  c.opt :rev, "The revision to revert to", :short => "-r", :type => :integer
  c.opt :all, "Revert entire repository", :short => "-a"
  c.help <<-HELP
amp revert [options]+ [FILE]+
  
  restore individual files or dirs to an earlier state
  
  (use update -r to check out earlier revisions, revert does not
  change the working dir parents)
  
  With no revision specified, revert the named files or directories
  to the contents they had in the parent of the working directory.
  This restores the contents of the affected files to an unmodified
  state and unschedules adds, removes, copies, and renames. If the
  working directory has two parents, you must explicitly specify the
  revision to revert to.
  
  Using the -r option, revert the given files or directories to their
  contents as of a specific revision. This can be helpful to "roll
  back" some or all of an earlier change.
  See 'amp help dates' for a list of formats valid for -d/--date.
  
  Revert modifies the working directory. It does not commit any
  changes, or change the parent of the working directory. If you
  revert to a revision other than the parent of the working
  directory, the reverted files will thus appear modified
  afterwards.
  
  If a file has been deleted, it is restored. If the executable
  mode of a file was changed, it is reset.
  
  If names are given, all files matching the names are reverted.
  If no arguments are given, no files are reverted.
  
  Modified files are saved with a .orig suffix before reverting.
  To disable these backups, use --no-backup.
HELP
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    list = args.map {|p| repo.relative_join(p) } # we assume they're files
    
    repo.revert list, opts
    
  end
end