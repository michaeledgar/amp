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
