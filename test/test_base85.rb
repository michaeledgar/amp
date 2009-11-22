require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestBase85 < Test::Unit::TestCase
  def test_encode
    assert_equal("Xk~0{Zy<DNWpZUKAZ>XdZeeX@AZc?TZE0g@VP$L~AZTxQAYpQ4AbD?fAarkJVR=6",
               Amp::Encoding::Base85.encode("hello there, my name is michael! how are you today?"))
  end
  
  def test_decode
    assert_equal("hello there, my name is michael! how are you today?",
               Amp::Encoding::Base85.decode("Xk~0{Zy<DNWpZUKAZ>XdZeeX@AZc?TZE0g@VP$L~AZTxQAYpQ4AbD?fAarkJVR=6"))
  end
end
