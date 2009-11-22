command :lolcats do |c|
  c.opt :cheezburger, "Add cheezburger to lolcat"
  c.on_run do |opts, args|
    puts "lolcats!"
    puts "lolcats!"
    puts "lolcats!"
    puts "lolcats!"
    puts "lolcats!"
  end
  
  c.before do |opts, args|
    puts "Before lolcats...."
  end
  c.after do |opts, args|
    puts "After lolcats!"
  end
end