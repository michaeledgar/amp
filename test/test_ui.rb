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

require 'stringio'
require File.join(File.expand_path(File.dirname(__FILE__)), 'testutilities')
require File.join(File.dirname(__FILE__), "../lib/amp/support/amp_ui")

class TestAmpUI < AmpTestCase
  include Amp
  def setup
    @old_stdin = $stdin
    @old_stdout = $stdout
    @stdout = $stdout = StringIO.new
  end
  
  def teardown
    $stdin = @old_stdin
    $stdout = @old_stdout
  end
  
  def set_stdin(new_in)
    @stdin = $stdin = StringIO.new(new_in)
    @stdin.rewind
  end
  
  def test_tell
    UI::tell "some output"
    assert_equal "some output", @stdout.string
  end
  
  def test_say
    UI::say "some output"
    assert_equal "some output\n", @stdout.string
  end
  
  def test_ask_integer
    set_stdin("15\n")
    assert_equal 15, UI::ask("number please? ", Fixnum)
    set_stdin("15\n")
    assert_equal 15, UI::ask("number please? ", Integer)
    set_stdin("15\n")
    assert_equal 15, UI::ask("number please? ", Bignum)
    set_stdin("15\n")
    assert_equal 15, UI::ask("number please? ", Numeric)
  end
  
  def test_ask_float
    set_stdin("123.45\n")
    assert_equal 123.45, UI::ask("number please? ", Float)
  end
  
  def test_ask_string
    set_stdin("Hello, world!\n")
    assert_equal "Hello, world!", UI::ask("some input", String)
  end
  
  def test_ask_array
    set_stdin("Hi, There, some, stuff")
    assert_equal ["Hi", "There", "some", "stuff"], UI::ask("some array: ", Array)
  end
  
  def test_yes_or_no
    set_stdin("yes\n")
    assert UI::yes_or_no
  end
  
  def test_yes_or_no_false
    set_stdin("no\n")
    assert_false UI::yes_or_no
  end
  
  def test_choose
    closed_over = nil
    set_stdin("1\n")
    UI::choose do |menu|
      menu.choice("First") {closed_over = 1}
      menu.choice("Second") {closed_over = 2}
    end
    assert_equal closed_over, 1
  end
  
end
