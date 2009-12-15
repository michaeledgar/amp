require 'pp'
require 'sinatra/base'
require 'rack/contrib'
require 'zlib'

require 'time'  # for Time.httpdate
require 'rack/utils'

module Sinatra
  ##
  # = AmpExtension
  # This module adds a single DSL method to the sinatra base class:
  # amp_repository. This method allows you to specify an HTTP path for
  # an amp repo. You can call this method multiple times to specify
  # multiple repositories for your server.
  #
  # @example - This will start a server, serving the directory the file is in,
  #  at http://localhost:4567/
  #     require 'amp'
  #     require 'sinatra'
  #     require 'amp/server/extension/amp_extension'
  #     
  #     amp_repository "/", Amp::Repositories.pick(nil, ".")
  #
  module AmpExtension
    
    def amp_repositories; @@amp_repositories ||= {}; end
    
    ##
    # This method will specify that the sinatra application should serve the
    # repository +repo+ using Mercurial's HTTP(S) protocol at +http_path+.
    # You can call this method multiple times for multiple repositories on
    # different paths.
    #
    # @example - This will start a server, serving the directory the file is in,
    #  at http://localhost:4567/
    #     require 'amp'
    #     require 'sinatra'
    #     require 'amp/server/extension/amp_extension'
    #     
    #     amp_repository "/", Amp::Repositories.pick(nil, ".")
    #
    # @param [String] http_path the URL path from which to serve the repository
    # @param [Repository] repo the repository being served - typically a LocalRepository.
    def amp_repository(http_path, repo)
      amp_repositories[http_path] = repo
      
      get http_path do
        if ACCEPTABLE_COMMANDS.include?(params[:cmd])
          send("amp_get_#{params[:cmd]}".to_sym, repo)
        else
          pass
        end
      end
    end
    
    # All the commands we are capable of accepting
    ACCEPTABLE_COMMANDS = [ 'branches', 'heads', 'lookup', 'capabilities', 'between', 'changegroup', 'changegroupsubset', 'unbundle' ]
    READABLE_COMMANDS   = [ 'branches', 'heads', 'lookup', 'capabilities', 'between', 'changegroup', 'changegroupsubset' ]
    
  end
  
  ##
  # These methods are helpers that the server will run to implement the Mercurial
  # HTTP(S) protocol. These should not be overridden if Mercurial compatibility is
  # required. All methods - unless otherwise specified - return the exact data string
  # that the server will serve as the HTTP data.
  module AmpRepoMethods
    
    ##
    # Checks if the given command performs a read operation
    #
    # @param [String] cmd the command to check
    # @return [Boolean] does the command perform any reads on the repo?
    def command_reads?(cmd);   AmpExtension::READABLE_COMMANDS.include?(cmd); end
    
    ##
    # Checks if the given command performs a write operation
    #
    # @param [String] cmd the command to check
    # @return [Boolean] does the command perform any writes on the repo?
    def command_writes?(cmd); !command_reads?(cmd); end

    ##
    # Command: lookup
    #
    # Looks up a node-id for a key - the key could be an integer (for a revision index),
    # a partial node_id (such as 12dead34beef), or even "tip" to get the current tip.
    # Only concerns revisions in the changelog (the "global" revisions)
    #
    # HTTP parameter: "key" => the key being looked up in the changelogs
    #
    # @param [Repository] amp_repo the repository being inspected
    # @return [String] a response to deliver to the client, in the format "#{success} #{node_id}",
    #   where success is 1 for a successful lookup and node_id is 0 for a failed lookup.
    def amp_get_lookup(amp_repo)
      begin
        rev = amp_repo.lookup(params["key"]).hexlify
        success = 1
      rescue StandardError => e
        rev = e.to_s
        success = 0
      end
      
      "#{success} #{rev}\n"
    end
    
    ##
    # Command: heads
    #
    # Looks up the heads for the given repository. No parameters are taken - just the heads
    # are returned.
    #
    # @param [Repository] amp_repo the repository whose heads are examined
    # @return [String] a response to deliver to the client, with each head returned as a full
    #   node-id, in hex form (so 40 bytes total), each separated by a single space.
    def amp_get_heads(amp_repo)
      repo = amp_repo
      repo.heads.map {|x| x.hexlify}.join(" ")
    end
    
    def amp_get_branches(amp_repo)
      nodes = []
      if params["nodes"]
        nodes = params["nodes"].split(" ").map {|x| x.unhexlify}
      end
      amp_repo.branches(nodes).map do |branches|
        branches.map {|branch| branch.hexlify}.join(" ")
      end.join "\n"
    end
    
    ##
    # Command: capabilities
    #
    # Returns what special commands the server is capable of performing. This is where new
    # additions to the protocol are added, so new clients can check to make sure new features
    # are supported.
    #
    # @param [Repository] amp_repo the repository whose capabilities are returned
    # @return [String] a response to deliver to the client, with each capability listed,
    #   separated by spaces. If the capability has multiple values (such as 'unbundle'),
    #   it is returned in the format "capability=value1,value2,value3" instead of just 
    #   "capability". No spaces are allowed in the capability= fragment.
    def amp_get_capabilities(amp_repo)
      caps = ["lookup", "changegroupsubset"]
      # uncompressed for streaming?
      caps << "unbundle=#{Amp::Mercurial::RevlogSupport::ChangeGroup::FORMAT_PRIORITIES.join(',')}"
      caps.join ' '
    end
    
    ##
    # Command: between
    #
    # Takes a list of node pairs. Each pair has a "start" and an "end" node ID, which specify
    # a range of revisions. The +between+ command returns the nodes between the start and the
    # end, exclusive, for each provided pair.
    #
    # HTTP param: pairs. Each pair is presented as 2 node IDs, as hex, separated by a a hyphen.
    # then, each pair is delimited by other pairs with a space. Example:
    #     pair1startnodeid-pair1endnodeid pair2startnodeid-pair2endnodeid pair3startnodeid-pair3endnodeid
    #
    # @param [Repository] amp_repo the repository upon which to perform node lookups
    # @return [String] a response to deliver to the client, with the nodes between each pair
    #   provided. Each pair provided by the client will result in a list of node IDs - this list
    #   is returned as each node ID in the list, with spaces between the nodes. Each pair has its
    #   results on a new line. Example output for 3 provided pairs:
    #      abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde 1234567890123456789012345678901234567890
    #      1234567890123456789012345678901234567890
    #      abcdeabcdeabcdeabcdeabcdeabcdeabcdeabcde
    #   
    def amp_get_between(amp_repo)
      pairs = []
      
      if params["pairs"]
        pairs = params["pairs"].split(" ").map {|p| p.split("-").map {|i| i.unhexlify } }
      end
      
      amp_repo.between(pairs).map do |nodes|
        nodes.map {|i| i.hexlify }.join " "
      end.join "\n"
    end
    
    ##
    # = DelayedGzipper
    # Takes a block when initialized, but doesn't run the block. It actually
    # saves the block, and then runs it later, streaming the results into a
    # GZip stream. Very memory friendly. 
    #
    # This class is designed to work with Rack. All it has to do is implement an
    # #each method which takes a block, and which calls that method when
    # gzip data is to be written out. This way data doesn't have to be generated,
    # then processed, then processed, etc. It is actually streamed to the client.
    class DelayedGzipper
      
      ##
      # Creates a new DelayedGzipper. All you must do is create a new DelayedGzipper,
      # whose block results in an IO-like object, and return it as the result of
      # a Sinatra/Rack endpoint. Rack will run the #each method to stream the data
      # out.
      #
      # @yield The block provided will be stored and executed lazily later when
      #   the results of the block need to be generated and gzipped. Should return
      #   an IO-like object to maximize memory-friendliness.
      def initialize(&block)
        @result_generator = block
      end
      
      ##
      # For Rack compliance. The block should be called whenever data is to be written
      # to the client. We actually save the block, and use a GzipWriter to funnel the
      # gzipped data into the block. Pretty nifty.
      def each(&block)
        
        # Save the writer for safe-keeping
        @writer = block
        
        # This creates a gzip-writer. By passing in +self+ as the parameter, when we
        # write to the gzip-writer, it will then call #write on +self+ with the
        # gzipped data. This allows us to handle the compressed data immediately
        # instead of funneling it to a buffer or something useless like that.
        gzip  = ::Zlib::GzipWriter.new self
        gzip.mtime = Time.now
        
        # Gets the IO-like object that we need to gzip
        f = @result_generator.call
        
        begin
          chunk = f.read 4.kb
          gzip << chunk if chunk && chunk.any?
        end while chunk && chunk.any?
        
        # Finish it off
        gzip.close
        
        # We're done!
        @writer = nil
      end

      ##
      # Called by GzipWriter so we can immediately handle our gzipped data.
      # We write it to the client using the @writer given to us in #each.
      #
      # @param [String] data the data to write to the client. Gzipped.
      def write(data)
        @writer.call data
      end
    end
    
    ##
    # Helper method for setting up the headers for lazily gzipped results in a sinatra
    # app.
    #
    # @return [Rack::Utils::HeaderHash] the headers that tell a client to expect
    #   gzipped data, and that we don't know how big the data is going to be,
    #   because we're gzipping it on the fly!
    def gzipped_response
      headers = Rack::Utils::HeaderHash.new(response.headers)
      vary = headers["Vary"].to_s.split(",").map { |v| v.strip }
      
      unless vary.include?("*") || vary.include?("Accept-Encoding")
        headers["Vary"] = vary.push("Accept-Encoding").join ","
      end
      
      headers.delete 'Content-Length'
      headers["Content-Encoding"] = "gzip"
      headers
    end
    
    ##
    # Command: changegroup
    #
    # Gets a given changegroup from the repository. Starts at the requested roots,
    # and then goes to the heads of the repository from those roots.
    #
    # HTTP Param: roots. The roots of the trees we are requesting, in the form of
    # a list of node IDs. the IDs are in hex, and separated by spaces.
    #
    # @param [Repository] amp_repo the repository from which we are requesting the
    #   changegroup.
    # @return [String] the changegroup to be returned to the client. Well, more
    #   specifically, we halt processing, return an object that will gzip our
    #   data on the fly without using ridiculous amounts of memory, and with the
    #   correct headers. It ends up being the changegroup, or a large bundled up
    #   set of changesets, for the client to add to its repo (or just examine).
    def amp_get_changegroup(amp_repo)
      headers = gzipped_response
      
      nodes = []
      if params["roots"]
        nodes = params["roots"].split(" ").map {|i| i.unhexlify }
      end
      
      result = DelayedGzipper.new do
        amp_repo.changegroup(nodes, :serve)
      end
      
      throw :halt, [200, headers, result]

    end
    
    ##
    # Command: changegroupsubset
    # Requires an explicit capability: changegroupsubset
    #
    # Gets a given changegroup subset from the repository. Starts at the requested roots,
    # and then goes to the heads given as parameters. This is how one might "slice"
    # a repository, just as one slices an array with arr[3..7]. The "root" is 3, the
    # "head" is 7. However, one can provide a number of roots or heads, as a mercurial
    # repository is a DAG, and not a simple list of numbers such as 3..7. 
    #
    # HTTP Param: roots. The roots of the trees we are requesting, in the form of
    # a list of node IDs. the IDs are in hex, and separated by spaces.
    # HTTP Param: heads. The heads of the slice of the trees we are requesting.
    # The changegroup will stop being processed at the heads. In the form of a list of
    # node IDs, each in hex, and separated by spaces.
    #
    # @param [Repository] amp_repo the repository from which we are requesting the
    #   changegroup subset.
    # @return [String] the changegroup subset to be returned to the client. Well, more
    #   specifically, we halt processing, return an object that will gzip our
    #   data on the fly without using ridiculous amounts of memory, and with the
    #   correct headers. It ends up being the changegroup subset, or a large bundled up
    #   set of changesets, for the client to add to its repo (or just examine).
    def amp_get_changegroupsubset(amp_repo)
      headers = gzipped_response
      
      bases, heads = [], []
      
      bases = params["bases"].split(" ").map {|i| i.unhexlify } if params["bases"]
      heads = params["heads"].split(" ").map {|i| i.unhexlify } if params["heads"]
      
      result = DelayedGzipper.new do
        amp_repo.changegroup_subset bases, heads, :serve
      end
      
      throw :halt, [200, headers, result]
    end
    
    def amp_get_fake_writing(amp_repo)
      "You're logged in!"
    end
    
    ##
    # Command: unbundle
    #
    # This command is used when a client wishes to push over HTTP. A bundle is posted
    # as the request's data body.
    #
    # HTTP Method: post
    # HTTP parameters: heads. The client repo's heads. Could be "force".hexlify, if
    #   the client is going to push anyway.
    # HTTP post body: the bundled up set of changegroups.
    #
    # @param [Repository] amp_repo the repository to be pushed to
    # @return [String] the results of the push, which are streamed to the client.
    #
    # @todo locking
    # @todo finish this method!
    def amp_get_unbundle(amp_repo)
      their_heads = params["heads"].split(" ")
      
      check_heads = proc do
        heads = amp_repo.heads.map {|i| i.hexlify}
        return their_heads == ["force".hexlify] || their_heads == heads
      end
      
      unless check_heads.call
        throw :halt, [200, "unsynced changes"]
      end
      
      Tempfile.open("amp-unbundle-") do |fp|
        length = request.content_length
        fp.write request.body
        
        unless check_heads.call
          # in case our heads have changed in the last few milliseconds
          throw :halt, [200, "unsynced changes"]
        end
        fp.seek(0, IO::SEEK_SET)
        header = fp.read(6)
        if header.start_with?("HG") && !header.start_with?("HG10")
          raise ArgumentError.new("unknown bundle version")
        elsif !Amp::Mercurial::RevlogSupport::ChangeGroup::BUNDLE_HEADERS.include?(header)
          raise ArgumentError.new("unknown bundle compression type")
        end
        
        stream = Amp::Mercurial::RevlogSupport::ChangeGroup.unbundle(header, fp)
        
      end
      
    end
  end
  
  helpers  AmpRepoMethods
  register AmpExtension
end
