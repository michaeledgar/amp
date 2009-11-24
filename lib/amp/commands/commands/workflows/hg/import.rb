command :import do |c|
  c.workflow :hg
  c.desc "Import an ordered set of patches"
  c.help <<-EOS
amp import [options]+ [FILE]+
  
  Import a list of patches and commit them individually.

  If there are outstanding changes in the working directory, import
  will abort unless given the -f flag.

  You can import a patch straight from a mail message. Even patches
  as attachments work (body part must be type text/plain or
  text/x-patch to be used). From and Subject headers of email
  message are used as default committer and commit message. All
  text/plain body parts before first diff are added to commit
  message.

  If the imported patch was generated by amp export, user and description
  from patch override values from message headers and body. Values
  given on command line with -m and -u override these.

  If --exact is specified, import will set the working directory
  to the parent of each patch before applying it, and will abort
  if the resulting changeset has a different ID than the one
  recorded in the patch. This may happen due to character set
  problems or other deficiencies in the text patch format.

  With --similarity, amp will attempt to discover renames and copies
  in the patch in the same way as 'addremove'.

  To read a patch from standard input, use patch name "-".
  
  Where options are:
EOS
  
  c.on_run do |opts, args|
    require 'date'
    require 'open-uri'
    
    repo = opts[:repository]
    patches = args
    
    opts[:date] &&= DateTime.parse(opts[:date])
    opts[:similarity] = Float(opts[:similarity] || 0)
    
    if opts[:similarity] < 0 || opts[:similarity] > 100
      raise abort('similarity must be between 0 and 100')
    end
    
    if opts[:exact] || !opts[:force]
      raise abort("Outstanding changes or uncommitted merges exist") if repo.changed?
    end
    
    d     = opts[:base]
    strip = opts[:strip]
    repo.lock_working_and_store do
      patches.each do |patch|
        patch_file = File.join d, patch
        
        if patch_file == '-'
          Amp::UI.status 'applying patch from STDIN'
          patch_file = $stdin
        else
          Amp::UI.status "applying #{patch_file}"
          patch_file = Kernel.open patch_file # uses open-uri's version of #open
        end
        
        data = Amp::Patch.extract patch_file
        # python uses an array for this:
        #  tmpname, message, user, date, branch, nodeid, p1, p2 = *data
        # WRONG BITCH! We're using a hash
        raise abort('no patch found') if data[:tmp_name].nil?
        
        begin
          message = if (msg = c.log_message opts[:message], opts[:log_file])
                      msg
                    elsif !data[:message].empty?
                      data[:message].strip
                    end # defaults to nil
          Amp::UI.debug "message: #{message}"
          
          wp = repo.parents
          if opts[:exact]
            raise abort('not a mercurial patch') unless data[:node_id] && data[:p1]
            p1 = repo.lookup data[:p1]
            p2 = repo.lookup data[:p2] || Amp::RevlogSupport::Node::NULL_ID.hexlify
            
            repo.update(p1, false, true, nil).success? if p1 != wp.first.node
            repo.dirstate.parents = [p1, p2]
          elsif p2
            begin
              p1 = repo.lookup p1
              p2 = repo.lookup p2
              repo.dirstate.parents = [p1, p2] if p1 == wp[0].node
            rescue Amp::RepoError
              # Do nothing...
            end
          end
          
          if opts[:exact] || opts[:"import-branch"]
            repo.dirstate.branch = data[:branch] || 'default'
          end
          
          files = {}
          begin
            fuzz = Amp::Patch.patch data[:tmp_name], :strip => data[:strip],
                                                     :cwd   => repo.root   ,
                                                     :file  => files
          ensure
            files = Amp::Patch.update_dir repo, files, opts.pick(:similarity)
          end
          
          unless opts[:"no-commit"]
            n = repo.commit files, :message => message                   ,
                                   :user    => opts[:user] || data[:user],
                                   :date    => opts[:date] || data[:date]
            if opts[:exact]
              if n.hexlify != data[:node_id]
                repo.rollback!
                raise abort('patch is damaged or loses information')
              end
            end
            
            # Force a dirstate write so that the next transaction
            # backups an up-do-date file.
            repo.dirstate.write
          end
        ensure
          File.safe_unlink data[:tmp_name]
        end
      end
    end
  end  # end on_run
end