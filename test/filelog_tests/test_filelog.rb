require File.join(File.expand_path(File.dirname(__FILE__)), '../testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp"))

require 'minitest/spec'
require 'minitest/mock'

class TestFilelog < AmpTestCase
  
  def setup
    opener = Amp::Opener.new(File.dirname(__FILE__))
    opener.default = :open_file
    @filelog = Amp::Mercurial::FileLog.new(opener, "_manifest.txt.i")
  end
  
  def test_load_changelog
    assert_not_nil @filelog
  end
  
  def test_detect_metadata
    assert @filelog.has_metadata?("\1\nsomedata\1\notherdata")
  end
  
  def test_detect_lack_of_metadata
    assert_false @filelog.has_metadata?("otherdata")
  end
  
  def test_finds_start_of_normal_data
    assert_equal 12, @filelog.normal_data_start("\1\nsomedata\1\notherdata")
  end
  
  def test_finds_end_of_meta_data
    assert_equal 10, @filelog.metadata_end("\1\nsomedata\1\notherdata")
  end
  
  def test_can_read_normal_data
    def @filelog.decompress_revision(node)
      "somedata"
    end
    assert_equal "somedata", @filelog.read("abc")
  end
  
  def test_can_read_data_with_meta
    def @filelog.decompress_revision(node)
      "\1\nmetametameta\1\nnormaldata"
    end
    assert_equal "normaldata", @filelog.read("cde")
  end
  
  def test_can_read_metadata
    def @filelog.decompress_revision(node)
      "\1\nmetakey: metavalue\notherkey: othervalue\n\1\nnormaldata"
    end
    expected = {"metakey" => "metavalue", "otherkey" => "othervalue"}
    assert_equal expected, @filelog.read_meta("cde")
  end
  
  def test_can_read_no_metadata
    def @filelog.decompress_revision(node)
      "normaldata"
    end
    expected = {}
    assert_equal expected, @filelog.read_meta("cde")
  end
  
  def test_can_inject_metadata
    meta = {"metakey" => "metavalue", "otherkey" => "othervalue"}
    text = "normaldata"
    expected_1 = "\1\nmetakey: metavalue\notherkey: othervalue\n\1\nnormaldata"
    expected_2 = "\1\notherkey: othervalue\nmetakey: metavalue\n\1\nnormaldata"
    result = @filelog.inject_metadata(text, meta)
    if result != expected_1 && result != expected_2
      flunk "#{result.inspect} should be either #{expected_1.inspect} or #{expected_2.inspect}"
    else
      assert true # count this as a passed assertion :-)
    end
  end
  
  def test_can_inject_null_metadata
    meta = {}
    text = "normaldata"
    expected = "normaldata"
    assert_equal expected, @filelog.inject_metadata(text, meta)
  end
end