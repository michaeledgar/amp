module Amp
  module Repositories
    module Mercurial
      
      ##
      # This module adds verification to Mercurial repositories.
      #
      # The main public method provided is #verify. The rest are support methods that
      # will keep to themselves.
      #
      # This is directly ported from verify.py from the Mercurial source. This is for
      # the simple reason that, because we are re-implementing Mercurial, we should
      # rely on their verification over our own. If we discover bugs in their
      # verification, we'll patch them and send in the patches to selenic, but for now, we'll
      # trust that theirs is on the money.
      module Verification
        
        ##
        # Runs a verification sweep on the repository.
        #
        # @return [VerificationResult] the results of the verification, which
        #   includes error messages, warning counts, and so on.
        def verify
          result = Verifier.new(self).verify
        end
        
        ##
        # Handles all logic for verifying a single repository and collecting the results.
        #
        # Public interface: initialize with a repository and run #verify.
        class Verifier
          attr_accessor :repository
          alias_method :repo, :repository
          
          attr_reader :changelog, :manifest
          
          ##
          # Creates a new Verifier. The Verifier can verify a Mercurial repository.
          # 
          # @param [Repository] repo the repository this verifier will examine
          def initialize(repo)
            @repository = repo
            @result = VerificationResult.new(0, 0, 0, 0, 0)
            
            @bad_revisions = {}
            @changelog = repo.changelog
            @manifest  = repo.manifest
          end
          
          ##
          # Runs a verification sweep on the repository this verifier is handling.
          #
          # @return [VerificationResult] the results of the verification, which
          #   includes error messages, warning counts, and so on.
          def verify
            # Maps manifest node IDs to the link revision to which they belong
            manifest_linkrevs = Hash.new {|h,k| h[k] = []}
            
            # Maps filenames to a list of link revisions (global revision #s) in which
            # that file was changed
            file_linkrevs = Hash.new {|h, k| h[k] = []}
            
            # file_node_ids stores a hash for each file. The hash stored maps that file's node IDs
            # (the node stored in the file log itself) to the global "link revision index" - the
            # revision index in the changelog (and the one the user always sees)
            file_node_ids = Hash.new {|h, k| h[k] = {}}
            
            verify_changelog(manifest_linkrevs, file_linkrevs)
            verify_manifest(manifest_linkrevs,  file_node_ids)
            verify_crosscheck(manifest_linkrevs, file_linkrevs, file_node_ids)
            UI.status("checking files")
            store_files = verify_store
            verify_files(file_linkrevs, file_node_ids, store_files)
            @result
          end
          
          ##
          # Verifies the changelog. Updates acceptable file_linkrevs and manifest_linkrevs
          # along the way, since the changelog knows which files have been changed when,
          # and which manifest entries go with which changelog entries.
          #
          # @param [Hash] manifest_linkrevs the mapping between manifest node IDs and changelog
          #   revision numbers
          # @param [Hash] file_linkrevs a mapping between filenames and a list of changelog
          #   revision numbers where the file was modified, added, or deleted.
          def verify_changelog(manifest_linkrevs, file_linkrevs)
            Amp::UI.status("checking changelog...")
            check_revlog(@changelog, "changelog")
            seen = {}
            # can't use the nice #each because it assumes functioning changelog and whatnot
            @changelog.size.times do |idx|
              node = @changelog.node_id_for_index idx
              check_entry(@changelog, idx, node, seen, [idx], "changelog")
              begin
                changelog_entry = @changelog.read(node)
                manifest_linkrevs[changelog_entry.first] << idx
                changelog_entry[3].each {|f| file_linkrevs[f] << idx}
              rescue Exception => err
                exception(idx, "unpacking changeset #{node.short_hex}:", err, "changelog")
              end
            end
            @result.changesets = @changelog.size
          end
          
          ##
          # Verifies the manifest and its nodes. Also updates file_node_ids to store the
          # node ID of files at given points in the manifest's history.
          #
          # @param [Hash] manifest_linkrevs the mapping between manifest node IDs and changelog
          #   revision numbers
          # @param [Hash] file_node_ids maps filenames to a mapping from file node IDs to global
          #   link revisions.
          def verify_manifest(manifest_linkrevs, file_node_ids)
            Amp::UI.status("checking manifests...")
            check_revlog(@manifest, "manifest")
            seen = {}
            
            @manifest.size.times do |idx|
              node = @manifest.node_id_for_index idx
              link_rev = check_entry(@manifest, idx, node, seen, manifest_linkrevs[node], "manifest")
              manifest_linkrevs.delete node
              
              begin
                @manifest.read_delta(node).each do |filename, file_node|
                  if filename.empty?
                    error(link_rev, "file without name in manifest")
                  elsif filename != "/dev/null"
                    file_node_map = file_node_ids[filename]
                    file_node_map[file_node] ||= idx
                  end
                end
              rescue Exception => err
                exception(idx, "reading manfiest delta #{node.short_hex}", err, "manifest")
              end
            end
          end
          
          ##
          # Crosschecks the changelog agains the manifest and vice-versa. There should be no
          # remaining unmatched manifest node IDs, nor any files not in file_node_map.
          # A few other checks, too.
          #
          # @param [Hash] manifest_linkrevs the mapping between manifest node IDs and changelog
          #   revision numbers
          # @param [Hash] file_linkrevs a mapping between filenames and a list of changelog
          #   revision numbers where the file was modified, added, or deleted.
          # @param [Hash] file_node_ids maps filenames to a mapping from file node IDs to global
          #   link revisions.
          def verify_crosscheck(manifest_linkrevs, file_linkrevs, file_node_ids)
            Amp::UI.status("crosschecking files in changesets and manifests")
            
            # Check for node IDs found in the changelog, but not the manifest
            if @manifest.any?
              # check for any manifest node IDs we found in changesets, but not in the manifest
              manifest_linkrevs.map {|node, idx| [idx, node]}.sort.each do |idx, node|
                error(idx, "changeset refers to unknown manifest #{node.short_hex}")
              end
              
              # check for any file node IDs we found in the changeset, but not in the manifest
              file_linkrevs.sort.each do |file, _|
                if file_node_ids[file].empty?
                  error(file_linkrevs[file].first, "in changeset but not in manifest", file)
                end
              end
            end
            
            # Check for node IDs found in the manifest, but not the changelog.
            if @changelog.any?
              file_node_ids.map {|file,_| file}.sort.each do |file|
                unless file_linkrevs[file]
                  begin
                    filelog = @repository.file(file)
                    link_rev = file_node_ids[file].map {|node| filelog.link_revision_for_index(filelog.revision_index_for_node(node))}.min
                  rescue
                    link_rev = nil
                  end
                  error(link_rev, "in manifest but not in changeset", file)
                end
              end
            end
          end
          
          ##
          # Verifies the store, and returns a hash with names of files that are OK
          #
          # @return [Hash<String => Boolean>] a hash with filenames as keys and "true" or "false"
          #   as values, indicating whether the file exists and is accessible
          def verify_store
            store_files = {}
            @repository.store.datafiles.each do |file, encoded_filename, size|
              if file.nil? || file.empty?
                error(nil, "can't decode filename from store: #{encoded_filename}")
              elsif size > 0
                store_files[file] = true
              end
            end
            store_files
          end
          
          ##
          # Verifies the individual file logs one by one.
          #
          # @param [Hash] file_linkrevs a mapping between filenames and a list of changelog
          #   revision numbers where the file was modified, added, or deleted.
          # @param [Hash] file_node_ids maps filenames to a mapping from file node IDs to global
          #   link revisions.
          # @param [Hash] store_files a mapping keeping track of which file logs are in the store
          def verify_files(file_linkrevs, file_node_ids, store_files)
            files = (file_node_ids.keys + file_linkrevs.keys).uniq.sort
            @result.files = files.size
            files.each do |file|
              link_rev = file_linkrevs[file].first
              
              begin
                file_log = @repository.file(file) 
              rescue Exception => err
                error(link_rev, "broken revlog! (#{err})", file)
                next
              end
              
              file_log.files.each do |ff|
                unless store_files.delete(ff)
                  error(link_rev, "missing revlog!", ff)
                end
              end
              
              verify_filelog(file, file_log, file_linkrevs, file_node_ids)
            end
          end
          
          ##
          # Verifies a single file log. This is a complicated process - we need to cross-
          # check a lot of data, which is why this has been extracted into its own method.
          #
          # @param [String] filename the name of the file we're verifying
          # @param [FileLog] file_log the file log we're verifying
          # @param [Hash] file_linkrevs a mapping between filenames and a list of changelog
          #   revision numbers where the file was modified, added, or deleted.
          # @param [Hash] file_node_ids maps filenames to a mapping from file node IDs to global
          #   link revisions.
          def verify_filelog(file, file_log, file_linkrevs, file_node_ids)
            check_revlog(file_log, file)
            seen = {}
            file_log.index_size.times do |idx|
              @result.revisions += 1
              node = file_log.node_id_for_index(idx)
              link_rev = check_entry(file_log, idx, node, seen, file_linkrevs[file], file)
              
              # Make sure that one of the manifests referenced the node ID. If not, one of our
              # manifests is wrong!
              if file_node_ids[file]
                if @manifest.any? && !file_node_ids[file][node]
                  error(link_rev, "#{node.short_hex} not found in manifests", file)
                else
                  file_node_ids[file].delete node
                end
              end
              
              # Make sure the size of the uncompressed file is correct.
              begin
                text = file_log.read node
                rename_info = file_log.renamed? node
                if text.size != file_log.uncompressed_size_for_index(idx)
                  if file_log.decompress_revision(node).size != file_log.uncompressed_size_for_index(idx)
                    error(link_rev, "unpacked size is #{text.size}, #{file_log.size(idx)} expected", file)
                  end
                end
              rescue Exception => err
                exception(link_rev, "unpacking #{node.short_hex}", err, file)
              end
              
              # Check if we screwed up renaming a file (like lost the source revlog or something)
              begin
                if rename_info && rename_info.any?
                  filelog_src = @repository.file(rename_info.first)
                  if filelog_src.index_size == 0
                    error(link_rev, "empty or missing copy source revlog "+
                                    "#{rename_info[0]}, #{rename_info[1].short_hex}", file)
                  elsif rename_info[1] == RevlogSupport::Node::NULL_ID
                    warn("#{file}@#{link_rev}: copy source revision is NULL_ID "+
                         "#{rename_info[0]}:#{rename_info[1].short_hex}", file)
                  else
                    rev = filelog_src.revision_index_for_node(rename_info[1])
                  end
                end
              rescue Exception => err
                exception(link_rev, "checking rename of #{node.short_hex}", err, file)
              end
            end
            
            # Final cross-check
            if file_node_ids[file] && file_node_ids[file].any?
              file_node_ids[file].map { |node, link_rev| 
                [@manifest.link_revision_for_index(link_rev), node]
              }.sort.each do |link_rev, node|
                error(link_rev, "#{node.short_hex} in manifests not found", file)
              end
            end
          end
          
          private
          
          ##
          # Checks a revlog for inconsistencies with the main format, such as
          # having trailing bytes or incorrect formats
          #
          # @param [Revlog] log the log we will be verifying
          # @param [String] name the name of the file this log is stored in
          def check_revlog(log, name)
            #p name
            if log.empty? && (@changelog.any? || @revlog.any?)
              return error(0, "#{name} is empty or missing")
            end
            
            size_diffs = log.checksize
            # checksize returns a hash with these keys: index_diff, data_diff
            if size_diffs[:data_diff] != 0
              error(nil, "data size off by #{size_diffs[:data_diff]} bytes", name) 
            end
            if size_diffs[:index_diff] != 0
              error(nil, "index off by #{size_diffs[:index_diff]} bytes", name)
            end
            
            v0 = RevlogSupport::Support::REVLOG_VERSION_0
            if log.index.version != v0
              warn("#{name} uses revlog format 1. changelog uses format 0.") if @changelog.index.version == v0
            elsif log.index.version == v0
              warn("#{name} uses revlog format 0. that's really old.")
            end
          end
          
          ##
          # Checks a single entry in a revision log for inconsistencies.
          #
          # @param [Revlog] log the revision log we're examining
          # @param [Fixnum] revision the index # of the revision being examined
          # @param [String] node the node ID of the revision being examined
          # @param [Hash] seen the list of node IDs we've already seen
          # @param [Array] ok_link_revisions the acceptable link revisions for the given entry
          # @param [String] filename the name of the file containing the revlog
          def check_entry(log, revision, node, seen, ok_link_revisions, filename)
            link_rev = log.link_revision_for_index log.revision_index_for_node(node)
            # is the link_revision invalid?
            if link_rev < 0 || (changelog.any? && ! ok_link_revisions.include?(link_rev))
              problem = (link_rev < 0 || link_rev >= changelog.size) ? "nonexistent" : "unexpected"
              error(nil, "revision #{revision} points to #{problem} changeset #{link_rev}", filename)
              
              if ok_link_revisions.any?
                warn("(expected #{ok_link_revisions.join(" ")})")
              end
              link_rev = nil # don't use this link_revision, because it's clearly wrong.
            end
            
            begin
              log.parents_for_node(node).each do |parent|
                if !seen[parent] && parent != RevlogSupport::Node::NULL_ID
                  error(link_rev, "unknown parent #{parent.short_hex} of #{node.short_hex}", filename)
                end
              end
            rescue StandardError => e 
              # TODO: do real exception handling
              exception(link_rev, "error checking parents of #{node.short_hex}: ", e, filename)
            end
            
            if seen[node]
              error(link_rev, "duplicate revision #{revision} (#{seen[node]})", filename)
            end
            seen[node] = revision
            return link_rev
          end
          
          ##
          # Produce an error based on an exception. Matches mercurial's.
          #
          # @param [Fixnum] revision the link-revision the error is associated with
          # @param [String, #to_s] message the message to print with the error
          # @param [Exception] exception the exception that raised this error
          # @param [String, #to_s] filename (nil) the name of the file with an error.
          #     nil for changelog/manifest
          def exception(revision, message, exception, filename)
            if exception.kind_of?(Interrupt)
              UI.warn("interrupted")
              raise
            end
            error(revision, "#{message} #{exception}\n", filename)
          end
          
          ##
          # Produce an error that looks like Mercurial's
          # meh compatibility makes me sad
          #
          # @param [Fixnum] revision the link-revision the error is associated with
          # @param [String, #to_s] message the message to print with the error
          # @param [String, #to_s] filename (nil) the name of the file with an error.
          #     nil for changelog/manifest
          def error(revision, message, filename = nil)
            if revision
              @bad_revisions[revision] = true
            else
              revision = "?"
            end
            new_message = "#{revision}: #{message}"
            new_message = "#{filename}@#{new_message}" if filename
            UI.say new_message
            @result.errors += 1
          end
          
          ##
          # Adds a warning to the results
          #
          # @param [String, #to_s] message the user's warning
          def warn(message)
            UI.say "warning: #{message}"
            @result.warnings += 1
          end
        end
        
        ##
        # Simple struct that handles the results of a verification.
        class VerificationResult < Struct.new(:warnings, :errors, :revisions, :files, :changesets)
          def initialize(*args)
            super(*args)
            @warnings   = 0
            @errors     = 0
            @revisions  = 0
            @files      = 0
            @changesets = 0
          end
        end
        
      end
    end
  end
end