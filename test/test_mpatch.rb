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
  
end
