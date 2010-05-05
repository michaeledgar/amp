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

require 'rubygems'
require 'haml'
require 'sass'

module Amp
  module Servers
    
    ##
    # The FancyHTTPServer takes the Authorized server one step further, by adding
    # a web interface.  The web interface is optional - just use the superclass
    # instead of this one. The fancy_views directory contains all the templates
    # used by the web interface.
    class FancyHTTPServer < HTTPAuthorizedServer
      
      # Configure sinatra for our view locations
      set :views, File.expand_path(File.join(File.dirname(__FILE__), "fancy_views"))
      set :public, File.expand_path(File.join(File.dirname(__FILE__), "fancy_views"))
      enable :static
      
      PAGE_SIZE = 20
      
      class << self
        def get_paths(*paths, &blk)
          paths.each {|path| get path, &blk }
        end
      end
      
      ##
      # Extremely important method - this method sets up the server setting a
      # given path to represent the provided repository. Superclasses handle
      # actually setting up the repository for pushes/pulls, but this class
      # also adds the web interface on top of that. So this method needs to establish
      # all of the relevant web paths for Sinatra so Sinatra will handle
      # web requests.
      def self.amp_repository(http_path, repo, opts={})
        super(http_path, repo)
        
        # Normalize the http_path, because we'll be adding/removing slashes a lot
        # coming up.
        http_path.chomp!('/')
        
        ##
        # Defines a path to view a specific changeset by some unique identifier.
        #
        # - root/changeset/abcdef123456/  
        # -- shows changeset with id (possbily just a prefix) of abcdef123456
        get "#{http_path}/changeset/:changeset/?" do |cs|
          @changeset = repo[cs]
          haml :changeset, :locals => {:root => http_path, :repo => repo}
        end
        
        ##
        # Defines a set of paths for this repository to access a list
        # of commits. Thie defines the following paths:
        # - root/
        # - root/commits/
        # - root/commits/4/ (where 4 is a page number)
        get_paths "#{http_path}/", "#{http_path}/commits/?", "#{http_path}/commits/:page/?" do
          page  = params[:page] ? params[:page].to_i : 1
          start = repo.size - 1 - (page * PAGE_SIZE)
          commits_to_view = (start..(start + PAGE_SIZE)).to_a.map {|i| repo[i]}.reverse
          haml :commits, :locals => {:root => http_path, :opts => opts, :repo => repo, 
                                     :page => page, :commits => commits_to_view, 
                                     :pageroot => "#{http_path}/commits"}
        end

        
        ##
        # Shows the commits created by the user. Paginated. Same display as
        # the full-commit-listing.
        #
        # - root/users/adgar/
        # -- Views adgar's most recent PAGE_SIZE commits
        # - root/users/adgar/2/
        # -- Views the second page of adgar's commits
        get_paths "#{http_path}/users/:user/?", "#{http_path}/users/:user/:page/?" do
          page = params[:page] ? params[:page].to_i : 1
          all_users_commits = repo.select {|x| x.user == params[:user]}.reverse
          commits_to_view = all_users_commits.enum_slice(PAGE_SIZE).to_a[page-1]
          haml :commits, :locals => {:root => http_path, :opts => opts, :repo => repo, 
                                     :page => page, :commits => commits_to_view, 
                                     :pageroot => "#{http_path}/users/#{params[:user]}"}
        end
        
        ##
        # Directly access a file, possibly scoped by a changeset, for the
        # current repository. Defaults to tip if changeset is not specified, though
        # the changeset should only not be specified if accessing the root. Otherwise
        # things get messy.
        #
        # - root/code/
        # -- Views the root of the source tree at the tip revision
        # - root/code/tip/
        # -- Also views the root of the source tree at the tip revision
        # - root/code/tip/README
        # -- Views the README file at the tip revision
        # - root/code/abcdef/lib/amp/silly.rb
        # -- Views the file lib/amp/silly.rb at revision abcdef
        get_paths "#{http_path}/code/:changeset/?*", "#{http_path}/code/?*" do
          path = params[:splat].join.shift('/').chomp('/') # clean it of slashes
          changeset_node = params[:changeset] || "tip"
          changeset = repo[changeset_node]
          
          info = load_browser_info changeset, path
          browser_html = render_browser(repo, http_path, changeset_node, info)
          
          path, vf_cur, file_path = info[:path], info[:vf_cur], info[:file_path]
          
          haml :file, :locals => {:root => http_path, :repo => repo,
                                  :path => path,      :vf_cur => vf_cur, :file_path => file_path,
                                  :changeset => changeset, :browser_html => browser_html}
        end

        ##
        # Shows the diff of a file with its most recent changeset, scoped a
        # given changeset. No specifying diffs is really supported just yet. 
        # The file and changeset should be specified.
        #
        # - root/diff/tip/silly.rb
        # -- Shows the diff of silly.rb at tip and README at its most recent state
        # - root/diff/tip/
        # -- Shows the diff of a readme file at the root of the directory, or nothing at all,
        #    from the tip revision to its most recent state.
        get "#{http_path}/diff/:changeset/*" do
          path = params[:splat].join.shift('/').chomp('/') # clean it of slashes
          changeset_node = params[:changeset] || "tip"
          changeset = repo[changeset_node]
          
          info = load_browser_info changeset, path
          browser_html = render_browser(repo, http_path, changeset_node, info)
          
          path, vf_cur, file_path = info[:path], info[:vf_cur], info[:file_path]
          
          haml :file_diff, :locals => {:root => http_path, :repo => repo,
                                       :path => path,      :vf_cur => vf_cur, :file_path => file_path,
                                       :changeset => changeset, :browser_html => browser_html}
        end
        
        ##
        # Displays the raw data for the requested file at the given changeset. Does not
        # do any formatting. A file should always be provided. There is no default file.
        #
        # - /root/raw/abcdef1234/README.md
        # -- displays the raw markdown file README.md as it existed at revision abcdef1234
        get "#{http_path}/raw/:changeset/*" do
          changeset_node = params[:changeset]
          path = params[:splat].join.shift("/").chomp("/")
          
          changeset = repo[changeset_node]
          vf_cur = changeset.get_file path
          
          content_type "text/plain"
          vf_cur.data
        end
        
        ##
        # Retrieves the stylesheet for the code browser and web display
        # Uses sass.
        #
        # - /stylesheet.css
        get '/stylesheet.css' do
          content_type 'text/css', :charset => 'utf-8'
          sass :stylesheet
        end
        
      end
      
      helpers do
        
        ##
        # Prepares the file listing for the file browser when looking
        # at source, possibly scoped by a changeset. Has to be able
        # to tell directories apart from files.
        def load_browser_info(changeset, path)
          
          mapping = changeset.manifest_entry
          file_path = nil
          # if the path is a file (because we only keep track of files) look it
          # up directly
          if mapping[path]
            # give it the appropriate information (the versioned file)
            file_path = path
            path = Dir.dirname path
          elsif mapping.keys.grep(/^#{path}readme/i).any?
            # If we're not asking for a file, check if there's a readme.
            file_path = mapping.keys.grep(/^#{path}readme/i).first
          end
          # path is now the directory to view. force trailing slash.
          path << '/' unless path.empty?
          
          vf_cur = changeset.get_file(file_path) if file_path
          all_files = mapping.files.select {|f| f.start_with?(path)}.map {|x| x[path.size..-1].shift("/")}
          # files have no slash, directories do
          dirs, files = all_files.partition {|f| f.include?("/")}
          # get only the first level of subdirs
          dirs.map! {|dir| dir[0...dir.index("/")]}.uniq!
          
          # prepare file list for the browser
          file_list = files.map do |name|
            {:link => path + name, :type => :file, :name => name }
          end
          file_list += dirs.map do |name|
            {:link => path + name, :type => :directory , :name => name }
          end
          file_list.sort! {|h1, h2| h1[:name] <=> h2[:name] } # alphabetically sorted
                    
          {:path => path.chomp('/'), :vf_cur => vf_cur, :file_list => file_list, :file_path => file_path}
        end
        
        ##
        # Renders the file browser scoped for a repository, a path, a changeset node,
        # and the info prepared by load_browser_info.
        #
        # @param [Repository] repo the repository we're dealing with
        # @param [String] http_path the http_path we've assigned this repository to
        # @param [String] changeset_node the node we're scoped by
        # @param [Hash] info browser-related info provided by load_browser_info - consider opaque
        # @return [String] the HTML marking up the browser
        def render_browser(repo, http_path, changeset_node, info)
          info.merge!({:root => http_path, :changeset_node => changeset_node, :repo => repo})
          haml :_browser, :locals => info
        end
        
        ##
        # Links to a given user's page. This page provides information about that user's
        # commit history and any particular extra information.
        #
        # @param [String] root the root of this repository's http path
        # @param [String] user the name of the user to look up
        # @param [Hash<String=>String>] opts the HTML attributes to attach to the tag
        # @return [String] an HTML link to the user's info page
        def link_to_user(root, user, opts={})
          link(root, "users", user, nil, opts)
        end
        
        ##
        # Produces a generic link to an action on either a full changeset or
        # a file, scoped by a given repository. If a file is provided, the
        # request is also scoped by the changeset provided. Any additional
        # options are treated as html attributes to include.
        #
        # @param [String] root the root path of the repository
        # @param [Symbol] action the action to link to, such as :diff or :changeset
        # @param [String] changeset_node the unique ID identifying the changeset
        #   this action is scoped by
        # @param [String] file (nil) the file for the query. Can be nil, in which
        #   case the action operates on the entire repository (or the root)
        # @param [Hash<String => String>] opts the options to turn into html attribute-value
        #   pairs and inject into the link's markup
        # @return [String] an HTML link to the given action on a given repository,
        #   scoped by a changeset and a filepath.
        def link(root, action, changeset_node, file = nil, opts={})
          file = "/#{file}" if file
          changeset_node = changeset_node[0..11]
          text = opts.delete(:text) || changeset_node
          additional_opts = opts.map {|key, value| %{#{key}="#{value}"}}.join(" ")
          %{<a href="#{root}/#{action}/#{changeset_node}#{file}" #{additional_opts}>
              #{text}
            </a>}
        end
        
        ##
        # Provides a nice link to a changeset's root. Haml helper.
        #
        # @param [String] root the root of the repo's http path
        # @param [String] changeset_node the node to link to
        # @param [Hash] opts any options to use to modify the output html
        # @return [String] an HTML link to the given changeset.
        def link_to_changeset(root, changeset_node, opts={})
          link(root, :changeset, changeset_node, nil, opts)
        end
        
        ##
        # Provides a nice link to a file in the file browser at a given changeset. 
        # Haml helper. Defaults the text of the link to the name of the file
        #
        # @param [String] root the root of the repo's http path
        # @param [String] changeset_node the node to link to
        # @param [String] file (nil) the name of the file to load.
        # @param [Hash] opts any options to use to modify the output html
        # @return [String] an HTML link to the given file scoped by the given changeset.
        def link_to_file(root, changeset_node, file=nil, opts={})
          opts[:text] ||= file
          link(root, :code, changeset_node, file, opts)
        end
        
        ##
        # Provides a nice link to a file's raw source at a given changeset.
        #
        # @param [String] root the root of the repo's http path
        # @param [String] changeset_node the node to link to
        # @param [String] file (nil) the name of the file to load.
        # @param [Hash] opts any options to use to modify the output html
        # @return [String] an HTML link to the given file's raw source scoped by the
        #   given changeset
        def link_to_file_raw(root, changeset_node, file=nil, opts={})
          opts[:text] ||= file
          link(root, :raw, changeset_node, file, opts)
        end
        
        ##
        # Provides a nice link to a file at a given changeset diffed with its previous
        # changeset.
        #
        # @param [String] root the root of the repo's http path
        # @param [String] changeset_node the node to link to
        # @param [String] file (nil) the name of the file to diff.
        # @param [Hash] opts any options to use to modify the output html
        # @return [String] an HTML link to the given file's diffed source scoped by the
        #   given changeset
        def link_to_file_diff(root, changeset_node, file=nil, opts={})
          opts[:text] ||= file
          link(root, :diff, changeset_node, file, opts)
        end
        
        ##
        # Highlights the given text if possible, or at the very least, preformats it.
        # The rescue block currently protects if UV is not installed, as well as any
        # errors that arise from its usage (invalid syntaxes, etc.)
        #
        # @param [String] text the text to highlight
        # @param [Hash] options the options for highlighting
        # @option opts [String] :format ("ruby") Which code syntax to use
        # @option opts [String] :theme ("twilight") Which theme to display in
        # @option opts [Boolean] :lines (false) Should line numbers be displayed?
        # @return [String] an HTML string with the code preformatted for display in a web page
        def highlight_text(text, opts = {:format => "ruby", :theme => "twilight", :lines => false})
          begin
            require 'uv'
            ::Haml::Helpers.preserve(Uv.parse( text.rstrip, "xhtml", opts[:format].to_s, opts[:lines], opts[:theme]))
          rescue LoadError => err
            STDERR.puts "You should install UltraViolet for syntax highlighting goodness!"
            return "<pre>\n#{text}\n</pre>"
          rescue StandardError => err
            return "<pre>\n#{text}\n</pre>"
          end
        end
        
        ##
        # Returns a date relative to the current time based on the number
        # of intervening seconds. Accurate to the second.
        #
        # @param [Date, Time] o_date the date or time to compare to right now.
        # @return [String] a string representing the difference in time between the provided
        #   date and the current time.
        def rel_date(o_date)
          a = (Time.now-o_date).to_i
          case a
            when 0 then return 'just now'
            when 1 then return 'a second ago'
            when 2..59 then return a.to_s+' seconds ago' 
            when 60..119 then return 'a minute ago' #120 = 2 minutes
            when 120..3540 then return (a/60).to_i.to_s+' minutes ago'
            when 3541..7100 then return 'an hour ago' # 3600 = 1 hour
            when 7101..82800 then return ((a+99)/3600).to_i.to_s+' hours ago' 
            when 82801..172000 then return 'a day ago' # 86400 = 1 day
            when 172001..518400 then return ((a+800)/(60*60*24)).to_i.to_s+' days ago'
          end
          return o_date.strftime("%B %d, %Y")
        end
        
        ##
        # Returns the name of the ultraviolet syntax for a given filetype based on its extension.
        #
        # @param [String] ext the extension to parse
        # @return [Symbol] the symbol used by ultraviolet to highlight a file with the
        #   given extension.
        def format_for_filename(ext)
          # in case they passed in a full filename by mistake.
          ext = File.extname(ext)
          return :text if ext.nil? || ext.empty?
          
          # The following are special cases i could find, where the symbol
          # for the syntax isn't the same as the extension. I'm sure there's more.
          case ext.downcase
          when ".rb"
            :ruby
          when ".py"
            :python
          when ".cpp"
            :"c++"
          when ".txt"
            :text
          when ".md", ".markdown"
            :markdown
          else
            ext[1..-1].to_sym
          end
        end
        
        ##
        # Takes a diff, discards uninteresting lines, and wraps the interesting ones in specially
        # designed <li> tags, so we can style them.
        #
        # @parma [String] input_diff the diff text to prepare
        # @return [Array<String>] the lines of the diff to display
        def parse_diff(input_diff)
          line_counter_a, line_counter_b = 0, 0
          input_diff.split_lines_better.map do |line|
            if line[0,1] == ' '
              res = %{<li class='diff-unmod'><pre>#{line_counter_a} #{line_counter_b}&nbsp;#{line.rstrip}</pre></li>\n}
              line_counter_a += 1
              line_counter_b += 1
            elsif line[0,3] == '+++' # discard
            elsif line[0,3] == '---' # discard
            elsif line[0,1] == '+'
              res = %{<li class='diff-add'><pre>#{" " * line_counter_b.to_s.size} #{line_counter_b} &nbsp;#{line.rstrip}</pre></li>\n}
              line_counter_b += 1
            elsif line[0,1] == '-'
              res = %{<li class='diff-del'><pre>#{line_counter_a} #{" " * line_counter_a.to_s.size} &nbsp;#{line.rstrip}</pre></li>\n}
              line_counter_a += 1
            elsif line[0,2] == '@@'
              line_counter_a, line_counter_b = line.scan(/\-(\d+),\d+ \+(\d+),\d+/).shift.map {|x| x.to_i}
              res = %{<li class='diff-ctx'><pre>&nbsp;#{line.rstrip}</pre></li>\n}
            end
            res
          end
        end
      end
      
    end
  end
end
