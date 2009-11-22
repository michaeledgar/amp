command :add do |c|
  c.workflow :git
  c.desc "Add a file to the repository (it will be tracked from here on)"
  c.opt :all,   "Adds all untracked files to the repository", :short => "-a"
  c.opt :force, "Forces addition of ignored files", :short => "-f"
  c.opt :"dry-run", "Doesn't actually add files - just shows output", :short => "-n"
  c.opt :verbose, "Verbose output", :short => "-v"
  c.help <<-HELP
amp add [-n] [--force | -f] [--interactive | -i] [--patch | -p]
             [--all | [--update | -u]] [--refresh] [--ignore-errors] [--]
             <filepattern>...

add the specified files on the next commit
This command:

    * Schedules files to be version controlled and added to the repository.
    
    * If an ignored file is explicitly named to be added, then the command will
      abort. If an ignored file is added with a pattern, then they will be ignored silently.

    * The files will be added to the repository at the next commit. To
      undo an add before that, see [amp revert].
    
    * See the help for `git add` to see how this differs from the Mercurial implementation.

HELP
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    working_changeset = repo[nil]
    
    files    = args.reject {|p| p.include?("*") }
    patterns = args.select {|p| p.include?("*") }
    
    if opts[:all]
      matcher = Amp::Match.create(:files => []) { |file| !repo.dirstate.include?(file) }
    else
      matcher = Amp::Match.create(:files => files, :includer => (["syntax: glob"] + patterns)) { false }
    end
    
    names = []
    exact = {}
    working_changeset.walk(matcher, true).each do |file, _|
      if matcher.exact? file
        if repo.dirstate.ignore(file) && !opts[:force]
          raise abort("Can't add the ignored file #{file}. Use --force to override")
        end
        Amp::UI.status "adding #{file.relative_path repo.root}" if opts[:verbose]
        names << file
        exact[file] = true
      elsif !repo.dirstate.include?(file) && (!repo.dirstate.ignore(file) || opts[:force])
        Amp::UI.status "adding #{file.relative_path repo.root}"
        names << file
      end
    end
    
    rejected = repo.add names unless opts[:"dry-run"]
    
    if names.size == 1
      Amp::UI.say "File #{names.first.blue} has been added at #{Time.now}"
    else
      Amp::UI.say "#{names.size.to_s.blue} files have been added at #{Time.now}"
    end
  end
end