require 'rubygems'
require 'sinatra/base'
require 'rack/deflater'
need { 'extension/amp_extension' }
need { 'extension/authorization' }

module Amp
  module Servers
    ##
    # = HTTPServer
    # General HTTP Server that serves up a Mercurial repository under the
    # Mercurial HTTP protocol. Any mercurial client (including Amp) can use
    # this server for push/pull operations, clones, and so on.
    # Note: this server only provides methods for dealing with Mercurial clients. 
    # It is not a full-blown web server with a web interface to the repository.
    #
    # It is worth noting that one may serve many repositories using one server
    # using this class. Spiffy, eh?
    class HTTPServer < Sinatra::Base
      register Sinatra::AmpExtension
      helpers  Sinatra::AmpRepoMethods
    end
    
    ##
    # = HTTPAuthorizedServer
    # General HTTP Server that has some form of authentication. Implements
    # user-logic methods, as every subclass will have the same interface
    # for adding/removing users. Note: this server only provides methods
    # for dealing with Mercurial clients. It is not a full-blown web server
    # with a web interface to the repository. The users you add to an
    # HTTPAuthorizedServer are the credentials a user must provide when pushing
    # to a repository (for example), or checking out a private repository.
    #
    # It is worth noting that one may serve many repositories using one server
    # using this class. Spiffy, eh?
    class HTTPAuthorizedServer < HTTPServer
      set :amp_storage_manner, :unset
      class << self
        def set_storage(manner, opts={})
          if amp_storage_manner != :unset
            raise RuntimeError.new("Can't redefine storage type.")
          end
          
          case manner.to_sym
          when :memory
            extend RepoUserManagement::Memory
          else
            raise "Unknown storage manner #{manner.inspect}"
          end
          
          set :amp_storage_manner, manner.to_sym
        end
      
        def set_permission(style, *args)
          case style
          when :writer
            set_writer *args
          when :reader
            set_reader *args
          else
            raise ArgumentError.new("Unknown permission level: #{style.to_s.inspect}")
          end
        end
      
        ##
        # Sets whether to use digest or basic authentication. May only be called once,
        # for now.
        #
        # @param [Symbol, String] manner the type of authentication
        def set_authentication(manner, opts={})
          case manner.to_sym
          when :basic
            helpers Sinatra::BasicAuthorization
          when :digest
            helpers Sinatra::DigestAuthorization
          end
          # one-time method. don't yet support.
          def set_authentication
            raise RuntimeError.new("Can't redefine authentication type.")
          end
        end
      end
      
      set :authorization_realm, "Amp Repository"
      
      ##
      # Gets all the registered repositories. Helper method.
      #
      # @return [Array<LocalRepository>] All the repositories registered with the server
      def repos
        self.class.repos
      end
      
      ##
      # Gets all the registered users. Helper method.
      #
      # @return [Array<Amp::Servers::User>] All the users registered with the server
      def users
        self.class.users
      end
      
      ##
      # This block is run on every single request, before the server code for the request is processed.
      before do
        cmd  = params["cmd"]
        repo = self.class.amp_repositories[request.path_info]
        
        if cmd.nil? or cmd.empty? or !repos[repo] or !repos[repo][:private] && command_reads?(cmd)
          true
        else
          login_required
        end
      end
      
      ##
      # General helper methods for the server
      helpers do
        ##
        # Is the repository URL private? The URL is expected to be good.
        #
        # @param [String] repo the URL to the repository. Expected to be correct
        def repo_is_private?(repo)
          repos[repo][:private]
        end
        
        ##
        # Is the repository URL public?
        # 
        # @param [String] repo the URL to the repository. Expected to be correct
        def repo_is_public?(repo) 
          !repo_is_private?(repo)
        end
        
        ##
        # Pay attention kids -- this returns a HASH!!!!!!!!
        # This is a hash of :user, :read, and :write
        # 
        # @param [String] repo path to the repo on the web
        # @param [String] username the dude we're looking for
        # @return [{:user => Amp::Servers::User, :read => Boolean, :write => Boolean}]
        def get_user_and_permissions(repo, username)
          if u = repos[repo][:users][username]
            return u
          end
          
          {:user  => User.public_user,
           :read  => (repos[repo][:private] ? false : true),
           :write => false }
        end
      end
    end
    
  end
end

