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
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class OppositeMethodTestKlass
  def base(input)
    !!input
  end
  opposite_method :opposite, :base
end

class TestSupport < AmpTestCase
  def test_split_newlines
    assert_equal(["hi there what's\n", "\r up there\r kids\n", " lol"], "hi there what's\n\r up there\r kids\n lol".split_newlines)
  end
  
  def test_opposite_method
    obj = OppositeMethodTestKlass.new
    assert_respond_to obj, :opposite
    assert obj.base(true)
    assert_false obj.opposite(true)
    assert_false obj.base(false)
    assert obj.opposite(false)
  end
  
  def test_array_hash
    hash = ArrayHash.new
    assert_equal [], hash[:hello]
    hash[:other] << "hi"
    assert_equal ["hi"], hash[:other]
  end
  
  def test_symbol_to_proc
    assert_equal [1,2,3], ["1","2","3"].map(&:to_i)
  end
  
  def test_time_to_diff
    t = Time.at(1234567890.123456)
    expected = "2009-02-13 18:31:30.123456"
    assert_equal expected, t.to_diff
  end
  
  def test_hide_password
    url = "http://user:password@www.bob.com/"
    expected = "http://user:***@www.bob.com/"
    assert_equal expected, url.hide_password
    
    url = "https://u:somepass@.ru" # weird URL
    expected = "https://u:***@.ru"
    assert_equal expected, url.hide_password
  end
  
  def test_hexlify
    assert_equal "0102dead", "\x01\x02\xde\xad".hexlify
    assert_equal "fffedabb1234", "\xff\xfe\xda\xbb\x12\x34".hexlify
  end
  
  ###
  # File additions. Really it's more just like 
end



