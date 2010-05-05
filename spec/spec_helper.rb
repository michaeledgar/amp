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

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'amp'
require 'spec'
require 'spec/autorun'
require 'stringio'

def with_swizzled_io
  swizzled_out, $stdout = $stdout, StringIO.new
  yield
  $stdout, swizzled_out = swizzled_out, $stdout
  return swizzled_out.string
end

Spec::Runner.configure do |config|
  
end
