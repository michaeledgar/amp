
require 'digest'

if RUBY_VERSION < "1.9"
  require 'ftools'
  
  autoload :Etc,      'etc'
  autoload :Pathname, 'pathname'
  autoload :Tempfile, 'tempfile'
  autoload :Socket,   'socket'
  autoload :WeakRef,  'weakref'
else
  require 'fileutils'
  require 'socket'
  require 'pathname'
  require 'etc'
  require 'tempfile'
  require 'weakref'
end
autoload :ERB,      'erb'

Boolean = :bool unless defined? Boolean

class OSError < StandardError; end
#              _                   ___
#             /\) _              //  7
#        _   / / (/\           (_,_/\ 
#       /\) ( Y)  \ \           \    \  
#      / /   ""   (Y )           \    \  
#     ( Y)  _      ""            _\    \__  
#      ""  (/\       _         (   \     )   
#           \ \     /\)         \___\___/   
#           (Y )   / /           
#            ""   ( Y)           
#                  ""       This is the AbortError. Fear it.
# 4/20. nuff said (c'est la verite)
# Strange. These used to be ASCII penises.
class AbortError < StandardError
  def to_s
    "abort: "+super
  end
end

module Kernel
  def abort(str)
    AbortError.new str
  end
end

class LockError < StandardError
  attr_reader :errno, :filename, :desc
  def initialize(errno, strerror, filename, desc)
    super(strerror)
    @errno, @filename, @desc = errno, filename, desc
  end
  def to_s
    "LockError (#{@errno} @ #{@filename}) #{@strerror}: #{super}"
  end
end

class LockHeld < LockError
  attr_reader :locker
  def initialize(errno, filename, desc, locker)
    super(errno, "Lock Held", filename, desc)
    @locker = locker
  end
end
class LockUnavailable < LockError; end

class AuthorizationError < StandardError; end

module Platform
  
  if RUBY_PLATFORM =~ /darwin/i
     OS = :unix
     IMPL = :macosx
  elsif RUBY_PLATFORM =~ /linux/i
     OS = :unix
     IMPL = :linux
  elsif RUBY_PLATFORM =~ /freebsd/i
     OS = :unix
     IMPL = :freebsd
  elsif RUBY_PLATFORM =~ /netbsd/i
     OS = :unix
     IMPL = :netbsd
  elsif RUBY_PLATFORM =~ /mswin/i
     OS = :win32
     IMPL = :mswin
  elsif RUBY_PLATFORM =~ /cygwin/i
     OS = :unix
     IMPL = :cygwin
  elsif RUBY_PLATFORM =~ /mingw/i
     OS = :win32
     IMPL = :mingw
  elsif RUBY_PLATFORM =~ /bccwin/i
     OS = :win32
     IMPL = :bccwin
  elsif RUBY_PLATFORM =~ /wince/i
     OS = :win32
     IMPL = :wince
  elsif RUBY_PLATFORM =~ /vms/i
     OS = :vms
     IMPL = :vms
  elsif RUBY_PLATFORM =~ /os2/i
     OS = :os2
     IMPL = :os2 # maybe there is some better choice here?
  else
     OS = :unknown
     IMPL = :unknown
  end
  
  if RUBY_PLATFORM =~ /(i\d86)/i
     ARCH = :x86
  elsif RUBY_PLATFORM =~ /(x86_64|amd64)/i
     ARCH = :x86_64
  elsif RUBY_PLATFORM =~ /ia64/i
     ARCH = :ia64
  elsif RUBY_PLATFORM =~ /powerpc/i
     ARCH = :powerpc
  elsif RUBY_PLATFORM =~ /alpha/i
     ARCH = :alpha
  elsif RUBY_PLATFORM =~ /universal/i
     ARCH = :universal
  else
     ARCH = :unknown
  end
   
end


