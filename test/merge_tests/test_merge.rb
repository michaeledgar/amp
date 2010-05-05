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

require File.join(File.expand_path(File.dirname(__FILE__)), '../testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp"))

class TestMerge < AmpTestCase
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
    Amp::Merges::Mercurial::ThreeWayMerger.three_way_merge(TEST_LOCAL, TEST_BASE, TEST_REMOTE,
                                                :labels => ["local","other"])
    $stderr = old # and reassign
    
    File.move TEST_LOCAL , TEST_OUT
    File.move TEST_BACKUP, TEST_LOCAL
    assert_equal File.read(TEST_EXPECTED), File.read(TEST_OUT)
  end
  
end