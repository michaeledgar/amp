##################################################################
#                  Licensing Information                         #
#                                                                #
#  The following code is licensed, as standalone code, under     #
#  the Ruby License, unless otherwise directed within the code.  #
#                                                                #
#  For information on the license of this code when distributed  #
#  with and used in conjunction with the other modules in the    #
#  Amp project, please see the root-level LICENSE file.          #
#                                                                #
#  © Michael J. Edgar and Ari Brown, 2009-2010                   #
#                                                                #
##################################################################

require File.expand_path(File.join(File.dirname(__FILE__), "..", 'command_helper'))
cmd = easy_get_command("hg", /([^\/]*)_spec.rb/.match(__FILE__)[1])

describe cmd do
  before do
    @repo = mock("repo")
    @changeset = mock("changeset")
    
    @repo.stub!(:size).and_return(5)
    @repo.stub!(:[], 4).and_return(@changeset)
    
    
    @changeset.stub!(:to_templated_s).and_return("mock_output")
  end
  it "gets the most recent revision and prints it" do
    output = with_swizzled_io do
      cmd.run({:repository => @repo})
    end
    output.should == "mock_output\n"
  end
  
  it "passes along the template option" do
    options = {:repository => @repo, :template => "sillytemp"}
    @changeset.should_receive(:to_templated_s).with(hash_including(:template => "sillytemp"))
    with_swizzled_io do
      cmd.run(options)
    end
  end
end