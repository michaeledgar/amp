require 'uri'

# to shut up those fucking warnings!
# taken from http://www.5dollarwhitebox.org/drupal/node/64
class Net::HTTP
  alias_method :old_initialize, :initialize
  def initialize(*args)
    old_initialize(*args)
    require 'openssl' unless defined? OpenSSL
    @ssl_context = OpenSSL::SSL::SSLContext.new
    @ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
  end
end

module Amp
  module Repositories
    ##
    # = This is the class for connecting to an HTTP[S]-based repository.
    # The protocol's pretty simple - just ?cmd="command", and any other
    # args you need. Should be pretty easy.
    class HTTPRepository < Repository
      include RevlogSupport::Node
      
      DEFAULT_HEADERS = {"User-agent" => "Amp-#{Amp::VERSION}",
                         "Accept" => "Application/Mercurial-0.1"}
      
      ##
      # The URL we connect to for this repository
      attr_reader :url
      
      ##
      # Should the repository connect via SSL?
      attr_accessor :secure
      
      ##
      # Returns whether the repository is local or not. Which it isn't. Because
      # we're connecting over HTTP.
      #
      # @return [Boolean] +false+. Because the repo isn't local.
      def local?; false; end
      
      ##
      # Standard initializer for a repository. However, "create" is a no-op.
      #
      # @param path the URL for the repository.
      # @param create useless
      # @param config the configuration for Amp right now.
      def initialize(path="", create=false, config=nil)
        @url, @config = URI.parse(path), config
        @auth_mode = :none
        raise InvalidArgumentError.new("Invalid URL for an HTTP repo!") if @url.nil?
      end
      
      ##
      # Loads the capabilities from the server when necessary. (Lazy loading)
      #
      # @return [Hash] the capabilities of the server, in the form:
      #      { capability => true }
      #   or
      #      { capability => "capability;settings;"}
      def get_capabilities
        return @capabilities if @capabilities
        begin
          @capabilities = {}
          do_read("capabilities").first.split.each do |k| 
            if k.include? "="
              key, value = k.split("=", 2)
              @capabilities[key] = value
            else
              @capabilities[k] = true
            end
          end
        rescue
          @capabilities = []
        end
        @capabilities
      end
      
      ##
      # Unsupported - raises an error.
      def lock; raise RepoError.new("You can't lock an HTTP repo."); end
      
      ##
      # Looks up a node with the given key. The key could be a node ID (full or
      # partial), an index number (though this is slightly risky as it might
      # match a node ID partially), "tip", and so on. See {LocalRepository#[]}.
      #
      # @param [String] key the key to look up - could be node ID, revision index,
      #   and so on.
      # @return [String] the full node ID of the requested node on the remote server
      def lookup(key)
        require_capability("lookup", "Look up Remote Revision")
        data = do_read("lookup", :key => key).first
        code, data = data.chomp.split(" ", 2)
        
        return data.unhexlify if code.to_i > 0
        raise RepoError.new("Unknown Revision #{data}")
      end
      
      ##
      # Gets all the heads of the repository. Returned in binary form.
      #
      # @return [Array<String>] the full, binary node_ids of all the heads on
      #   the remote server.
      def heads
        data = do_read("heads").first
        data.chomp.split(" ").map {|h| h.unhexlify }
      end
      
      ##
      # Gets the node IDs of all the branch roots in the repository. Uses
      # the supplied nodes to use to search for branches.
      #
      # @param [Array<String>] nodes the nodes to use as heads to search for
      #   branches. The search starts at each supplied node (or the tip, if
      #   left empty), and goes to that tree's root, and returns the relevant
      #   information for the branch.
      # @return [Array<Array<String>>] An array of arrays of strings. Each array
      #   has 4 components: [head, root, parent1, parent2].
      def branches(nodes)
        n = nodes.map {|n| n.hexlify }.join(" ")
        data = do_read("branches", :nodes => n).first
        data.split("\n").map do |b|
          b.split(" ").map {|b| b.unhexlify}
        end
      end
      
      ##
      # Asks the server to bundle up the given nodes into a changegroup, and returns it
      # uncompressed. This is for pulls.
      #
      # @todo figure out what the +kind+ parameter is for
      # @param [Array<String>] nodes the nodes to package into the changegroup
      # @param [NilClass] kind (UNUSED)
      # @return [StringIO] the uncompressed changegroup as a stream
      def changegroup(nodes, kind)
        n = nodes.map{|i| i.hexlify }.join ' '
        f = do_read('changegroup', n.empty? ? {} : {:roots => n}).first

        s = StringIO.new "",(ruby_19? ? "w+:ASCII-8BIT" : "w+")
        s.write Zlib::Inflate.inflate(f)
        s.pos = 0
        s
      end
      
      ##
      # Asks the server to bundle up all the necessary nodes between the lists
      # bases and heads. It is returned as a stream that reads it in a decompressed
      # fashion. This is for pulls.
      # 
      # @param [Array<String>] bases the base nodes of the subset we're requesting.
      #   Should be an array (or any Enumerable) of node ids.
      # @param [Array<String>] heads the heads of the subset we're requesting.
      #   These nodes will be retrieved as well. Should be an array of node IDs.
      # @param [NilClass] source i have no idea (UNUSED)
      # @return [StringIO] the uncompressed changegroup subset as a stream.
      def changegroup_subset(bases, heads, source)
        #require_capability 'changegroupsubset', 'look up remote changes'
        base_list = bases.map {|n| n.hexlify }.join ' '
        head_list = heads.map {|n| n.hexlify }.join ' '
