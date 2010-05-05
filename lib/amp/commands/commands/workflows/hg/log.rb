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

command :log do |c|
  c.workflow :hg
  c.desc "Prints the commit history."
  c.opt :verbose, "Verbose output", {:short => "-v"}
  c.opt :limit, "Limit how many revisions to show", {:short => "-l", :type => :integer}
  c.opt :template, "Which template to use while printing", {:short => "-t", :type => :string, :default => "default"}
  c.opt :no_output, "Doesn't print output (useful for benchmarking)"
  
  c.on_run do |options, args|
    repo = options[:repository]
    limit = options[:limit]
    limit = repo.size if limit.nil?
    
    start = repo.size - 1
    stop  = start - limit + 1
    
    options.merge! :template_type => :log
    start.downto stop do |x|
      puts repo[x].to_templated_s(options) unless options[:no_output]
    end
  end
end
