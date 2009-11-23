require 'uv'
require 'haml'
def stylesheet(*args)
  result = []
  args.each do |name|
    result << %Q{<link href="/css/#{name}.css" rel="stylesheet" type="text/css" />}
  end
  result.join("\n")
end
alias :stylesheets :stylesheet

def render(path, locals={})
  path = (path =~ /src/ ? path : File.join(File.dirname(__FILE__), path))
  haml = Haml::Engine.new(File.read(path))
  return haml.render(Object.new, locals)
end

def javascript(*scripts)
  result = []
  scripts.each do |name|
    result << %Q{<script language='javascript' src='/scripts/#{name}' type='text/javascript'></script>}
  end
  result.join("\n")
end
alias :javascripts :javascript

def shellscript(text)
  "<span class='shellscript'>#{text}</span>"
end

def symbol(text)
  "<span class='ruby-symbol'>#{text.is_a?(Symbol) ? text.inspect : text}</span>"
end



def ruby_link(text = "Ruby")
  link_to "http://www.ruby-lang.org/", text
end

def git_link(text = "git")
  link_to "http://git-scm.com/", text
end

def hg_link(text = "Mercurial")
  link_to "http://mercurial.selenic.com/", text
end

def yard_link(text = "YARD")
  link_to "http://yard.soen.ca/", text
end

def lighthouse_link(text = "Lighthouse")
  link_to "http://carbonica.lighthouseapp.com/projects/35539-amp/tickets/new", text
end

%w(workflows ampfile commands).each do |link|
  eval %Q{
    def #{link}_link(text="#{link}")
      link_to "/about/#{link}.html", text
    end
  }
end

def contribute_link(text = "contribute")
  link_to "/contribute/", text
end

def link_to(link, text)
  "<a href='#{link}'>#{text}</a>"
end

def blue_amp(text = "amp")
  "<span class='amp'>#{text}</span>"
end

def commit_count
  path_to_amp = File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "bin", "amp"))
  hash = %x(#{path_to_amp} stats).split("\n").inject({}) do |hash, line|
    result = line.split(/\s+/)
    next unless result.size >= 2
    hash[result[0][0..-2]] = result[1].to_i
    hash
  end
  hash["<a href='mailto:adgar@carboni.ca'>adgar</a>"] = hash.delete("michaeledgar") + 558 # old repo
  hash["<a href='mailto:seydar@carboni.ca'>seydar</a>"] = hash.delete("seydar") + (hash.delete("ari") || 0) + 251                      # old repo
  
  hash = hash.sort do |(key1, value1), (key2, value2)|
    value2 <=> value1
  end
  hash
end

def themes
  [ :active4d, :all_hallows_eve, :amy, :blackboard, :brilliance_black, :brilliance_dull, 
    :cobalt, :dawn, :eiffel, :espresso_libre, :idle, :iplastic, :lazy, :mac_classic, :magicwb_amiga, 
    :pastels_on_dark, :slush_poppies, :spacecadet, :sunburst, :twilight, :zenburnesque]
end

module SyntaxHighlighter
  include Haml::Filters::Base
  def initialize(text)
    @text = highlight_text(text)
  end
  def highlight_text(text, opts = {:format => "ruby", :theme => "twilight", :lines => false})
    Uv.parse( text, "xhtml", opts[:format], opts[:lines], opts[:theme])
  end
  def render(text)
    all_lines = text.split(/\n/)
    if all_lines.first =~ /#!highlighting/
      line = all_lines.first
      syntax = (line =~ /syntax=([\w-]+)/) ? $1 : "ruby"
      theme = (line =~ /theme=(\w+)/) ? $1 : "twilight"
      lines = (line =~ /lines=(\w+)/) ? ($1 == 'true') : false
      text = all_lines[1..-1].join("\n")
      Haml::Helpers.preserve(highlight_text(text.rstrip, :format => syntax, :theme => theme, :lines => lines))
    else
      Haml::Helpers.preserve(highlight_text(text.rstrip))
    end
  end
end
