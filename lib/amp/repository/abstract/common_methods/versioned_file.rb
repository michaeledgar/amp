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
    
    ##
    # = CommonVersionedFileMethods
    #
    # These methods are common to all repositories, and this module is mixed into
    # the AbstractLocalRepository class. This guarantees that all repositories will
    # have these methods.
    #
    # No methods should be placed into this module unless it relies on methods in the
    # general API for repositories.
    module CommonVersionedFileMethods
      
      def unified_diff_with(other_vf, opts = {})    
        Diffs::Mercurial::MercurialDiff.unified_diff(self.data, self.changeset.easy_date, 
                                                     other_vf.data, other_vf.changeset.easy_date,
                                                     self.path, other_vf.path || "/dev/null", 
                                                     false, opts)
      end
      
      ##
      # Compares two versioned files - namely, their data.
      # 
      # @param [VersionedFile] other what to compare to
      # @return [Boolean] true if the two are the same
      def ===(other)
        self.path == other.path &&
        self.data == other.data
      end
      
      # Returns if the file has been changed since its parent. Slow.
      # If your implementation has a fast way of doing this, we recommend
      # you override this method.
      #
      # @return [Boolean] has the file been changed since its parent?
      def clean?
        self === parents.first
      end
      opposite_method :dirty?, :clean?
      
      ##
      # User who committed this revision to this file
      # 
      # @return [String] the user
      def user; changeset.user; end
      
      ##
      # Date this revision to this file was committed
      # 
      # @return [DateTime]
      def date; changeset.date; end
      
      ##
      # The description of the commit that contained this file revision
      # 
      # @return [String]
      def description; changeset.description; end
      
      ##
      # The branch this tracked file belongs to
      # 
      # @return [String]
      def branch; changeset.branch; end
      
      ##
      # Working directory has no children!
      def children; []; end
    end
  end
end