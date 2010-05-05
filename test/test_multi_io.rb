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

require 'stringio'
require File.join(File.expand_path(File.dirname(__FILE__)), 'testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp/support/multi_io"))

class TestMultiIO < AmpTestCase
  def setup
    input1 = StringIO.new("input1")
    input2 = StringIO.new("input2input2")
    input3 = StringIO.new("input3")
    @multi_io = Amp::Support::MultiIO.new(input1, input2, input3)
  end
  
  def test_read_all
    assert_equal "input1input2input2input3", @multi_io.read
  end
  
  def test_read_3_bytes
    assert_equal "inp", @multi_io.read(3)
  end
  
  def test_rewind
    @multi_io.read(3)
    @multi_io.rewind
    assert_equal 0, @multi_io.tell
  end
  
  def test_pos
    @multi_io.read(7)
    assert_equal 7, @multi_io.tell
  end
  
  def test_read_crossing_ios
    assert_equal "input1inp", @multi_io.read(9)
    assert_equal "ut2input2in", @multi_io.read(11)
    assert_equal "put3", @multi_io.read
  end
  
  
  
end