class File::Stat
  
  ##
  # Used for comparing two files (approximately). This was
  # our guide: http://docs.python.org/library/os.html#os.stat
  # 
  # @param  [File::Stat] other the other stats to compare
  # @return [Boolean] whether they are similar enough or not
  def ===(other)
    self.mode  == other.mode  &&
    self.ino   == other.ino   &&
    self.dev   == other.dev   &&
    self.nlink == other.nlink &&
    self.uid   == other.uid   &&
    self.gid   == other.gid   &&
    self.size  == other.size  &&
    self.atime == other.atime &&
    self.mtime == other.atime &&
    self.ctime == other.ctime
  end
end

class Module
  ##
  # Makes an instance or module method memoized. Works by aliasing
  # the old method and creating a new one in its place.
  #
  # @param [Symbol, #to_sym] meth_name the name of the method to memoize
  # @param [Boolean] module_function_please should we call module_function on
  #   the aliased method? necessary if you are memoizing a module's function
  #   made available as a singleton method via +module_function+.
  # @return the module itself.
  def memoize_method(meth_name, module_function_please = false)
    meth_name = meth_name.to_sym
    aliased_meth = "__memo_#{meth_name}".to_sym
    # alias to a new method
    alias_method aliased_meth, meth_name
    # module_function the newly aliased method if necessary
    if module_function_please && self.class == Module
      module_function aliased_meth
    end
    # incase it doesn't exist yet
    @__memo_cache ||= {}
    # our new method! Replacing the old one.
    define_method meth_name do |*args|
      # we store the memoized data with an i-var.
      @__memo_cache[meth_name] ||= {}
      cache = @__memo_cache[meth_name]
      
      # if we have the cached value, return it
      result = cache[args]
      return result if result
      # cache miss. find the value
      result = send(aliased_meth, *args)
      cache[args] = result
      result
    end
    self
  end
end

module Kernel
  ##
  # Allows any code called within the block to access non-existent files
  # without raising an exception. Only "file not found" exceptions are
  # ignored - all other exceptions will be raised as normal.
  #
  # @yield The block is run with all missing-file exceptions caught and ignored.
  def ignore_missing_files
    begin
      yield
    rescue Errno::ENOENT
    rescue StandardError
      raise
    end
  end  
  
  ##
  # The built-in Ruby 1.8.x implementation will only show a certain number
  # of context lines at the start and end of its backtrace when an exception
  # is raised. All other levels of the stack will be labeled "... 15 levels ..."
  # Sadly, sometimes some important information is in those 15 levels, and without
  # patching the interpreter, there's no way to just disable that abbreviation.
  #
  # So, we simply catch all exceptions, print their full backtrace, and then exit!
  #
  # @yield The block is run, and any exceptions raised print their full backtrace.
  def full_backtrace_please
    message = ["***** Left engine failure *****",
               "***** Ejection system error *****",
               "***** Vaccuum in booster engine *****"
              ][rand(3)]
    begin
      yield
    rescue AbortError => e
      Amp::UI.say "Operation aborted."
      raise
    rescue StandardError => e
      Amp::UI.say message
      Amp::UI.say e.to_s
      e.backtrace.each {|err| Amp::UI.say "\tfrom #{err}" }
      exit
    end
  end
  
end

class Dir

  ##
  # Iterates over a directory, yielding an array with the
  # {File::Stat} entry for each file/directory in the requested directory.
  # @param [String] path the path to iterate over
  # @param [Boolean] stat should we retrieve stat information?
  # @param [String] skip a filename to always skip
  # @return [[String, File::Stat, String]] Each entry in the format [File path,
  #   statistic struct, file type].
  def self.stat_list path, stat=false, skip=nil
    result = []
    prefix = path
    prefix += File::SEPARATOR unless prefix =~ /#{File::SEPARATOR}$/
    names = Dir.entries(path).select {|i| i != "." && i != ".."}.sort
    names.each do |fn|
      st = File.lstat(prefix + fn)
      return [] if fn == skip && File.directory?(prefix + fn)
      if st.ftype && st.ftype !~ /unknown/
        newval = [fn, st.ftype, st]
      else
        newval = [fn, st.ftype]
      end
      result << newval
      yield newval if block_given?
    end
    result
  end
  
  def self.tmpdir
    "/tmp" # default, but it should never ever be used!
    # i mean it's ok if it is
    # but i'd be caught off guard if this ends up being used in the code
  end
  
  ##
  # Same as File.dirname, but returns an empty string instead of '.'
  # 
  # @param [String] path the path to get the directory of
  def self.dirname(path)
    File.dirname(path) == '.' ? '' : File.dirname(path)
  end
  
