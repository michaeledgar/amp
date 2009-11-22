command :archive do |c|
  c.workflow :hg
  c.desc "Create an unversioned archive of a repository revision"
  
  c.opt :"no-decode", "Do not pass files through decoders"
  c.opt :prefix     , "Directory prefix for files in archive",     :short => '-p', :type => :string
  c.opt :rev        , "Revision to distribute",                    :short => '-r', :type => :integer
  c.opt :type       , "Type of distribution to create",            :short => '-t', :type => :string
  c.opt :include    , "Include names matching the given patterns", :short => '-I', :type => :string
  c.opt :exclude    , "Exclude names matching the given patterns", :short => '-X', :type => :string
  
  c.help <<-HELP
amp archive [options]+ dest

    By default, the revision used is the parent of the working
    directory; use "-r" to specify a different revision.

    To specify the type of archive to create, use "-t". Valid
    types are:

    "files" (default): a directory full of files
    "tar": tar archive, uncompressed
    "tbz2": tar archive, compressed using bzip2
    "tgz": tar archive, compressed using gzip
    "uzip": zip archive, uncompressed
    "zip": zip archive, compressed using deflate

    The exact name of the destination archive or directory is given
    using a format string; see "hg help export" for details.

    Each member added to an archive file has a directory prefix
    prepended. Use "-p" to specify a format string for the prefix.
    The default is the basename of the archive, with suffixes removed.

    Where options are:
HELP
  c.synonyms :export, :x
  
  c.on_run do |opts, args|
    repo      = opts[:repository]
    rev       = opts[:rev]
    changeset = repo[rev]
    dest      = args.shift
    
    matcher   = Amp::Match.create(:includer => opts[:include],
                                  :excluder => opts[:exclude]) { true }
    
    
    Amp::UI::tell "created destination \"#{dest}\", now writing files"
    
    make_tar_file = lambda do |tar_dest|
      File.open(tar_dest, 'w') do |tarfile|
        Archive::Tar::Minitar::Writer.open(tarfile) do |tar|
          changeset.walk(matcher).each do |file|
            Amp::UI::tell '.' # use dots to keep track
            data = changeset.get_file(file).data
            tar.add_file_simple(File.join(File.amp_split_extension(dest).first,file), :size => data.size, :mode => 0644) { |f| f.write data }
          end
        end
      end
    end
    
    case opts[:type]
    when 'files' # a directory full of files
      FileUtils.mkdir_p dest
      Dir.chdir dest
            
      changeset.walk(matcher).each do |file|
        Amp::UI::tell '.' # use dots to keep track
        FileUtils.mkdir_p File.dirname(file) # make all the leading dirs
        File.open(file, 'w') {|f| f.write changeset.get_file(file).data } # now write the data
      end
      
    when 'tar' # tar archive, uncompressed
      make_tar_file[dest]
    when 'tbz2' # tar archive, compressed using bzip2
      # http://www.nabble.com/how-to-stream-or-write-data-into-a-tar.gz-file-as-if-the-data-were--from-files--td19498643.html
      need { '../../../../../../ext/amp/bz2/bz2' }
      
      tar_name = File.amp_split_extension(dest).first + '.tar'
      
      make_tar_file[tar_name]
      
      File.open(tar_name) do |in_tar|
        BZ2::Writer.open(dest) do |f|
          in_tar.amp_each_chunk { |chunk| Amp::UI::tell 'c'; f.write chunk }
        end
      end
      
      File.unlink(tar_name)
    when 'tgz' # tar archive, compressed using gzip
      # http://www.nabble.com/how-to-stream-or-write-data-into-a-tar.gz-file-as-if-the-data-were--from-files--td19498643.html
      require 'zlib'
      tar_name = File.amp_split_extension(dest).first + '.tar'
      
      make_tar_file[tar_name]
      
      File.open(tar_name) do |in_tar|
        Zlib::GzipWriter.open(dest) do |f|
          in_tar.amp_each_chunk { |chunk| Amp::UI::tell 'c'; f.write chunk }
        end
      end
      
      File.unlink(tar_name)
    when 'uzip' # zip archive, uncompressed
      raise "Not Yet Implemented"
    when 'zip' # zip archive, compressed using deflate
      
      # Open up the destination
      Zip::ZipFile.open dest, Zip::ZipFile::CREATE do |z|
        # For each file in the revision that matches what we want
        changeset.walk(matcher).each do |f|
          Amp::UI::tell '.' # use dots to keep track
          # create a file-spot for the file in the changeset
          # and write the data to it
          z.get_output_stream(f) {|q| q << changeset.get_file(f).data }
        end
        z.commit
      end
    else
      raise "Unknown compression type: #{opts[:type]}"
    end
    
    Amp::UI::say " revision exported!"
  end
end
