##
# == RepoUserManagement
# This module manages the repository-user relationships that occur.
# Information is stored in memory.
module Amp
  module Servers
    module RepoUserManagement
      module Memory
        
        ##
        # All the repositories stored in a hash.
        # @example repos['monkey'] = {:users => {String => {:user => Amp::Servers::User,
        #                                                   :read => Boolean, :write => Boolean}},
        #                             :private => Boolean}
        def repos; @repos ||= {}; @repos.default = {}; @repos; end
            
        def users; @users ||= {}; end
        
        ##
        # Adds a user to the system. This is not repository specific.
        #
        # @param [Hash] user_info The user data, in hash form. Passed to {User.from_hash}
        # @option user_info [String] :username The username for the user
        # @option user_info [String] :password The cleartext (unencrypted) password.
        def add_user(user_info={})
          new_user = User.from_hash user_info
          users[new_user.username] = new_user # universal list of users
        end
        alias_method :<<, :add_user
        
        
        ##
        # Adds a given username/password combination to the system, for a given
        # repository, with write privileges.
        #
        # @param [Repository] repository The repository to which are associating the user
        # @param [Amp::Servers::User] user The user to give write priveleges to
        def set_writer(repository, user)
          repos[repository] ||= {:users => {}, :private => false}
          repos[repository][:users][user.username] ||= {:user => user, :read => true, :write => true}
          repos[repository][:users][user.username][:read]  = true # these are unnecessary if we are adding a user
          repos[repository][:users][user.username][:write] = true
        end
        
        ##
        # Adds a given username/password combination to the system, for a given
        # repository, with read-only privileges. This will override any other settings
        # previously set. For example, a call to #set_writer and then #set_reader would
        # be as though #set_writer never happened.
        #
        # @param [Repository] repository The repository to which are associating the user
        # @param [Amp::Servers::User] user The user to give write priveleges to
        def set_reader(repository, user)
          repos[repository] ||= {:users => {}, :private => false}
          repos[repository][:users][user.username] ||= {:user => user, :read => true, :write => false}
          repos[repository][:users][user.username][:read]  = true
          repos[repository][:users][user.username][:write] = false
        end
        
        ##
        # Sets the given repository's privacy levels. Repositories default to being
        # public, and must be set to be private using this method. This method can also
        # be used to later make a private repository public without stopping the server.
        #
        # @param [Repository] repository The repository for which to set privacy settings
        # @param [Boolean] _private (true) whether the repository should be private or not
        def set_private(repository, _private=true)
          repos[repository][:private] = !!_private
        end
        
      end
      
    end
  end
end