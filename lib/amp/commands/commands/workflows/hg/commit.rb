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
    
    changes = calculate_dirstate_commit(repo, files, match)
    opts[:modified], opts[:removed] = (changes[:modified] + changes[:added]), changes[:removed]
    File.open("/log.txt","a") {|f| f.puts "committing: #{opts.inspect} #{args.inspect} #{changes.inspect}\n"}
    repo.commit opts
  end
  
  ##
  # Calculates what changes to commit for the given list of files.
  # Bases this upon the dirstate.
  #
  # @param [Array<String>] files the explicit files to check (if any)
  # @param [Amp::Match] match the matcher object to fall back on
  # @return [Hash] all the changes from the current dirstate.
  def calculate_dirstate_commit(repo, files, match)
    changes = nil
    if files.any?
      changes = {:modified => [], :removed => [], :added => []}
      # split the files up so we can deal with them appropriately
      files.each do |file|
        case repo.staging_area.file_status file
        when :normal, :merged, :added
          changes[:modified] << file
        when :removed
          changes[:removed]  << file
        when :untracked
          Amp::UI.warn "#{file} not tracked!"
        else
          Amp::UI.err "#{file} has unknown state #{state[0]}"
        end
      end
    else
      changes = repo.status(:match => match)
    end
    changes
  end
end