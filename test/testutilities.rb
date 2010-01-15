require 'test/unit'
require 'rubygems'
require 'minitest/unit'

class AmpTestCase < MiniTest::Unit::TestCase
  def setup
    super
    tmpdir = nil
    Dir.chdir Dir.tmpdir do tmpdir = Dir.pwd end # HACK OSX /private/tmp
    @tempdir = File.join tmpdir, "test_amp_#{$$}"
    @tempdir.untaint
  end
  
  def tempdir
    @tempdir
  end
  
  def teardown
    FileUtils.rm_rf @tempdir if defined?(@tempdir) && @tempdir && File.exist?(@tempdir)
  end

  
  # taken from rubygems
  def write_file(path)
    path = File.join(@tempdir, path)
    dir = File.dirname path
    FileUtils.mkdir_p dir

    open path, 'wb' do |io|
      yield io
    end

    path
  end
  
  def assert_regexp_equal(areg, breg)
    # because regexes, inspected, seems to be killing assert_equal
    assert areg.inspect == breg.inspect, "#{areg.inspect} is not equal to #{breg.inspect}"
  end
  
  def assert_false(val)
    assert_equal(false, !!val)
  end

  def assert_not_nil(val)
    refute_equal(nil, val)
  end

  def assert_file_contents(file, contents)
    File.open(file,"r") do |f|
      assert_equal f.read, contents
    end
  end
end

MiniTest::Unit.autorun