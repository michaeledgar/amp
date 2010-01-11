command :bisect do |c|
  c.workflow :hg
  
  c.desc "subdivision search of changesets"
  c.help <<-EOS
amp bisect [-gbsr] [-c CMD] [REV]
  
  This command helps to find changesets which introduce problems.
  To use, mark the earliest changeset you know exhibits the problem
  as bad, then mark the latest changeset which is free from the
  problem as good. Bisect will update your working directory to a
  revision for testing (unless the --noupdate option is specified).
  Once you have performed tests, mark the working directory as bad
  or good and bisect will either update to another candidate changeset
  or announce that it has found the bad revision.
  
  As a shortcut, you can also use the revision argument to mark a
  revision as good or bad without checking it out first.
  
  If you supply a command it will be used for automatic bisection. Its exit
  status will be used as flag to mark revision as bad or good. In case exit
  status is 0 the revision is marked as good, 125 - skipped, 127 (command not
  found) - bisection will be aborted and any other status bigger than 0 will
  mark revision as bad."
  
  Where options are:
EOS
  
  c.opt :command, "The command to run to test", :short => '-c', :type => :string, :default => 'ruby'
  c.opt :"dirty-room", "Eval the ruby code in -f in the context of this amp binary (faster than shelling out)", :short => '-d'
  c.opt :file, "The file to run with --command (which defaults to ruby) for testing", :short => '-f', :type => :string
  c.opt :"no-update", "Don't update the working directory during tests", :short => '-U'
  
  c.before do |opts, args|
    # Set the command to be the command and the file joined together in
    # perfect harmony. If file isn't set, command will still work.
    # If command isn't set, it defaults to 'ruby' up in the command parsing
    # so actually it's always set unless there's a problem between the keyboard
    # and chair. I'm sorry this isn't cross platform. Find room in your heart
    # to forgive me.
    opts[:command] = "#{opts[:command]} #{opts[:file]} 1>/dev/null 2>/dev/null"
    
    if opts[:"dirty-room"]
      raise "The --dirty-room option needs --file as well" unless opts[:file]
    end
    
    # If we have to preserve the working directory, then copy
    # it to a super secret location and do the work there
    if opts[:"no-update"]
      require 'fileutils'
      
      opts[:testing_repo] = "../.amp_bisect_#{Time.now}"
      FileUtils.cp_r repo.path, opts[:testing_repo]
    end
    
    true
  end
  
  c.after do |opts, args|
    if opts[:"no-update"]
      FileUtils.rm_rf opts[:testing_repo]
    end
  end
  
  c.on_run do |opts, args|
    #################################
    # VARIABLE PREP
    #################################
    # Set up some variables and make
    # $display be set to false.
    # Also set up what the proc is to
    # test each revision. Assign a cute
    # phrase to tell the user what's going
    # on.
    # 
    
    repo = opts[:repository]
    old  = $display
    $display = false # so revert won't be so chatty!
    
    # This is the sample to run. The proc needs to return true
    # or false
    if opts[:command]
      using = "use `#{opts[:command].red}`"
      run_sample = proc { system opts[:command] }
    elsif opts[:"dirty-room"]
      using = "evaluate #{opts[:file]} in this Ruby interpreter"
      run_sample = proc { eval File.read(opts[:file]) }
    else
      raise "Must have the --command or --dirty-room option set!"
    end
    
    
    ########################################
    # COMPLIMENT WHOEVER IS READING THE CODE
    ########################################
    
    # Hey! That's a really nice shirt. Where'd you get it?
    
    Amp::UI.say <<-EOS
OK! Terve! Today we're going to be bisecting your repository find a bug.
Let's see... We're set to #{using} to do some bug hunting.

Enough talk, let's go Orkin-Man on this bug!
========
EOS
    
    
    #############################################
    # BINARY SEARCH
    #############################################
    # Here's where we actually do the work. We're
    # just going through in a standard binary
    # search method. I haven't actually written
    # a BS method in a long time so I don't know
    # if this is official, but it works.
    # 
    
    last_good = 0
    last_bad  = repo.size - 1
    test_rev  = last_bad
    is_good   = {} # {revision :: integer => good? :: boolean}
    
    until (last_good - last_bad).abs < 1
      repo.clean test_rev
      
      # if the code sample works
      if run_sample[]
        is_good[test_rev] = true # then it's a success and mark it as such
        break if test_rev == last_good
        last_good = test_rev
      else
        is_good[test_rev] = false
        last_bad = test_rev
      end
      
      test_rev = (last_good + last_bad) / 2
    end
    
    ############################################
    # CLEANING UP
    ############################################
    # Restore the working directory to its proper
    # state and restore the $display variable.
    # Report on the results of the binary search
    # and say whether there is a bug, and if there
    # is a bug, say where it starts.
    # 
    
    repo.clean(repo.size - 1)
    $display = old # and put things as they were
    
    if is_good[last_bad]
      Amp::UI.say "The selected range of history passes the test. No bug found."
    else
      Amp::UI.say "Revision #{last_bad} has the bug!"
    end
  end
  
  # c.on_run do |opts, args|
  #   repo = opts[:repository]
  #   
  #   # Hey! That's a really nice shirt. Where'd you get it?
  #   last_good = 0
  #   last_bad  = repo.size - 1
  #   test_rev  = last_bad
  #   is_good  = {} # {revision :: integer => good? :: boolean}
  #   a = [true] * 1#((repo.size / 2) + 3)
  #   a.concat([false] * (repo.size - a.size))
  #   p a
  #   
  #   run_sample = proc do |test_rev|
  #     a[test_rev]
  #   end
  #   
  #   until (last_good - last_bad).abs < 1
  #     #repo.revert [], :to => test_rev
  #     p [last_good, last_bad]
  #     
  #     # if the code sample works
  #     if run_sample[test_rev]
  #       is_good[test_rev] = true # then it's a success and mark it as such
  #       break if test_rev == last_good
  #       last_good = test_rev
  #     else
  #       is_good[test_rev] = false
  #       last_bad = test_rev
  #     end
  #     
  #     test_rev = (last_good + last_bad) / 2
  #   end
  #   
  #   if is_good[last_bad]
  #     Amp::UI.say "The selected range of history passes the test. No bug found."
  #   else
  #     Amp::UI.say "Revision #{last_bad} has the bug!"
  #   end
  # end
end

# Now for some helpers!
module Kernel
  def bisect_command(name, opts={})
    command name.to_sym do |c|
      
      # set the default options as passed in
      opts.each do |k, v|
        c.default k, v
      end
      
      yield self if block_given?
    end
  end
end