require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp"))

class TestMerge < Test::Unit::TestCase
  TEST_BASE = File.expand_path(File.join(File.dirname(__FILE__), 'base.txt'))
  TEST_LOCAL = File.expand_path(File.join(File.dirname(__FILE__), 'local.txt'))
  TEST_REMOTE = File.expand_path(File.join(File.dirname(__FILE__), 'remote.txt'))
  TEST_EXPECTED = File.expand_path(File.join(File.dirname(__FILE__), 'expected.local.txt'))
  TEST_OUT = File.expand_path(File.join(File.dirname(__FILE__), 'local.txt.out'))
  TEST_BACKUP = File.expand_path(File.join(File.dirname(__FILE__), 'local.txt.bak'))
  
  def test_full_merge
    File.copy TEST_LOCAL, TEST_BACKUP
    
    # kill the error output...
    old, $stderr = $stderr, StringIO.new
    Amp::Merges::ThreeWayMerger.three_way_merge(TEST_LOCAL, TEST_BASE, TEST_REMOTE,
                                                :labels => ["local","other"])
    $stderr = old # and reassign
    
    File.move TEST_LOCAL , TEST_OUT
    File.move TEST_BACKUP, TEST_LOCAL
    assert_equal File.read(TEST_EXPECTED), File.read(TEST_OUT)
  end
  
end