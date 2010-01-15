require File.join(File.expand_path(File.dirname(__FILE__)), 'testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))

class Test19Compatibility < AmpTestCase
  
  def test_string_any?
    assert "hello".any?
  end
  
  def test_string_any_false
    assert_false "".any?
  end
  
  def test_lines
    input = "hello\nthere\n\n mike"
    expected = ["hello\n","there\n","\n"," mike"]
    result = []
    input.lines {|str| result << str}
    assert_equal expected, result
  end
  
  def test_lines_to_enum
    input = "hello\nthere\n\n mike"
    # can't do a kind_of? because ruby1.9 has ::Enumerator and
    # 1.8 uses Enumerable::Enumerator
    classname = input.lines.class.to_s.split("::").last
    assert_equal "Enumerator", classname
  end
  
  def test_ord
    assert_equal "h".ord, 104
  end
  
  def test_ord_long_string
    assert_equal "hello".ord, 104
  end
  
  def test_tap
    value = "hi there"
    in_block = nil
    value.tap {|val| in_block = val}
    assert_equal value, in_block
  end
  
  
end