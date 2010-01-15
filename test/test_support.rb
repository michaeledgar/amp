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
  
  def test_absolute
    root = "/root"
    paths = { "/Monkey"  => "/Monkey",
              "asd/asdf" => "/root/asd/asdf",
              "bllop"    => "/root/bllop"
            }
    
    paths.each do |path, result|
      assert_equal result, path.absolute(root)
    end
  end
  
  def test_opposite_method
    obj = OppositeMethodTestKlass.new
    assert_respond_to obj, :opposite
    assert obj.base(true)
    assert_false obj.opposite(true)
    assert_false obj.base(false)
    assert obj.opposite(false)
  end
  
end



