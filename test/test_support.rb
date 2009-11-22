require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestSupport < Test::Unit::TestCase
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
  
end



