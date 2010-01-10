

class String
	# escapes special characters
	def to_ansi
    self
	end
end

class String
  ##
  # Returns the string, encoded for a tty terminal with the given color code.
  #
  # @param [String] color_code a TTY color code
  # @return [String] the string wrapped in non-printing characters to make the text
  #   appear in a given color
  def colorize(color_code, closing_tag = 39)
    "\e[#{color_code}m#{self}\e[#{closing_tag}m"
  end
  
  [:black, :red, :green, :yellow, :blue, :magenta, :cyan, :white].tap do |list|
    list.each_with_index do |arg, idx|
      define_method(arg) { colorize(30 + idx, 39) }
      define_method("on_#{arg}") { colorize(40 + idx, 49) }
    end
    define_method :color do |*args|
      result = self
      args.each do |arg|
        if arg.to_s[0,3] == "on_"
        then base = 40; arg = arg.to_s[3..-1].to_sym
        else base = 30
        end
        result = result.colorize(base + list.index(arg), base + 9)
      end
      result
    end
  end
  
  # Returns the string, colored red.
  def bold; colorize(1, 22); end
  def underline; colorize(4, 24); end
  def blink; colorize(5, 25); end
end

module MaRuKu
  class MDDocument
	  # Render as a LaTeX fragment 
	  def to_ansi
		  children_to_ansi
	  end
  end
end

module MaRuKu
  module Out
    module Ansi 
	    
    	def to_ansi_hrule
    	  "\n#{'-' * 40}\n" 
    	end
    	def to_ansi_linebreak
    	  "\n " 
    	end

    	def to_ansi_paragraph 
    		children_to_ansi+"\n\n"
    	end

    	def latex_color(s, command='color')
    		if s =~ /^\#(\w\w)(\w\w)(\w\w)$/
    			r = $1.hex; g = $2.hex; b=$3.hex
    			# convert from 0-255 to 0.0-1.0
    			r = r / 255.0; g = g / 255.0; b = b / 255.0; 
    			"\\#{command}[rgb]{%0.2f,%0.2f,%0.2f}" % [r,g,b]
    		elsif s =~ /^\#(\w)(\w)(\w)$/
    			r = $1.hex; g = $2.hex; b=$3.hex
    			# convert from 0-15 to 0.0-1.0
    			r = r / 15.0; g = g / 15.0; b = b / 15.0; 
    			"\\#{command}[rgb]{%0.2f,%0.2f,%0.2f}" % [r,g,b]
    		else	
    			"\\#{command}{#{s}}"
    		end
    	end

    	def to_ansi_code
    	  source = self.raw_code
    		return source.to_s.black.on_green+"\n\n"
    	end


    	def to_ansi_header
        level = self.level
    		title = children_to_ansi
        length = title.size
        
        if level == 1 || level == 3 then title = title.bold end
        if level == 1 || level == 2 then title = title.underline end
        
        %{#{title}\n\n}
    	end

    	def to_ansi_ul
    	  children_to_ansi + "\n"
    	end

    	def to_ansi_quote
    	  wrap_as_environment('quote')
    	end
    	def to_ansi_ol
    	  wrap_as_environment('enumerate')
    	end
    	def to_ansi_li
    		"* #{children_to_ansi}\n"  
    	end
    	def to_ansi_li_span
    		"* #{children_to_ansi}\n"
    	end

    	def to_ansi_strong
    		"#{children_to_ansi}".bold
     	end
    	def to_ansi_emphasis
    		"#{children_to_ansi}".underline
    	end

    	def wrap_as_span(c)
    		"{#{c} #{children_to_ansi}}"
    	end

    	def to_ansi_inline_code
    		source = self.raw_code
    		return source.to_s.black.on_green
    	end

    	def to_ansi_immediate_link
    		url = self.url
    		text = url.gsub(/^mailto:/,'') # don't show mailto
        #	gsub('~','$\sim$')
    		text = latex_escape(text)
    		if url[0,1] == '#'
    			url = url[1,url.size]
    			return "\\hyperlink{#{url}}{#{text}}"
    		else
    			return "\\href{#{url}}{#{text}}"
    		end
    	end

    	def to_ansi_im_link
    		url = self.url

    		if url[0,1] == '#'
    			url = url[1,url.size]
    			return "#{children_to_ansi} (#{url})"
    		else
    			return "#{children_to_ansi} (#{url})"
    		end
    	end

    	def to_ansi_link
    		id = self.ref_id
    		ref = @doc.refs[id]
    		if not ref
    			$stderr.puts "Could not find id = '#{id}'"
    			return children_to_ansi
    		else
    			url = ref[:url]
    			#title = ref[:title] || 'no title'

    			if url[0,1] == '#'
    				url = url[1,url.size]
    				return "\\hyperlink{#{url}}{#{children_to_ansi}}"
    			else
    				return "\\href{#{url}}{#{children_to_ansi}}"
    			end
    		end

    	end

    	def to_ansi_email_address
    		"#{self.email}"
    	end

    	def to_ansi_raw_html
    		#'{\bf Raw HTML removed in ansi version }'
    		""
    	end

    	def to_ansi_abbr
    		children_to_ansi
    	end

    	# Convert each child to html
    	def children_to_ansi
    		array_to_ansi(@children)
    	end

    	def array_to_ansi(array, join_char='')
    		e = []
    		array.each do |c|
    			method = c.kind_of?(MDElement) ? "to_ansi_#{c.node_type}" : "to_ansi"

    			if not c.respond_to?(method)
    				next
    			end

    			h =  c.send(method)

    			if h.nil?
    				raise "Nil ansi for #{c.inspect} created with method #{method}"
    			end

    			if h.kind_of?Array
    				e = e + h
    			else
    				e << h
    			end
    		end

    		e.join(join_char)
    	end
    end 
  end 
end