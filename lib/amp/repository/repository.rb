module Amp
  module Repositories
    class RepoError < StandardError; end
    
    # make this git-hg-svn-cvs-whatever friendly!
    def self.pick(config, path='', create=false)
      # # Determine the repository format.
      # 
      # # This hash is formatted like:
      # # {telltale_file_or_directory => AssociatedModule}
      # mod = {'.hg' => Mercurial}.detect do |telltale, _|
      #   File.exist? File.join(path, telltale)
      # end.last # because Hash#detect returns [k, v]
      # 
      # # Raise hell if we can't get a format
      # raise "Unknown Repository Format for #{path.inspect}" unless mod
      # 
      # # Now we create the appropriate local repository
      # mod::Picker.pick config, path, create
      GenericRepoPicker.each do |picker|
        return picker.pick(config, path, create) if picker.repo_in_dir?(path)
      end
      #Mercurial::Picker.pick config, path, create # cheat KILLME
    end # def self.pick
    
  end # module Repositories
  
end # module Amp