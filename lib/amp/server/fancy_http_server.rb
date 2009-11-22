require 'rubygems'
require 'haml'
require 'sass'

class Hash
  alias_method :get, :[]
  ##
  # Same as #[], but will take regexps and try to match those.
  # This will bug out if you are using regexps as keys
  # 
  # @return [Hash, Value] will return either a hash (if supplied with a regexp)
  #   or whatever it would normally return.
  def [](key)
    case key
    when Regexp
      select {|k, _| k =~ key }.to_hash
    else
      get key
    end
  end
end

module Amp
  module Servers
    
    class FancyHTTPServer < HTTPAuthorizedServer
      
      set :views, File.expand_path(File.join(File.dirname(__FILE__), "fancy_views"))
      enable :static
      set :public, File.expand_path(File.join(File.dirname(__FILE__), "fancy_views"))
      
      def self.amp_repository(http_path, repo, opts={})
        super(http_path, repo)
        
        http_path.chomp!('/')
        path_slashed = http_path + "/"
        
        get "#{http_path}/changeset/:changeset/?" do |cs|
          @changeset = repo[cs]
          haml :changeset, :locals => {:root => http_path, :repo => repo}
        end
        
        
        [http_path+"/", "#{http_path}/commits/?", "#{http_path}/commits/:page/?"].each do |path|
          get path do
            haml :commits, :locals => {:root => http_path, :opts => opts, :repo => repo, :page => params[:page].to_i}
          end
        end
        
        
        get "#{http_path}/users/:user" do
          if users[params[:user]]
            "You are browsing user #{params[:user]} in a repository located at #{repo.inspect}"
          else
            "User #{params[:user].inspect} not found :-("
          end
        end
        
        ["#{http_path}/code/:changeset/?*", "#{http_path}/code/?*"].each do |p|
          get p do
            path = params[:splat].join
            path = path.shift('/').chomp('/') # clean it of slashes
            changeset_node = params[:changeset] || "tip"
            changeset = repo[changeset_node]
            
            info = load_browser_info changeset, path
            file_list, path, vf_cur, orig_path = info[:file_list], info[:path], info[:vf_cur], info[:orig_path]
            
            haml :file, :locals => {:root => http_path, :repo => repo,     :file_list => file_list,
                                    :path => path,      :vf_cur => vf_cur, :orig_path => orig_path,
                                    :changeset => changeset}
          end
        end

        get "#{http_path}/diff/:changeset/*" do
          path = params[:splat].join
          path = path.shift('/').chomp('/') # clean it of slashes
          changeset_node = params[:changeset] || "tip"
          changeset = repo[changeset_node]
          
          info = load_browser_info changeset, path
          file_list, path, vf_cur, orig_path = info[:file_list], info[:path], info[:vf_cur], info[:orig_path]
          
          haml :file_diff, :locals => {:root => http_path, :repo => repo,     :file_list => file_list,
                                  :path => path,      :vf_cur => vf_cur, :orig_path => orig_path,
                                  :changeset => changeset}
        end
        
        get "#{http_path}/raw/:changeset/*" do
          changeset_node = params[:changeset]
          path = params[:splat].join.shift("/").chomp("/")
          
          changeset = repo[changeset_node]
          vf_cur = changeset.get_file path
          
          content_type "text/plain"
          vf_cur.data
        end
        
        get '/stylesheet.css' do
          content_type 'text/css', :charset => 'utf-8'
          sass :stylesheet
        end
        
      end
      
      helpers do
        
        def load_browser_info(changeset, path)
          
          mapping = changeset.manifest
          orig_path = nil
          # if the path is a file (because we only keep track of files)
          if mapping[path]
            # give it the appropriate information (the versioned file)
            vf_cur    = changeset.get_file(path)
            file_list = [] # and return an empty file_list
            orig_path = path
            path = Dir.dirname path
          end
          
          files = mapping.files.select {|f| Dir.dirname(f) == path }.map {|f| f[path.size..-1].shift '/' }
          dirs  = mapping.files.select {|f| File.amp_directories_to(f, true).index(path) && Dir.dirname(f) != path } # only go one deep
          dirs.map! do |d|
            idx = File.amp_directories_to(d, true).index path
            File.amp_directories_to(d, true)[idx - 1][path.size..-1].shift '/'
          end.uniq!
          
          path = path.empty? ? '' : path + '/'
          
          file_list = files.map do |name|
            {:link => path + name ,
             :type => :file,
             :name => name }
          end
          
          file_list += dirs.map do |name|
            {:link => path + name,
             :type => :directory ,
             :name => name       }
          end
          
          file_list.sort! {|h1, h2| h1[:name] <=> h2[:name] } # alphabetically sorted
          vf_cur ||= if mapping[/#{path}readme/i].any? # map[//] returns a hash
                       change_id = params[:changeset] || "tip"
                       readme    = mapping[/#{path}readme/i].keys.first
                       orig_path = readme
                       changeset.get_file readme
                     else
                       nil
                     end
          
          path = path.chomp '/' # path will not have any trailing slashes
          
          {:path => path, :vf_cur => vf_cur, :file_list => file_list, :orig_path => orig_path}
        end
        
        def link(root, action, changeset_node, after_path, opts={})
          after_path = "/#{after_path}" if after_path
          changeset_node = changeset_node[0..11]
          text = opts.delete(:text) || changeset_node
          additional_opts = opts.map {|key, value| %{#{key}="#{value}"}}.join(" ")
          %{<a href="#{root}/#{action}/#{changeset_node}#{after_path}" #{additional_opts}>
              #{text}
            </a>}
        end
        
        def link_to_changeset(root, changeset_node, opts={})
          link(root, :changeset, changeset_node, nil, opts)
        end
        
        def link_to_file(root, changeset_node, file=nil, opts={})
          opts[:text] ||= file
          link(root, :code, changeset_node, file, opts)
        end
        
        def link_to_file_raw(root, changeset_node, file=nil, opts={})
          opts[:text] ||= file
          link(root, :raw, changeset_node, file, opts)
        end
        
        def link_to_file_diff(root, changeset_node, file=nil, opts={})
          opts[:text] ||= file
          link(root, :diff, changeset_node, file, opts)
        end
        
        def highlight_text(text, opts = {:format => "ruby", :theme => "twilight", :lines => false})
          require 'uv'
          ::Haml::Helpers.preserve(Uv.parse( text.rstrip, "xhtml", opts[:format].to_s, opts[:lines], opts[:theme]))
        end
        
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
        
        def format_for_filename(ext)
          ext = File.extname(ext)
          return :text if ext.nil? || ext.empty?
          
          case ext.downcase
          when ".rb"
            :ruby
          when ".py"
            :python
          when ".cpp"
            :"c++"
          when ".txt"
            :text
          else
            ext[1..-1].to_sym
          end
        end
        
        def parse_diff(input_diff)
          line_counter_a, line_counter_b = 0, 0
          input_diff.split_lines_better.map do |line|
            if line[0,1] == ' '
              res = %{<li class='diff-unmod'><pre>#{line_counter_a} #{line_counter_b}&nbsp;#{line.rstrip}</pre></li>\n}
              line_counter_a += 1
              line_counter_b += 1
            elsif line[0,3] == '+++'
            elsif line[0,3] == '---'
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
