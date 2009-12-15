module Amp
  module Repositories
    module Mercurial
      
      ##
      # = Lock
      # Manages a given lock file, indicating that the enclosing folder should not
      # be modified. Typically used during destructive operations on a repo (such as
      # a commit or push).
      #
      # We must be compatible with Mercurial's lock format, unfortunately. Doesn't life
      # suck?
      #####
      ##### From Mercurial code, explaining their format:
      #####
      #
      # lock is symlink on platforms that support it, file on others.
      #
      # symlink is used because create of directory entry and contents
      # are atomic even over nfs.
      #
      # old-style lock: symlink to pid
      # new-style lock: symlink to hostname:pid
      class Lock
        @@host = nil
        
        ##
        # Initializes the lock to a given file name, and creates the lock, effectively
        # locking the containing directory.
        #
        # @param [String] file the path to the the lock file to create
        # @param [Hash<Symbol => Object>] opts the options to use when creating the lock
        # @option [Integer] options :timeout (-1) the length of time to keep trying to create the lock.
        #   defaults to -1 (indefinitely)
        # @option [Proc, #call] options :release_fxn (nil) A proc to run when the
        #   lock is released
        # @option [String] options :desc (nil) A description of the lock
        def initialize(file, opts={:timeout => -1})
          @file = file
          @held = false
          @timeout = opts[:timeout]
          @release_fxn = opts[:release_fxn]
          @description = opts[:desc]
          apply_lock
        end
        
        ##
        # Applies the lock. Will sleep the thread for +timeout+ time trying to apply the lock before
        # giving up and raising an error.
        def apply_lock
          timeout = @timeout
          while true do
            begin
              # try_lock will raise of there is already a lock.
              try_lock
              return true
            rescue LockHeld => e
              # We'll put up with this exception for @timeout times, then give up.
              if timeout != 0
                sleep(1)
                timeout > 0 && timeout -= 1
                next
              end
              # Timeout's up? Raise an exception.
              raise LockHeld.new(Errno::ETIMEDOUT::Errno, e.filename, @desc, e.locker)
            end
          end
        end
        
        ##
        # Attempts to apply the lock. Raises if unsuccessful. Contains the logic for actually naming
        # the lock.
        def try_lock
          if @@host.nil?
            @@host = Socket.gethostname
          end
          lockname = "#{@@host}:#{Process.pid}"
          while !@held
            begin
              make_a_lock(@file, lockname)
              @held = true
            rescue Errno::EEXIST
              locker = test_lock
              unless locker.nil?
                raise LockHeld.new(Errno::EAGAIN::Errno, @file, @desc, locker)
              end
            rescue SystemCallError => e
              raise LockUnavailable.new(e.errno, e.to_s, @file, @desc)
            end
          end
        end
        
        ##
        # Creates a lock at the given location, with info about the locking process. Uses
        # a symlink if possible, because even over NFS, creating a symlink is atomic. Nice.
        # Otherwise, it will call make_a_lock_in_file on inferior OS's (cough windows cough)
        # and put the data in there.
        #
        # The symlink is actually a non-working symlink - it points the filename (such as "hglock")
        # to the data, even though the data is not an actual file. So hglock -> "medgar:25043" is
        # a sort-of possible lock this method would create.
        #
        # @param [String] file the filename of the lock
        # @param [String] info the info to store in the lock
        def make_a_lock(file, info)
          begin
            File.symlink(info, file)
          rescue Errno::EEXIST
            raise
          rescue
            make_a_lock_in_file(file, info)
          end
        end
        
        ##
        # Creates a lock at the given location, storing the info about the locking process in
        # an actual lock file. These locks are not preferred, because symlinks are atomic even
        # over NFS. Anyway, very simple. Create the file, write in the info, close 'er up.
        # That's 1 line in ruby, folks.
        #
        # @see make_a_lock
        # @param [String] file the filename of the lock
        # @param [String] info the info to store in the lock
        def make_a_lock_in_file(file, info)
          File.open(file, "w+") {|out| out.write info }
        end
        
        ##
        # Reads in the data associated with a lock file.
        #
        # @param [String] file the path to the lock file to read
        # @return [String] the data in the lock. In the format "#{locking_host}:#{locking_pid}"
        def read_lock(file)
          begin
            return File.readlink(file)
          rescue Errno::EINVAL, Errno::ENOSYS
            return File.read(file)
          end
        end
        
        ##
        # Checks to see if there is a process running with id +pid+.
        #
        # @param [Fixnum] pid the process ID to look up
        # @return [Boolean] is there a process with the given pid?
        def test_pid(pid)
          return true if Platform::OS == :vms
          
          begin
            # Doesn't actually kill it
            Process.kill(0, pid)
            true
          rescue Errno::ESRCH::Errno
            true
          rescue
            false
          end
        end
            
        
        ##
        # Text from mercurial code:
        #
        # return id of locker if lock is valid, else None.
        #
        # If old-style lock, we cannot tell what machine locker is on.
        # with new-style lock, if locker is on this machine, we can
        # see if locker is alive.  If locker is on this machine but
        # not alive, we can safely break lock.
        #
        # The lock file is only deleted when None is returned.
        def test_lock
          locker = read_lock(@file)
          host, pid = locker.split(":", 1)
          return locker if pid.nil? || host != @@host
          
          pid = pid.to_i
          return locker if pid == 0
          
          return locker if test_pid pid
          
          # if locker dead, break lock.  must do this with another lock
          # held, or can race and break valid lock.
          begin
            the_lock = Lock.new(@file + ".break")
            the_lock.try_lock
            File.unlink(@file)
            the_lock.release
          rescue LockError
            return locker
          end
        end
          
        ##
        # Releases the lock, signalling that it is now safe to modify the directory in which
        # the lock is found.
        def release
          if @held
            @held = false
            @release_fxn.call if @release_fxn
            
            File.unlink(@file) rescue ""
          end
        end
          
        
      end
    end
  end
end