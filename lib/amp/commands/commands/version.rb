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

command :version do |c|
  c.workflow :all
  
  c.desc "Prints the current version of Amp."
  c.opt :super, "Print out a hash of the source for amp to verify its integrity"
  c.on_run do |options, args|
    puts "Amp version #{Amp::VERSION} (#{Amp::VERSION_TITLE})"
    
    if options[:super]
      require 'digest/md5'
      digest = Digest::MD5.new
      
      files = Dir["#{Amp::CODE_ROOT}/**/**/**/**/**/**/**/**/**/*.rb"]
      files.each do |file|
        open(file) {|f| digest << f.read(8192) } # read in the file in 8K chunks
      end
      
      puts "\tIntegrity Digest: #{digest.hexdigest}"
    end
  end
end