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
    class RepoError < StandardError; end
    
    ##
    # Picks a repository provided a user configuration, a path, and whether
    # we have permission to create the repository.
    #
    # This is the entry point for repo-independent command dispatch.  We need
    # to know if the given repository is of a particular type. We iterate
    # over all known types, ask each type "does this path look like your kind
    # of repo?", and if it says "yes", use that type.
    #
    # Note: this does NOT handle when there are two types of repositories in
    # a given directory.
    def self.pick(config, path='', create=false)
      GenericRepoPicker.each do |picker|
        return picker.pick(config, path, create) if picker.repo_in_dir?(path)
      end
      
      # We have found... nothing
      nil
    end # def self.pick
    
  end # module Repositories
  
end # module Amp