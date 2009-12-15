desc 'Statistics of Code'
task :stats do
  MINIMUM_LOC = 15
  DONT_COUNT = lambda do |file|
    [file =~ /lib\/amp\/dependencies\/zip/, file =~ /bz2/, file =~ /\/resources\//, 
     file =~ /^test/ && file.split("/").last !~ /^test/,
     file =~ /ext\/amp\/priority_queue\/priority_queue.c/,
     file =~ /amp\/dependencies\/priority_queue/].any?
  end
  
  require 'lib/amp/support/support.rb'
  
  puts "\nStats  ====================================="
  
  files = FileList['lib/**/*.rb'] +
          FileList["test/**/*.rb"] +
          FileList["ext/**/*.c"]
  
  puts ScriptLines.headline
  sum = ScriptLines.new("TOTAL (#{files.size} file#{files.size == 1 ? '' : 's'})")

  # Print stats for each file.
  files.each do |fn|
    next if DONT_COUNT[fn]
    File.open(fn) do |file|
      klass = (fn =~ /\.rb/) ? RubyScriptLines : CScriptLines
      script_lines = klass.new(fn)
  	  script_lines.read(file)
      sum += script_lines
      puts script_lines unless script_lines.lines_of_code < MINIMUM_LOC
    end
  end

  # Print total stats.
  puts sum
  puts "Percent comments: %.2f%" % [(sum.comment_lines.to_f / sum.lines_of_code) * 100]
end

# 
# Graciously ripped from the Ruby Cookbook
# which, btw, rocks
class ScriptLines

  attr_reader :name
  attr_accessor :bytes, :lines, :lines_of_code, :comment_lines

  LINE_FORMAT = '%8s %8s %8s %8s %s'

  def self.headline
    sprintf LINE_FORMAT, "BYTES", "LINES", "LOC", "COMMENT", "FILE"
  end

  # The 'name' argument is usually a filename
  def initialize(name)
    @name = name
    @bytes = 0
    @lines = 0    # total number of lines
    @lines_of_code = 0
    @comment_lines = 0
  end


  # Get a new ScriptLines instance whose counters hold the
  # sum of self and other.
  def +(other)
    sum = self.dup
    sum.bytes += other.bytes
    sum.lines += other.lines
    sum.lines_of_code += other.lines_of_code
    sum.comment_lines += other.comment_lines
    sum
  end

  # Get a formatted string containing all counter numbers and the
  # name of this instance.
  def to_s
    nom = (@comment_lines.to_f / @lines_of_code.to_f) < 0.4 ? @name.red   : @name
    nom = (@comment_lines.to_f / @lines_of_code.to_f) > 0.8 ? @name.green : nom
    
    sprintf LINE_FORMAT,
    @bytes, @lines, @lines_of_code, @comment_lines, nom
  end
end

class RubyScriptLines < ScriptLines
  
  # Iterates over all the lines in io (io might be a file or a
  # string), analyses them and appropriately increases the counter
  # attributes.
  def read(io)
    in_multiline_comment = false
    io.each { |line|
      @lines += 1
      @bytes += line.size
      case line
      when /^=begin(\s|$)/
        in_multiline_comment = true
        @comment_lines += 1
      when /^=end(\s|$)/
        @comment_lines += 1
        in_multiline_comment = false
      when /^\s*#/
        @comment_lines += 1
      when /^\s*$/
        # empty/whitespace only line
      else
        if in_multiline_comment
          @comment_lines += 1
        else
          @lines_of_code += 1
        end
      end
    }
  end
end
class CScriptLines < ScriptLines
  
  # Iterates over all the lines in io (io might be a file or a
  # string), analyses them and appropriately increases the counter
  # attributes.
  def read(io)
    in_multiline_comment = false
    io.each { |line|
      @lines += 1
      @bytes += line.size
      case line
      when /^\s*\/\*/
        in_multiline_comment = true unless line =~ /\*\//
        @comment_lines += 1
      when /\*\//
        @comment_lines += 1
        in_multiline_comment = false
      when /^\s*\/\//
        @comment_lines += 1
      when /^\s*$/
        # empty/whitespace only line
      else
        if in_multiline_comment
          @comment_lines += 1
        else
          @lines_of_code += 1
        end
      end
    }
  end
end