require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp/commands/command.rb"))

class TestCommmands < Test::Unit::TestCase
  include Amp
  include Amp::KernelMethods
  extend  Amp::KernelMethods
  @@command = Amp::Command.new :testingzorz do |c|
    c.opt :silly, "Silliness"
    c.opt :shorted, "Shorted", :short => "-s"
    c.opt :stringy, "Stringed", :type => :string
    c.opt :"stop-at-filter", "Testing before filters"
    c.before do |opts, args|
      $_test_before_ran = true
      $_test_ran_on_run = false # reset this one
      if opts[:"stop-at-filter"]
        cut!
      end
      true
    end
    
    c.on_run do |opts, args|
      $_test_silly = opts[:silly]
      $_test_silly_given = opts[:silly_given]
      $_test_shorted = opts[:shorted]
      $_test_shorted_given = opts[:shorted_given]
      $_test_stringy = opts[:stringy]
      $_test_stringy_given = opts[:stringy_given]
      $_test_args = args
      $_test_ran_on_run = true
    end
  end
  
  def set_argv(new_argv)
    argv = Object.send(:remove_const, :ARGV)
    Object.send(:const_set, :ARGV, new_argv)
    return argv
  end

  def cloak_argv(temp_argv)
    $break = false
    argv = set_argv(temp_argv)
    yield
    set_argv(argv)
  end
  
  def test_anything_runs
    cloak_argv([]) do
      opts = @@command.collect_options
      @@command.run(opts, Object::ARGV)
    end
    
    assert $_test_ran_on_run
    assert $_test_before_ran
  end
  
  def test_long_option
    cloak_argv(["--silly"]) do
      opts = @@command.collect_options
      @@command.run(opts, Object::ARGV)
    end
    
    assert $_test_silly_given
    assert $_test_silly
  end
  
  def test_short_option
    cloak_argv(["-s"]) do
      opts = @@command.collect_options
      @@command.run(opts, Object::ARGV)
    end
    
    assert $_test_shorted
    assert $_test_shorted_given
  end
  
  def test_string_option
    cloak_argv(["--stringy", "thestring"]) do
      opts = @@command.collect_options
      @@command.run(opts, Object::ARGV)
    end
    
    assert_equal "thestring", $_test_stringy
    assert $_test_stringy_given
  end
  
  def test_extra_args
    cloak_argv(["--stringy", "thestring", "arg1", "arg2"]) do
      opts = @@command.collect_options
      @@command.run(opts, Object::ARGV)
    end
    
    assert_equal ["arg1","arg2"], $_test_args
  end
  
  def test_break
    cloak_argv(["--stop-at-filter"]) do
      opts = @@command.collect_options
      @@command.run(opts, Object::ARGV)
    end
    
    assert $_test_before_ran
    assert_false $_test_ran_on_run
  end
  
  def test_maybe_repo
    assert_false Amp::Command::MAYBE_REPO_ALLOWED[:testingzorz]
    @@command.maybe_repo
    assert Amp::Command::MAYBE_REPO_ALLOWED[:testingzorz]
    @@command.maybe_repo = false
    assert_false Amp::Command::MAYBE_REPO_ALLOWED[:testingzorz]
  end
  
  def test_no_repo
    assert_false Amp::Command::NO_REPO_ALLOWED[:testingzorz]
    @@command.no_repo
    assert Amp::Command::NO_REPO_ALLOWED[:testingzorz]
    @@command.no_repo = false
    assert_false Amp::Command::NO_REPO_ALLOWED[:testingzorz]
  end
end
