require File.join(File.expand_path(File.dirname(__FILE__)), 'testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp/templates/template"))

class TestTemplates < AmpTestCase
  include Amp::Support  
  
  def setup
    @template = Template.new(:log, :test, :erb, "<%= name %> <%= age %>")
  end
  
  def test_new_template
    assert @template
  end
  
  def test_unregister
    Template.unregister(:log, :test)
    assert_nil(Template[:log, :test])
  end
  
  def test_render
    name = "Steve"
    age = 21
    assert_equal "Steve 21", @template.render({}, binding)
  end
  
  def test_locals
    locals = {:name => "Steve", :age => 21}
    assert_equal("Steve 21", @template.render(locals))
  end
  
  def test_loading_defaults
    Template.ensure_templates_loaded
    assert Template.templates_loaded?
    assert_not_nil(Template[:mercurial, "default-commit"])
    assert_not_nil(Template[:mercurial, "default-log"])
  end
    
end