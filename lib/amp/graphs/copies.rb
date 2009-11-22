module Amp
  module Graphs
    ##
    # = CopyCalculator
    #
    # This module manages finding what files have been copied between two
    # changesets, using a base, ancestor changeset. Closely related to merging.
    # We need this class because Mercurial, by default, allows us to copy files
    # and move files, and be smart enough to follow these copies throughout the
    # version history. Other VCS's just treat the moved file as a brand-new file.
    # Thus, when we update from one changeset to another, we need to follow
    # these copies.
    module CopyCalculator
      
      ##
      # Calculates the copies between 2 changesets, using a pre-calculated common ancestor
      # node. This is used during updates as part of Mercurial's ability to track renames
      # without git-style guessing. Unfortunately it does require some amount of calculation.
      # This method returns two hashes in an array: [renames, divergent]. "Renames" are
      # moves from one file to another, and "divergent" are two moves of the same file,
      # only with different end-names. See @example for how divergent works.
      #
      # @todo Add tracking of directory renames!
      #
      # @example
      # if the local changeset renamed "foo" to "bar", and the remote changeset renamed 
      # "foo" to "baz", then the "divergent" hash would be:
      #     {"foo" => ["bar", "baz"]}
      # 
      # @param [Repository] repo The repo for which we are calculating changes. Typically
      #   a LocalRepository.
      # @param [Changeset] changeset_local The local (or just 1 of the bases) changeset.
      # @param [Changeset] changeset_remote The remote (or the second base) changeset
      # @param [Changeset] changeset_ancestor The common ancestor between {changeset_local}
      #   and {changeset_remote}
      # @param [Boolean] check_dirs (false) Whether or not to analyze for directory renames.
      #   this is an expensive operation, so it defaults to false.
      # @return [[Hash, Hash]] This method returns two hashes in an array, where the first
      #   is a list of normal file-moves ("foo" renamed to "bar" returns {"foo" => "bar"}) 
      #   and the second is a list of divergent file-moves (see @example)
      #
      def self.find_copies(repo, changeset_local, changeset_remote, changeset_ancestor, check_dirs=false)
        # are we udpating from an empty directory? quite easy.
        if changeset_local.nil? || changeset_remote.nil? || 
           changeset_remote == changeset_local
          return {}, {}
        end
        # avoid silly behavior for parent -> working directory
        if changeset_remote.node == nil && c1.node == repo.dirstate.parents.first
          return repo.dirstate.copies, {}
        end
        
        limit = find_limit(repo, changeset_local.revision, changeset_remote.revision)
        man_local    = changeset_local.manifest
        man_remote   = changeset_remote.manifest
        man_ancestor = changeset_ancestor.manifest
        
        # gets the versioned_file for a given file and node ID
        easy_file_lookup = proc do |file, node|
          if node.size == 20
            return repo.versioned_file(file, :file_id => node) 
          end
          cs = (changeset_local.revision == nil) ? changeset_local : changeset_remote
          return cs.get_file(file)
        end
        
        ctx = easy_file_lookup
        copy = {}
        full_copy = {}
        diverge = {}
        
        # check for copies from manifest1 to manifest2
        check_copies = proc do |file, man1, man2|
          vf1 = easy_file_lookup[file, man1[file]]
          find_old_names(vf1, limit) do |old_name|
            full_copy[file] = old_name # remember for dir rename detection
            if man2[old_name] # original file in other manifest?
              # if the original file is unchanged on the other branch,
              # no merge needed
              if man2[old_name] != man_ancestor[old_name]
                vf2 = easy_file_lookup[old_file, man2[old_file]]
                vfa = vf1.ancestor(vf2)
                # related and name changed on only one side?
                if vfa && (vfa.path == file || vfa.path == vf2.path) && (vf1 == vfa || vf2 == vfa)
                  copy[file] = old_file
                end
              end
            elsif man_ancestor[old_file]
              (diverge[old_file] ||= []) << file
            end
          end
        end
        
        UI.debug("   searching for copies back to rev #{limit}")
        
        unmatched_1 = double_intersection(man_local, man_remote, man_ancestor)
        unmatched_2 = double_intersection(man_remote, man_local, man_ancestor)
        
        UI.debug("   unmatched files in local:\n #{unmatched_1.join("\n")}") if unmatched_1.any?
        UI.debug("   unmatched files in other:\n #{unmatched_2.join("\n")}") if unmatched_2.any?
        
        unmatched_1.each {|file| check_copies[file, man_local, man_remote] }
        unmatched_2.each {|file| check_copies[file, man_remote, man_local] }
        
        diverge_2 = {}
        diverge.each do |old_file, file_list|
          if file_list.size == 1
            diverge.delete old_file 
          else
            file_list.each {|file| diverge_2[file] = true}
          end
        end
        
        if !(full_copy.any?) || !check_dirs
          return copy, diverge
        end
        
        # CHECK FOR DIRECTORY RENAMES
        # TODO TODO TODO
      end
      
      private
      
      ##
      # Find the earliest revision in the repository that is an ancestor of EITHER a OR b,
      # but NOT both. In other words, find the oldest ancestor on a branch.
      #
      # @param [Repository] repo the repository we're calculatizing on
      # @param [Integer] a one changeset's revision #
      # @param [Integer] b the other changeset's revision #
      # @return [Integer] the earliest revision index that is an ancestor of only 1 of the
      #   two changesets.
      def self.find_limit(repo, a, b)
        # basic idea:
        # - mark a and b with different sides
        # - if a parent's children are all on the same side, the parent is
        #   on that side, otherwise it is on no side
        # - walk the graph in topological order with the help of a heap;
        #   - add unseen parents to side map
        #   - clear side of any parent that has children on different sides
        #   - track number of interesting revs that might still be on a side
        #   - track the lowest interesting rev seen
        #   - quit when interesting revs is zero
        changelog = repo.changelog
        working = changelog.size # this revision index is 1 higher than the real highest
        a ||= working
        b ||= working
        
        side = {a => -1, b => 1}
        visit = PriorityQueue.new # because i don't have any other data structure that
        visit[-a] = -a            # maintains a sorted order
        visit[-b] = -b
        interesting = visit.size  # could be 1 if a == b
        limit = working
        while interesting > 0
          r, junk = -(visit.delete_min) # get the next lowest revision
          if r == working
            # different way of getting parents in this case
            parents = repo.dirstate.parents.map {|p| changelog.rev(p)} 
          else
            # normal way of getting parents
            parents = changelog.parent_indices_for_index(r)
          end
          parents.each do |parent|
            if !side[parent] 
              # haven't seen the parent before, so let's put it on a side.
              side[parent] = side[r]
              interesting += 1 if side[parent] != 0 # if it's on a side
              visit[-parent] = -parent
            elsif side[parent] && side[parent] != side[r]
              # if we're here, then the parent has been seen by BOTH sides. so it's no good.
              side[parent] = 0
              interesting -= 1
            end
          end
          # if we're here and side[r] isn't 0, then it's an ancestor to [one and only one]
          # of the 2 root nodes. so keep it.
          if side[r] && side[r] != 0
            limit = r
            interesting -= 1
          end
        end
        limit
      end
      
      ##
      # Go back in time until revision {limit}, grabbing old names that {versioned_file}
      # was moved from.
      #
      # @param [VersionedFile] versioned_file the file for which we are finding old names
      # @param [Integer] limit the minimum revision back in time in which we should 
      #   search for old names
      # @return [Array<String>] old names for the current file.
      def self.find_old_names(versioned_file, limit)
        # wooooo recursion unrolling!
        old  = {}
        seen = {}
        orig = versioned_file.path
        visit = [[versioned_file, 0]]
        while visit.any? do
          file, depth = visit.shift
          str = file.to_s
          next if seen[str]
          
          seen[str] = true
          if file.path != orig && !old[file.path]
            old[file.path] = [depth, file.path]
          end
          next if file.revision < limit && file.revision != nil
          visit += file.parents.each {|p| [p, depth - 1]}
        end
        old.values.sort.map {|o| o[1]}
      end
      
      ##
      # Returns all the parent directories of every file in the provided array,
      # recursively, as a map. Each entry maps a directory to {true}. It's really
      # just a set, but I'm too lazy to use a set. Sorry.
      #
      # @param [Array<String>] files a list of files for which we need all the parent
      #   directories
      # @return [Hash] a map: each entry maps a directory name to {true}, because it's
      #   really just a set, because I'm too lazy to use a set.
      def self.all_parent_dirs(files)
        dirs = {}
        files.each do |file|
          file = picky_dirname file
          until dirs[file]
            dirs[file] = true
            file = picky_dirname file
          end
        end
        dirs
      end
      
      ##
      # This method will find the path of the containing directory for the file
      # pointed to by {path}. We use this instead of File.dirname because we
      # want to return the empty string instead of "." if there is no path separator
      # in the provided string.
      #
      # @param [String] path the path to the file we want the directory name of
      # @return [String] the path of the containing directory of the provided file
      def self.picky_dirname(path)
        Dir.dirname path
      end
      
      ##
      # Returns a list of elements in d1 that are not in d2 or d3. We have this method
      # because Mercurial's source has this method.
      #
      # @param [Array] d1 a list of items we wish to filter
      # @param [Array] d2 a list of items we do NOT want in d1
      # @param [Array] d3 a list of items we do NOT want in d1
      # @return [Array] a list of items in d1 that are not present in d2 or d3
      def self.double_intersection(d1, d2, d3)
        d1.reject {|i| d2.include?(i) || d3.include?(i) }
      end
    end
  end
end