end

class File
  
  ##
  # Checks if a file exists, without following symlinks.
  #
  # @param [String] filename the path to the file to check
  # @return [Boolean] whether or not the file exists (ignoring symlinks)
  def amp_lexist?(filename)
    !!File.lstat(filename) rescue false
  end
  
  ##
  # Sets a file's executable bit.
  #
  # @todo Windows version
  # @param [String] path the path to the file
  # @param [Boolean] executable sets whether the file is executable or not
  def self.amp_set_executable(path, executable)
    s = File.lstat(path).mode
    sx = s & 0100
    if executable && !sx
      # Turn on +x for every +r bit when making a file executable
      # and obey umask. (direct from merc. source)
      File.chmod(s | (s & 0444) >> 2 & ~(File.umask(0)), path)
    elsif !executable && sx
      File.chmod(s & 0666 , path)
    end
  end
  
  ##
  # Does a registry lookup.
  # *nix version.
  #
  # @todo Add Windows Version
  def self.amp_lookup_reg(a,b)
    nil
  end
  
  ##
  # Finds an executable for {command}. Searches like the OS does. If
  # command is a basename then PATH is searched for {command}. PATH
  # isn't searched if command is an absolute or relative path.
  # If command isn't found, nil is returned. *nix only.
  #
  # @todo Add Windows Version.
  # @param [String] command the executable to find
  # @return [String, nil] If the executable is found, the full path is returned.
  def self.amp_find_executable(command)
    find_if_exists = proc do |executable|
      return executable if File.exist? executable
      return nil
    end
    
    return find_if_exists[command] if command.include?(File::SEPARATOR)
    ENV["PATH"].split(File::PATH_SEPARATOR).each do |path|
      executable = find_if_exists[File.join(path, command)]
      return executable if executable
    end
    
    nil
  end

  ##
  # taken from Rails' ActiveSupport
  # all or nothing babyyyyyyyy
  # use this only for writes, otherwise it's just inefficient
  # file_name is FULL PATH
  def self.amp_atomic_write(file_name, mode='w', default_mode=nil, temp_dir=Dir.tmpdir, &block)
    File.makedirs(File.dirname(file_name))
    FileUtils.touch(file_name) unless File.exists? file_name
    # this is sorta like "checking out" a file
    # but only if we're *just* writing
    new_path = join temp_dir, amp_make_tmpname(basename(file_name))
    unless mode == 'w'
      copy(file_name, new_path) # allowing us to use mode "a" and others
    end

    
    # open and close it
    val = Kernel::open new_path, mode, &block
    
    begin
      # Get original file permissions
      old_stat = stat(file_name)
    rescue Errno::ENOENT
      # No old permissions, write a temp file to determine the defaults
      check_name = ".permissions_check.#{Thread.current.object_id}.#{Process.pid}.#{rand(1000000)}"
      Kernel::open(check_name, "w") { }
      old_stat = stat(check_name)
      unlink(check_name)
      delete(check_name)
    end
    
    # do a chmod, pretty much
    begin
      nlink = File.amp_num_hardlinks(file_name)
    rescue Errno::ENOENT, OSError
      nlink = 0
      d = File.dirname(file_name)
      File.mkdir_p(d, default_mode) unless File.directory? d
    end
    
    new_mode = default_mode & 0666 if default_mode
    
    # Overwrite original file with temp file
    amp_force_rename(new_path, file_name)
    
    # Set correct permissions on new file
    chown(old_stat.uid, old_stat.gid, file_name)
    chmod(new_mode || old_stat.mode, file_name)
    
    val
  end
  
  ##
  # Makes a fancy, quite-random name for a temporary file.
  # Uses the file's name, the current time, the process number, a random number,
  # and the file's extension to make a very random filename.
  #
  # Of course, it could still fail.
  # 
  # @param  [String] basename The base name of the file - just the file's name and extension
  # @return [String] the pseudo-random name of the file to be created
  def self.amp_make_tmpname(basename)
    case basename
    when Array
      prefix, suffix = *basename
    else
      prefix, suffix = basename, "."+File.extname(basename)
    end
  
    t = Time.now.strftime("%Y%m%d")
    path = "#{prefix}#{t}-#{$$}-#{rand(0x100000000).to_s(36)}-#{suffix}"
  end
  
  ##
  # Reads a range from the file.
  # 
  # @param  [Range] range the byte indices to read between (and including)
  # @return [String] the data read from the file
  def [](range)
    p = pos
    seek(range.first)
    val = read(range.last - range.first + 1)
    seek p
    val
  end
  
  ##
  # Reads +n+ bytes at a time and yield them from the given file
  #
  # @param [Integer] num_bytes the number of bytes to yield
  # @yield Yields a chunk that is at most +num_bytes+ from the file until the
  #   file is exhausted. Poor file, it's so tired.
  # @yieldparam [String] the chunk from the file.
  def amp_each_chunk(num_bytes = 4.kb)
    buffer = nil
    while buffer = read(num_bytes)
      yield buffer
    end
  end
  
  ##
  # Finds the number of hard links to the file.
  # 
  # @param  [String] file the full path to the file to lookup
  # @return [Integer] the number of hard links to the file
  def self.amp_num_hardlinks(file)
    lstat = File.lstat(file)
    raise OSError.new("no lstat on windows") if lstat.nil?
    lstat.nlink
  end
  
  ##
  # All directories leading up to this path
  # 
  # @example directories_to "/Users/ari/src/monkey.txt" # => 
  #                           ["/Users/ari/src", "/Users/ari", "/Users"]
  # @example directories_to "/Users/ari/src/monkey.txt", true # => 
  #                           ["/Users/ari/src", "/Users/ari", "/Users", ""]
  # @param  [String] path the path to the file we're examining
  # @param  [Boolean] empty whether or not to return an empty string as well
  # @return [Array] the directories leading up to this path
  def self.amp_directories_to(path, empty=false)
    dirs = path.split('/')[0..-2]
    ret  = []
    
    dirs.size.times { ret << dirs.join('/'); dirs.pop }
    ret << '' if empty
    ret
  end
  
  ##
  # Forces a rename from file to dst, removing the dst file if it
  # already exists. Avoids system exceptions that might result.
  # 
  # @param [String] file the source file path
  # @param [String] dst the destination file path
  def self.amp_force_rename(file, dst)
    return unless File.exist? file
    if File.exist? dst
      File.unlink dst
      File.rename file, dst
    else
      File.rename file, dst
    end
  end
  
  ##
  # Returns the full name of the file, excluding path information.
  # 
  # @param [File] file the {File} to check
  # @return the name of the file
  def self.amp_name(file)
    File.split(file.path).last
  end
  
  ##
  # Splits the path into two parts: pre-extension, and extension, including
  # the dot.
  # File.amp_split_extension "/usr/bin/conf.ini" => ["conf",".ini"]
  # 
  # @param [String] path the path to the file to split up
  # @return [String, String] the [filename pre extension, file extension] of
  #   the file provided.
  def self.amp_split_extension(path)
    ext  = File.extname  path
    base = File.basename path, ext
    [base, ext]
  end
