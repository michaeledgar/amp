module Amp
  module Repositories
    module Mercurial
      
      ##
      # = BundleRepository
      # This class represents a read-only repository that combines both local
      # repository data with a bundle file. The bundle file contains un-merged-in
      # changesets - this is useful for, say, previewing the results of a pull
      # action.
      #
      # A bundle is stored in the following manner:
      #  - Changelog entries
      #  - Manifest  entries
      #  - Modified File entry #1
      #  - Modified File entry #2
      #  - ...
      #  - Modified file entry #N
      class BundleRepository < LocalRepository
        def initialize(path="", config=nil, bundle_name="")
          @temp_parent = nil
          # Figure out what to do here - if there's no current local repository, that
          # takes some special work.
          begin
            super(path, false, config) # don't create, just look for a repository
          rescue
            # Ok, no local repository. Let's make one really quickly.
            @temp_parent = File.join(Dir.tmpdir, File.amp_make_tmpname("bundlerepo"))
            File.mkdir(@temp_parent)
            tmprepo = LocalRepository.new(@temp_parent, true, config) # true -> create
            super(@temp_parent, false, config) # and proceed as scheduled!
          end
          
          # Set up our URL variable, if anyone asks us what it is
          if path
            @url = "bundle:#{path}+#{bundle_name}"
          else
            @url = "bundle:#{bundle_name}"
          end
          
          @temp_file = nil
          @bundle_file = File.open(bundle_name, "r")
          
          @bundle_file.seek(0, IO::SEEK_END)
          Amp::UI.debug "Bundle File Size: #{@bundle_file.tell}"
          @bundle_file.seek(0, IO::SEEK_SET)
          
          # OK, now for the fun part - check the header to see if we're compressed.
          header = @bundle_file.read(6)
          # And switch based on that header
          if !header.start_with?("HG")
            # Not even an HG file. FML. Bail
            raise abort("#{bundle_name}: not a Mercurial bundle file")
          elsif not header.start_with?("HG10")
            # Not a version we understand, bail
            raise abort("#{bundle_name}: unknown bundle version")
          elsif header == "HG10BZ" || header == "HG10GZ"
            # Compressed! We'll have to save to a new file, because this could get messy.
            temp_file = Tempfile.new("hg-bundle-hg10un", @root)
            @temp_file_path = temp_file.path
            # Are we BZip, or GZip?
            case header
            when "HG10BZ"
              # fuck BZip. Seriously.
              headerio = StringIO.new "BZ", (ruby_19? ? "w+:ASCII-8BIT" : "w+")
              input = Amp::Support::MultiIO.new(headerio, @bundle_file)
              decomp = BZ2::Reader.new(input)
            when "HG10GZ"
              # Gzip is much nicer.
              decomp = Zlib::GzipReader.new(@bundle_file)
            end
            
            # We're writing this in an uncompressed fashion, of course.
            @temp_file.write("HG10UN")
            # While we can uncompressed....
            while !r.eof? do
              # Write the uncompressed data to our new file!
              @temp_file.write decomp.read(4096)
            end
            # and close 'er up
            @temp_file.close
            
            # Close the compressed bundle file
            @bundle_file.close
            # And re-open the uncompressed bundle file!
            @bundle_file = File.open(@temp_file_path, "r")
            # Skip the header.
            @bundle_file.seek(6)
          elsif header == "HG10UN"
            # uncompressed, do nothing
          else
            # We have no idae what's going on
            raise abort("#{bundle_name}: unknown bundle compression type")
          end
          # This hash stores pairs of {filename => position_in_bundle_file_of_this_file} 
          @bundle_files_positions = {}
        end
        
        ##
        # Gets the changelog of the repository. This is different from {LocalRepository#changelog}
        # in that it uses a {BundleChangeLog}. Also, since the manifest is stored in the bundle
        # directly after the changelog, by checking our position in the bundle file, we can save
        # where the bundle_file is stored.
        #
        # @return [BundleChangeLog] the changelog for this repository.
        def changelog
          @changelog      ||= Bundles::BundleChangeLog.new(@store.opener, @bundle_file)
          @manifest_start ||= @bundle_file.tell
          @changelog
        end
        
        ##
        # Gets the manifest of the repository. This is different from {LocalRepository#manifest}
        # in that it uses a {BundleManifest}. The file logs are stored in the bundle directly
        # after the manifest, so once we load the manifest, we save where the file logs start
        # when we are done loading the manifest.
        #
        # This has the side-effect of loading the changelog, if it hasn't been loaded already -#
        # this is necessary because the manifest changesets are stored after the changelog changesets,
        # and we must fully load the changelog changesets to know where to look for the manifest changesets.
        #
        # Don't look at me, I didn't design the file format.
        #
        # @return [BundleChangeLog] the changelog for this repository.
        def manifest
          return @manifest if @manifest
          @bundle_file.seek manifest_start
          @manifest   ||= Bundles::BundleManifest.new @store.opener, @bundle_file, proc {|n| changelog.rev(n) }
          @file_start ||= @bundle_file.tell
          @manifest
        end
        
        ##
        # Returns the position in the bundle file where the manifest changesets are located.
        # This involves loading the changelog first - see {#manifest}
        #
        # @return [Integer] the position in the bundle file where we can find the manifest
        #   changesets.
        def manifest_start
          changelog && @manifest_start
        end
        
        ##
        # Returns the position in the bundle file where the file log changesets are located.
        # This involves loading the changelog and the manifest first - see {#manifest}.
        #
        # @return [Integer] the position in the bundle file where we can find the file-log
        #   changesets.
        def file_start
          manifest && @file_start
        end
        
        ##
        # Gets the file-log for the given path, so we can look at an individual
        # file's history, for example. However, we need to be cognizant of files that
        # traverse the local repository's history as well as the bundle file.
        # 
        # @param [String] f the path to the file
        # @return [FileLog] a filelog (a type of revision log) for the given file
        def file(filename)
          
          # Load the file-log positions now - we didn't do this in the constructor for a reason
          # (if they don't ask for them, don't load them!)
          if @bundle_files_positions.empty?
            # Jump to the file position
            @bundle_file.seek file_start
            while true
              # get a changegroup chunk - it'll be the filename
              chunk = RevlogSupport::ChangeGroup.get_chunk @bundle_file
              # no filename? bail
              break if chunk.nil? || chunk.empty?
              
              # Now that we've read the filename, we're at the start of the changelogs for that
              # file. So let's save this position for later.
              @bundle_files_positions[chunk] = @bundle_file.tell
              # Then read chunks until we get to the next file!
              RevlogSupport::ChangeGroup.each_chunk(@bundle_file) {|c|}
            end
          end
          
          # Remove leading slash
          filename = filename.shift("/")
          
          # Does this file cross local history as well as the bundle?
          if @bundle_files_positions[filename]
            # If so, we'll need to make a BundleFileLog. Meh. 
            @bundle_file.seek @bundle_files_positions[filename]
            Bundles::BundleFileLog.new @store.opener, filename, @bundle_file, proc {|n| changelog.rev(n) }
          else
            # Nope? Make a normal FileLog!
            FileLog.new(@store.opener, filename)
          end
        end  
        
        ##
        # Gets the URL for this repository - unused, I believe.
        #
        # @return [String] the URL for the repository
        def url; @url; end
        
        ##
        # Closes the repository - in this case, it closes the bundle_file. Analogous to closing
        # an SSHRepository's socket.
        def close
          @bundle_file.close
        end
        
        # We can't copy files. Read-only.
        def can_copy?; false; end
        # Gets the current working directory. Not sure why we need this.
        def get_cwd; Dir.pwd; end
        
      end
    end
  end
end