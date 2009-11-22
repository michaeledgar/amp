command :view do |c|
  c.workflow :hg
  
  c.desc "Decompresses a file (or files) at a given revision and prints its data"
  c.opt :output, "print output to file with formatted name", :type => :string
  c.opt :rev, "specify which revision to view", :type => :string
  
  c.synonym :cat # mercurial notation
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    changeset = repo[opts[:rev]] # if unspecified will give nil which gives working directory anyway
    changeset = changeset.parents.first unless opts[:rev] # parent of working dir if unspecified
    
    should_close = !!opts[:output]
    
    output_io = lambda do |filename|
      if opts[:output]
        path = opts[:output].gsub(/%s/, File.basename(filename)).gsub(/%d/, File.dirname(filename)).
                             gsub(/%p/, filename)
        File.open(path, "w")
      else
        $stdout
      end
    end
    
    args.each do |file|
      versioned_file = changeset.get_file(repo.relative_join(file))
      text           = versioned_file.data
      output         = output_io[versioned_file.repo_path]
      
      output.write text # write it exactly as is
    end
  end
end
    