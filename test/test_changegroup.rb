require 'stringio'
require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestChangegroup < Test::Unit::TestCase
  include Amp::Mercurial::RevlogSupport
  
  def test_compressor_uncompressed
    compressor = ChangeGroup.compressor_by_type("HG10UN")
    assert_kind_of StringIO, compressor
    assert_respond_to compressor, :flush
    compressor << "input string"
    assert_equal "input string", compressor.flush
  end
  
  def test_compressor_no_header
    assert_kind_of StringIO, ChangeGroup.compressor_by_type("")
  end
  
  def test_compressor_zlib
    compressor = ChangeGroup.compressor_by_type("HG10GZ")
    assert_kind_of Zlib::Deflate, compressor
  end
  
  def test_compressor_bz
    # this fails. bz2 is borked atm.
    # compressor = ChangeGroup.compressor_by_type("HG10BZ")
    # assert_kind_of BZ2::Writer, compressor
  end
  
  def test_unbundle_uncompressed
    input_io = StringIO.new("input data")
    decompressing_io = ChangeGroup.unbundle("HG10UN", input_io)
    assert_equal("input data", decompressing_io.read)
  end
  
  def test_unbundle_funny_header
    input_io = StringIO.new("input data")
    funny_header = "BUNDLE"
    decompressing_io = ChangeGroup.unbundle(funny_header, input_io)
    assert_equal("BUNDLEinput data", decompressing_io.read)
  end
  
  def test_unbundle_gzip
    input_io = StringIO.new("", "r+")
    gzip_maker = Zlib::GzipWriter.new(input_io)
    gzip_maker << "input string"
    gzip_maker.flush
    gzip_maker.close
    input_io.reopen(input_io.string,"r")
    input_io.rewind
    decompressing_io = ChangeGroup.unbundle("HG10GZ", input_io)
    assert_kind_of Zlib::GzipReader, decompressing_io
    assert_equal "input string", decompressing_io.read
  end
    
  
end
