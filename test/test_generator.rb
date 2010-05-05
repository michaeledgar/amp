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

require File.join(File.expand_path(File.dirname(__FILE__)), 'testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp/support/generator"))

class FibonacciGeneratorTester < Generator
  def generator_loop
    a, b = 0, 1
    while true
      yield_gen b
      a, b = b, a + b
    end
  end
end

class TestGenerator < AmpTestCase
  def setup
    @generator = FibonacciGeneratorTester.new
  end
  
  def test_next
    assert_equal 1, @generator.next
    assert_equal 1, @generator.next
    assert_equal 2, @generator.next
    assert_equal 3, @generator.next
    assert_equal 5, @generator.next
  end
  
  def test_reset
    10.times { @generator.next }
    #reset it, first num should be 1
    @generator.reset
    assert_equal 1, @generator.next
  end
  
end