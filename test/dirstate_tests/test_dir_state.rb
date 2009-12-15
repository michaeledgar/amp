require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp"))

# easyness
class String
  def dir_local; File.expand_path(File.join(File.dirname(__FILE__), self)); end
end


class TestDirState < Test::Unit::TestCase
  
  def setup
    f = File.open File.join(File.dirname(__FILE__), "hgrc")
    @config = PythonConfig::ConfigParser.new f
    opener = Amp::Opener.new File.expand_path(File.dirname(__FILE__))
    opener.default = :open_file
    @state = Amp::Repositories::Mercurial::DirState.new File.expand_path(File.dirname(__FILE__)), @config, opener
    @files = []
  end
  
  def teardown
    @files ||= []
    @files.map {|f| File.delete f.dir_local }
    @files = []
  end
  
  def test_root
    assert_equal File.expand_path(File.dirname(__FILE__)), @state.root
  end
  
  def test_config
    assert_equal @config,  @state.config
  end
  
  def test_parents_equals
    @state.parents = ["asdfasdf", Amp::Mercurial::RevlogSupport::Node::NULL_ID]
    
    assert_equal ["asdfasdf", Amp::Mercurial::RevlogSupport::Node::NULL_ID], @state.parents
    
    @state.parents = "asdfasdf"
    
    assert_equal ["asdfasdf", Amp::Mercurial::RevlogSupport::Node::NULL_ID], @state.parents
  end
  
  def test_dirty?
    @state.parents = ["asdfasdf", Amp::Mercurial::RevlogSupport::Node::NULL_ID] # something to dirty it up
    
    assert @state.dirty?
  end
  
  def test_dirty
    add_file "elephant"
    @state.dirty "elephant"
    
    assert @state["elephant"].dirty?
  end
  
  def test_maybe_dirty
    add_file "eels"
    @state.maybe_dirty "eels"
    
    assert !@state.copy_map["eels"]
    assert @state["eels"].maybe_dirty?
  end
  
  def test_branch_equals
    @files << 'branch'
    @state.branch = "monkey!"
    
    text = File.read "branch".dir_local
    assert_equal text, "monkey!\n"
    assert_equal text.chomp, @state.branch
  end
  
  def test_copy
    add_file "buttmunch"
    @state.copy "buttmunch" => "arsemunch"
    
    assert_equal "buttmunch", @state.copy_map["arsemunch"]
    assert @state.dirty?
    
    @state.copy "arsemunch" => "buttmunch"
    
    assert @state.copy_map["buttmunch"]
    assert @state.copy_map["arsemunch"]
  end
  
  def test_add
    add_file "test"
    
    assert @state.files.include?("test")
    assert !@state.copy_map["test"]
  end
  
  # shouldn't actually happen IRL, but let's make sure we have
  # the same quirks
  def test_remove
    add_file "monkey" # make sure it's in @files
    @state.remove "monkey"
    
    assert @state["monkey"].removed?
  end
  
  def test_forget
    add_file "taco"
    @state.forget "taco"
    
    assert @state["taco"].untracked?
  end
  
  def test_merge
    add_file "burritos"
    @state.merge "burritos"
    
    assert @state["burritos"].merged? 
  end
  
  def test_normal
    add_file "poop"
    @state.normal "poop"
    
    assert @state["poop"].normal?
    assert !@state.copy_map["poop"]
  end
  
  def test_clear
    add_file "poopy"
    @state.clear
    
    assert @state.files.empty?
  end
  
  def test_rebuild
    #add_file "testy"
    
    files = @state.files.dup
    rents = @state.parents.dup
    
    @state.rebuild rents, files
    assert_equal files, @state.files
  end
  
  def test_write
    add_file "oh_nuit"
    @state.write
    
    info = File.read("dirstate".dir_local)
    info.force_encoding("ASCII-8BIT")  if RUBY_VERSION >= "1.9"
    string = "\000\000\000\000\000\000\000" +
             "\000\000\000\000\000\000\000" +
             "\000\000\000\000\000\000\000" +
             "\000\000\000\000\000\000\000" +
             "\000\000\000\000\000\000\000" +
             "\000\000\000\000\000a\000\000" +
             "\000\000\377\377\377\377\377" +
             "\377\377\377\000\000\000\aoh_nuit"
    assert_equal string, info
  end
  
  def test_parse
    @files = []
    # some fake data
    open "dirstate".dir_local, "w" do |f|
      string = "\000\000\000\000\000\000\000" +
               "\000\000\000\000\000\000\000" +
               "\000\000\000\000\000\000\000" +
               "\000\000\000\000\000\000\000" +
               "\000\000\000\000\000\000\000" +
               "\000\000\000\000\000a\000\000" +
               "\000\000\377\377\377\377\377" +
               "\377\377\377\000\000\000\aoh_nuit"
      f.write string
    end
    
    @state.send :read!
    
    assert_equal({"oh_nuit" => Amp::Repositories::Mercurial::DirStateEntry.new(:added, 0, -1, -1)}, @state.files)
    assert_equal({}, @state.copy_map)
  end

  private
  def add_file(name)
    open name.dir_local, "w" do |f|
      f.puts "testyness!"
    end
    
    @state.add name
    (@files ||= []) << name
  end

end

