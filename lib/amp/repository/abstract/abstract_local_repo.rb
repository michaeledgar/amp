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
    ##
    # This class contains the functionality of all repositories ever.
    # Methods here rely on certain base methods that are unimplemented,
    # left as an exercise for the reader.

    class AbstractLocalRepository
      include CommonLocalRepoMethods
      
      ##
      # Returns the root of the repository (not the .hg/.git root)
      #
      # @return [String]
      def root
        raise NotImplementedError.new("root() must be implemented by subclasses of AbstractLocalRepository.")
      end
      
      ##
      # Returns the staging area for the repository, which provides the ability to add/remove
      # files in the next commit.
      #
      # @return [AbstractStagingArea]
      def staging_area
        raise NotImplementedError.new("staging_area() must be implemented by subclasses of AbstractLocalRepository.")
      end
      
      ##
      # Has the file been modified from node1 to node2?
      # 
      # @param [String] file the file to check
      # @param [Hash] opts needs to have :node1 and :node2
      # @return [Boolean] has the +file+ been modified?
      def file_modified?(file, opts={})
        raise NotImplementedError.new("file_modified?() must be implemented by subclasses of AbstractLocalRepository.")
      end
      
      ##
      # Write +text+ to +filename+, where +filename+
      # is local to the root.
      #
      # @param [String] filename The file as relative to the root
      # @param [String] text The text to write to said file
      def working_write(filename, text)
        raise NotImplementedError.new("working_write() must be implemented by subclasses of AbstractLocalRepository.")
      end
      
      ##
      # Commits a changeset or set of files to the repository. You will quite often
      # use this method since it's basically the basis of version control systems.
      #
      # @api
      # @param [Hash] opts the options to this method are all optional, so it's a very
      #   flexible method. Options listed below.
      # @option opts [Array] :modified ([]) which files have been added or modified
      #   that you want to be added as a changeset.
      # @option opts [Array] :removed ([]) which files should be removed in this
      #   commit?
      # @option opts [Hash] :extra ({}) any extra data, such as "close" => true
      #   will close the active branch.
      # @option opts [String] :message ("") the message for the commit. An editor
      #   will be opened if this is not provided.
      # @option opts [Boolean] :force (false) Forces the commit, ignoring minor details
      #   like when you try to commit when no files have been changed.
      # @option opts [Match] :match (nil) A match object to specify how to pick files
      #   to commit. These are useful so you don't accidentally commit ignored files,
      #   for example.
      # @option opts [Array<String>] :parents (nil) the node IDs of the parents under
      #   which this changeset will be committed. No more than 2 for mercurial.
      # @option opts [Boolean] :empty_ok (false) Is an empty commit message a-ok?
      # @option opts [Boolean] :force_editor (false) Do we force the editor to be
      #   opened, even if :message is provided?
      # @option opts [String] :user (ENV["HGUSER"]) the username to associate with the commit.
      #   Defaults to AmpConfig#username.
      # @option opts [DateTime, Time, Date] :date (Time.now) the date to mark with
      #   the commit. Useful if you miss a deadline and want to pretend that you actually
      #   made it!
      # @return [String] the digest referring to this entry in the changelog
      def commit(opts={})
        raise NotImplementedError.new("commit() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Pushes changesets to a remote repository.
      #
      # @param [Repository] remote_repo the remote repository object to push to
      # @param [Hash] options extra options for pushing
      # @option options [Boolean] :force (false) Force pushing, even if it would create
      #   new heads (or some other error arises)
      # @option options [Array<Fixnum, String>] :revs ([]) specify which revisions to push
      # @return [Boolean] for success/failure
      def push(remote_repo, options = {})
        raise NotImplementedError.new("push() must be implemented by subclasses of AbstractLocalRepository.")
      end

      ##
      # Pulls changesets from a remote repository 
      # Does *not* apply them to the working directory.
      #
      # @param [Repository] remote_repo the remote repository object to pull from
      # @param [Hash] options extra options for pulling
      # @option options [Array<String, Fixnum>] :heads ([]) which repository heads to pull, such as
      #   a branch name or a sha-1 identifier
      # @option options [Boolean] :force (false) force the pull, ignoring any errors or warnings
      # @return [Boolean] for success/failure
      def pull(remote_repo, options = {})
        raise NotImplementedError.new("pull() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Returns a changeset for the given revision.
      # Must support at least integer indexing as well as a string "node ID", if the repository
      # system has such IDs. Also "tip" should return the tip of the revision tree.
      #
      # @return [AbstractChangeset]
      def [](revision)
        raise NotImplementedError.new("[]() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Returns the number of changesets in the repository.
      #
      # @return [Fixnum]
      def size
        raise NotImplementedError.new("size() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # Gets a given file at the given revision, in the form of an AbstractVersionedFile object.
      #
      # @return [AbstractVersionedFile]
      def get_file(file, revision)
        raise NotImplementedError.new("get_file() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # In whatever conflict-resolution system your repository format defines, mark a given file
      # as in conflict. If your format does not manage conflict resolution, re-define this method as
      # a no-op.
      #
      # @return [Boolean]
      def mark_conflicted(*filenames)
        raise NotImplementedError.new("mark_conflicted() must be implemented by subclasses of AbstractLocalRepository.")
      end
  
      ##
      # In whatever conflict-resolution system your repository format defines, mark a given file
      # as no longer in conflict (resolved). If your format does not manage conflict resolution,
      # re-define this method as a no-op.
      #
      # @return [Boolean]
      def mark_resolved(*filenames)
        raise NotImplementedError.new("mark_resolved() must be implemented by subclasses of AbstractLocalRepository.")
      end
      
      ##
      # Attempts to resolve the given file, according to how mercurial manages
      # merges. Needed for api compliance.
      #
      # @api
      # @param [String] filename the file to attempt to resolve
      def try_resolve_conflict(filename)
        raise NotImplementedError.new("try_resolve_conflict() must be implemented by subclasses of AbstractLocalRepository.")
      end
      
      ##
      # Returns all files that have not been merged. In other words, if we're 
      # waiting for the user to fix up their merge, then return the list of files
      # we need to be correct before merging.
      #
      # @todo think up a better name
      #
      # @return [Array<Array<String, Symbol>>] an array of String-Symbol pairs - the
      #   filename is the first entry, the status of the merge is the second.
      def uncommitted_merge_files
        raise NotImplementedError.new("uncommitted_merge_files() must be implemented by subclasses of AbstractLocalRepository.")
      end
      
      ##
      # Regarding branch support.
      #
      # For each repository format, you begin in a default branch.  Each repo format, of
      # course, starts with a different default branch.  Mercurial's is "default", Git's is "master".
      #
      # @api
      # @return [String] the default branch name
      def default_branch_name
        raise NotImplementedError.new("default_branch_name() must be implemented by subclasses of AbstractLocalRepository.")
      end
    end
  end
end