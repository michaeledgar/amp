require File.expand_path(File.join(File.dirname(__FILE__), "..", 'command_helper'))
cmd = easy_get_command("hg", /([^\/]*)_spec.rb/.match(__FILE__)[1])

describe cmd do
  it "fails when given less than 2 arguments" do
    lambda do
      with_swizzled_io do
        cmd.run({}, ["file_src"])
      end
    end.should raise_exception(AbortError)
  end
  
  it "fails when given more than 2 arguments but no directory as a destination" do
    File.stub!(:directory?, "/dir/").and_return(false)
    lambda do
      with_swizzled_io do
        cmd.run({}, ["file_src", "file_2_src", "/dir/"])
      end
    end.should raise_exception(AbortError)
  end
  
  it "copies one file to a new location when given two arguments" do
    repo = mock("repo")
    staging_area = mock("staging_area")
    repo.should_receive(:staging_area).and_return(staging_area)
    staging_area.should_receive(:copy).with("first_file", "target_file", anything)
    with_swizzled_io do
      cmd.run({:repository => repo}, ["first_file", "target_file"])
    end
  end
  
  it "copies multiple file to a new directory when given three or more arguments" do
    repo = mock("repo")
    staging_area = mock("staging_area")
    repo.should_receive(:staging_area).any_number_of_times.and_return(staging_area)
    staging_area.should_receive(:copy).with("first_file", "target_dir", anything)
    staging_area.should_receive(:copy).with("second_file", "target_dir", anything)
    staging_area.should_receive(:copy).with("third_file", "target_dir", anything)
    File.stub!(:directory?, "target_dir").and_return(true)
    with_swizzled_io do
      cmd.run({:repository => repo}, ["first_file", "second_file", "third_file", "target_dir"])
    end
  end
  
  
end