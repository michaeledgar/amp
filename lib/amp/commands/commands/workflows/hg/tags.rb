command "tags" do |c|
  c.desc "Lists the repository tags."
  c.workflow :hg
  c.opt :quiet, "Prints only tag names", :short => "-q"
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    text = tag_type = ""
    
    list = repo.tag_list.each do |entry|
      if entry[:revision] == :unknown
        entry[:revision] = repo.changelog.rev(entry[:node])
      end
    end
    list.sort! {|a, b| b[:revision] <=> a[:revision]}
    
    list.each do |entry|
      tag, node, revision = entry[:tag], entry[:node], entry[:revision]
      if !opts[:quiet]
        text = "#{revision.to_s.rjust(5)}:#{node.short_hex}"
        tag_type = (entry[:type] == "local") ? " local" : ""
      end
      Amp::UI.say("#{tag.ljust(30)} #{text}#{tag_type}")  
    end
  end
end