end

class Range
  # Given two ranges return the range where they intersect or None.
  # 
  # >>> intersect((0, 10), (0, 6))
  # (0, 6)
  # >>> intersect((0, 10), (5, 15))
  # (5, 10)
  # >>> intersect((0, 10), (10, 15))
  # >>> intersect((0, 9), (10, 15))
  # >>> intersect((0, 9), (7, 15))
  # (7, 9)
  def intersect(rb)
    ra = self
    start_a = [ra.begin, rb.begin].max
    start_b = [ra.end,   rb.end  ].min
    if start_a < start_b
      start_a..start_b
    else
      nil
    end
  end
  alias_method :-, :intersect
end

class Hash
  
  ##
  # Given a list of key names, and a specified value, we create a hash
  # with those keys all equal to +value+. Useful for making true/false
  # tables with speedy lookup.
  # 
  # @param  [Enumerable] iterable any object with Enumerable mixed in can
  #   create a hash.
  # @param  [Object] value (true) the value to assign each key to in the resultant hash
  # @return [Hash] a hash with keys from +iterable+, all set to +value+
  def self.with_keys(iterable, value=true)
    iterable.inject({}) {|h, k| h.merge!(k => value) }
  end
  
  ##
  # Create a subset of +self+ with keys +keys+.
  def pick(*keys)
    keys.inject({}) {|h, (k, v)| h[k] = v }
  end
  
