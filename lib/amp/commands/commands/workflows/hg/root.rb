command :root do |c|
  c.workflow :hg
  c.desc "Prints the current repository's root path."
  c.help <<-EOF
amp root
  
  Prints the path to the current repository's root.
EOF
  c.on_run do |opts, args|
    repo = opts[:repository]
    puts repo.root
  end
end