#        p base_list, head_list
        f, code = *do_read("changegroupsubset", :bases => base_list, :heads => head_list)
        
        s = StringIO.new "",(ruby_19? ? "w+:ASCII-8BIT" : "w+")
        s.write Zlib::Inflate.inflate(f)
        s.rewind
        s
      end
      
      ##
      # Sends a bundled up changegroup to the server, who will add it to its repository.
      # Uses the bundle format.
      #
      # @param [StringIO] cg the changegroup to push as a stream.
      # @param [Array<String>] heads the heads of the changegroup being sent
      # @param [NilClass] source no idea UNUSED
      # @return [Fixnum] the response code from the server (1 indicates success)
      def unbundle(cg, heads, source)
        # have to stream bundle to a temp file because we do not have
        # http 1.1 chunked transfer
        
        type = ''
        types = capable? 'unbundle'
        
        # servers older than d1b16a746db6 will send 'unbundle' as a boolean
        # capability
        # this will be a list of allowed bundle compression types
        types = types.split ',' rescue ['']
        
        # pick a compression format
        types.each do |x|
          (type = x and break) if RevlogSupport::ChangeGroup::BUNDLE_HEADERS.include? x
        end
        
        # compress and create the bundle
        data = RevlogSupport::ChangeGroup.write_bundle cg, type
        
        # send the data
        resp = do_read 'unbundle', :data => data.string,
                                   :headers => {'Content-Type' => 'application/octet-stream'},
                                   :heads => heads.map{|h| h.hexlify }.join(' ')
        # parse output
        resp_code, output = resp.first.split "\n"
        
        # make sure the reponse was in an expected format (i.e. with a response code)
        unless resp_code.to_i.to_s == resp_code
          raise abort("push failed (unexpected response): #{resp}")
        end
        
        # output any text from the server
        UI::say output
        # return 1 for success, 0 for failure
        resp_code.to_i
      end
      
      def stream_out
        do_cmd 'stream_out'
      end
      
      ##
      # For each provided pair of nodes, return the nodes between the pair.
      #
      # @param [Array<Array<String>>] an array of node pairs, so an array of an array
      #   of strings. The first node is the head, the second node is the root of the pair.
      # @return [Array<Array<String>>] for each pair, we return 1 array, which contains
      #   the node IDs of every node between the pair.
      # add lstrip to split_newlines to fix but not cure bug
      def between(pairs)
        batch = 8
        ret   = []
        
        (0..(pairs.size)).step(batch) do |i|
          n = pairs[i..(i+batch-1)].map {|p| p.map {|k| k.hexlify }.join("-") }.join(" ")
          d, code = *do_read("between", :pairs => n)
          
          raise RepoError.new("unexpected code: #{code}") unless code == 200
          
          ret += d.lstrip.split_newlines.map {|l| (l && l.split(" ").map{|i| i.unhexlify }) || []}
        end
        Amp::UI.debug "between returns: #{ret.inspect}"
        ret
      end
      
      private
      
      ##
      # Runs the given command by the server, gets the response. Takes the name of the command,
      # the data, headers, etc. The command is assumed to be a GET request, unless args[:data] is
      # set, in which case it is sent via POST.
      #
      # @param [String] command the command to send to the server, such as "heads"
      # @param [Hash] args the arguments you need to provide - for lookup, it
      #   might be the revision indicies.
      # @return [String] the response data from the server.
      def do_cmd(command, args={})
        require 'net/http'
        
        # Be safe for recursive calls
        work_args = args.dup
        # grab data, but don't leave it in, or it'll be added to the query string
        data = work_args.delete(:data) || nil
        # and headers, but don't leave it in, or it'll be added to the query string
        headers = work_args.delete(:headers) || {}
        
        # Our query string is "cmd => command" plus any other parts of the args hash
        query = { "cmd" => command }
        query.merge! work_args
        
        # break it up, make a query
        host = @url.host
        path = @url.path
        # Was having trouble with this... should be safe now
        path += "?" + URI.escape(query.map {|k,v| "#{k}=#{v}"}.join("&"), /[^-_!~*'()a-zA-Z\d;\/?:@&=+$,\[\]]/n)
        
        # silly scoping
        response = nil
        # Create an HTTP object so we can send our request. static methods aren't flexible
        # enough for us
        sess = Net::HTTP.new host, @url.port
        # Use SSL if necessary
        sess.use_ssl = true if secure
        # Let's send our request!
        sess.start do |http|
          # if we have data, it's a POST
          if data
            req = Net::HTTP::Post.new(path)
            req.body = data
          else
            # otherwise, it's a GET
            req = Net::HTTP::Get.new(path)
          end
          if @auth_mode == :digest
            # Set digest headers
            req.digest_auth @username, @password, @auth_digest
          elsif @auth_mode == :basic
            # Set basic auth headers
            req.basic_auth  @username, @password
          end
          # Copy over the default headers
          DEFAULT_HEADERS.each {|k, v| req[k] = v}
          # Then overwrite them (and add new ones) from our arguments
          headers.each {|k, v| req[k] = v}
          # And send the request!
          response = http.request(req)
        end
        # Case on response - we'll be using the kind_of? style of switch statement
        # here
        case response
        when Net::HTTPRedirection
          # Redirect to a new URL - grab the new URL...
          newurl = response["Location"]
          @url = URI.parse(newurl)
          # and try that again.
          do_cmd(command, args)
        when Net::HTTPUnauthorized
          if @auth_mode == :digest
            # no other handlers!
            raise AuthorizationError.new("Failed to authenticate to local repository!")
          elsif @auth_mode == :basic
            # failed to authenticate via basic, so escalate to digest mode
            @auth_mode = :digest
            @auth_digest = response
            do_cmd command, args
          else
            # They want a username and password. A few routes:
            # First, check the URL for the username:password@host format
            @username ||= @url.user 
            @password ||= @url.password
            # and start off with basic authentication
            @auth_mode = :basic
            # If the URL didn't contain the username AND password, ask the user for them.
            unless @username && @password
              UI::say "==> HTTP Authentication Required"
              
              @username = UI::ask 'username: '
              @password = UI::ask 'password: ', :password
            end
            
            # Recursively call the command
            do_cmd command, args
          end
        else
          # We got a successful response! Woo!
          response
        end
      end
      
      ##
      # This is a helper for do_cmd - it splits up the response object into
      # two relevant parts: the response body, and the response code.
      #
      # @param [String] command the remote command to execute, such as "heads"
      # @param [Hash] args the arguments to pass to the request. Takes some special values. All
      #   other values are sent in the query string.
      # @option args [String] :data (nil) the POST data to send
      # @option args [Hash] :headers ({}) the headers to send with the request, not including
      #   any authentication or user-agent headers.
      # @return [Array] the response data, in the form [body, response_code]
      def do_read(command, args={})
        response = do_cmd(command, args)
        [response.body, response.code.to_i]
      end
    end
    
    ##
    # A special form of the HTTPRepository, except that it is secured over SSL (HTTPS).
    # Other than that, nothing fancy about it.
    class HTTPSRepository < HTTPRepository
      def initialize(*args)
        require 'net/https'
        
        super(*args)
        self.secure = true
      end
    end
  end
end
