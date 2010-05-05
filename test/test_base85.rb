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

class TestBase85 < AmpTestCase
  def test_encode
    assert_equal("Xk~0{Zy<DNWpZUKAZ>XdZeeX@AZc?TZE0g@VP$L~AZTxQAYpQ4AbD?fAarkJVR=6",
               Amp::Encoding::Base85.encode("hello there, my name is michael! how are you today?"))
  end
  
  def test_decode
    assert_equal("hello there, my name is michael! how are you today?",
               Amp::Encoding::Base85.decode("Xk~0{Zy<DNWpZUKAZ>XdZeeX@AZc?TZE0g@VP$L~AZTxQAYpQ4AbD?fAarkJVR=6"))
  end
end