end

class Array

  ## 
  # Sums all the items in the array
  # 
  # @return [Array] the items summed
  def sum
    inject(0) {|sum, x| sum + x }
  end
  
  ##
  # Returns the second item in the array
  #
  # @return [Object] the second item in the array
  def second; self[1]; end
  
  # Deletes the given range from the array, in-place.
  def delete_range(range)
    newend =   (range.end < 0)   ? self.size + range.end : range.end
    newbegin = (range.begin < 0) ? self.size + range.begin : range.begin
    newrange = Range.new newbegin, newend
    pos = newrange.first
    newrange.each {|i| self.delete_at pos }
    
    self
  end
  
  def to_hash
    inject({}) {|h, (k, v)| h.merge k => v }
  end
  
  def short_hex
    map {|e| e.short_hex }
  end
  alias_method :short, :short_hex
  
end

class Integer
  
  # methods for converting between file sizes
  def bytes
    self
  end
  alias_method :byte, :bytes
  alias_method :b,    :bytes
  
  # methods for converting between file sizes
  def kilobytes
    1024 * bytes
  end
  alias_method :kilobyte, :kilobytes
  alias_method :kb,       :kilobytes
  
  # methods for converting between file sizes
  def megabytes
    1024 * kilobytes
  end
  alias_method :megabyte, :megabytes
  alias_method :mb,       :megabytes
  
  # methods for converting between file sizes
  def gigabytes
    1024 * megabytes
  end
  alias_method :gigabyte, :gigabytes
  alias_method :gb,       :gigabytes
  
  
  ##
  # Forces this integer to be negative if it's supposed to be!
  # 
  # @param [Fixnum] bits the number of bits to use - signed shorts are different from
  #   signed longs!
  def to_signed(bits)
    return to_signed_16 if bits == 16
    return to_signed_32 if bits == 32
    raise "Unexpected number of bits: #{bits}"
  end
  
end

