# taken straight from the need gem!
# need takes a block which should contain a string of the relative path to the file
# you wish to need.
$times = []

##
# Loads a given file, relative to the directory of the file executing the need statement.
#
# @example need { "silly.rb" }
# @example need("silly.rb")
# @param [String] file the file to load
def need(file=nil, &block)
  # do some timing if we're still benchmarking
  s = Time.now if ENV["TESTING"] == "true"
  
  if block_given?
    if RUBY_VERSION < "1.9" && (!defined?(RUBY_ENGINE) || RUBY_ENGINE != 'rbx')
      require File.expand_path(File.join(File.dirname(eval("__FILE__", block.binding)),block.call)) # 1.9 hack
    else
      require File.expand_path(File.join(File.dirname(caller_file(0)),block.call))
    end
  elsif file
    require File.expand_path(File.join(File.dirname(__FILE__),file))
  end
  # do some timing if we're still benchmarking
  $times << [Time.now - s, block ? block.call : file]  if ENV["TESTING"] == "true"
end

##
# Loads an entire directory, relative to the caller's file
#
# @example require_dir { "commands/**/*.rb" }
# @param [String] dir the directory, in glob format, to load
# @yield returns the string of the directory
def require_dir(dir=nil, &block)
  # do some timing if we're still benchmarking
  s = Time.now if ENV["TESTING"] == "true"
  
  if block_given?
    Dir[File.join(Amp::CODE_ROOT, block.call)].each do |f|
      unless File.directory? f
        f = f[Amp::CODE_ROOT.size+1..-1]
        require f
      end
    end
  else
    Dir[dir].each {|f| require f unless File.directory? f }
  end
  
  # do some timing if we're still benchmarking
  $times << [Time.now - s, block ? block.call : file]  if ENV["TESTING"] == "true"
end

##
# Finds the caller's file path. +level+ specifies how far down the call stack to look.
#
# @param [Fixnum] level the point in the call stack to look - 0 = top, 1 = caller, etc.
# @return [String, NilClass] the path to the caller function's file.
def caller_file(level=0)
  if caller[level] # call stack big enough?
    if RUBY_VERSION < "1.9" # this is for 1.8
      File.expand_path(caller[level].split(":").first)
    else
      File.expand_path(caller[level+1].split(":").first)
    end
  end # returns nil by default
end
private :caller_file

##
# Loads a C extension, or an alternate file if the C cannot be loaded for any reason
# (such as the user not compiling it).
#
# @param [String] path_to_c the path to the C library. Will be loaded relative to
#   the caller's file.
# @param [String] path_to_alt the path to the pure ruby version of the C library. Will
#   be loaded relative to the caller's file
def amp_c_extension(path_to_c, path_to_alt)
  
  if $USE_RUBY
    Amp::UI.debug "Loading alternative ruby: #{path_to_alt}"
    require File.join(File.dirname(caller_file(1)), path_to_alt)
    return
  end
  
  begin
    offset = RUBY_VERSION < "1.9" ? 1 : 0
    require File.expand_path(File.join(File.dirname(caller_file(offset)), path_to_c))
  rescue LoadError # C Version could not be found, try ruby version
    Amp::UI.debug "Loading alternative ruby: #{path_to_alt}"
    require File.join(File.dirname(caller_file(1)), path_to_alt)
  end
end
