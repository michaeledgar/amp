#######################################################################
#                  Licensing Information                              #
#                                                                     #
#  The following code is a derivative work of the code from the       #
#  Mercurial project, which is licensed GPLv2. This code therefore    #
#  is also licensed under the terms of the GNU Public License,        #
#  verison 2.                                                         #
#                                                                     #
#  For information on the license of this code when distributed       #
#  with and used in conjunction with the other modules in the         #
#  Amp project, please see the root-level LICENSE file.               #
#                                                                     #
#  © Michael J. Edgar and Ari Brown, 2009-2010                        #
#                                                                     #
#######################################################################

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
  
  RESERVED_TAG_NAMES = ["tip", ".", "null"]
  
  ##
  # Before block: simple argument and option validation.
  c.before do |opts, args|
    names = args
    
    # First, make sure that the tag names are unique.
    if names.map! {|n| n.strip}.uniq!
      raise abort("tag names must be unique")
    end
    
    # Make sure that the tags they provided aren't reserved
    names.each do |n|
      if RESERVED_TAG_NAMES.include? n
        raise abort("the tag name #{n} is reserved")
      end
    end
    
    # Make sure the options fit together
    if opts[:rev] && opts[:remove]
      raise abort("--rev and --remove are incompatible")
    end
    true
  end
  
  ##
  # Now let's do some more heavy-duty validation: do the tag names not work with the repo?
  c.before do |opts, args|
    names = args
    repo = opts[:repository]
    if opts[:remove]
      expected_type = opts[:local] ? "local" : "global"
      # They're removing a tag. Let's make sure those tags exist, and that the user
      # isn't confused about what type of tag it is.
      names.each do |name|
        # Tag exists, right?
        unless repo.tag_type name
          raise abort("tag #{name} does not exist")
        end
        # User doesn't think a global tag is a local one or something silly, right?
        if repo.tag_type(name) != expected_type
          raise abort("tag #{name} is not a #{expected_type} tag")
        end
      end
    elsif !opts[:force]
      # Make sure they're not re-using a tag name.
      names.each do |name|
        if repo.tags[name]
          raise abort("tag #{name} already exists (use -f to force)")
        end
      end
    end
    true
  end
  
  ##
  # If we get here, we passed a ton of validation!
  c.on_run do |opts, args|
    repo = opts[:repository]
    names = args
    
    # Let's extract our arguments.  Since this command creates a commit, we
    # let the user specify a bunch of commit parameters. Damn users.
    user = opts[:user] || opts[:global_config].username
    date = opts[:date] ? DateTime.parse(opts[:date]) : Time.now
    rev  = opts[:rev]  || "."
    message = opts[:message]
    
    # If we're removing a tag, we can infer some variables now.
    if opts[:remove]
      rev = Amp::Mercurial::RevlogSupport::Node::NULL_ID
      message ||= "Removed tag #{names.join(", ")}"
    end
    
    ##
    # One last check... You're not trying to tag an uncommitted merge, are you?
    # You crazy?
    if !rev && Amp::Mercurial::RevlogSupport::Node::null?(repo.dirstate.parents[1])
      raise abort("uncommited merge - please provide a specific revision")
    end
    
    # Lookup the node ID
    node = repo[rev].node
    
    # Apply the new commit!
    message ||= "Added tag #{names.join(", ")} for changeset #{node.short_hex}"
    repo.apply_tag names, node, :message => message, 
                                :local => opts[:local],
                                :user => user,
                                :date => date
  end
end