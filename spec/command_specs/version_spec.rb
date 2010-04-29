require File.expand_path(File.join(File.dirname(__FILE__), 'command_helper'))
cmd = easy_get_command("all", /([^\/]*)_spec.rb/.match(__FILE__)[1])

describe cmd do
  it "prints the current version" do
    output = with_swizzled_io do
      cmd.run
    end
    output.should include Amp::VERSION.to_s
  end
  
  it "prints the nifty codename" do
    output = with_swizzled_io do
      cmd.run
    end
    output.should include Amp::VERSION.to_s
  end
end