require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestBdiff < Test::Unit::TestCase
  include Amp::Diffs

  def test_create_bdiff
    input = "hi there\ni'm cool"
    output = "hi there\ni'm stupid"
    expected_output = "\000\000\000\t\000\000\000\021\000\000\000\ni'm stupid"
    assert_equal(expected_output, BinaryDiff.bdiff(input, output))
  end
  
  def test_another_bdiff
    input = "c913df15006c6e06504414acf8acfedd32e5875d\nmichaeledgar@michael-edgars-macbook-pro.local"+
            "\n1248396415 14400\nSTYLE.txt\n\nFirst commit."
    output = "b2a7f7ab636d1dbd06afd90f1bf287dfb92762fb\nmichaeledgar@michael-edgars-macbook-pro.local"+
             "\n1248396417 14400\ncommand.rb\ncommands/annotate.rb\ncommands/heads.rb"+
             "\ncommands/manifest.rb\ncommands/status.rb\n\nSecond commit, added commands"
    expected_output = "\x00\x00\x00\x00\x00\x00\x00)\x00\x00\x00)b2a7f7ab636d1dbd06afd90f1bf287dfb92762fb"+
                      "\n\x00\x00\x00W\x00\x00\x00r\x00\x00\x00k1248396417 14400\ncommand.rb"+
                      "\ncommands/annotate.rb\ncommands/heads.rb\ncommands/manifest.rb"+
                      "\ncommands/status.rb\n\x00\x00\x00s\x00\x00\x00\x80\x00\x00\x00\x1d"+
                      "Second commit, added commands"
    assert_equal(expected_output, BinaryDiff.bdiff(input, output))
  end
  
  def test_yet_another_bdiff
    input = "The Amp Commandments Redux:\n\t1. This is intended to genreate a conflict. "+
            "I'm out of witty stuff to put here."
    output = "\t1. This is intended to genreate a conflict. I'm out of witty stuff to put here."
    expected_output = "\x00\x00\x00\x00\x00\x00\x00\x1c\x00\x00\x00\x00"
    assert_equal(expected_output, BinaryDiff.bdiff(input, output))
  end
  
  def test_create_simple_bdiff
    input = ""
    output = "hi there\ni'm stupid"
    expected_output = "\000\000\000\000\000\000\000\000\000\000\000\x13"+output
    assert_equal expected_output, BinaryDiff.bdiff(input, output)
  end
end
