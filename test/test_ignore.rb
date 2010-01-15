require File.join(File.expand_path(File.dirname(__FILE__)), 'testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class TestIgnore < AmpTestCase
  include Amp::Mercurial::Ignore
  
  def setup
    super
    @ignore_path = self.write_file "ignore" do |io|
      io << "syntax: glob\n" << "test/**/test_*.rb\n" << "doc/*\n"
      io << "syntax: regexp\n\.DS_Store\n"
    end
  end

  #### parse_line #############

  def test_parse_line_no_sym
    assert_nil parse_line(nil, "doc/*")
  end
  
  def test_parse_line_regexp
    expected = /doc\/(\d\d\d)/
    assert_regexp_equal expected, parse_line(:regexp, "doc/(\\d\\d\\d)")
  end
  
  def test_parse_line_glob_one_star
    input = "test/*/test_*.rb"
    expected = /^test\/[^\/]*\/test_[^\/]*\.rb/
    result = parse_line(:glob, input)
    assert_regexp_equal expected, result
  end
  
  def test_glob_one_star_matches
    input = "test/*/test_*.rb"
    result = parse_line(:glob, input)
    assert_match(result, "test/silly/test_crazy.rb")
  end
  
  def test_glob_one_star_is_not_relative
    input = "test/*/test_*.rb"
    result = parse_line(:glob, input)
    refute_match(result, "some/test/silly/test_crazy.rb")
  end
    
  def test_parse_line_relglob_one_star
    input = "test/*/test_*.rb"
    expected = /test\/[^\/]*\/test_[^\/]*\.rb/
    result = parse_line(:relglob, input)
    assert_regexp_equal expected, result
  end
  
  def test_relglob_one_star_matches
    input = "test/*/test_*.rb"
    result = parse_line(:relglob, input)
    assert_match(result, "test/silly/test_crazy.rb")
  end
  
  def test_relglob_one_star_also_relative
    input = "test/*/test_*.rb"
    result = parse_line(:relglob, input)
    assert_match(result, "some/test/silly/test_crazy.rb")
  end
  
  def test_parse_line_glob_two_star
    input = "test/**/test_*.rb"
    expected = /^test\/(?:.*\/)*test_[^\/]*\.rb/
    result = parse_line(:glob, input)
    assert_regexp_equal expected, result
  end
  
  def test_glob_two_star_matches_subdirs
    input = "test/**/test_*.rb"
    result = parse_line(:glob, input)
    assert_match(result, "test/first/second/third/fourth/test_filez.rb")
  end
  
  def test_glob_two_star_matches_no_subdirs
    input = "test/**/test_*.rb"
    result = parse_line(:glob, input)
    assert_match(result, "test/test_filez.rb")
  end
  
  #### matcher_for_string #############
  
  # defaults to regexp
  def test_matcher_for_string_nilcase
    expected = /doc\/(\d\d\d)/
    result = matcher_for_string("doc/(\\d\\d\\d)")
    assert_regexp_equal expected, result
  end
  
  def test_matcher_for_string_glob
    input = "glob: test/**/test_*.rb"
    expected = /^test\/(?:.*\/)*test_[^\/]*\.rb/
    result = matcher_for_string(input)
    assert_regexp_equal expected, result
  end
  
  def test_matcher_for_string_relglob
    input = "relglob: test/**/test_*.rb"
    expected = /test\/(?:.*\/)*test_[^\/]*\.rb/
    result = matcher_for_string(input)
    assert_regexp_equal expected, result
  end
  
  def test_matcher_for_string_regexp
    expected = /doc\/(\d\d\d)/
    result = matcher_for_string("regexp: doc/(\\d\\d\\d)")
    assert_regexp_equal expected, result
  end
  
  #### regexps_to_proc #############
  
  def test_regexps_to_proc_matches
    prok = regexps_to_proc(/abc/, /bcd/, /a*bc/)
    assert prok.call("abc")
    assert prok.call("aaaaabc")
    assert prok.call("bcd")
  end
  
  def test_regexps_to_proc_doesnt_match
    prok = regexps_to_proc(/abc/, /bcd/, /a*bc/)
    assert_false prok.call("cde")
  end
  
  #### strip_comment #############
  
  def test_strip_comment_simple
    assert_equal "", strip_comment("# hello there")
  end
  
  def test_strip_comment_other_stuff
    assert_equal "hello ", strip_comment("hello # there")
  end
  
  def test_strip_comment_no_comment
    assert_equal "hello there", strip_comment("hello there")
  end
  
  def test_strip_comment_escaped_hashes
    assert_equal "hello # there", strip_comment("hello \\# there")
  end
  
  def test_strip_comment_complex
    assert_equal "hello # there ##", strip_comment("hello \\# there \\#\\## some comment")
  end
  
  #### parse_lines #############
  
  def test_parse_lines_simple
    input = "hello\nthere\nhow\nare\nyou"
    assert_equal %w[hello there how are you], parse_lines(input)
  end
  
  def test_parse_lines_strip_whitespace
    input = "hello  \t\nthere\t  \nhow\t\t  \t\nare  \t\t  \nyou  \t\t  \t"
    assert_equal %w[hello there how are you], parse_lines(input)
  end
  
  def test_parse_lines_remove_empty
    input = "hello\n\nthere\n\ni\n  \nam\n\n\n\n\nmike"
    assert_equal %w[hello there i am mike], parse_lines(input)
  end
  
  def test_parse_lines_strip_comments
    input = <<-EOF
hi there # introduction
my name 
  
is mike   
EOF
    expected = ["hi there", "my name", "is mike"]
    assert_equal expected, parse_lines(input)
  end
  
  #### matcher_for_text #############
  
  def test_matcher_for_text_simple
    input = "syntax: regexp\n\\.DS_Store # God damn OS X files\ndoc/\\d\\d\\d.txt\n\n"
    expected = [/\.DS_Store/, /doc\/\d\d\d.txt/]
    result = matcher_for_text input
    expected.zip(result).each {|a,b| assert_regexp_equal a,b}
  end
  
  def test_matcher_for_text_mixed
    input = "syntax: regexp\n\\.DS_Store # God damn OS X files\nsyntax: glob  \ntest/**/test_*.rb\n\n"
    expected = [/\.DS_Store/, /^test\/(?:.*\/)*test_[^\/]*\.rb/]
    result = matcher_for_text input
    expected.zip(result).each {|a,b| assert_regexp_equal a,b}
  end
  
  #### parse_ignore #############
  
  def test_parse_ignore
    proc = parse_ignore File.dirname(@ignore_path), "ignore"
    assert proc.call("test/some/test/dir/test_crazy.rb")
    assert proc.call("test/test_crazy.rb")
    assert proc.call("doc/file.html")
    assert_false proc.call("dir/doc/dir/file.html")
    assert proc.call(".DS_Store")
    assert proc.call("some/dir/.DS_Store")
  end
end
