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

require 'minitest/spec'
require 'minitest/mock'

class TestChangelog < AmpTestCase
  
  def setup
    opener = Amp::Opener.new(File.dirname(__FILE__))
    opener.default = :open_file
    @changelog = Amp::Mercurial::ChangeLog.new(opener)
  end
  
  def test_load_changelog
    assert_not_nil @changelog
  end
  
  def test_decode_extra
    extra = "key:value"
    assert_equal({"key" => "value"}, @changelog.decode_extra(extra))
  end
  
  def test_decode_extra_advanced
    extra = "key:value\0okey:value:thing"
    assert_equal({"key" => "value", "okey" => "value:thing"}, @changelog.decode_extra(extra))
  end
  
  def test_decode_extra_more
    extra = "key: value \0otherkey:other value goes here"
    expected = {"key" => " value ", "otherkey" => "other value goes here"}
    assert_equal expected, @changelog.decode_extra(extra)
  end
  
  def test_encode_extra
    input = {"key" => "value"}
    expected = "key:value"
    assert_equal expected, @changelog.encode_extra(input)
  end
  
  def test_decode_extra_advanced
    input = {"key" => "value", "okey" => "value:thing"}
    expected = "key:value\0okey:value:thing"
    assert_equal expected, @changelog.encode_extra(input)
  end
  
  def test_decode_extra_more
    expected = "key: value \0otherkey:other value goes here"
    input = {"key" => " value ", "otherkey" => "other value goes here"}
    assert_equal expected, @changelog.encode_extra(input)
  end
  
  def test_decoding_full_entry
    def @changelog.decompress_revision(*args)
      result_from_decompress = "1023456789010234567890102345678901023456
adgar
1271004470 14400 branch:silly\x00close:1
some_file.rb
another_file.rb
silly_file.rb

a description goes here and can contain
newlines and all kinds
of stuff"
    end
    result = @changelog.read("abcde")
    assert_equal "1023456789010234567890102345678901023456".unhexlify, result[0]
    assert_equal "adgar", result[1]
    assert_equal [1271004470, 14400], result[2]
    assert_equal ["some_file.rb", "another_file.rb", "silly_file.rb"], result[3]
    assert_equal "a description goes here and can contain\nnewlines and all kinds\nof stuff", result[4]
    assert_equal({"branch" => "silly", "close" => "1"}, result[5])
  end
  
  def test_add_changes_invalid_username_raises
    assert_raises(Amp::Mercurial::RevlogSupport::RevlogError) do
      @changelog.add(nil, nil, nil, nil, nil, nil, "invalid\nusername")
    end
  end
  
  def test_add_changes
    manifest = "\x0\x1\x2\x3\x4\x5\x6\x7\x8\x9\xa\xb\xc\xd\xe\xf\x10\x11\x12\x13"
    files = ["abc.rb", "cde.rb"]
    desc = "This commit is very interesting.\n I like this commit.\n Lots of good stuff."
    user = "adgar the barbarian"
    date = Time.now
    extra = {"branch" => "anotherbranch"}
    
    compiled_text = "000102030405060708090a0b0c0d0e0f10111213
adgar the barbarian
#{date.to_i} #{-1 * date.utc_offset} branch:anotherbranch
abc.rb
cde.rb

This commit is very interesting.
 I like this commit.
 Lots of good stuff."

    assert_equal compiled_text, @changelog.compile_commit_text(manifest, user, date, files, desc, extra)
  end
end