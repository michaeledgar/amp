require File.expand_path(File.join(File.dirname(__FILE__), "..", 'command_helper'))
cmd = easy_get_command("hg", /([^\/]*)_spec.rb/.match(__FILE__)[1])

describe cmd do
  before do
    @repo = mock("repo")
    @repo.stub!(:root).and_return("/")
    @repo.stub!(:status).and_return({:unknown => ["abc","bcd","cde"], :deleted => ["zxy","xyw"]})
    
    @staging_area = mock("staging_area")
    @staging_area.stub!(:add)
    @staging_area.stub!(:remove)
    
    @repo.stub!(:staging_area).and_return(@staging_area)
  end
  
  it "doesn't add or remove anything when --dry-run is specified" do
    @staging_area.should_not_receive :add
    @staging_area.should_not_receive :remove
    with_swizzled_io do
      cmd.run(:repository => @repo, :"dry-run" => true)
    end
  end
  
  it "announces each file added" do
    output = with_swizzled_io do
      cmd.run(:repository => @repo, :"dry-run" => true)
    end
    output.should include "Adding abc"
    output.should include "Adding bcd"
    output.should include "Adding cde"
  end
  
  it "announces each file removed" do
    output = with_swizzled_io do
      cmd.run(:repository => @repo, :"dry-run" => true)
    end
    output.should include "Removing zxy"
    output.should include "Removing xyw"
  end
  
  it "adds unknown files" do
    @staging_area.should_receive(:add).with(["abc", "bcd", "cde"])
    with_swizzled_io do
      cmd.run(:repository => @repo)
    end
  end
  
  it "removes missing files" do
    @staging_area.should_receive(:remove).with(["zxy", "xyw"])
    with_swizzled_io do
      cmd.run(:repository => @repo)
    end
  end
end