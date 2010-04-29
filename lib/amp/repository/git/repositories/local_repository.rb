module Amp
  module Repositories    
    module Git
      
      class LocalRepository < Amp::Repositories::AbstractLocalRepository
        
        attr_accessor :root
        attr_accessor :config
        attr_accessor :file_opener
        attr_accessor :git_opener
        attr_accessor :staging_area
        
        def initialize(path="", create=false, config=nil)
          super(path, create, config)
          
          @config = config
          
          @file_opener = Amp::Opener.new @root # This will open relative to the repo root
          @file_opener.default = :open_file    # these two are the same, pretty much
          @git_opener  = Amp::Opener.new @root # this will open relative to root/.git
          @git_opener.default  = :open_git     # just with different defaults
          
          @staging_area = Amp::Repositories::Git::StagingArea.new self
          
          if create
            init
          end
        end
        
        def init(config=@config)
          super(config)
          
          `cd #{@root} && git init 2> /dev/null`
          true
        end
        
        ##
        # Regarding branch support.
        #
        # For each repository format, you begin in a default branch.  Each repo format, of
        # course, starts with a different default branch.  Git's is "master".
        #
        # @api
        # @return [String] the default branch name
        def default_branch_name
          "master"
        end
        
        def commit(opts={})
          add_all_files
          string = "git commit #{opts[:user] ? "--author #{opts[:user].inspect}" : "" }" +
                   " #{opts[:empty_ok] ? "--allow-empty" : "" }" +
                   " #{opts[:message] ? "-m #{opts[:message].inspect}" : "" } 2> /dev/null"
          string.strip!
          
          system string
        end
        
        def add_all_files
          staging_area.add status[:modified]
        end
        
        def forget(*files)
          staging_area.forget *files
        end
        
        def [](rev)
          case rev
          when String
            Amp::Git::Changeset.new self, rev
          when nil
            Amp::Git::WorkingDirectoryChangeset.new self
          when 'tip', :tip
            Amp::Git::Changeset.new self, parents[0]
          when Integer
            revs = `git log --pretty=oneline 2> /dev/null`.split("\n")
            short_name = revs[revs.size - 1 - rev].split(' ').first
            Amp::Git::Changeset.new self, short_name
          end
        end
        
        def size
          `git log --pretty=oneline 2> /dev/null`.split("\n").size
        end
        
        ##
        # Write +text+ to +filename+, where +filename+
        # is local to the root.
        #
        # @param [String] filename The file as relative to the root
        # @param [String] text The text to write to said file
        def working_write(filename, text)
          file_opener.open filename, 'w' do |f|
            f.write text
          end
        end
        
        ##
        # Determines if a file has been modified from :node1 to :node2.
        # 
        # @return [Boolean] has it been modified
        def file_modified?(file, opts={})
          file_status(file, opts) == :included
        end
        
        ##
        # Returns a Symbol.
        # Possible results:
        # :added (subset of :included)
        # :removed
        # :untracked
        # :included (aka :modified)
        # :normal
        # 
        # If you call localrepo#status from this method... well...
        # I DARE YOU!
        def file_status(filename, opts={})
          parse_status! opts
          inverted = @status.inject({}) do |h, (k, v)|
            v.each {|v_| h[v_] = k }
            h
          end
          
          # Now convert it so it uses the same jargon
          # we REALLY need to get the dirstate and localrepo on
          # the same page here.
          case inverted[filename]
          when :modified
            :included
          when :added
            :added
          when :removed
            :removed
          when :unknown
            :untracked
          else
            :normal
          end
            
        end
        
        def parse_status!(opts={})
          return if @parsed
          
          data    = `git status #{opts[:node1]}..#{opts[:node2]}  2> /dev/null`.split("\n")
          @status = data.inject({}) do |h, line| # yeah i know stfu
            case line
            when /^#\s+(\w+):\s(.+)$/
              h[$1.to_sym] = $2; h
            when /^#\s+([^ ]+)$/
              h[:unknown] = $1; h
            else
              h
            end
          end
          @parsed = true
        end
        
        def parents
          first = `git log -1 HEAD 2> /dev/null`
          dad   = first[/^commit (.+)$/, 1]
          dad   = dad ? dad[0..6] : nil
          mom   = nil
          
          if first =~ /Merge: (.+)\.\.\. (.+)\.\.\.$/ # Merge: 1c002dd... 35cfb2b...
            dad = $1 # just have them both use the short name, nbd
            mom = $2
          end
          
          [dad, mom]
        end
        
      end
    end
  end
end
