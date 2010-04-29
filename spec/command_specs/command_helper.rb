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