class String
  ##
  # Returns the string, encoded for a tty terminal with the given color code.
  #
  # @param [String] color_code a TTY color code
  # @return [String] the string wrapped in non-printing characters to make the text
  #   appear in a given color
  def colorize(color_code)
    "#{color_code}#{self}\e[0m"
  end
  
  # Returns the string, colored red.
  def red; colorize("\e[31m"); end
  def green; colorize("\e[32m"); end
  def yellow; colorize("\e[33m"); end
  def blue; colorize("\e[34m"); end
  def magenta; colorize("\e[35m"); end
  def cyan; colorize("\e[36m"); end
  def white; colorize("\e[37m"); end
  
  ##
  # Returns the path from +root+ to the path represented by the string. Will fail
  # if the string is not inside +root+.
  # 
  # @param [String] root the root from which we want the relative path
  # @return [String] the relative path from +root+ to the string itself
  def relative_path(root)
    return '' if self == root
    
    # return a more local path if possible...
    return self[root.length..-1] if start_with? root
    self # else we're outside the repo
  end
  
  # Am I equal to the NULL_ID used in revision logs?
  def null?
    self == Amp::RevlogSupport::Node::NULL_ID
  end
  
  # Am I not equal to the NULL_ID used in revision logs?
  def not_null?
    !(null?)
  end
  
  ##
  # Does the string start with the given prefix?
  #
  # @param [String] prefix the prefix to test
  # @return [Boolean] does the string start with the given prefix?
  def start_with?(prefix)
    self[0,prefix.size] == prefix  # self =~ /^#{str}/
  end
  
  ##
  # Does the string end with the given suffix?
  #
  # @param [String] suffix the suffix to test
  # @return [Boolean] does the string end with the given suffix?
  def end_with?(suffix)
    self[-suffix.size, suffix.size] == suffix   # self =~ /#{str}$/
  end
  
  ##
  # Pops the given character off the front of the string, but only if
  # the string starts with the given character. Otherwise, nothing happens.
  # Often used to remove troublesome leading slashes. Much like an "lchomp" method.
  #
  # @param [String] char the character to remove from the front of the string
  # @return [String] the string with the leading +char+ removed (if it is there).
  def shift(char)
    return '' if self.empty?
    return self[1..-1] if self.start_with? char
    self
  end
  alias_method :lchomp, :shift

  
  ##
  # Splits on newlines only, removing extra blank line at end if there is one.
  # This is how mercurial does it and i'm sticking to it. This method is evil.
  # DON'T USE IT.
  def split_newlines(add_newlines=true)
    return [] if self.empty?
    lines = self.split("\n").map {|l| l + (add_newlines ? "\n" : "") } 
    return lines if lines.size == 1
    if (add_newlines && lines.last == "\n") || (!add_newlines && lines.last.empty?)
      lines.pop 
    else
      lines[-1] = lines[-1][0..-2] if lines[-1][-1,1] == "\n"
    end
    lines
  end
  
  ##
  # Newer version of split_newlines that works better. This splits on newlines,
  # but includes the newline in each entry in the resultant string array.
  #
  # @return [Array<String>] the string split up into lines
  def split_lines_better
    result = []
    each_line {|l| result << l}
    result
  end
  
  ##
  # easy md5!
  #
  # @return [Digest::MD5] the MD5 digest of the string in hex form
  def md5
    Digest::MD5.new.update(self)
  end
  
  ##
  # easy sha1!
  # This is unsafe, as SHA1 kinda sucks.
  #
  # @return [Digest::SHA1] the SHA1 digest of the string in hex form
  def sha1
    Digest::SHA1.new.update(self)
  end
  
  ##
  # If the string is the name of a command, run it. Else,
  # raise hell.
  # 
  # @param [Hash] options hash of the options for the command
  # @param [Array] args array of extra args
  # @return [Amp::Command] the command which will be run
  def run(options={}, args=[])
    if cmd = Amp::Command[self]
      cmd.run options, args
    else
      raise "No such command #{self}"
    end
  end 
  
  # Converts this text into hex. each letter is replaced with
  # it's hex counterpart 
  def hexlify
    str = ""
    self.each_byte do |i|
      str << i.to_s(16).rjust(2, "0")
    end
    str
  end
  
  ##
  # Converts this text into hex, and trims it a little for readability.
  def short_hex
    hexlify[0..9]
  end
  
  ##
  # removes the password from a url. else, just returns self
  # @return [String] the URL with passwords censored.
  def hide_password
    if s = self.match(/^http(?:s)?:\/\/[^:]+(?::([^:]+))?(@)/)
      string = ''
      string << self[0..s.begin(1)-1]           # get from beginning to the pass
      string << '***'
      string << self[s.begin(2)..-1]
      string
    else
      self
    end
  end
  
  ##
  # Adds minimal slashes to escape the string
  # @return [String] the string slightly escaped.
  def add_slashes
    self.gsub(/\\/,"\\\\").gsub(/\n/,"\\n").gsub(/\r/,"\\r").gsub("\0","\\0")
  end
  
  ##
  # Removes minimal slashes to unescape the string
  # @return [String] the string slightly unescaped.
  def remove_slashes
    self.gsub(/\\0/,"\0").gsub(/\\r/,"\r").gsub(/\\n/,"\n").gsub(/\\\\/,"\\")
  end
  
  ##
  # returns the path as an absolute path with +root+
  # ROOT MUST BE ABSOLUTE
  # 
  # @param [String] root absolute path to the root
  def absolute(root)
    return self if self[0] == ?/
    "#{root}/#{self}"
  end
  
  ##
  # Attempts to discern if the string represents binary data or not. Not 100% accurate.
  # Is part of the YAML code that comes with ruby, but since we don't load rubygems,
  # we don't get this method for free.
  #
  # @return [Boolean] is the string (most likely) binary data?
  
  def is_binary_data?
      ( self.count( "^ -~", "^\r\n" ) / self.size > 0.3 || self.count( "\x00" ) > 0 ) unless empty?
  end
  alias_method :binary?, :is_binary_data?
