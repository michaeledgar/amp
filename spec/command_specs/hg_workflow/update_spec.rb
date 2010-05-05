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
  UPDATE_INPUT = "5"
  CLEAN_INPUT  = "abc"
  
  before do
    @repo = mock("repo")
    @repo.stub!(:update, UPDATE_INPUT).and_return({:merged => 1})
    @repo.stub!(:clean, CLEAN_INPUT).and_return({:added => ["a","b"], :deleted => ["something"]})
  end
  
  it "fails when given --rev and --node" do
    with_swizzled_io do
      lambda {cmd.run(:repository => @repo, :rev => "5", :node => "abc")}.should raise_exception
    end
  end
  
  it "passes --rev to update" do
    @repo.should_receive(:update).with(UPDATE_INPUT)
    with_swizzled_io do
      cmd.run(:repository => @repo, :rev => UPDATE_INPUT)
    end
  end
  
  it "uses #clean when --clean is specified" do
    @repo.should_not_receive(:update)
    @repo.should_receive(:clean)
    with_swizzled_io do
      cmd.run(:repository => @repo, :clean => true)
    end
  end
  
  it "passes node in when --node is specified" do
    @repo.should_receive(:clean).with(CLEAN_INPUT)
    with_swizzled_io do
      cmd.run(:repository => @repo, :node => CLEAN_INPUT, :clean => true)
    end
  end
  
  it "parses the resulting stats into nicely-formatted output" do
    output = with_swizzled_io do
      cmd.run(:repository => @repo, :node => CLEAN_INPUT, :clean => true)
    end
    output.should include "2 files added"
    output.should include "1 files deleted"
  end
end