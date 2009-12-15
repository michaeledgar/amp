# -*- coding: us-ascii -*-
require 'stringio'
require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestMpatch < Test::Unit::TestCase
  include Amp::Diffs::Mercurial
  def test_apply_patch
    patch = "\000\000\000\t\000\000\000\021\000\000\000\ni'm stupid"
    input = "hi there\ni'm cool"
    assert_equal("hi there\ni'm stupid", MercurialPatch.apply_patches(input, [patch]))
  end
  
end
