require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestMdiff < Test::Unit::TestCase
  include Amp::Diffs::Mercurial

  def test_default_whitespace_clean
    opts = MercurialDiff::DEFAULT_OPTIONS.dup
    result = MercurialDiff.whitespace_clean(" hello \n\r \t\t what's \t\n up\t there",
                                            opts)
    expected = " hello \n\r \t\t what's \t\n up\t there"
    assert_equal(expected, result)
  end
  def test_whitespace_clean_ignore_ws
    opts = MercurialDiff::DEFAULT_OPTIONS.dup
    opts[:ignore_ws] = true
    result = MercurialDiff.whitespace_clean(" hello \n\r \t\t what's \t\n up\t there",
                                            opts)
    expected = "hello\n\rwhat's\nupthere"
    assert_equal(expected, result)
  end
  def test_whitespace_clean_ignore_ws_amount
    opts = MercurialDiff::DEFAULT_OPTIONS.dup
    opts[:ignore_ws_amount] = true
    result = MercurialDiff.whitespace_clean(" hello \n\r \t\t what's \t\n up\t there",
                                            opts)
    expected = " hello\n\r what's\n up there"
    assert_equal(expected, result)
  end
  def test_whitespace_clean_ignore_blank_lines
    opts = MercurialDiff::DEFAULT_OPTIONS.dup
    opts[:ignore_blank_lines] = true
    result = MercurialDiff.whitespace_clean(" hello \n\r \t\t what's \t\n up\t there",
                                            opts)
    expected = " hello \r \t\t what's \t up\t there"
    assert_equal(expected, result)
  end
  def test_whitespace_clean_all_ignored
    opts = MercurialDiff::DEFAULT_OPTIONS.dup
    opts[:ignore_blank_lines] = opts[:ignore_ws_amount] = opts[:ignore_ws]=true
    result = MercurialDiff.whitespace_clean(" hello \n\r \t\t what's \t\n up\t there",
                                            opts)
    expected = "hello\rwhat'supthere"
    assert_equal(expected, result)
  end
  
  def test_diffline_default
    opts = MercurialDiff::DEFAULT_OPTIONS.dup
    result = MercurialDiff.diff_line([1,2], "hello there", "hello mom", opts)
    expected = "diff -r 1 -r 2 hello there\n"
    assert_equal(expected, result)
  end
  def test_diffline_git
    opts = MercurialDiff::DEFAULT_OPTIONS.dup
    opts[:git] = true
    result = MercurialDiff.diff_line([1,2], "hello there", "hello mom", opts)
    expected = "diff --git a/hello there b/hello mom\n"
    assert_equal(expected, result)
  end
  
  def test_unified_diff
    opts = MercurialDiff::DEFAULT_OPTIONS.dup
    original_day = Time.local(2009, 3, 30, 9, 45, 15, 123456)
    second_day = Time.local(2009, 4, 2, 3, 17, 53, 654321)
    start_text = "line 1 is long\nline two isn't\n\nwe just had a blank line\ncool or what?\nlol ok last line\n\n\njust kidding"
    end_text = "line 1 is short\nline two isn't\n\n\nwe just had a blank line\ncool or lame?\nlol ok last line\n\njust kidding\nfor serious now"
    expected = "--- a/hello_there.rb\t2009-03-30 09:45:15.123456\n+++ b/hello_there.rb\t2009-04-02 03:17:53.654321\n" +
               "@@ -1,9 +1,10 @@\n-line 1 is long\n+line 1 is short\n line two isn't\n \n+\n we just had a blank line\n" +
               "-cool or what?\n+cool or lame?\n lol ok last line\n \n-\n-just kidding\n\\ No newline at end of file\n+just "+
               "kidding\n+for serious now\n\\ No newline at end of file\n"
    result = MercurialDiff.unified_diff(start_text, original_day, end_text, second_day, "hello_there.rb", "hello_there.rb")
    
  end
end
