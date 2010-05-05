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

command :manifest do |c|
  c.workflow :hg
  c.desc "Prints the manifest at a given revision (defaults to working directory)"
  c.add_opt :rev, "Specifies the revision to check", {:short => "-r", :type => :integer}
  c.on_run do |options, arguments|
    revision = options[:rev] || "tip"
    repo = options[:repository]
        
    repo[revision].each do |k, _|
      puts "#{k}"
    end
  end
end