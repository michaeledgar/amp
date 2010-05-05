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

require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp/commands/command.rb"))
include Amp::KernelMethods
extend  Amp::KernelMethods
require_dir { 'amp/commands/commands/*.rb'}
require_dir { 'amp/commands/commands/workflows/hg/*.rb'}
$display = true

def easy_get_command(flow, cmd)
  Amp::Command.workflows[flow.to_sym][cmd.to_sym]
end