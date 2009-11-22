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
      
      module Sequel
        
        def self.extended(klass)
          require 'sequel'
          
          # Set up the database
          # Oh gods please have mercy on my soul
          const_set 'DB', Sequel.sqlite("amp_serve_#{klass.user_db_name}.db")
          
          DB.create_table :users do
            primary_key :id
            String :username, :unique => true, :null => false
            String :password, :null => false
          end
          
          DB.create_table :repos do
            primary_key :id
            String  :url,     :unique => true, :null => false
            String  :path,    :null => false
            boolean :private, :default => false
          end
          
          DB.create_table :permissions do
            foreign_key :repo_id, :repos
            foreign_key :user_id, :users
            boolean     :read
            boolean     :write
          end
          
          # find room in your heart to forgive me
          # constants can't be assigned to in a method
          const_set 'USERS', DB[:users]
          const_set 'REPOS', DB[:repos]
          const_set 'PERMS', DB[:permissions]
        end
        
        ##
        # All the repositories stored in a hash.
        # 
        # @todo slow as fuck
        # @example repos['monkey'] = {:users => {String => {:user => Amp::Servers::User,
        #                                                   :read => Boolean, :write => Boolean}},
        #                             :private => Boolean}
        def repos
          REPOS.inject({}) do |h, v|
            uss = PERMS[:repo_id => v[:id]]
            q = uss.map do |p|
              {:user => USERS[:user_id => p[:user_id]],
               :read => p[:read], :write => p[:write] }
            end
            z = q.inject({}) {|h, v| h.merge v[:user][:username] => v }
            
            h.merge v[:url] => {:users => z, :private => v[:private]}
          end
        end
            
        def users
          USERS.inject({}) do |s, v|
            s.merge v[:username] => v
          end
        end
                
        ##
        # Adds a user to the system. This is not repository specific.
        #
        # @param [Hash] user_info The user data, in hash form. Passed to {User.from_hash}
        # @option user_info [String] :username The username for the user
        # @option user_info [String] :password The cleartext (unencrypted) password.
        def add_user(user_info={})
          USERS << user_info
        end
        alias_method :<<, :add_user
        
        ##
        # Adds a given username/password combination to the system, for a given
        # repository, with write privileges.
        #
        # @todo don't know if this actually works
        # @param [Repository] repository The repository to which are associating the user
        # @param [Amp::Servers::User] user The user to give write priveleges to
        def set_writer(repository, user)
          perm = PERMS.filter 'repo_id = ? and user_id = ?', REPOS.first(:url => repository).id, user[:id]
          perm.update :read  => true
          perm.update :write => true
        end
        
        ##
        # Adds a given username/password combination to the system, for a given
        # repository, with read-only privileges. This will override any other settings
        # previously set. For example, a call to #set_writer and then #set_reader would
        # be as though #set_writer never happened.
        # 
        # @todo don't know if this actually works
        # @param [Repository] repository The repository to which are associating the user
        # @param [Amp::Servers::User] user The user to give write priveleges to
        def set_reader(repository, user)
          perm = PERMS.filter 'repo_id = ? and user_id = ?', REPOS.first(:url => repository).id, user[:id]
          perm.update :read  => true
          perm.update :write => false
        end
        
        ##
        # Sets the given repository's privacy levels. Repositories default to being
        # public, and must be set to be private using this method. This method can also
        # be used to later make a private repository public without stopping the server.
        #
        # @todo don't know if this actually works
        # @param [Repository] repository The repository for which to set privacy settings
        # @param [Boolean] _private (true) whether the repository should be private or not
        def set_private(repository, _private=true)
          REPOS[:url => repository] = {:private => true}
        end
        
      end
      
      module DataMapper
        
        def self.extended(klass)
          require 'dm-core'
          
          users = Class.new do
            include DataMapper::Resource
            property :username, String
            property :password, String
            
            has n, :perms
          end
          const_set 'User', users
          
          perms = Class.new do
            include DataMapper::Resource
            property :read
            property :write
            
            belongs_to :user
            belongs_to :repo
          end
          const_set 'Perm', perms
          
          repo = Class.new do
            include DataMapper::Resource
            property :url,  String
            property :path, String
            
            has n, :perms
          end
          const_set 'Repo', repo
        end
        
        ##
        # All the repositories stored in a hash.
        # 
        # @todo slow as fuck
        # @example repos['monkey'] = {:users => {String => {:user => Amp::Servers::User,
        #                                                   :read => Boolean, :write => Boolean}},
        #                             :private => Boolean}
        def repos
          
        end
            
        def users
          
        end
                
        ##
        # Adds a user to the system. This is not repository specific.
        #
        # @param [Hash] user_info The user data, in hash form. Passed to {User.from_hash}
        # @option user_info [String] :username The username for the user
        # @option user_info [String] :password The cleartext (unencrypted) password.
        def add_user(user_info={})
          
        end
        alias_method :<<, :add_user
        
        ##
        # Adds a given username/password combination to the system, for a given
        # repository, with write privileges.
        #
        # @todo don't know if this actually works
        # @param [Repository] repository The repository to which are associating the user
        # @param [Amp::Servers::User] user The user to give write priveleges to
        def set_writer(repository, user)
          
        end
        
        ##
        # Adds a given username/password combination to the system, for a given
        # repository, with read-only privileges. This will override any other settings
        # previously set. For example, a call to #set_writer and then #set_reader would
        # be as though #set_writer never happened.
        # 
        # @todo don't know if this actually works
        # @param [Repository] repository The repository to which are associating the user
        # @param [Amp::Servers::User] user The user to give write priveleges to
        def set_reader(repository, user)
          
        end
        
        ##
        # Sets the given repository's privacy levels. Repositories default to being
        # public, and must be set to be private using this method. This method can also
        # be used to later make a private repository public without stopping the server.
        #
        # @todo don't know if this actually works
        # @param [Repository] repository The repository for which to set privacy settings
        # @param [Boolean] _private (true) whether the repository should be private or not
        def set_private(repository, _private=true)
          
        end
        
      end
    end
  end
end