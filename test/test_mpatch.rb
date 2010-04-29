# -*- coding: us-ascii -*-
require 'stringio'
require File.join(File.expand_path(File.dirname(__FILE__)), 'testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestMpatch < AmpTestCase
  include Amp::Diffs::Mercurial
  def test_apply_patch
    patch = "\000\000\000\t\000\000\000\021\000\000\000\ni'm stupid"
    input = "hi there\ni'm cool"
    assert_equal("hi there\ni'm stupid", MercurialPatch.apply_patches(input, [patch]))
  end
  
  def test_apply_trivial_patch
    patch = "\0\0\0\0\0\0\0\0\0\0\0\x10abcdefghijklmnop"
    input = ""
    assert_equal("abcdefghijklmnop", MercurialPatch.apply_patches(input, [patch]))
  end
  
  def test_apply_empty_patches
    patch = "\0\0\0\0\0\0\0\0\0\0\0\0"
    input = "simple message"
    assert_equal("simple message", MercurialPatch.apply_patches(input, [patch, patch, patch]))
  end
  
  def test_apply_multiple_patches
    # start with "abcdEFGHijklMNOPqrstUVWXyz"
    # patch over "1234" over the EFGH
    # patch over "OVERWRITE" over the "qrst"
    patch = "\0\0\0\x4\0\0\0\x8\0\0\0\x041234"
    patch2 = "\0\0\0\x10\0\0\0\x14\0\0\0\x09OVERWRITE"
    input = "abcdEFGHijklMNOPqrstUVWXyz"
    expected = "abcd1234ijklMNOPOVERWRITEUVWXyz"
    assert_equal expected, MercurialPatch.apply_patches(input, [patch, patch2])
  end
end
