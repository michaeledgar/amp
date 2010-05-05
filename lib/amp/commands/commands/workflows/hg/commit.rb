##################################################################
#                  Licensing Information                         #
#                                                                #
#  The following code is licensed, as standalone code, under     #
#  the Ruby License, unless otherwise directed within the code.  #
#                                                                #
#  For information on the license of this code when distributed  #
#  with and used in conjunction with the other modules in the    #
#  Amp project, please see the root-level LICENSE file.          #
#                                                                #
#  © Michael J. Edgar and Ari Brown, 2009-2010                   #
#                                                                #
##################################################################

command :commit do |c|
  c.workflow :hg
  
  c.desc "Commit files from the staging area to the repository"
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
    # Forces a status check - kinda nice, actually.
    full_status = repo.status
    if files.any?
      changes = {:modified => [], :removed => [], :added => []}
      # split the files up so we can deal with them appropriately
      files.each do |file|
        case repo.staging_area.file_status file
        when :merged, :added
          changes[:modified] << file
        when :normal
          changes[:modified] << file if full_status[:modified].include?(file)
        when :removed
          changes[:removed]  << file
        when :untracked
          if File.directory?(file)
            changes[:modified].concat full_status[:modified].select {|x| x.start_with?(file)}
            changes[:removed].concat  full_status[:removed].select  {|x| x.start_with?(file)}
            # no warning if given empty directory
          else
            Amp::UI.warn "#{file} not tracked!"
          end
        else
          Amp::UI.err "#{file} has unknown state #{state[0]}"
        end
      end
    else
      changes = full_status
    end
    changes
  end
  
end