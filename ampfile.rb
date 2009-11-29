# need { 'lib/amp/extensions/ditz' }
# need { 'lib/amp/extensions/lighthouse' }

# Amp::LighthouseHook.add_hooks(:commit) do |hook|
#   hook.token   = 'e4d6af1951c240e00c216bad3c52cf269cba4a7c'
#   hook.account = 'carbonica'
#   hook.project = 'amp'
# end

Amp::Command.new("silly") do |c|
  c.workflow :hg
  c.on_run do |options, args|
    puts "You're silly!"
    puts "You're REALLLY silly!"
  end
  c.desc "tell you how silly you are"
end

command :push do |c|
  c.before { system "hg verify" }
end

template :silly, <<-EOF
<%= change_node.inspect %> <%= revision %>
EOF

command "stats" do |c|
  c.workflow :hg
  c.desc "Prints how many commits each user has contributed"
  c.on_run do |opts, args|
    repo = opts[:repository]
    users = Hash.new {|h, k| h[k] = 0}
    repo.each do |changeset|
      users[changeset.user.split("@").first] += 1 #
    end
    users.to_a.sort {|a,b| b[1] <=> a[1]}.each do |u,c|
      puts "#{u}: #{c}"
    end
  end
end

namespace :docs do
  
  command "gen" do |c|
    c.desc "create the docs"
    c.on_run {|o, a| `rake yard:doc`; puts 'docs made!' }
  end
  
  command "upload" do |c|
    c.desc "upload the docs"
    c.on_run {|o, a| puts "docs uploaded!!!!" }
  end
  
  namespace :search do
    
    command "methods" do |c|
      c.desc "search method names"
      c.on_run {|o, a| puts "#{a.inspect}"}
    end
  end
end
