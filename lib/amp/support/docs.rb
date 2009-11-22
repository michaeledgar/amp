require 'rubygems'
require 'yard'

YARD::Registry.load

module Docable
  
  def tag_callbacks; @tag_callbacks ||= {}; end
  
  def tag_callback(name, &block)
    tag_callbacks[name] = block
  end
  
  def docs_for(method)
    klass = YARD::Registry.all(:class).detect do |k|
      k.name == name.split("::").last.to_sym
    end
    
    meth = klass.meths.detect {|m| m.name == method }
    
    puts "=== Documentation for #{self}##{method}"
    puts meth.docstring
    puts "---"
    puts meth.signature
    puts
    
    tag_callbacks.to_a.sort.each do |(tag, block)|
      if meth.has_tag? tag
        puts
        tags = meth.tags.select {|t| t.tag_name == tag.to_s }
        block.call meth, tags
        puts
      end
    end
    
    puts "It can be found at #{meth.file}:#{meth.line}"
    puts "==="
  end
end

class Object
  extend Docable
  
  tag_callback :param do |meth, tags|
    puts "Arguments are:"
    tags.each do |p|
      puts "\t[#{p.types.join ', '}] #{p.name} #{"|" if p.text } #{p.text}"
    end
  end
  
  tag_callback :tags do |meth, tags|
    puts "Tagged with: #{tags.map {|t| t.tags }.join ', '}"
  end
end
