command "tags" do |c|
  c.workflow :hg
  
  c.desc "Lists the repository tags."
  c.opt :quiet, "Prints only tag names", :short => "-q"
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    list = repo.tag_list
    list.reverse!
    tag_type = ""
    list.each do |entry|
      tag, node, revision = entry[:tag], entry[:node], entry[:revision]
      if opts[:quiet]
        Amp::UI.say "#{tag}"
        next
      end
      if revision == -2
        revision = repo.changelog.rev(node)
      end
      text = "#{revision.to_s.rjust(5)}:#{node.short_hex}"
      tag_type = (repo.tag_type(tag) == "local") ? " local" : ""
      
      Amp::UI.say("#{tag.ljust(30)} #{text}#{tag_type}")  
    end
  end
end