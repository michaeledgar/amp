require File.expand_path(File.join(File.dirname(__FILE__), "..", 'command_helper'))
cmd = easy_get_command("hg", /([^\/]*)_spec.rb/.match(__FILE__)[1])

describe cmd do
  before do
    @repo = mock("repo")
    @repo.stub!(:root).and_return("some root goes here")
  end
  
  it "prints the repository's root" do
    output = with_swizzled_io do
      cmd.run(:repository => @repo)
    end
    output.should == "some root goes here\n"
  end
end