end

class Time
  ##
  # Returns the date in a format suitable for unified diffs.
  # 
  # @return [String] diff format: 2009-03-28 18:45:12.541298
  def to_diff
    strftime("%Y-%m-%d %H:%M:%S.#{usec}")
  end
  
  # Returns a nifty date stamp for certain diff types. not used yet.
  def date_str(offset=0, format="%a %b %d %H:%M:%S %Y %1%2")
    t, tz = self, offset
    if format =~ /%1/ || format =~ /%2/
      sign = (tz > 0) ? "-" : "+"
      minutes = tz.abs / 60
      format.gsub!(/%1/, "#{sign}#{(minutes / 60).to_s.rjust(2,'0')}")
      format.gsub!(/%2/, "#{(minutes % 60).to_s.rjust(2,'0')}")
    end
    (self - tz).gmtime.strftime(format)
  end 
  
end

class Proc
  
  ##
  # Alias for #call, pretty much.
  # 
  # @param [Hash] options hash of the options for the command
  # @param [Array] args array of extra args
  def run(options={}, args=[])
    call options, args
  end
end

class Symbol
  
  # Converts the symbol to an integer used for tracking the state
  # of files in the dir_state.
  def to_hg_int
    case self
    when :normal, :dirty
      110 # "n".ord
    when :untracked
      63 # "?".ord
    when :added
      97 # "a".ord
    when :removed
      114 # "r".ord
    when :merged
      109 # "m".ord
    else
      raise "No known hg value for #{self}"
    end
  end
  
  # Converts the symbol to the letter it corresponds to
  def to_hg_letter
    to_hg_int.chr
  end
  
  def to_proc
    proc do |arg|
      arg.send self
    end
  end
end

# net_digest_auth.rb

module Net
  autoload :HTTP,  'net/http'
  autoload :HTTPS, 'net/https'
  # Written by Eric Hodel <drbrain@segment7.net>
  module HTTPHeader
    @@nonce_count = -1
    CNONCE = Digest::MD5.new.update("%x" % (Time.now.to_i + rand(65535))).hexdigest
    def digest_auth(user, password, response)
      # based on http://segment7.net/projects/ruby/snippets/digest_auth.rb
      @@nonce_count += 1

      response['www-authenticate'] =~ /^(\w+) (.*)/

      params = {}
      $2.gsub(/(\w+)="(.*?)"/) { params[$1] = $2 }

      a_1 = "#{user}:#{params['realm']}:#{password}"
      a_2 = "#{@method}:#{@path}"
      request_digest = ''
      request_digest << Digest::MD5.new.update(a_1).hexdigest
      request_digest << ':' << params['nonce']
      request_digest << ':' << ('%08x' % @@nonce_count)
      request_digest << ':' << CNONCE
      request_digest << ':' << params['qop']
      request_digest << ':' << Digest::MD5.new.update(a_2).hexdigest

      header = []
      header << "Digest username=\"#{user}\""
      header << "realm=\"#{params['realm']}\""
      
      header << "qop=#{params['qop']}"

      header << "algorithm=MD5"
      header << "uri=\"#{@path}\""
      header << "nonce=\"#{params['nonce']}\""
      header << "nc=#{'%08x' % @@nonce_count}"
      header << "cnonce=\"#{CNONCE}\""
      header << "response=\"#{Digest::MD5.new.update(request_digest).hexdigest}\""

      @header['Authorization'] = header
    end
  end
