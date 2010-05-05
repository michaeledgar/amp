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

command :tip do |c|
  c.workflow :hg
  
  c.desc "Prints the information about the repository's tip"
  c.opt :template, "Which template to use while printing", :short => "-t", :type => :string, :default => "default"
  
  c.on_run do |options, args|
    repo = options[:repository]
    options.merge! :template_type => :log
    puts repo[repo.size - 1].to_templated_s(options)

  end
end