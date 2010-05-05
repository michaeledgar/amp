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