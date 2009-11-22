##
# This command will go through your repository's working directory, and if it
# discovers any files that it was tracking, but have mysteriously disappeared,
# the command will assume you meant to remove it (stop tracking it), and remove it
# for you. Similarly, if you have any files that are untracked and have appeared
# in your repository, and they aren't ignored by your .hgignore file, then we
# assume you wanted to add them, and add them for you.
#
# The only significant difference between this command and Mercurial's implementation
# is the addition of the interactive mode. This mode asks the user before each removal
# and addition. Personally, I added it because I don't like blanket actions taken across
# my entire repository. It's off by default.
command :addremove do |c|
  c.workflow :hg
  
  c.desc "Add all new files, delete all missing files"
  c.opt :interactive, "Asks about each file before adding/removing", :default => false, :short => "-a"
  c.opt :include, "include names matching the given patterns", :type => :string, :short => "-I"
  c.opt :exclude, "exclude names matching the given patterns", :type => :string, :short => "-E"
  c.opt :"dry-run", "Don't perform actions, just print output", :short => "-n"
  c.help <<-EOS
amp addremove [options]+

  New files are ignored if they match any of the patterns in .hgignore. As
  with add, these changes take effect at the next commit.

  Use the -s option to detect renamed files. With a parameter > 0,
  this compares every removed file with every added file and records
  those similar enough as renames. This option takes a percentage
  between 0 (disabled) and 100 (files must be identical) as its
  parameter. Detecting renamed files this way can be expensive.
  
  Where options are:
EOS

  c.on_run do |opts, args|
    repo = opts[:repository]
    
    # Standard preparation for mercurial-style matching. We need a match object.
    # If a file is missed by our matcher, assume we want it included (unknown files match
    # this situation)
    matcher = Amp::Match.create(:includer => opts[:include], :excluder => opts[:exclude]) { true }
    # Get only the deleted and unknown files. We'll remove the former and add the latter.
    results = repo.status(:match => matcher, :deleted => true, :added => false, :unknown => true,
                          :ignored => false, :modified => false, :clean => false)
    
    Amp::UI.say
    # Prettified, add check later if user disables colors
    Amp::UI.say "ADDING FILES".blue if results[:unknown].any?
    # Handle adding the files now
    if opts[:interactive]
      # Interactive means we ask the user if they want to add the file or not.
      # Build a list based on what they agree upon, then add that list
      to_add = []
      results[:unknown].each do |file|
        add = Amp::UI.yes_or_no("Add #{file.relative_path(repo.root).blue}? [y/n] ")
        to_add << file if add
      end
    else
      # Otherwise, just let the user know what we're about to add
      results[:unknown].each {|file| Amp::UI.say "Adding #{file.relative_path repo.root}" }
      to_add = results[:unknown]
    end
    repo.add(to_add) unless opts[:"dry-run"]
    
    Amp::UI.say
    # Prettified, add check later if user disables colors
    Amp::UI.say "REMOVING FILES".red if results[:deleted].any?
    # Now we remove any files that mysteriously disappeared on us
    if opts[:interactive]
      # Interactive means ask the user if they want to remove a file from the repo or not.
      # Build a list.
      to_del = []
      results[:deleted].each do |file|
        del = Amp::UI.yes_or_no("Remove #{file.relative_path(repo.root).red}?")
        to_del << file if del
      end
    else
      # Otherwise, just inform the user of the damage (yes I'm biased against this command)
      results[:deleted].each {|file| Amp::UI.say "Removing #{file.relative_path repo.root}" }
      to_del = results[:deleted]
    end
    repo.remove to_del unless opts[:"dry-run"]
    
  end
end