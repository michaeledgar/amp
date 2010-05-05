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

# temporary hack to make sure helper functions don't leak into the global
# namespace.
Module.new do
  ##
  # Creates the stats command and injects it into the runtime.
  # Relatively similar to the HG churn command though it shares no
  # actual lineage - I (Michael Edgar) started this as a simple demonstration
  # command long before I knew about the official churn extension. I'm adding
  # some churn features along the way, but this code has nothing to do with churn.
  command "stats" do |c|
    c.workflow :hg
    c.opt :template, "A template string to compute the grouping key. Defaults to <%= user %>.", 
          :type => :string, :default => "<%= user %>", :short => "-t"
    c.opt :dateformat, "Use formatted date of commit as the grouping key", :type => :string, :short => "-f"
    c.opt :sort, "Sorts by the grouping key instead of commit/change amount"
    c.desc "Prints how many commits each user has contributed"
    c.on_run do |opts, args|
      repo = opts[:repository]
      results = Hash.new {|h, k| h[k] = 0}
    
      # We need a proc that extracts the key to use from the changeset
      keyproc = build_key_proc opts
      # Iterate over each changeset, counting changesets based on the key
      repo.each do |changeset|
        results[keyproc[changeset]] += 1 #
      end
      pairs = results.to_a
    
      # Sort based on options given
      sort_pairs! pairs, opts
    
      # Print our output as a histogram
      puts Amp::Statistics.histogram(pairs, Amp::Support.terminal_size[0])
    end
  
    ##
    # Prepares a proc that, when run on a changeset, extracts a grouping key
    # from the changeset.  This is highly customizable by the user as it is
    # the backbone behind providing useful output.
    #
    # @param [Hash<Symbol => Object>] opts the opts provided by the user
    # @return [Proc] a proc that takes a changeset as a parameter and
    #   returns a string key to be used for grouping
    def build_key_proc(opts)
      if opts[:dateformat]
      then keyproc = proc {|changeset| changeset.easy_date.strftime(opts[:dateformat])}
      else keyproc = proc {|changeset| changeset.to_templated_s(:"template-raw" => opts[:template]) }
      end
    end
  
    ##
    # Sorts the results based on the options provided to the command by
    # the user.
    #
    # @param [Array<String, Integer>] pairs the pairs of key-value churned results.
    #   will be sorted in-place.
    # @param [Hash<Symbol => Object>] opts the options provided by the user
    def sort_pairs!(pairs, opts)
      if opts[:sort]
      then pairs.sort! {|a, b| a[0] <=> b[0]} # sort keys ascending
      else pairs.sort! {|a, b| b[1] <=> a[1]} # sort values descending
      end
    end
  end
end