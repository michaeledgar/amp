# alias old_puts puts
# def puts(*args)
#   return if args.empty?
#   old_puts (['[', caller[0].inspect, ' -- ', *args] << ']').join
# end
# 
# alias old_p p
# def p(*args)
#   args.map! {|a| a.inspect }
#   old_puts (['[', caller[0].inspect, ' -- ', *args] << ']').join
# end

##
def show_caller_for(meth, lines, new_meth="__#{meth}__")
  lines = [*lines]
  alias_method "#{new_meth}".to_sym, meth
  self.class_eval(<<-HELP)
def #{meth}(*args, &block)
  #{lines.join("\n")}
  #{new_meth}(*args, &block)
end
HELP
end

$hash = Hash.new {|h, k| h[k] = 0 }
# 
# String.class_eval do
#   show_caller_for :split_newlines, "$hash[caller[0]] += 1"
# end

if ENV["TESTING"] == "true"
  END {
    require 'pp'
    STDERR.puts $hash.inspect if $hash.any?
  }
end
