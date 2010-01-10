# Any ruby code here will be executed before Amp loads a repository and
# dispatches a command.
#
# Example command:
#
# command "echo" do |c|
#    c.opt :"no-newline", "Don't print a trailing newline character", :short => "-n"
#    c.on_run do |opts, args|
#        print args.join(" ")
#        print "\n" unless opts[:"no-newline"]
#    end
# end
