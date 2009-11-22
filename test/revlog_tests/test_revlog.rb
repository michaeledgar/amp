# -*- coding: us-ascii -*-

require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp"))

class TestRevlog < Test::Unit::TestCase
  TEST_REVLOG_INDEX = "testindex.i"
  
  def setup
    opener = Amp::Opener.new(File.expand_path(File.dirname(__FILE__)))
    opener.default = :open_file # for testing purposes!
    @revlog = Amp::Revlog.new(opener, TEST_REVLOG_INDEX)
  end
  
  def test_load_revlog
    assert_not_nil @revlog
    assert_equal(TEST_REVLOG_INDEX[0..-3] + ".d", @revlog.data_file)
  end
  
  def test_revlog_tip
    result = @revlog.tip
    expected = "|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"
    assert_equal expected, result
  end
  
  def test_revlog_size
    result = @revlog.size
    expected = 51
    assert_equal expected, result
  end
  
  def test_revlog_node_id_for_index
    result = @revlog.node_id_for_index 10
    expected = "\xf8`\x8b/\x1dR\xa2\xaf\x0c\x10M\x89y\xf7,\xdc\xfd6\xaaI"
    assert_equal expected, result
    result = @revlog.node_id_for_index 40
    expected = "\x03\xb2\xdd\x03\x8b\xc7\x9cDaA\xb8\xbd\xebg\xcc\x18\x06\x91A\xf0"
    assert_equal expected, result
    result = @revlog.node_id_for_index 51
    expected = "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    assert_equal expected, result
  end
  
  def test_revlog_revision_index_for_node
    result = @revlog.revision_index_for_node "\xf8`\x8b/\x1dR\xa2\xaf\x0c\x10M\x89y\xf7,\xdc\xfd6\xaaI"
    expected = 10
    assert_equal expected, result
    result = @revlog.revision_index_for_node "\x03\xb2\xdd\x03\x8b\xc7\x9cDaA\xb8\xbd\xebg\xcc\x18\x06\x91A\xf0"
    expected = 40
    assert_equal expected, result
    result = @revlog.revision_index_for_node "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    expected = -1
    assert_equal expected, result
  end
  
  def test_revlog_link_revision_for_index
    result = @revlog.link_revision_for_index 22
    expected = 22
    assert_equal expected,result
    result = @revlog.link_revision_for_index 40
    expected = 40
    assert_equal expected,result
    result = @revlog.link_revision_for_index 1
    expected = 1
    assert_equal expected,result
  end
  
  def test_revlog_base_revision_for_index
    result = @revlog.base_revision_for_index 1
    expected = 0
    assert_equal expected,result
    result = @revlog.base_revision_for_index 10
    expected = 7
    assert_equal expected,result
    result = @revlog.base_revision_for_index 50
    expected = 48
    assert_equal expected,result
  end
  
  def test_revlog_parents_for_node
    result = @revlog.parents_for_node "\xf8`\x8b/\x1dR\xa2\xaf\x0c\x10M\x89y\xf7,\xdc\xfd6\xaaI"
    expected = ["\xd1\x818?\xc0*\xdf\xe4r\x13\x00\x95T\xf5\xbb\xf9\x84k\xc8\x1c", "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"]
    assert_equal expected,result
    result = @revlog.parents_for_node "\x03\xb2\xdd\x03\x8b\xc7\x9cDaA\xb8\xbd\xebg\xcc\x18\x06\x91A\xf0"
    expected = ["\x8cL\x01\nU#7\x1d\x1c5\xfb\x9b,vM\xbe\x80\x862M", "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"]
    assert_equal expected,result
    result = @revlog.parents_for_node "` \xf6W_\xab\xf9+es-Ee\x14\xff\x1d\xf4\xf5\xd7\xfb"
    expected = ["\x01\x0c\\\xbe\x1ea\xc3\xcfu\xeeM\xfa\xfc#\xd0\x87%\xb2\x9bA", "\xd84l\x9e\x04\xe1s0\x1e2T\x98f\"&\xa2\xd9\xad\xc5\x7f"]
    assert_equal expected,result
  end
  
  def test_revlog_parent_indices_for_index
    result = @revlog.parent_indices_for_index 24
    expected = [23, -1]
    assert_equal expected,result
    result = @revlog.parent_indices_for_index 25
    expected = [24, 21]
    assert_equal expected,result
    result = @revlog.parent_indices_for_index 26
    expected = [22, 25]
    assert_equal expected,result
  end
  
  def test_revlog_data_start_for_index
    result = @revlog.data_start_for_index 42
    expected = 6995
    assert_equal expected,result
    result = @revlog.data_start_for_index 7
    expected = 1335
    assert_equal expected,result
    result = @revlog.data_start_for_index 35
    expected = 5810
    assert_equal expected,result
  end
  
  def test_revlog_data_length_for_index
    result = @revlog.data_size_for_index 42
    expected = 95
    assert_equal expected,result
    result = @revlog.data_size_for_index 7
    expected = 128
    assert_equal expected,result
    result = @revlog.data_size_for_index 35
    expected = 122
    assert_equal expected,result
  end
  
  def test_revlog_data_end_for_index
    result = @revlog.data_end_for_index 42
    expected = 7090
    assert_equal expected,result
    result = @revlog.data_end_for_index 7
    expected = 1463
    assert_equal expected,result
    result = @revlog.data_end_for_index 35
    expected = 5932
    assert_equal expected,result
  end
  
  def test_revlog_reachable
    result = @revlog.reachable_nodes_for_node "|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"
    expected = {"\x82\x8b\xd3\x98\xea\xcb\rq\xf1\xb1\xdbg\xe8\xbe!(\x19\x1f\x9d\x93" => true,
     "\x87\x16\xac\xec?\xd2{\xc5\xba\xa9\n\x8d\x82\xf5\x9e\xa5\xd2<+Z" => true,
     "\xfb\x7f\xe6*\x92\x0e\xb9!\xd6\x10\x06(\xf98&\xd6\x90\x06\xc23" => true,
     "\x19}\xe0X\xf7\x90\xf6\x88\xcf\x06\x95E\x13ym\xde=msk" => true,
     "\x9c\x91\xd9\xb1\xec\xf4L/\x16\xaf=\xc9&\x14\xad.v\xaf\xce\\" => true,
     "\xce\x10\x8a<\xb8%\x90T\x19+R1\xe4\x7f\xd5J\\\xf9\xe0\x81" => true,
     "I\xde:;7\x16\xfaK\x02\xdb\xbf0\xb5(c\xd8\xf6\xfe\x80\x08" => true,
     "\x99\xc5\xf6\xcb|6f\xca\xc1\xc6\xae\x86\xe9\xda\x1e\xf2\xcf\xee\xf9\xe8" => true,
     "!i2I7$A\xfe\xe9\x80G\xbe\xa7\xb50Mb\\\x89\x0e" => true,
     "\x8cL\x01\nU#7\x1d\x1c5\xfb\x9b,vM\xbe\x80\x862M" => true,
     "\xf9`\xd4\xdcQ\x1c`\x0c\xc0\x10\xa2\xeb\x81\xe4:\xae,\x81\x1f\xa3" => true,
     "co\xac\xbd\x02\xfb\xdc\xd5\x93\x16\x9a\xb5\xa3\x9ep}R\xe9\xa7\x19" => true,
     "g\xf4t-\xcc|w\xc01v\x80JH\x93\x05\xaa\x07\x13F\xe1" => true,
     "\x0b\xf3\x81\\\xe1k\x19\x14Qa\xbah|\xa4?\xfa\xb4\xa4VH" => true,
     "W5\xbe\xb7n\xfdd\xa4nn\x14\x0b\xc6\xf1\xbf\xee\x8e\x92\xeeF" => true,
     "\x14\x07T\xfb\xc4\xdc\x88\xb7\xb3\x13\xb2\x9e-\xd4\xe87\xb8X+B" => true,
     "_\xf7\xf8\xdd\xfd\xfa\xda1\xe0\x97\x96\xa1\\\xe0g\xe1}p\x1bn" => true,
     "\x1fZd\xa4\xc7\xb8V\xcaK@b\xc3\x7f{YD\xd1:{\xb6" => true,
     "\xd0D\x9a\x99h\x06\"\x9e\x16C\x89F\xa4\xff\xf1\xa0N\xcaj\xc6" => true,
     "R\xed\x19\x93\r\xcd\xb2\xc6b|J\x89\xf7\xa7% E\xfa}\xe9" => true,
     "\x03\xb2\xdd\x03\x8b\xc7\x9cDaA\xb8\xbd\xebg\xcc\x18\x06\x91A\xf0" => true,
     "\xc0t\xcf\x9a%p{\xe4X\xbb.+\xa0\xbe\xf5\x99\x1a\xc7{\xde" => true,
     "E \xc3\xc6\xcc\x99\x91\x01H\xfe\x95s\xc4I@\xafrW$\xa1" => true,
     "\x12>\xf0\x91W\x88 \x8d\xf8\xb3\xa2<{\xed \x90\xe1\x9b\x0e\xda" => true,
     "vO\x00\x85\x19\x968\xc0\x9b\x80\x9a\xec*\x9c\x12\xcd\xd9\x15\xf1\xee" => true,
     "#.9\xc3f\xec\x9b\t\x96\xffqKz3<\x16\x9a\x95\x11\x1d" => true,
     "C\xfe\xec\xf2\x8fL\xb3\x95\xb5\x8d\x1f\xb1\xbc\xc7Y\xfe\xae\xf5;=" => true,
     "\xa0\x89\xde\xcd\x9bt\x98\xdc\xf9\x0c#,XZ\xc0\xc8\xeb\xa6/\xd4" => true,
     "\x8fR$g\xcc!l\xfe\xa4\xc7\xe5\x87G\xd3\xe75!g\xa5_" => true,
     "\xef%\xc7Z\x0co\x08B\xed\x80\x98\t\x18)\xecj\x1c\x9b\x9b\x94" => true,
     "\xf7>6\xc4=\xe3\xe8$\x08\x9b\x87\x95P\x1c\xbe\\4\xfa\xed\xce" => true,
     "\x01\x0c\\\xbe\x1ea\xc3\xcfu\xeeM\xfa\xfc#\xd0\x87%\xb2\x9bA" => true,
     ")\xc1\xc5r\xbc\x10\x86\xdc\xf2:\xca\xda\xe5i\x7f\xb6\x1c\x14i1" => true,
     "\xb0\x94\xcc,\\\xacY\x87\xa4\x9a1\xbc\x88jM\xafM\xd3\xd0\xee" => true,
     "s\xc3\x8dK\xcb\xe9\x93\xd1\x8a\xf2\xe4\xc8\xc3f\xd1J\xe8\x8c\xeaZ" => true,
     "\x08\xe9\x07^\x1d\x9a\xed|\xb2QC\xd6\x8a\xd9:@\xf2\xdcT$" => true,
     "|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02" => true,
     "\x18\xac\x85\x85q\x01Z\x85\x0ff\x1b\x9c\xc1hM\x1cX\xcd\x9b\xa7" => true,
     "` \xf6W_\xab\xf9+es-Ee\x14\xff\x1d\xf4\xf5\xd7\xfb" => true,
     "o(\xef\xc0\xe3(\xbdP6=P\xd7!\xa4a$\x10\x1a\xce\xc4" => true,
     "\x02\x8c\xfb\xa9\x16\xb1&\xa7\x04\xa0\xfezr\x8d5\x9b\x1c2\xacv" => true,
     "\x1e\x0eA+q\xa0\x16cm\xe2\xc8\xa1\xbfJ\xfb\r\x15,\xd3*" => true,
     "\xd1\x818?\xc0*\xdf\xe4r\x13\x00\x95T\xf5\xbb\xf9\x84k\xc8\x1c" => true,
     "\n\xb7\xdc\x9b\x80l-lWGK?\x8a\x9dxq\xef\xdf&@" => true,
     "\x07?\xae0\xaa`\xec\x97x=\x7f\x95 \xbc\x1c\x0e\x16\xe4\xe1\xe8" => true,
     "\xe2\xeaP\x89\x1b\xa7\xc9\x03H\x0fh\xc4f\xd8\xd8w\xa8\xf9\xd3\xb6" => true,
     "\xf5\xd0fy\x11\xe1\xf9\xfc\xe1\xb9\x9e\xc4Gp\x00\xcd\xb5\xa4*\xcc" => true,
     "\t\xb2\x0f\xe5\xc2\xba\x1a\xa9>\xb0#\x8c\x85l\x0e\xb6\x18\xc1s\xcb" => true,
     "\xd84l\x9e\x04\xe1s0\x1e2T\x98f\"&\xa2\xd9\xad\xc5\x7f" => true,
     "\x87\xb9\x16\xc6\xb9\xafF\x8b\xa8\x99,g\xca]\x9a\xc9g\xe5^\x94" => true,
     "\xf8`\x8b/\x1dR\xa2\xaf\x0c\x10M\x89y\xf7,\xdc\xfd6\xaaI" => true}
    expected.each do |k, v|
      unless result.keys.include? k
        flunk
      end
    end
    assert true
  end
  
  def test_revlog_ancestors
    result = @revlog.ancestors([10]).to_a.sort
    expected = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    assert_equal expected, result
  end
  
  def test_revlog_descendants
    result = @revlog.descendants([30]).to_a.sort
    expected = [31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50]
    assert_equal expected, result
  end
  
  def test_revlog_heads
    result = @revlog.heads.to_a.sort
    expected = ["|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"]
    assert_equal expected, result
  end
  
  def test_revlog_between
    result = @revlog.nodes_between(["\xc0t\xcf\x9a%p{\xe4X\xbb.+\xa0\xbe\xf5\x99\x1a\xc7{\xde"],
                                   ["|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"])
    expected = {:between => ["\xc0t\xcf\x9a%p{\xe4X\xbb.+\xa0\xbe\xf5\x99\x1a\xc7{\xde", "\xfb\x7f\xe6*\x92\x0e\xb9!\xd6\x10\x06(\xf98&\xd6\x90\x06\xc23", "\x1e\x0eA+q\xa0\x16cm\xe2\xc8\xa1\xbfJ\xfb\r\x15,\xd3*", "|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"],
                :roots => ["\xc0t\xcf\x9a%p{\xe4X\xbb.+\xa0\xbe\xf5\x99\x1a\xc7{\xde"],
                :heads => ["|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"]}
    assert_equal expected, result
  end
  
  def test_revlog_children
    result = @revlog.children("` \xf6W_\xab\xf9+es-Ee\x14\xff\x1d\xf4\xf5\xd7\xfb")
    expected = ["\xb0\x94\xcc,\\\xacY\x87\xa4\x9a1\xbc\x88jM\xafM\xd3\xd0\xee"]
    assert_equal expected, result
  end
  def test_revlog_id_match
    result = @revlog.id_match("` \xf6W_\xab\xf9+es-Ee\x14\xff\x1d\xf4\xf5\xd7\xfb")
    expected = "` \xf6W_\xab\xf9+es-Ee\x14\xff\x1d\xf4\xf5\xd7\xfb"
    assert_equal expected, result
    result = @revlog.id_match(5)
    expected = "\xf5\xd0fy\x11\xe1\xf9\xfc\xe1\xb9\x9e\xc4Gp\x00\xcd\xb5\xa4*\xcc"
    assert_equal expected, result
  end
  
  def test_revlog_partial_match
    result = @revlog.partial_id_match("7c03fe1439812bcc35a397942a49e2b954a9ac")
    expected = "|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"
    assert_equal expected, result
  end
  
  def test_revlog_lookup_id
    result = @revlog.lookup_id("` \xf6W_\xab\xf9+es-Ee\x14\xff\x1d\xf4\xf5\xd7\xfb")
    expected = "` \xf6W_\xab\xf9+es-Ee\x14\xff\x1d\xf4\xf5\xd7\xfb"
    assert_equal expected, result
    result = @revlog.lookup_id(5)
    expected = "\xf5\xd0fy\x11\xe1\xf9\xfc\xe1\xb9\x9e\xc4Gp\x00\xcd\xb5\xa4*\xcc"
    assert_equal expected, result
    result = @revlog.lookup_id("7c03fe1439812bcc35a397942a49e2b954a9ac")
    expected = "|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"
    assert_equal expected, result
  end
  
  def test_revlog_cmp
    str = "273f0c435892dea22da8ef93a44ebcacc797b7c3\nmichaeledgar@michael-edgars-macbook-pro.local\n1238527096 " +
          "14400\nlib/revlogs/revlog.rb\nlib/revlogs/revlog_support.rb\nlib/support/support.rb\n\ntweaked to use "+
          ".null? and .not_null?\n\nari... lol... node_ids are strings, so putting .null? on the Numeric class wasn't"+
          " the way to go ;-)"
    node = "|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02"
    assert_equal false, @revlog.cmp(node, str)
  end
  
  def test_revlog_get_chunk
    result = @revlog.get_chunk 3
    expected = "\x00\x00\x00\x00\x00\x00\x00)\x00\x00\x00)2ac51d136ec922ba54cb149dfcdcbd9a17253ab0\n\x00\x00\x00W\x00\x00"+
               "\x00h\x00\x00\x00/1238272471 14400\nManifest.txt\nbin/amp\njolts.rb\n\x00\x00\x00s\x00\x00\x00\xd0\x00\x00"+
               "\x00\\lib/commands/dispatch.rb\nlib/encoding/bdiff.rb\nlib/encoding/difflib.rb\ntest/test_difflib.rb\n\x00"+
               "\x00\x00\xd1\x00\x00\x00\xec\x00\x00\x00yadded difflib port, added binary diff class (which mercurial-diff "+
               "uses)\nadded jolts.rb - which is the Rakefile, basically"
    assert_equal expected, result
  end
  
  def test_revlog_revision_diff
    result = @revlog.revision_diff 4,5
    expected = "\x00\x00\x00\x00\x00\x00\x00)\x00\x00\x00)e7cebf6558e7de50f9afa223ce13262afcc296a1\n\x00\x00\x00W\x00\x00\x00"+
              "h\x00\x00\x00\x1b1238296608 14400\n.hgignore\n\x00\x00\x00q\x00\x00\x00q\x00\x00\x00\x93lib/commands/command.rb"+
              "\nlib/commands/dispatch.rb\nlib/encoding/base85.rb\nlib/encoding/bdiff.rb\nlib/encoding/difflib.rb\nlib/repository"+
              "/repository.rb\n\x00\x00\x00\x89\x00\x00\x00\xd9\x00\x00\x00PButtload of documentation. Added an .hgignore to avoid"+
              " the docs being versioned."
    assert_equal expected, result
  end
  def test_revlog_decompress_revision
    result = @revlog.decompress_revision "\xc0t\xcf\x9a%p{\xe4X\xbb.+\xa0\xbe\xf5\x99\x1a\xc7{\xde"
    expected = "6a3d4041fc19b7d64ce9f2567ea4564cb1106594\nmichaeledgar@michael-edgars-macbook-pro.local\n1238480134 "+
               "14400\nlib/encoding/mdiff.rb\ntest/test_mdiff.rb\n\nmore interesting testing revealed bugs in mercurial"+
               " diff. they're fixed with hacks. test in for a complex unified diff!"
    assert_equal expected, result
  end
  def test_revlog_add_revision
    cmp_file = "./test/revlog_tests/revision_added_changelog.i"
    new_file = "./test/revlog_tests/test_adding_index.i"
    opener = Amp::Opener.new(".")
    opener.default = :open_file
    newrevlog = Amp::Revlog.new(opener, new_file)
    Amp::Journal.start("sillymonkey.tx") do |j|
      newrevlog.add_revision("silly", j, 50, "|\x03\xfe\x149\x81+\xcc5\xa3\x97\x94*I\xe2\xb9T\xa9\xac\x02", "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    end
    new_str = ""
    cmp_str = ""
    File.open(new_file, "r") do |f|
      new_str = f.read
    end
    File.open(cmp_file, "r") do |f|
       cmp_str = f.read
    end
    i = 0
    new_str.force_encoding("ASCII-8BIT") if RUBY_VERSION >= "1.9"
    cmp_str.force_encoding("ASCII-8BIT") if RUBY_VERSION >= "1.9"
    
    new_str = new_str.split("")
    cmp_str = cmp_str.split("")
    while new_str.first == cmp_str.first && new_str.size > 0
      new_str.shift
      cmp_str.shift
      i += 1
    end
    unless new_str.empty? && cmp_str.empty?
      puts "Failed at byte #{ i }"
      flunk
    end
    assert true
  end
  
  # def test_revlog_ancestor
  #      assert_equal(19, @revlog.rev(@revlog.ancestor(@revlog.node(19), @revlog.node(45))))
  #    end
end