end

module Amp
  module Support
    SYSTEM = {}
    UMASK = File.umask
    
    @@rc_path = nil
    # Returns all paths to hgrc files on the system.
    def self.rc_path
      if @@rc_path.nil?
        if ENV['HGRCPATH']
          @@rc_path = []
          ENV['HGRCPATH'].split(File::PATH_SEPARATOR).each do |p|
            next if p.empty?
            if File.directory?(p)
              File.stat_list(p) do |f, kind|
                if f =~ /\.rc$/
                  @@rc_path << File.join(p, f)
                end
              end
            else
              @@rc_path << p
            end
          end
        else
          @@rc_path = self.os_rcpath
        end
      end
      @@rc_path
    end
    
    
    ##
    # Advanced calling of system().
    #
    # Allows the caller to provide substitute environment variables and
    # the directory to use
    def self.system(command, opts={})
      backup_dir = Dir.pwd # in case something goes wrong
      temp_environ, temp_path = opts.delete(:environ), opts.delete(:chdir) || backup_dir
      
	  	if (temp_environ)
     	 	old_env = ENV.to_hash
      	temp_environ["HG"] = $amp_executable || File.amp_find_executable("amp")
      	temp_environ.each {|k, v| ENV[k] = v.to_s}
	  	end
      Dir.chdir(temp_path) do
        rc = Kernel::system(command)
      end
    ensure
      ENV.clear.update(old_env) if temp_environ
      Dir.chdir(backup_dir)    
    end
    
    ##
    # Parses the URL for amp-specific reasons.
    #
    # @param [String] url The url to parse.
    # @param [Array] revs The revisions that will be used for this operation.
    # @return [Hash] A hash, specifying :url, :revs, and :head
    def self.parse_hg_url(url, revs=nil)
      revs ||= [] # in case nil is passed
      
      unless url =~ /#/
        hds = revs.any? ? revs : nil
        return {:url => url, :revs => hds, :head => revs[-1]}
      end
      
      url, branch = url.split('#')[0..1]
      checkout = revs[-1] || branch
      {:url => url, :revs => revs + [branch], :head => checkout}
    end
    # Returns the paths to hgrc files, specific to this type of system.
    def self.os_rcpath
      path = system_rcpath
      path += user_rcpath
      path.map! {|f| File.expand_path f}
      path
    end
    
    # Returns the hgrc files for the current user, specific to the particular
    # OS and user.
    def self.user_rcpath
      [File.expand_path("~/.hgrc")]
    end
    
    # Returns all hgrc files for the given path
    def self.rc_files_for_path path
      rcs = [File.join(path, "hgrc")]
      rcdir = File.join(path, "hgrc.d")
      begin
        Dir.stat_list(rcdir) {|f, kind| rcs << File.join(rcdir, f) if f =~ /\.rc$/}
      rescue
      end
      rcs
    end
    
    # gets the logged-in username
    def self.get_username
      Etc.getlogin
    end
    
    # gets the fully-qualified-domain-name for fake usernames
    def self.get_fully_qualified_domain_name
      require 'socket'
      Socket.gethostbyname(Socket.gethostname).first
    end
    
    # Returns the hgrc paths specific to this type of system, and are
    # system-wide.
    def self.system_rcpath
      path = []
      if ARGV.size > 0
        path += rc_files_for_path(File.dirname(ARGV[0]) + "/../etc/mercurial")
      end
      path += rc_files_for_path "/etc/mercurial"
      path
    end
    
    # Figures up the system is running on a little or big endian processor
    # architecture, and upates the SYSTEM[] hash in the Support module.
    def self.determine_endianness
      num = 0x12345678
      native = [num].pack('l')
      netunpack = native.unpack('N')[0]
      if num == netunpack
        SYSTEM[:endian] = :big
      else
        SYSTEM[:endian] = :little
      end   
    end
    
    determine_endianness
  end
end
