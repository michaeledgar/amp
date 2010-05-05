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

command :info do |c|
  c.workflow :hg
  c.desc "Print information about one or more changesets"
  c.opt :template, "Which template to use while printing", {:short => "-t", :type => :string, :default => "default"}
  
  c.on_run do |opts, args|
    #arguments are the revisions
    repo = opts[:repository]
    
    args.empty? && args = ['tip']
    opts.merge! :template_type => :log
    
    args.each do |arg|
      index = arg
      puts repo[index].to_templated_s(opts)
    end
  end
end