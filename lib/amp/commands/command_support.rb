module Amp
  
  module CommandSupport
    # When a user specifies a range, REV_SEP is between the given revisions. 
    REV_SEP = ":"
    
    ##
    # Looks up the node ID of a given revision in the repository. Since this method uses
    # Repository#lookup, the choices for "value" are very flexible. You can choose a
    # revision number, a partial node ID, "tip", and so on. See LocalRepository#lookup
    # for more details.
    #
    # @see {LocalRepository#lookup}
    # @param [Repository] repo the repository in which to lookup the node
    # @param [String, Integer] value the search term for the node - could be a revision
    #   index #, a partial node ID, and so on
    # @param [String, Integer] default the default search term, in case +value+ is nil.
    # @return [String] the full node ID of the node that is found, or +nil+ if none is found.
    def revision_lookup(repo, value, default = nil)
      value ||= default
      repo.lookup(value)
    end
    
    ##
    # Prints the statistics returned from an update or merge. These are given in the form
    # of a hash, such as {:added => 0, :unresolved => 3, ...}, and should be printed
    # in a nice manner.
    #
    # @param [Hash<Symbol => Fixnum>] stats the statistics resulting from an update, merge
    #   or clean command.
    def print_update_stats(stats)
      Amp::UI.status stats.map {|note, files| "#{files.size} files #{note}" }.join(", ")
    end
      
    ##
    # Parses strings that represent a range of 
    # 
    # @example
    #      revision_pair(repo, ["10:tip"])     #=> [repo.lookup(10), repo.lookup("tip")]
    #      revision_pair(repo, ["10", "tip"])  #=> [repo.lookup(10), repo.lookup("tip")]
    #      revision_pair(repo, ":tip")         #=> [repo.lookup(0),  repo.lookup("tip")]
    # @param [Repository] repo the repository to use when looking up revisions
    # @param [Array, String] revisions the revisions to parse. Could be a set of strings,
    #   passed directly in from the command line, or could just be 1 string.
    # @return [Array<String>] the node IDs that correspond to the start and end of the
    #   specified range of changesets
    def revision_pair(repo, revisions)
      #revisions = [revisions] unless revisions.is_a?(Array)
      if !revisions || revisions.empty?
        return repo.dirstate.parents.first, nil
      end
      stop = nil
      
      if revisions.size == 1
        #old revision compared with working dir?
        if revisions[0].include? REV_SEP
          start, stop = revisions.first.split REV_SEP, 2
          start = revision_lookup repo, start, 0
          stop  = revision_lookup repo, stop, repo.size - 1
        else
          start = revision_lookup repo, revisions.first
        end
      elsif revisions.size == 2
        if revisions.first.include?(REV_SEP) ||
           revisions.second.include?(REV_SEP)
           raise ArgumentError.new("too many revisions specified")
        end
        start = revision_lookup(repo, revisions.first)
        stop  = revision_lookup(repo, revisions.second)
      else
        raise ArgumentError.new("too many revisions specified")
      end
      [start, stop]
    end
    
    # returns [String, Array || nil, String]
    def parse_url(*arr)
      url  = arr.shift
      revs = arr.shift || []
      
      unless url =~ /#/
        hds = revs.any? ? revs : []
        return url, hds, revs[-1]
      end
      
      url, branch = url.split('#')[0..1]
      checkout = revs[-1] || branch
      [url, revs + [branch], checkout]
    end
    
    def local_path(path)
      case path
      when /file:\/\/localhost\//
        path[17..-1]
      when /file:\/\//
        path[8..-1]
      when /file:/
        path[6..-1]
      else
        path
      end
    end
    
    # Return repository location relative to cwd or from [paths]
    def expand_path(*arr)
      loc  = arr.shift
      dflt = arr.shift # dflt = default
      cnfg = arr.pop   # always take the last
    
      return loc if loc =~ /:\/\// or File.directory?(File.join(loc, '.hg'))
    
      path = cnfg['paths'][loc]
    
      if !path && dflt
        path = cnfg['paths'][dflt]
      end
      path || loc
    end
    
    def log_message(message, logfile)
      if message && logfile
        raise abort('options --message and --logfile are mutually exclusive')
      end
      
      if !message && logfile
        begin
          message = logfile == '-' ? $stdin.read : File.read(logfile)
        rescue IOError => e
          raise abort("can't read commit message '#{logfile}': #{e}")
        end
      end
      
      message
    end
    
  end
end