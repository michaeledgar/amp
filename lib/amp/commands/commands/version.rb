command :version do |c|
  c.desc "Prints the current version of Amp."
  c.workflow :all
  c.on_run do |options, args|
    puts "Amp version #{Amp::VERSION} (#{Amp::VERSION_TITLE})"
  end
end