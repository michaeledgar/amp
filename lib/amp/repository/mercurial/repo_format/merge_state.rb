module Amp
  module Merges
    module Mercurial
      
      ##
      # = MergeState
      # MergeState handles the merge/ directory in the repository, in order
      # to keep track of how well the current merge is progressing. There is
      # a file called merge/state that lists all the files that need merging
      # and a little info about whether it has beeen merged or not.
      #
      # You can add a file to the mergestate, iterate over all of them, quickly
      # look up to see if a file is still dirty, and so on.
      class MergeState
        include Enumerable
        
        ##
        # Initializes a new mergestate with the given repo, and reads in all the
        # information from merge/state.
        #
        # @param repo the repository being inspected
        def initialize(repo)
          @repo = repo
          read!
        end
        
        ##
        # Resets the merge status, by clearing all merge information and files
        # 
        # @param node the node we're working with? seems kinda useless
        def reset(node = nil)
          @state = {}
          @local = node if node
          FileUtils.rm_rf @repo.join("merge")
        end
        alias_method :reset!, :reset
        
        ##
        # Returns whether the file is part of a merge or not
        # 
        # @return [Boolean] if the dirty file in our state and not nil?
        def include?(dirty_file)
          not @state[dirty_file].nil?
        end
        
        ##
        # Accesses the the given file's merge status - can be "u" for unmerged,
        # or other stuff we haven't figured out yet.
        #
        # @param [String] dirty_file the path to the file for merging.
        # @return [String] the status as a letter - so far "u" means unmerged or "r"
        #   for resolved.
        def [](dirty_file)
          @state[dirty_file] ? @state[dirty_file][0, 1] : ""
        end
        
        ##
        # Adds a file to the mergestate, which creates a separate file
        # in the merge directory with all the information. I don't know
        # what these parameters are for yet.
        def add(fcl, fco, fca, fd, flags)
          hash = Digest::SHA1.new.update(fcl.path).hexdigest
          @repo.open("merge/#{hash}", "w") do |file|
            file.write fcl.data
          end
          @state[fd] = ["u", hash, fcl.path, fca.path, fca.file_node.hexlify,
                        fco.path, flags]
          save
        end
        
        ##
        # Iterates over all the files that are involved in the current
        # merging transaction.
        #
        # @yield each file, sorted by filename, that needs merging.
        # @yieldparam file the filename that needs (or has been) merged.
        # @yieldparam state all the information about the current merge with
        #   this file.
        def each
          @state.keys.sort.each do |key|
            yield(key, @state[key])
          end
        end
        
        ##
        # Marks the given file with a given state, which is 1 letter. "u" means
        # unmerged, "r" means resolved.
        #
        # @param [String] dirty_file the file path for marking
        # @param [String] state the state - "u" for unmerged, "r" for resolved.
        def mark(dirty_file, state)
          @state[dirty_file][0] = state
          save
        end
        
        ##
        # Resolves the given file for a merge between 2 changesets.
        #
        # @param dirty_file the path to the file for merging
        # @param working_changeset the current changeset that is the destination
        #   of the merge
        # @param other_changeset the newer changeset, which we're merging to
        def resolve(dirty_file, working_changeset, other_changeset)
          return 0 if self[dirty_file] == "r"
          state, hash, lfile, afile, anode, ofile, flags = @state[dirty_file]
          r = true
          @repo.open("merge/#{hash}") do |file|
            @repo.working_write(dirty_file, file.read, flags)
            working_file  = working_changeset[dirty_file]
            other_file    = other_changeset[ofile]
            ancestor_file = @repo.versioned_file(afile, :file_id => anode)
            r = MergeUI.file_merge(@repo, @local, lfile, working_file, other_file, ancestor_file)
          end
          
          mark(dirty_file, "r") if r.nil? || r == false
          return r
        end
        
        ##
        # Public access to writing the file.
        def save
          write!
        end
        alias_method :save!, :save
        
        private
        
        ##
        # Reads in the merge state and sets up all our instance variables.
        #
        def read!
          @state = {}
          ignore_missing_files do
            local_node = nil
            @repo.open("merge/state") do |file|
              get_node = true
              file.each_line do |line|
                if get_node
                  local_node = line.chomp
                  get_node = false
                else
                  parts = line.chomp.split("\0")
                  @state[parts[0]] = parts[1..-1]
                end
              end
              @local = local_node.unhexlify
            end
          end
        end
        
        ##
        # Saves the merge state to disk.
        #
        def write!
          @repo.open("merge/state","w") do |file|
            file.write @local.hexlify + "\n"
            @state.each do |key, val|
              file.write "#{([key] + val).join("\0")}\n"
            end
          end
        end
        
      end
    end
  end
end