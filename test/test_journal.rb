require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestJournal < Test::Unit::TestCase
  def test_journal
    tfile = "tempjournal"
    j = Amp::Mercurial::Journal.new(Amp::StandardErrorReporter, tfile, nil)
    j << ["file",12345]
    
    
    test_open = open(tfile)
    assert_equal("file\0#{12345}\n", test_open.read)
    test_open.close
    j.close
    
    assert !File.exists?(tfile)
  end
  
  def test_journal_start_mode
    tfile = "tempjournal"
    Amp::Mercurial::Journal.start tfile do |j|
      j << ["file",12345]
      test_open = open(tfile)
      assert_equal("file\0#{12345}\n", test_open.read)
      test_open.close
    end
    assert !File.exists?(tfile)
  end
end