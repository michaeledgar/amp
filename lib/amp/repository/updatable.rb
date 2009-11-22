module Amp
  module Repositories
    
    ##
    # This module contains all the code that makes a repository able to
    # update its working directory.
    module Updatable
      include Amp::RevlogSupport::Node
      
      ##
      # Updates the repository to the given node. One of the major operations on a repository.
      # This will update the working directory to the given node.
      #
      # @todo add lock
      # @param [String, Integer] node the revision to which we are updating the repository. Can
      #   be either a node ID or an integer.
      # @param [Boolean] branch_merge whether to merge between branches
      # @param [Boolean] force whether to force branch merging or file overwriting
      # @param [Proc, #call] partial a function to filter file lists (dirstate not updated if this
      #   is passed)
      # @return [Array<Integer>] a set of statistics about the update. In the form:
      #   [updated, merged, removed, unresolved] where each entry is the # of files in that category.
      def update(node, branch_merge=false, force=false, partial=nil)
        # debugger
        self.status(:node_1 => self.dirstate.parents.first, :node_2 => nil)
        working_changeset = self[nil]
        # tip of current branch
        node ||= branch_tags[working_changeset.branch]
        node = self.lookup("tip") if node.nil? && working_changeset.branch == "default"
        if node.nil?
          raise abort("branch #{working_changeset.branch} not found")
        end
        
        overwrite = force && !branch_merge
        parent_list = working_changeset.parents
        parent1, parent2 = parent_list.first, self[node]
        parent_ancestor = parent1.ancestor(parent2)
        
        fp1, fp2, xp1, xp2 = parent1.node, parent2.node, parent1.to_s, parent2.to_s
        fast_forward = false
        
        ## In this section, we make sure that we can actually do an update.
        ## No use starting an udpate if we can't finish!
        
        if !overwrite && parent_list.size > 1
          raise abort("outstanding uncommitted merges")
        end
        
        if branch_merge
          if parent_ancestor == parent2
            raise abort("can't merge with ancestor")
          elsif parent_ancestor == parent1
            if parent1.branch != parent2.branch
              fast_forward = true
            else
              raise abort("nothing to merge (use 'hg update' or check"+
                                   " 'hg heads')")
            end
          end
          if !force && (working_changeset.files.any? || working_changeset.deleted.any?)
            raise abort("oustanding uncommitted changes")
          end
        elsif !overwrite
          if parent_ancestor == parent1 || parent_ancestor == parent2
            # do nothing
          elsif parent1.branch == parent2.branch
            if working_changeset.files.any? || working_changeset.deleted.any?
              raise abort("crosses branches (use 'hg merge' or "+
                                   "'hg update -C' to discard changes)")
            end
            raise abort("crosses branches (use 'hg merge' or 'hg update -C')")
          elsif working_changeset.files.any? || working_changeset.deleted.any?
            raise abort("crosses named branches (use 'hg update -C'"+
                                 " to discard changes)")
          else
            overwrite = true
          end
        end
        
        ## Alright, now let's figure out exactly what we have to do to make this update.
        ## Shall we?
        
        actions = []
        check_unknown(working_changeset, parent2) if force
        check_collision(parent2) if false # case-sensitive file-system? seriously?
        
        actions += forget_removed(working_changeset, parent2, branch_merge)
        actions += manifest_merge(working_changeset, parent2, parent_ancestor, 
                                  overwrite, partial)
                                  
        ## Apply phase - apply the changes we just generated.
        unless branch_merge # just jump to the new revision
          fp1, fp2, xp1, xp2 = fp2, NULL_ID, xp2, ''
        end
        unless partial
          run_hook :preupdate, :throw => true, :parent1 => xp1, :parent2 => xp2
        end

        stats = apply_updates(actions, working_changeset, parent2)
        
        unless partial
          record_updates(actions, branch_merge)
          dirstate.parents = [fp1, fp2]
          if !branch_merge && !fast_forward
            dirstate.branch = parent2.branch
          end
          run_hook :update, :parent1 => xp1, :parent2 => xp2, :error => stats[3]
          dirstate.write
        end
        
        return stats
          
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
      
      private
      
      ##
      # This method will make sure that there are no differences between
      # untracked files in the working directory, and tracked files in
      # the new changeset. 
      #
      # @param [WorkingDirectoryChangeset] working_changeset the current working directory
      # @param [Changeset] target_changeset the destination changeset (that we're updating to)
      # @raise [AbortError] if an untracked file in the working directory is different from
      #   a tracked file in the target changeset, this abort error will be raised.
      def check_unknown(working_changeset, target_changeset)
        working_changeset.unknown.each do |file|
          if target_changeset[file] && target_changeset[file].cmp(working_changeset[file].data())
            raise abort("Untracked file in the working directory differs from "+
                                 "a tracked file in the requested revision: #{file}")
          end
        end
      end
      
      ##
      # This method will check if the target changeset will cause name collisions
      # when filenames are changed to all lower-case. This is important because
      # in the store, the file-logs are all changed to lower-case.
      #
      # @param [Changeset] target_changeset the destination changeset (that we're updating to)
      # @raise [AbortError] If two files have the same lower-case name, in 1 changeset,
      #   this error will be thrown.
      def check_collision(target_changeset)
        folded_names = {}
        target_changeset.each do |file|
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
      # @param [WorkingDirectoryChangeset] working_changeset the current working directory
      # @param [Changeset] target_changeset the destination changeset (that we're updating to)
      # @param [Boolean] branch_merge whether or not to delete working files
      # @return [[String, Symbol]] a list of actions that should be taken to complete
      #   a successful transition from working_changeset to target_changeset.
      def forget_removed(working_changeset, target_changeset, branch_merge)
        action_list = []
        action = branch_merge ? :remove : :forget
        working_changeset.deleted.each do |file|
          action_list << [file, action] unless target_changeset[file]
        end
        
        unless branch_merge
          working_changeset.removed.each do |file|
            action_list << [file, :forget] unless target_changeset[file]
          end
        end
        
        action_list
      end
      
      ##
      # Merge the local working changeset (local), and the target changeset (remote),
      # using the common ancestor (ancestor). Generates a merge action list to update
      # the manifest.
      #
      # @param [Changeset] local The working-directory changeset we're merging from
      # @param [Changeset] remote The target changeset we need to merge to
      # @param [Changeset] ancestor A common ancestor between the 2 parents
      # @param [Boolean] overwrite Can we delete working files?
      # @param [Proc] partial a function to filter file lists
      # @return [[String, Symbol]] A list of actions that should be taken to complete
      #   a successful transition from local to remote.
      def manifest_merge(local, remote, ancestor, overwrite, partial)
        UI::status("resolving manifests")
        UI::debug(" overwrite #{overwrite} partial #{partial}")
        UI::debug(" ancestor #{ancestor} local #{local} remote #{remote}")
        
        local_manifest = local.manifest
        remote_manifest = remote.manifest
        ancestor_manifest = ancestor.manifest
        backwards = (ancestor == remote)
        action_list = []
        copy, copied, diverge = {}, {}, {}
        
        flag_merge = lambda do |file_local, file_remote, file_ancestor|
          file_remote = file_ancestor = file_local unless file_remote
          
          a = ancestor_manifest.flags[file_ancestor]
          m = local_manifest.flags[file_local]
          n = remote_manifest.flags[file_remote]
          
          return m if m == n # flags are identical, we're fine
          
          if m.any? && n.any?
            unless a.any? # i'm so confused, ask the user what the flag should be!
              r = UI.ask("conflicting flags for #{file_local} (n)one, e(x)ec, or "+
                            "sym(l)ink?")
              return (r != "n") ? r : ''
            end
            return n if m == a # changed from m to n
            return m # changed from n to m
          end
          
          return m if m.any? && m != a # changed from a to m
          return n if n.any? && n != a # changed from a to n
          return '' #no more flag
        end
        
        act = lambda do |message, move, file, *args|
          UI::debug(" #{file}: #{message} -> #{move}")
          action_list << [file, move] + args
        end
        
        if ancestor && !(backwards || overwrite)
          if @config["merge", "followcopies", Boolean, true]
            dirs = @config["merge", "followdirs", Boolean, false] # don't track directory renames
            copy, diverge = Amp::Graphs::CopyCalculator.find_copies(self, local, remote, ancestor, dirs)
          end
          copied = Hash.with_keys(copy.values)
          diverge.each do |of, fl|
            act["divergent renames", :divergent_rename, of, fl]
          end
        end
        
        # Compare manifests
        local_manifest.each do |file, node|
          next if partial && !partial[file]
          
          if remote_manifest[file]
            rflags = (overwrite || backwards) ? remote_manifest.flags[file] : flag_merge[file,nil,nil]
            # Are files different?
            if node != remote_manifest[file]
              anc_node = ancestor_manifest[file] || NULL_ID
              
              if overwrite # Can we kill the file?
                act["clobbering", :get, file, rflags]
              elsif backwards # Or are we going back in time and cleaning?
                if !(node[20..-1]) || !(remote[file].cmp(local[file].data))
                  act["reverting", :get, file, rflags]
                end
              elsif node != anc_node && remote_manifest[file] != anc_node
                # are both nodes different from the ancestor?
                act["versions differ", :merge, file, file, file, rflags, false]
              elsif remote_manifest[file] != anc_node
                # is remote's version newer?
                act["remote is newer", :get, file, rflags]
              elsif local_manifest.flags[file] != rflags
                # local is newer, not overwrite, check mode bits (wtf does this mean)
                act["update permissions", :exec, file, rflags]
              end
            elsif local_manifest.flags[file] != rflags
              act["update permissions", :exec, file, rflags]
            end
          elsif copied[file]
            next
          elsif copy[file]
            file2 = copy[file]
            if !remote_manifest[file2] #directory rename
              act["remote renamed directory to #{file2}", :d, file, nil, file2, local_manifest.flags[file]]
            elsif local_manifest[file2] # case 2 A,B/B/B
              act["local copied to #{file2}", :merge, file, file2, file, 
                  flag_merge[file, file2, file2], false]
            else # case 4,21 A/B/B
              act["local moved to #{file2}", :merge, file, file2, file,
                  flag_merge[file, file2, file2], false]
            end
          elsif ancestor_manifest[file]
            if node != ancestor_manifest[file] && !overwrite
              if UI.ask("local changed #{file} which remote deleted\n" +
                        "use (c)hanged version or (d)elete?") == "d"
                act["prompt delete", :remove, file]
              else
                act["prompt keep", :add, file]
              end
            else
              act["other deleted", :remove, file]
            end
          else
            if (overwrite && node[20..-1] != "u") || (backwards && node[20..-1].empty?)
              act["remote deleted", :remove, file]
            end
          end   
        end
        
        remote_manifest.each do |file, node|
          next if partial && !(partial[file])
          next if local_manifest[file]
          next if copied[file]
          if copy[file]
            file2 = copy[file]
            if !(local_manifest[file2])
              act["local renamed directory to #{file2}", :directory, nil, file,
                  file2, remote_manifest.flags[file]]
            elsif remote_manifest[file2]
              act["remote copied to #{file}", :merge, file2, file, file,
                  flag_merge[file2, file, file2], false]
            else
              act["remote moved to #{file}", :merge, file2, file, file,
                  flag_merge[file2, file, file2], true]
            end
          elsif ancestor_manifest[file]
            if overwrite || backwards
              act["recreating", :get, file, remote_manifest.flags[file]]
            elsif node != ancestor_manifest[file]
              if UI.ask("remote changed #{file} which local deleted\n" +
                        "use (c)hanged version or leave (d)eleted?") == "c"
                act["prompt recreating", :get, file, remote_manifest.flags[file]]
              end
            end
          else
            act["remote created", :get, file, remote_manifest.flags[file]]
          end
        end
        
        action_list
      end
      
      def action_cmp(action1, action2)
        move1 = action1[1] # action out of the tuple
        move2 = action2[1] # action out of the tuple
        
        return action1 <=> action2 if move1 == move2
        return -1 if move1 == :remove
        return 1  if move2 == :remove
        return action1 <=> action2
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
        updated, merged, removed, unresolved = [], [], [], []
        merge_state.reset(working_changeset.parents.first.node)
        
        moves = []
        actions.sort! {|a1, a2| action_cmp a1, a2 }
        
        # prescan for merges in the list of actions.
        actions.each do |a|
          file, action = a[0], a[1]
          if action == :merge # ah ha! a merge.
            file2, filename_dest, flags, move = a[2..-1] # grab some info about it
            UI.debug("preserving #{file} for resolve of #{filename_dest}")
            vf_local = working_changeset[file] # look up our changesets we'll need later
            vf_other = target_changeset[file2]
            vf_base  = vf_local.ancestor(vf_other) || versioned_file(file, :file_id => NULL_REV)
            merge_state.add(vf_local, vf_other, vf_base, filename_dest, flags) # track this merge!
            
            moves << file if file != filename_dest && move
          end
        end
        
        # If we're moving any files, we can remove renamed ones now
        moves.each do |file|
          if File.amp_lexist?(working_join(file))
            UI.debug("removing #{file}")
            File.unlink(working_join(file))
          end
        end
        
        # TODO: add path auditor
        
        actions.each do |action|
          file, choice = action[0], action[1]
          next if file && file[0,1] == "/"
          case choice
          when :remove
            UI.note "removing #{file}"
            File.unlink(working_join(file))
            removed << file
          when :merge
            file2, file_dest, flags, move = action[2..-1]
            result = merge_state.resolve(file_dest, working_changeset, target_changeset)
            
            unresolved << file if result
            updated    << file if result.nil?
            merged     << file if result == false
            
            File.amp_set_executable(working_join(file_dest), flags && flags.include?('x'))
            if (file != file_dest && move && File.amp_lexist?(working_join(file)))
              UI.debug("removing #{file}")
              File.unlink(working_join(file))
            end
          when :get
            flags = action[2]
            UI.note("getting #{file}")
            data = target_changeset.get_file(file).data
            working_write(file, data, flags)
            updated << file
          when :directory
            file2, file_dest, flags = action[2..-1]
            if file && file.any?
              UI.note("moving #{file} to #{file_dest}")
              File.move(file, file_dest)
            end
            if file2 && file2.any?
              UI.note("getting #{file2} to #{file_dest}")
              data = target_changeset.get_file(file2).data
              working_write(file_dest, data, flags)
            end
            updated << file
          when :divergent_rename
            filelist = action[2]
            UI.warn("detected divergent renames of #{f} to:")
            filelist.each {|fn| UI.warn fn }
          when :exec
            flags = action[2]
            File.amp_set_executable(working_join(file), flags.include?('x'))
          end
          
        end
        
        hash = {:updated    => updated    ,
                :merged     => merged     ,
                :removed    => removed    ,
                :unresolved => unresolved }
                
        class << hash
          def success?; self[:unresolved].empty?; end
        end
        
        hash
      end
      
      ##
      # Records all the updates being made while merging to the new working directory.
      # It records them by writing to the dirstate.
      #
      # @param [Array<Array>] actions a list of actions to take
      # @param [Boolean] branch_merge is this a branch merge?
      def record_updates(actions, branch_merge)
        actions.each do |action|
          file, choice = action[0], action[1]
          case choice
          when :remove
            branch_merge and dirstate.remove(file) or dirstate.forget(file)
          when :add
            dirstate.add file unless branch_merge
          when :forget
            dirstate.forget file
          when :get
            branch_merge and dirstate.dirty(file) or dirstate.normal(file)
          when :merge
            file2, file_dest, flag, move = action[2..-1]
            if branch_merge
              dirstate.merge(file_dest)
              if file != file2 #copy/rename
                dirstate.remove file if move
                dirstate.copy(file,  file_dest) if file != file_dest
                dirstate.copy(file2, file_dest) if file == file_dest
              end
            else
              dirstate.maybe_dirty(file_dest)
              dirstate.forget(file) if move
            end
          when :directory
            file2, file_dest, flag = action[2..-1]
            next if !file2 && !(dirstate.include?(file))
            
            if branch_merge
              dirstate.add file_dest
              if file && file.any?
                dirstate.remove file
                dirstate.copy file, file_dest
              end
              dirstate.copy file2, file_dest if file2 && file2.any?
            else
              dirstate.normal file_dest
              dirstate.forget file if file && file.any?
            end
          end
        end
      end
    end
  end
end