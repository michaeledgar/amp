# Stolen from http://github.com/integrity/sinatra-authorization/blob/0761b5cc58597227364a9c8f3e91fcfc43154555/lib/sinatra/authorization.rb
# thank you!

require "sinatra/base"
 
module Sinatra
  # Code adapted from {Ryan Tomayko}[http://tomayko.com/about] and
  # {Christopher Schneid}[http://gittr.com], shared under an MIT License
  # Code significantly refactored for Amp
  module AbstractAuthorization
    def unauthorized!(www_authenticate = challenge)
      response["WWW-Authenticate"] = challenge
      throw :halt, [ 401, 'Authorization Required' ]
    end

    def bad_request!
      throw :halt, [ 400, 'Bad Request' ]
    end
    
    # Convenience method to determine if a user is logged in
    def authorized?
      !!request.env['REMOTE_USER']
    end
    alias :logged_in? :authorized?
 
    # Name provided by the current user to log in
    def current_user
      request.env['REMOTE_USER']
    end
  end
  
  ##
  # HTTP Authorization helpers for Sinatra.
  #
  # In your helpers module, include Sinatra::Authorization and then define
  # an #authorize(user, password) method to handle user provided
  # credentials.
  #
  # Inside your events, call #login_required to trigger the HTTP
  # Authorization window to pop up in the browser.
  #
  # Code adapted from {Ryan Tomayko}[http://tomayko.com/about] and
  # {Christopher Schneid}[http://gittr.com], shared under an MIT License
  # Code significantly refactored for Amp
  module BasicAuthorization
    include AbstractAuthorization
    #  
    # # From you app, call set :authorization_realm, "my app" to set this
    # # or define a #authorization_realm method in your helpers block.
    def challenge
      %(Basic realm="#{options.authorization_realm}")
    end
 
    # Call in any event that requires authentication
    def login_required
      return if authorized?
      unauthorized! unless auth.provided?
      bad_request!  unless auth.basic?
      unauthorized! unless authorize(*auth.credentials)
      request.env['REMOTE_USER'] = auth.username
    end
 
    
    ##
    # Whether or not the supplied username and password (and path) combination
    # are, as Taco Bell says, "Good To Go".
    # 
    # @param [String] username the plaintext that is passed in from the browser
    # @param [String] password the plaintext (!!!!!!) password from the browser
    # @return [Boolean] is the user/pass/path combo authorized?
    def authorize(username, password)
      repo = self.class.amp_repositories[request.path_info]
      return true unless repo && repos[repo]
      
      user = get_user_and_permissions repo, username # user = {:user => ..., :read => ..., :write => ...}
      return false if command_reads?(params["cmd"]) && !user[:read]
      return false if !command_reads?(params["cmd"]) && 
                      !user[:write] && repo_is_private?(repo)
                  
      user[:user].password == password
    end
    
    private
    
      def auth
        @auth ||= Rack::Auth::Basic::Request.new(request.env)
      end
  end
  
  # liberally lifted and modified from Rack's source
  # Code slightly refactored for Amp
  module DigestAuthorization
    include AbstractAuthorization
    
    def opaque; "DEADBEEF"; end
    
    QOP = 'auth'.freeze
    
    def login_required
      auth = Rack::Auth::Digest::Request.new(request.env)
      unauthorized! unless auth.provided?
      bad_request!  if !auth.digest?
      if valid?(auth)
        if auth.nonce.stale?
          return unauthorized!(challenge(:stale => true))
        else
          request.env["REMOTE_USER"] = auth.username
          return true
        end
      end
      unauthorized!
    end
    
    ##
    # This method verifies that the digest provided is accurate. This is the only
    # method involved in the authentication process that requires knowledge of the login
    # system, so it is exposed here, rather than {Sinatra::DigestAuthorization}.
    #
    # @param [Rack::Request] auth The request being used for authorization
    # @return [Boolean] is the user allowed to view the given material?
    def valid_digest?(auth)
      repo = self.class.amp_repositories[request.path_info]
      # no repo OR no users added to repo --> Access to anyone
      return true  unless repo && repos[repo]
      
      user = get_user_and_permissions repo, auth.username
      # User not in the system at all? Denied!
      return false unless user
      
      # if we're private
      if repo_is_private?(repo)
        # and the command is read-only, but user cannot read, they get Ben Wallace'd
        return false if command_reads?(params["cmd"]) && !user[:read]
      end
      
      # Command is write-only, but user cannot write --> Denied. Private/non-private doesn't matter.
      return false if command_writes?(params["cmd"]) && !user[:write]
      
      # Can't short-circuit this one. Just run the digest.
      digest(auth, user[:user].password) == auth.response
    end
    
    def auth_params(hash = {})
      param = Rack::Auth::Digest::Params.new do |param|
        param['realm'] = options.authorization_realm
        param['nonce'] = Rack::Auth::Digest::Nonce.new.to_s
        param['opaque'] = H(opaque)
        param['qop'] = QOP
        hash.each { |k, v| param[k] = v }
      end
    end

    def challenge(hash = {})
      "Digest #{auth_params(hash)}"
    end

    def valid?(auth)
      valid_opaque?(auth) && valid_nonce?(auth) && valid_digest?(auth)
    end

    def valid_qop?(auth)
      QOP == auth.qop
    end

    def valid_opaque?(auth)
      H(opaque) == auth.opaque
    end

    def valid_nonce?(auth)
      auth.nonce.valid?
    end

    def md5(data)
      ::Digest::MD5.hexdigest(data)
    end

    alias :H :md5

    def KD(secret, data)
      H([secret, data] * ':')
    end

    def A1(auth, password)
      [ auth.username, auth.realm, password ] * ':'
    end

    def A2(auth)
      [ auth.method, auth.uri ] * ':'
    end

    def digest(auth, password)
      # change false to match if we ever store hashed passes
      password_hash = false ? password : H(A1(auth, password))

      KD(password_hash, [ auth.nonce, auth.nc, auth.cnonce, QOP, H(A2(auth)) ] * ':')
    end
  end
  # add them in
  helpers BasicAuthorization
  helpers DigestAuthorization
end