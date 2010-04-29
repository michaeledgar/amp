module Amp
  module Repositories
    module Mercurial
      
      ##
      # This module contains all the code that makes a repository able to
      # update its working directory.
      module Updating
        include Amp::Mercurial::RevlogSupport::Node
        
        ##
        # Updates the repository to the given node. One of the major operations on a repository.
        # This means replacing the working directory with the contents of the given node.
        #
        # @todo add lock
        # @param [String, Integer] node the revision to which we are updating the repository. Can
        #   be either nil, a node ID, or an integer. If it is nil, it will update
        #   to the latest revision.
        # @param [Boolean] branch_merge whether to merge between branches
        # @param [Boolean] force whether to force branch merging or file overwriting
        # @param [Proc, #call] filter a function to filter file lists (dirstate not updated if this
        #   is passed)
        # @return [Array<Integer>] a set of statistics about the update. In the form:
        #   [updated, merged, removed, unresolved] where each entry is the # of files in that category.
        def update(node=nil, branch_merge=false, force=false, filter=nil)
          updater = Updater.new(self, :node => node, 
                                      :branch_merge => branch_merge, 
                                      :force => force, 
                                      :filter => filter)
          updater.update
        end
        
        ##
        # Merge two heads
        def merge(node, force=false)
          update node, true, force, false
        end
        
        ##
        # Updates the repository to the given node, clobbering (removing) changes
        # along the way. This has the effect of turning the working directory into
        # a pristine copy of the requested changeset. Really just a nice way of
        # skipping some arguments for the caller.
        #
        # @param [String] node the requested node
        def clean(node)
          update node, false, true, nil
        end
        
        ##
        # An Action that an updater takes, such as merging, getting a remote file,
        # removing a file, etc.
        module Action
          def self.for(*args)
            action = args.shift.to_s
            klass = Action.module_eval { const_get("#{action[0,1].upcase}#{action[1..-1]}Action") }
            klass.new(*args)
          end
          class GetAction < Struct.new(:file, :flags)
            def apply(repo, stats)
              UI.note("getting #{file}")
              data = target_changeset.get_file(file).data
              repo.working_write(file, data, flags)
              stats[:updated] << file
            end
            def record
            end
          end
          class RemoveAction < Struct.new(:file)
            def apply(repo, stats)
              UI.note "removing #{file}"
              File.unlink(repo.working_join(file))
              stats[:removed] << file
            end
            def record
            end
          end
          class AddAction < Struct.new(:file)
            def apply(repo, stats)
            end
            def record
            end
          end
          class ForgetAction < Struct.new(:file)
            def apply(repo, stats)
            end
            def record
            end
          end
          class ExecAction < Struct.new(:file, :flags)
            def apply(repo, stats)
              FileHelpers.set_executable(repo.working_join(file), flags.include?('x'))
            end
            def record
            end
          end
          class MergeAction < Struct.new(:file, :remote_file, :file_dest, :flags, :move)
            def apply(repo, stats)
              result = repo.merge_state.resolve(file_dest, working_changeset, target_changeset)
              
              if    result          then stats[:unresolved] << file
              elsif result.nil?     then stats[:updated] << file
              elsif result == false then stats[:merged] << file
              end

              FileHelpers.set_executable(repo.working_join(file_dest), flags && flags.include?('x'))
              if (file != file_dest && move && File.amp_lexist?(repo.working_join(file)))
                UI.debug("removing #{file}")
                File.unlink(repo.working_join(file))
              end
            end
            def record
            end
          end
          class Divergent_renameAction < Struct.new(:file, :newfiles)
            def apply(repo, stats)
              UI.warn("detected divergent renames of #{file} to:")
              newfiles.each {|fn| UI.warn fn }
            end
            def record
            end
          end
          class DirectoryAction < Struct.new(:file, :remote_file, :file_dest, :flags)
            def apply(repo, stats)
              if file && file.any?
                UI.note("moving #{file} to #{file_dest}")
                File.move(file, file_dest)
              end
              if remote_file && remote_file.any?
                UI.note("getting #{remote_file} to #{file_dest}")
                data = target_changeset.get_file(remote_file).data
                repo.working_write(file_dest, data, flags)
              end
              stats[:updated] << file
            end
            def record
            end
          end
        end
        ##
        # Class responsible for logic relating to updating the repository.
        #
        # Encapsulates one update operation using instance variables. This saves
        # the trouble of a purely functional approach, where we must pass around
        # a hash of values through each function, which just isn't necessary. Though
        # it is cute.
        class Updater
          ##
          # the default options for running an update.
          DEFAULT_OPTIONS = {:node => nil, :branch_merge => false, :force => false, :filter => nil}
          
          attr_reader :node, :branch_merge, :force, :filter
          attr_reader :working_changeset, :target_changeset
          attr_accessor :remote, :local, :ancestor
          
          ##
          # Creates an updater object, which will guide the repository through
          # an update of its working directory.
          #
          # @param [LocalRepository] repo the repository to work on
          # @param [Hash] opts the options for this update operation
          # @option opts [String, Integer] :node (nil) the node of the repository
          #    to update to. Will be passed into the repository's lookup method,
          #    so this can be a string or integer or what have you.
          # @option opts [Boolean] :branch_merge (false) is this a branch merge?
          #    in other words, if we run into conflicts, should that be expected?
          # @option opts [Boolean] :force (false) do we force the update, even
          #    if something unexpected happens?
          # @option opts [Proc, #call] :filter (nil) A proc that will help us
          #    filter out files. If this is passed, the dirstate isn't updated.
          def initialize(repo, opts = {})
            @repo = repo
            opts = DEFAULT_OPTIONS.merge(opts)
            @node, @branch_merge = opts[:node] , opts[:branch_merge]
            @force, @filter      = opts[:force], opts[:filter]
            
            initialize_ivars
          end
          
          ##
          # Sets up some useful ivars that we will need for a shit ton of processing
          # as we prepare for this update operation
          def initialize_ivars
            @working_changeset = @repo[nil]
            @target_changeset  = @repo[@node]
            # tip of current branch
            @node ||= @repo.branch_tags[@working_changeset.branch]
            @node = @repo.lookup("tip") if @node.nil? && @working_changeset.branch == "default"
            
            @remote = @repo[@node]
            @local_parent = @working_changeset.parents.first
            @ancestor = @local.ancestor(@remote)
          end
          
          ##
          # Can we overwrite files?
          #
          # @return [Boolean] whether or not overwriting files is OK
          def overwrite?
            @overwrite || (force && !branch_merge)
          end
          
          ##
          # Is this a valid fast-forward merge?
          #
          # @return [Boolean] is it a fast-forward merge/
          def fast_forward?
            branch_merge && ancestor != remote && 
                            ancestor == @local_parent && 
                            @local_parent.branch != remote.branch
          end
          
          ##
          # Is this a backwards, linear update?
          #
          # @return [Boolean] is it a fast-forward merge/
          def backwards?
            remote == ancestor
          end
          
          ##
          # Runs the update specified by this Updater object's properties.
          #
          # @return [Array<Integer>] a set of statistics about the update. In the form:
          #   [updated, merged, removed, unresolved] where each entry is the # of files in that category.
          def update
            verify_no_uncommitted_merge
            verify_valid_update
            
            check_unknown if force
            check_collision if false # case-insensitive file-system? seriously? (uh... mac os x ring a bell?)
            
            @actions = []
            
            forget_removed
            manifest_merge
            
            stats = apply_updates
          end
          
          ##
          # Adds an action to the action list (stuff to do).
          #
          # @param [String] file the filename to use
          # @param [Symbol] act the action to perform (such as :merge, :get)
          # @param [Array] args the extra arguments to the action.
          def act(act, file, *args)
            @actions << Action.for(act, file, *args)
          end
          
          ##
          # Adds an "add" action with the given file
          #
          # @see act
          # @param [String] file the file to add
          def add(file); @actions << Action::AddAction.new(file); end
          
          ##
          # Adds a "remove" action with the given file
          #
          # @see act
          # @param [String] file the file to remove
          def remove(file); @actions << Action::RemoveAction.new(file); end
          
          ##
          # Adds a "forget" action with the given file
          #
          # @see act
          # @param [String] file the file to forget
          def forget(file); @actions << Action::ForgetAction.new(file); end
          
          ##
          # Adds a "get" action for the given file and flags.
          # This action replaces the local file with the remote file 
          # with the given name and sets its flags to the specified flag.
          def get(file, flags); @actions << Action::GetAction.new(file, flags); end
          
          ##
          # Adds a "set flags" action with the given file and flags.
          # Used when the file needs only to have its flags changed to match the
          # target action
          #
          # @see act
          # @param [String] file the file to modify
          # @param [String] flags the flags to set
          def set_flags(file, flags); @actions << Action::ExecAction.new(file, flags); end
          
          ##
          # Adds a "merge" action with all the necessary information to merge
          # the two files.
          #
          # We need the working-directory filename, the target changeset filename, the
          # final name to use (we have to pick one, if they're different). We also need
          # the flags to use at the end, and we should know if a move is going to happen.
          #
          # @param [String] file the filename in the working changeset
          # @param [String] remote_file the filename in the target changeset
          # @param [String] file_dest the filename to use after merging
          # @param [String] flags the flags to assign the file when we finish merging
          # @param [Boolean] move should we move the file?
          def merge(file, remote_file, file_dest, flags, move)
            @actions << Action::MergeAction.new(file, remote_file, file_dest, flags, move)
          end
          
          ##
          # Adds a "directory rename" action with all the necessary information to merge
          # the two files.
          #
          # We need the working-directory filename, the target changeset filename, the
          # final name to use (we have to pick one, if they're different. We also need
          # the flags to use at the end.
          #
          # This is similar to a merge, except we *don't know one of the filenames*, because
          # a directory got renamed somewhere. So either :file or :remote_file is going to
          # be nil.
          #
          # @param [String] file the filename in the working changeset
          # @param [String] remote_file the filename in the target changeset
          # @param [String] file_dest the filename to use after merging
          # @param [String] flags the flags to assign the file when we finish merging
          def directory(file, remote_file, file_dest, flags)
            @actions << Action::DirectoryAction.new(file, remote_file, file_dest, flags)
          end
          
          ##
          # Adds a "divergent rename" action to the list. This action points out
          # that the same file has been renamed to a number of different possible names.
          # This just warns the user about it - there's no way we can reliably resolve
          # this for them.
          #
          # @param [String] file the original (working directory) filename
          # @param [Array<String>] other_files the list of the names this file could
          #   actually be
          def divergent_rename(file, other_files)
            @actions << Divergent_renameAction.new(file, other_files)
          end
          
          ##
          # Raises an abort if the working changeset is actually a merge (in which case
          # we have to commit first)
          def verify_no_uncommitted_merge
            if !overwrite? && @working_changeset.parents.size > 1
              raise abort("outstanding uncommitted merges")
            end
          end
          
          ##
          # Verifies that this update is valid. This is based on
          # the type of the udpate - if it's a branch merge, we have to make
          # sure it's a valid merge. If it's a non-destructive update, we
          # have to make sure we're not doing something destructive!
          def verify_valid_update
            if branch_merge
              verify_valid_branch_merge
            elsif !overwrite?
              verify_non_destructive
            end
          end
          
          ##
          # Verifies that the update is a valid branch merge. Just raises aborts
          # when the user does something he's not supposed to.
          def verify_valid_branch_merge
            # trying to merge backwards with a direct ancestor of the current directory.
            # that's crazy.
            if ancestor == remote
              raise abort("can't merge with ancestor")
            elsif ancestor == @local_parent
              # If we're at the branch point, without a difference in branch names, just do an update. 
              # Kind of the opposite of the last case, only isntead of trying to merge directly backward,
              # we're trying to merge directly forward. That's wrong.
              if @local_parent.branch == remote.branch
                raise abort("nothing to merge (use 'amp update' or check"+
                                     " 'amp heads')")
              end
            end
            # Can't merge when you have a dirty working directory. We don't want to lose
            # those changes!
            if !force && (working_changeset.changed_files.any? || working_changeset.deleted.any?)
              raise abort("oustanding uncommitted changes")
            end
          end
          
          ##
          # Verifies that the update is non-destructive. The user is simply trying
          # to load a different revision into their working directory. No harm, no
          # foul.
          def verify_non_destructive
            # Obviously non-destructive because we have a linear path.
            return if ancestor == @local_parent || ancestor == remote
            
            # At this point, they obviously are crossing a branch.
            
            if @local_parent.branch == remote.branch
              # Here's how this work: if you want to cross a *revision history branch* (not
              # a named branch), you have to do a branch merge. So that's not allowed.
              #
              # If dirty, print a special message about your changes
              if working_changeset.changed_files.any? || working_changeset.deleted.any?
                raise abort("crosses branches (use 'hg merge' or "+
                                     "'hg update -C' to discard changes)")
              end
              # Otherwise, just let them know they can't cross branches.
              raise abort("crosses branches (use 'hg merge' or 'hg update -C')")
            elsif working_changeset.changed_files.any? || working_changeset.deleted.any?
              # They're crossing to a named branch, but have a dirty working dir. not allowed.
              raise abort("crosses named branches (use 'hg update -C'"+
                                   " to discard changes)")
            else
              # They just want to switch to a named branch. That's ok, as long as they
              # have no uncommitted changes.
              @overwrite = true
            end
          end
          
          
          ##
          # This method will make sure that there are no differences between
          # untracked files in the working directory, and tracked files in
          # the new changeset. 
          #
          # @raise [AbortError] if an untracked file in the working directory is different from
          #   a tracked file in the target changeset, this abort error will be raised.
          def check_unknown
            working_changeset.unknown.each do |file|
              if target_changeset.all_files.include?(file) && target_changeset[file].cmp(working_changeset[file].data())
                raise abort("Untracked file in the working directory differs from "+
                                     "a tracked file in the requested revision: #{file} #{target_changeset[file]}")
              end
            end
          end
          
          ##
          # This method will check if the target changeset will cause name collisions
          # when filenames are changed to all lower-case. This is important because
          # in the store, the file-logs are all changed to lower-case.
          #
          # @raise [AbortError] If two files have the same lower-case name, in 1 changeset,
          #   this error will be thrown.
          def check_collision
            target_changeset.inject({}) do |folded_names, file|
              folded = file.downcase
              if folded_names[folded]
                raise abort("Case-folding name collision between #{folded_names[folded]} and #{file}.")
              end
              folded_names[folded] = file
            end
          end
          
          ##
          # Forget removed files (docs ripped from mercurial)
          # 
          # If we're jumping between revisions (as opposed to merging), and if
          # neither the working directory nor the target rev has the file,
          # then we need to remove it from the dirstate, to prevent the
          # dirstate from listing the file when it is no longer in the
          # manifest.
          # 
          # If we're merging, and the other revision has removed a file
          # that is not present in the working directory, we need to mark it
          # as removed.
          #
          # Adds actions to our global list of actions.
          def forget_removed
            action = branch_merge ? :remove : :forget
            working_changeset.deleted.each do |file|
              act action, file unless target_changeset[file]
            end

            unless branch_merge
              working_changeset.removed.each do |file|
                forget file unless target_changeset[file]
              end
            end
          end
          
          ##
          # Should the given file be filtered out by the updater?
          #
          # @param [String] file the filename to run through the filter (if any filter)
          # @return [Boolean] should the file be filtered?
          def should_filter?(file)
            filter && !filter.call(file)
          end
          ##
          # Merge the local working changeset (local), and the target changeset (remote),
          # using the common ancestor (ancestor). Generates a merge action list to update
          # the manifest.
          #
          # @return [[String, Symbol]] A list of actions that should be taken to complete
          #   a successful transition from local to remote.
          def manifest_merge
            UI::status("resolving manifests")
            UI::debug(" overwrite #{overwrite?} partial #{filter}")
            UI::debug(" ancestor #{ancestor} local #{local} remote #{remote}")
            
            copy = calculate_copies
            copied_files = Hash.with_keys(copy.values)
            
            # Compare manifests
            working_changeset.each do |file, node|
              update_local_file file, node, copy, copied_files
            end
            
            remote.each do |file, node|
              update_remote_file file, node, copy, copied_files
            end
          end
          
          ##
          # Create an action to perform to update a file that exists in our
          # local working changeset. This will require a bit of logic, because
          # there's all kinds of specific cases we have to narrow through.
          #
          # @param [String] file the filename we have in our working directory
          # @param [String] node an identifying node ID for the file's revision
          # @param [Hash] copy the map of copies between the two changesets
          # @param [Hash] copied_files a lookup hash for checking if a file has
          #   been involved in a copy
          def update_local_file(file, node, copy, copied_files)
            return if should_filter? file
            
            # Is the file also in the target changeset?
            if remote.include? file
              update_common_file file, node
            elsif copied_files[file]
              next
            elsif copy[file]
              update_locally_copied file, copy[file]
            elsif ancestor_manifest[file]
              update_remotely_deleted file
            else
              if (overwrite? && node[20..-1] == "u")) || (backwards? && node.size <= 20)
                remove file
              end
            end
          end
          
          ##
          # Create an action to perform to update a file that exists in the remote
          # changeset. This will involve checking to see if it also exists in the
          # local changeset, because if it covers a case we've already seen, we
          # shouldn't do anything. However, by using this method, we can find
          # files that have shown up in the target branch but haven't existed
          # in the working branch.
          #
          # @param [String] file the file to inspect
          # @param [String] node the node of the file
          # @param [Hash] copy the copy map involved in the changesets
          # @param [Hash] copied_files a lookup hash for checking if a file has
          #   been involved in a copy
          def update_remote_file(file, node, copy, copied_files)
            return if should_filter?(file) || 
                      working_changeset.include?(file) ||
                      copied_files[file]
            
            if copy[file]
              # If it's been copied, then we might need to do some work.
              update_copied_remote_file file, copy
            elsif ancestor.include? file
              # If the ancestor has the file, and the target has the file, and we don't,
              # then we'll probably have to do some merging to fix that up.
              update_remotely_modified_file file, node
            else
              # Just get the god damned file
              get file, remote.flags(file)
            end
          end
          
          ##
          # Create an action to update a file in the target changeset that has been
          # copied locally. This will create some interesting scenarios.
          #
          # @param [String] file the name of the file in the target changeset
          # @param [Hash] copy the copy map which organizes copies within changesets
          def update_copied_remote_file(file, copy)
            # the remote has a file that has been copied or moved from copy[file] to file.
            # file is also destination.
            src = copy[file]
            
            # If the user doen't even have the source, then we apparently renamed a directory.
            if !(working_changeset.include?(file2))
              directory nil, file, src, remote.flags(file)
            elsif remote.include? file2
              # If the remote also has the source, then it was copied, not moved
              merge src, file, file, flag_merge(src, file, src), false
            else
              # If the source is gone, it was moved. Hence that little "true" at the end there.
              merge src, file, file, flag_merge(src, file, src), true
            end
          end
          
          def update_remotely_modified_file(file, node)
            if overwrite? || backwards?
              get file, remote.flags(file)
            elsif node != ancestor.file_node(file)
              if UI.ask("remote changed #{file} which local deleted\n" +
                        "use (c)hanged version or leave (d)eleted?") == "c"
                get file, remote.flags(file)
              end
            end
          end
          
          
          ##
          # Create an action to perform on a file that exists in both the working
          # changeset, and the remote changeset. Will only create an action if
          # we need to do something to modify the file to reach the remote state.
          #
          # @param [String] file the filename that is in both the local and remote
          #   changesets
          # @param [String] node the file node ID of the file in the local changeset
          def update_common_file(file, node)
            rflags = (overwrite? || backwards?) ? remote.flags(file) : flag_merge(file,nil,nil)
            # Are files different?
            if node != remote.file_node file
              anc_node = ancestor.file_node(file) || NULL_ID
              # are we allowed to just overwrite?
              # or are we going back in time to clean up?
              # or is the remote newer along a linear update?
              if overwrite? || (backwards? && !remote[file].cmp(local[file].data)) ||
                               (node == anc_node && remote_manifest[file] != anc_node)
                # replace the local file with the remote file
                get file, rflags
                return
              elsif node != anc_node && remote_manifest[file] != anc_node
                # are both nodes different from the ancestor?
                merge file, file, file, rflags, false
                return
              end
            end
            if local_manifest.flags[file] != rflags
              # Are the files the same, but have different flags?
              set_flags file, rflags
            end
          end
          
          ##
          # Create an action that will update a file that is not in the target
          # changeset, and has been copied locally. The idea is that if we've copied
          # this file, maybe it's in the other changeset under its old name.
          # We check that, and can create a merge if so. Otherwise, we cry deeply.
          #
          # @param [String] file the name of the file being inspected
          # @param [String] renamed_file the old name of the file
          def update_locally_copied(file, renamed_file)
            if !remote_manifest[renamed_file] 
            # directory rename (I don't know what's going on here)
            then directory file, nil, renamed_file, working_changeset.flags[file]
            # We found the old name of the file in the remote manifest.
            else merge file, renamed_file, file, flag_merge[file, renamed_file, renamed_file], false
            end
          end
          
          ##
          # Locally, we have the file. The ancestor has the file. That bastard
          # remote changeset deleted our file somewhere. What do we do?
          #
          # Well, if we've changed it since the ancestor (i.e., we've been
          # using the file actively), and we aren't allowed to overwrite files, 
          # then we should probably ask. Because that remote changeset didn't 
          # want it, but we clearly do. So ask the user.
          #
          # Otherwise, just remove it.
          #
          # @param [String] file the file in question
          # @param [String] node the file node ID of the file in the local changeset
          def update_remotely_deleted(file, node)
            # 
            if node != ancestor.file_node(file) && !overwrite?
              if UI.ask("local changed #{file} which remote deleted\n" +
                        "use (c)hanged version or (d)elete?") == "d"
              then remove file
              else add file
              end
            else
              remove file
            end
          end
          
          ##
          # Determines which files have been copied, and marks divergent renames
          #
          # @return [Array<String>] a hash mapping copied files to their new name
          def calculate_copies
            # no copies if we don't have an ancestor.
            # no copies if we're going backwards.
            # no copies if we're overwriting.
            return {} unless ancestor && !(backwards? || overwrite?)
            # no copies if the user says not to follow them.
            return {} unless @config["merge", "followcopies", Boolean, true]

            
            dirs = @config["merge", "followdirs", Boolean, false]
            # calculate dem hoes!
            copy, diverge = Amp::Graphs::Mercurial::CopyCalculator.find_copies(self, local, remote, ancestor, dirs)
            
            # act upon each divergent rename (one branch renames to one name,
            # the other branch renames to a different name)
            diverge.each {|of, fl| divergent_rename of, fl }
            
            copy
          end
          
          ##
          # Figure out what the new flags of the file should be. We need to know
          # the name of the file in all 3 important changesets, since there could
          # be moves or copies.
          #
          # @param [String] file_local the name of the file in the local changeset
          # @param [String] file_remote the name of the file in the remote changeset
          # @param [String] file_ancestor the name of the file in the ancestor changeset
          # @return [String] the flags to use for the merged file
          def flag_merge(file_local, file_remote, file_ancestor)
            file_remote = file_ancestor = file_local unless file_remote
            
            a = ancestor.flags file_ancestor
            m = working_changeset.flags file_local
            n = remote.flags file_remote
            
            # flags are identical, so no merging needed
            return m if m == n 
            
            # m and n conflict. How do we pick which one to use?
            if m.any? && n.any?
              # m and n are both flags (not empty).
              
              # if there was no ancestor flag, there's no way to guess. As the user.
              if a.empty?
                r = UI.ask("conflicting flags for #{file_local} (n)one, e(x)ec, or "+
                              "sym(l)ink?")
                return (r != "n") ? r : ''
              end
              # There is an ancestor flag, so we return whichever one differs from the
              # ancestor.
              return m == a ? n : m
            end
            
            # m or n might be set, but not both. Choose one that differs from ancestor.s
            return m if m.any? && m != a # changed from a to m
            return n if n.any? && n != a # changed from a to n
            return '' #no more flag
          end
          
          ##
          # Compare two actions in the update action list
          #
          # @param [Action] action1 the first action
          def action_cmp(action1, action2)
            return action1.to_a <=> action2.to_a if action1.is_a?(action2.class)
            return -1 if action1 === Actions::RemoveAction
            return 1  if action2 === Actions::RemoveAction
            return action1.to_a <=> action2.to_a
          end
          
          ##
          # Apply the merge action list to the working directory, in order to migrate from
          # working_changeset to target_changeset.
          #
          # @todo add path auditor
          # @param [Array<Array>] actions list of actions to take to migrate from {working_changeset} to
          #   {target_changeset}.
          # @param [WorkingDirectoryChangeset] working_changeset the current changeset in the repository
          # @param [Changeset] target_changeset the changeset we are updating the working directory to.
          # @return [Hash] Statistics about the update. Keys are:
          #   :updated => files that were changed
          #   :merged  => files that were merged
          #   :removed => files that were removed
          #   :unresolved => files that had conflicts when merging that we couldn't fix
          def apply_updates(actions, working_changeset, target_changeset)
            results = results_hash
            @repo.merge_state.reset(working_changeset.parents.first.node)
            @actions.sort! {|a1, a2| action_cmp a1, a2 }

            # If we're moving any files, we can remove renamed ones now
            remove_moved_files

            # TODO: add path auditor
            @actions.each do |action|
              next if action.file && action.file[0,1] == "/"
              action.apply(@repo, results)
            end
            
            results
          end
          
          ##
          # Returns a statistics hash: it has the keys necessary for reporting
          # the results of an update/merge. It also has a #success? method on it.
          #
          # @return [Hash] a hash prepared for reporting update/merge statistics
          def results_hash
            hash = {:updated    => [],
                    :merged     => [],
                    :removed    => [],
                    :unresolved => []}

            class << hash
              def success?; self[:unresolved].empty?; end
            end
            hash
          end
          
          ##
          # Removes all moved files in an update/merge. What happens is this:
          # if we have file A, which has been moved to the file B in our target
          # changeset, we're gonna have A lying around. We have to get rid of A.
          # That's what this method does: it finds those left over files, and
          # gets rid of them before we start doing any updates.
          def remove_moved_files
            scan_for_merges.each do |file|
              if File.amp_lexist?(@repo.working_join(file))
                UI.debug("removing #{file}")
                File.unlink(@repo.working_join(file))
              end
            end
          end
          
          ##
          # Add merges in the action list to the merge state. Also, return any
          # merge-moves, so we can process them.
          #
          # @return [Array<String>] a list of files that were both merged and moved,
          #   so we can unlink their original location
          def scan_for_merges
            moves = []
            # prescan for merges in the list of actions.
            @actions.select {|act| act.is_a? Actions::MergeAction}.each do |a|
              # destructure the list
              file, remote_file, filename_dest, flags, move = a.file, a.remote_file, a.file_dest, a.flags, a.move
              UI.debug("preserving #{file} for resolve of #{filename_dest}")
              # look up our changeset for the merge state entry
              vf_local = working_changeset[file] 
              vf_other = target_changeset[remote_file]
              vf_base  = vf_local.ancestor(vf_other) || versioned_file(file, :file_id => NULL_REV)
              # track this merge!
              merge_state.add(vf_local, vf_other, vf_base, filename_dest, flags) 

              moves << file if file != filename_dest && move
            end
            moves
          end
          
        end # class Updater
      end # module Updating
    end # module Mercurial
  end # module Repositories
end # module Amp