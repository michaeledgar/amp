command :tag do |c|
  c.workflow :hg
  
  c.desc "Tags a revision with a given tag name"
  c.opt :rev, "Specifies which revision to tag", :short => "-r", :type => :string
  c.opt :message, "Specifies the commit message", :short => "-m", :type => :string
  c.opt :local, "Marks the tag as local only (not shared among repositories)", :short => "-l"
  c.opt :remove, "Removes the tag, instead of applying it", :short => "-R"
  c.opt :force, "Forces the tag to be applied, ignoring existing tags", :short => "-f"
  c.opt :user, "Specifies which user to commit under", :short => "-u", :type => :string
  c.opt :date, "Specifies which date to use", :short => "-d", :type => :string
  
  c.on_run do |opts, args|
    repo = opts[:repository]
    
    user = opts[:user] || opts[:global_config].username
    date = opts[:date] ? DateTime.parse(opts[:date]) : Time.now
    rev  = opts[:rev]  || "."
    message = opts[:message]
    
    names = args
    if names.map! {|n| n.strip}.uniq!
      raise abort("tag names must be unique")
    end
    names.each do |n|
      if ["tip",".","null"].include? n
        raise abort("the tag name #{n} is reserved")
      end
    end
    if opts[:rev] && opts[:remove]
      raise abort("--rev and --remove are incompatible")
    end
    
    #removing a tag
    if opts[:remove]
      expected_type = opts[:local] ? "local" : "global"
      names.each do |name|
        unless repo.tag_type name
          raise abort("tag #{name} does not exist")
        end
        if repo.tag_type(name) != expected_type
          raise abort("tag #{name} is not a #{expected_type} tag")
        end
      end
      rev = Amp::RevlogSupport::Node::NULL_ID
      message ||= "Removed tag #{names.join(", ")}"
    elsif !opts[:force]
      names.each do |name|
        if repo.tags[name]
          raise abort("tag #{name} already exists" +
                                             " (use -f to force)")
        end
      end
    end
    
    if !rev && repo.dirstate.parents[1] != Amp::RevlogSupport::Node::NULL_ID
      raise abort("uncommited merge - please provide" +
                                         " a specific revision")
    end
    
    node = repo[rev].node
    
    message ||= "Added tag #{names.join(", ")} for changeset #{node.short_hex}"
    repo.apply_tag names, node, :message => message, 
                                :local => opts[:local],
                                :user => user,
                                :date => date
  end
end