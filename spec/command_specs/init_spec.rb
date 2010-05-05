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

require File.expand_path(File.join(File.dirname(__FILE__), 'command_helper'))
cmd = easy_get_command("all", /([^\/]*)_spec.rb/.match(__FILE__)[1])

describe cmd do
  before(:all) do
    Amp::Repositories::Mercurial::LocalRepository = mock("hg_repo")
    Amp::Repositories::Mercurial::LocalRepository.stub!(:new)
    
    Amp::Repositories::Git::LocalRepository = mock("git_repo")
    Amp::Repositories::Git::LocalRepository.stub!(:new)
  end
  
  it "creates a mercurial repository" do
    Amp::Repositories::Mercurial::LocalRepository.should_receive(:new).with(anything, true, anything)
    output = with_swizzled_io do
      cmd.run({:type => "hg"})
    end
  end
  
  it "creates a git repository" do
    Amp::Repositories::Git::LocalRepository.should_receive(:new).with(anything, true, anything)
    output = with_swizzled_io do
      cmd.run({:type => "git"})
    end
  end
  
  it "errors on unknown repositories" do
    lambda do
      output = with_swizzled_io do
        cmd.run({:type => "sillypants"})
      end
    end.should raise_exception
  end
end