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

# Kernel.module_eval do
# 
#   show_caller_for :catch, "$hash[caller[0]] += 1"
# #  show_caller_for :throw, "$hash[caller[0]] += 1"
# end

if ENV["TESTING"] == "true"
  END {
    require 'pp'
    puts $hash.sort.inspect if $hash.any?
  }
end
