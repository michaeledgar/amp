require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestMatch < Test::Unit::TestCase

  def setup
    @all_files = ["silly.rb", "code/lib.rb", "code/support.yml", "bin/amp.rb", "test/test_bdiff.rb"]
    @match_files = ["code/support.yml", "bin/amp.rb"]
    @files = ['lib/amp.rb', 'lib/monkey', 'poop']
    @matcher1 = Amp::Match.create :files => @files,
                                  :includer => "regexp:\\.rbc$\n", # it will come in as such from the command line
                                  :excluder => /^(.+\/)?\.[^.].*/
    @block = proc {|f| f =~ /\.rbc$/ }
    @matcher2 = Amp::Match.new :files => @files, &@block
    
    @matcher3 = Amp::Match.create :includer => "glob: code/ext/*.o"
    
    @matcher4 = Amp::Match.create :includer => "glob: code/ext/**/*.o"
  end
  def test_files_match
    matcher = Amp::Match.create(:files => ["code/support.yml", "bin/amp.rb"])
    
    assert_false matcher.exact?("silly.rb")
    assert_false matcher.exact?("code/lib.rb")
    
    assert matcher.exact?("code/support.yml")
    assert matcher.exact?("bin/amp.rb")
    
    assert_false matcher.exact?("test/test_bdiff.rb")

  end
  
  def test_files_basic_approximate
    matcher = Amp::Match.create(:files => @match_files, :includer => "\.rb$")

    assert matcher.approximate?("silly.rb")
    assert matcher.approximate?("code/lib.rb")
    assert_false matcher.approximate?("code/support.yml")
    assert_false matcher.approximate?("bin/amp.rb") #in :files
    assert matcher.approximate?("test/test_bdiff.rb")
  end
  
  def test_call
    assert @matcher1.call('array.rbc')
    assert @matcher1.call('lib/amp.rb')
    assert !@matcher1.call('amp.rb')
    assert @matcher1.call('monkey/poop/sdf/sdf/testy.rbc')
    assert !@matcher1.call('busdfasdf')
    assert !@matcher1.call('.hgignore')
    assert !@matcher1.call('asdf/sdfs/sdf.asdf/sdf.sdf/.vimrc')
    
    assert @matcher2.call('array.rbc')
    assert @matcher2.call('lib/amp.rb')
    assert !@matcher2.call('amp.rb')
    assert @matcher2.call('monkey/poop/sdf/sdf/testy.rbc')
  end
  
  def test_files_basic_exclude
    matcher = Amp::Match.create(:files => [], :includer => ".*", :excluder => "code")

    assert_false matcher.failure?("silly.rb")
    assert matcher.failure?("code/lib.rb")
    assert matcher.failure?("code/support.yml")
    assert_false matcher.failure?("bin/amp.rb") #in :files
    assert_false matcher.failure?("test/test_bdiff.rb")
  end
  
  def test_approximate
    assert @matcher2.approximate?('testy.rbc')
    assert @matcher2.approximate?('monke/asd/fdf/drty.rbc')
    assert !@matcher2.approximate?('lib/amp.rb')
    assert !@matcher2.approximate?('buttmucnhc')
  end
  
  def test_globs
    assert @matcher3.call('code/ext/asdf.o')
    assert !@matcher3.call('code/ext/asdf.c')
    assert !@matcher3.call('code/ext/monkey/asdf.c')
    assert !@matcher3.call('code/ext/monkey/asdf.o')
    
    assert @matcher4.call('code/ext/asdf.o')
    assert !@matcher4.call('code/ext/asdf.c')
    assert !@matcher4.call('code/ext/monkey/asdf.c')
    assert @matcher4.call('code/ext/monkey/asdf.o')
  end
  
  def test_overall_match
    matcher = Amp::Match.create(:files => "code/support.yml", :includer => "\\.rb$", :excluder => "code")
    
    assert matcher.call("silly.rb") #include wins
    assert_false matcher.call("code/lib.rb") #exclude overrides include
    assert_raises StandardError do
      matcher.call("code/support.yml")
    end
    assert matcher.call("bin/amp.rb")
    assert matcher.call("test/test_bdiff.rb")
  end
  
  def test_block
    assert_equal @block, @matcher2.block
  end
  
  def test_exact?
    assert @matcher1.exact?('lib/amp.rb')
    assert @matcher1.exact?('poop')
    assert !@matcher1.exact?('monkey.rbc')
  end
  
  def test_exclude
    assert_equal([/^(.+\/)?\.[^.].*/], @matcher1.exclude)
  end
  
  def test_failure?
    assert @matcher1.failure?('.hgignore')
    assert @matcher1.failure?('lib/.vimrc')
    assert @matcher1.failure?('lib/.array.rbc')
  end
  
  def test_files
    assert_equal @files, @matcher1.files
  end
  
  # Uh, compare procs? wtf?
  def test_include
    assert_equal([/\.rbc$/], @matcher1.include)
  end
  
  def test_included
    assert @matcher1.included?('monkey.rbc')
    assert @matcher1.included?('asdf/sdf/sdf/s/array.rbc')
    assert @matcher1.included?('asd/.kernel.rbc') # shouldn't care about the excludes
  end
  
end
