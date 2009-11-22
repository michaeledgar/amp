command :default do |c|
  c.workflow :hg
  c.desc "run the `info` and `status` commands"
  
  c.on_run do |options, args|
    Amp::Command['info'].run   options, args
    Amp::Command['status'].run options, args
  end
end