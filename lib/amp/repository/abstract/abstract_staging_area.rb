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

module Amp
  module Repositories
    class AbstractStagingArea
      include CommonStagingAreaMethods
      
      ##
      # Marks a file to be added to the repository upon the next commit.
      # 
      # @param [[String]] filenames a list of files to add in the next commit
      # @return [Boolean] true for success, false for failure
      def add(*filenames)
        raise NotImplementedError.new("add() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Marks a file to be removed from the repository upon the next commit. Last argument
      # can be a hash, which can take an :unlink key, specifying whether the files should actually
      # be removed or not.
      # 
      # @param [[String]] filenames a list of files to remove in the next commit
      # @return [Boolean] true for success, false for failure
      def remove(*filenames)
        raise NotImplementedError.new("remove() must be implemented by subclasses of AbstractStagingArea.")
      end
        
      ##
      # Set +file+ as normal and clean. Un-removes any files marked as removed, and
      # un-adds any files marked as added.
      # 
      # @param  [Array<String>] files the name of the files to mark as normal
      # @return [Boolean] success marker
      def normal(*files)
        raise NotImplementedError.new("normal() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Mark the files as untracked.
      # 
      # @param  [Array<String>] files the name of the files to mark as untracked
      # @return [Boolean] success marker
      def forget(*files)
        raise NotImplementedError.new("forget() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Marks a file to be copied from the +from+ location to the +to+ location
      # in the next commit, while retaining history.
      # 
      # @param [String] from the source of the file copy
      # @param [String] to the destination of the file copy
      # @return [Boolean] true for success, false for failure
      def copy(from, to)
        raise NotImplementedError.new("copy() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Marks a file to be moved from the +from+ location to the +to+ location
      # in the next commit, while retaining history.
      # 
      # @param [String] from the source of the file move
      # @param [String] to the destination of the file move
      # @return [Boolean] true for success, false for failure
      def move(from, to)
        raise NotImplementedError.new("move() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Marks a modified file to be included in the next commit.
      # If your VCS does this implicitly, this should be defined as a no-op.
      # 
      # @param [[String]] filenames a list of files to include for committing
      # @return [Boolean] true for success, false for failure
      def include(*filenames)
        raise NotImplementedError.new("include() must be implemented by subclasses of AbstractStagingArea.")
      end
      alias_method :stage, :include
      
      ##
      # Mark a modified file to not be included in the next commit.
      # If your VCS does not include this idea because staging a file is implicit, this should
      # be defined as a no-op.
      # 
      # @param [[String]] filenames a list of files to remove from the staging area for committing
      # @return [Boolean] true for success, false for failure
      def exclude(*filenames)
        raise NotImplementedError.new("exclude() must be implemented by subclasses of AbstractStagingArea.")
      end
      alias_method :unstage, :exclude
      
      ##
      # Returns a Symbol.
      # Possible results:
      # :added (subset of :included)
      # :removed
      # :untracked
      # :included
      # :normal
      #
      def file_status(filename)
        raise NotImplementedError.new("file_status() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # The directory used by the VCS to store magical information (.hg, .git, etc.).
      #
      # @api
      # @return [String] relative to root
      def vcs_dir
        raise NotImplementedError.new("vcs_dir() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Saves the staging area's state.  Any added files, removed files, "normalized" files
      # will have that status saved here.
      def save
        raise NotImplementedError.new("save() must be implemented by subclasses of AbstractStagingArea")
      end
      
      ##
      # Returns all files tracked by the repository *for the working directory* - not
      # to be confused with the most recent changeset.
      #
      # @api
      # @return [Array<String>] all files tracked by the repository at this moment in
      #   time, including just-added files (for example) that haven't been committed yet.
      def all_files
        raise NotImplementedError.new("all_files() must be implemented by subclasses of AbstractStagingArea.")
      end
      
      ##
      # Returns whether the given directory is being ignored. Optional method - defaults to
      # +false+ at all times.
      #
      # @api-optional
      # @param [String] directory the directory to check against ignoring rules
      # @return [Boolean] are we ignoring this directory?
      def ignoring_directory?(directory)
        false
      end
      
      ##
      # Returns whether the given file is being ignored. Optional method - defaults to
      # +false+ at all times.
      #
      # @api-optional
      # @param [String] file the file to check against ignoring rules
      # @return [Boolean] are we ignoring this file?
      def ignoring_file?(file)
        false
      end
      
      ##
      # Does a detailed look at a file, to see if it is clean, modified, or needs to have its
      # content checked precisely.
      #
      # Supplements the built-in #status command so that its output will be cleaner.
      #
      # Defaults to report files as normal - it cannot check if a file has been modified
      # without this method being overridden.
      #
      # @api-optional
      #
      # @param [String] file the filename to look up
      # @param [File::Stats] st the current results of File.lstat(file)
      # @return [Symbol] a symbol representing the current file's status
      def file_precise_status(file, st)
        return :lookup
      end
      
      ##
      # Calculates the difference (in bytes) between a file and its last tracked state.
      #
      # Defaults to zero - in other words, it deactivates the delta feature.
      #
      # @api-optional
      # @param [String] file the filename to look up
      # @param [File::Stats] st the current results of File.lstat(file)
      # @return [Fixnum] the number of bytes difference between the file and
      #  its last tracked state.
      def calculate_delta(file, st)
        0
      end
      
    end
  end
end