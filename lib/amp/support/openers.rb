module Amp
  # opens files
  class Opener
    
    attr_reader :root
    
    attr_accessor :create_mode
    attr_accessor :default
    
    alias_method :base, :root
    
    ##
    # Creates a new opener with a root of +base+, and also set to open files in
    # the .hg subdirectory. If you set .default = :open_file, it will no longer
    # open files in the .hg subdir.
    # 
    # @param [String] base the root directory of the repository this opener will be
    #   used on
    def initialize(base)
      @root        = File.expand_path base
      @create_mode = nil
      @default     = nil
    end
    
    ##
    # Returns the path to the opener's root.
    #
    # @return path to the opener's root, as an absolute path.
    def path
      if @default == :open_file
        "#{root}/"
      else
        "#{root}/.hg/"
      end
    end
    
    ##
    # Read the file passed in with mode 'r'.
    # Synonymous with File.open(+file+, 'r') {|f| f.read } and
    # File.read(+file+)
    #
    # @param [String] file the relative path to the file we're opening
    # @return [String] the contents of the file
    def read(file)
      res = nil
      open(file, 'r') {|f| res = f.read }
      res
    end
    alias_method :contents, :read
    
    ##
    # Opens up the given file, exactly like you would do with File.open.
    # The parameters are the same. Defaults to opening a file in the .hg/
    # folder, but if @default == :open_file, will open it from the working
    # directory.
    #
    # If the mode includes write privileges, then the write will use an
    # atomic temporary file.
    #
    # @param [String] file the path to the file to open
    # @param [String] mode the read/write mode to open with (standard
    #   C choices here)
    # @yield Can yield the opened file if the block form is used
    def open(file, mode='r', &block)
      if @default == :open_file
        open_file file, mode, &block
      else
        open_hg file, mode, &block
      end
    end
    
    def join(file)
      File.join(root, file)
    end
    
    ##
    # Opens a file in the .hg repository using +@root+. This method
    # operates atomically, and ensures that the file is always closed
    # after use. The temporary files (while being atomically written)
    # are stored in "#{@root}/.hg", and are deleted after use. If only 
    # a read is being done, it instead uses Kernel::open instead of
    # File::amp_atomic_write.
    #
    # @param [String] file the file to open
    # @param [String] mode the mode with which to open the file ("w", "r", "a", ...)
    # @yield [file] code to run on the file
    # @yieldparam [File] file the opened file
    def open_hg(file, mode='w', &block)
      open_up_file File.join(root, ".hg"), file, mode, &block
    end
    
    ##
    # Opens a file in the repository (not in .hg).
    # Writes are done atomically, and reads are efficiently
    # done with Kernel::open. THIS IS NOT +open_up_file+!!!
    # 
    # @param [String] file the file to open
    # @param [String] mode the mode with which to open the file ("w", "r", "a", ...)
    # @yield [file] code to run on the file
    # @yieldparam [File] file the opened file
    def open_file(file, mode='w', &block)
      open_up_file root, file, mode, &block
    end
    
    ##
    # This does the actual opening of a file.
    # 
    # @param [String] dir This dir is where the temp file is made, but ALSO
    #   the parent dir of +file+
    # @param [String] file Just the file name. It must exist at "#{dir}/#{file}"
    def open_up_file(dir, file, mode, &block)
      path = File.join dir, file
      if mode == 'r' # if we're doing a read, make this super snappy
        Kernel::open path, mode, &block
      else # we're doing a write
        File::amp_atomic_write path, mode, @create_mode, dir, &block
      end
    end
    
  end
end
