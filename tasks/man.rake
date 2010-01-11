require 'rtfm/tasks'

RTFM::ManPage.new("amp", 1) do |page|
  page.summary = "Ruby-based VCS engine"
  
  page.option :verbose, "Enables verbose output for the entire Amp process."
  page.option :d, "Prings a variety of debug information about the arguments and options passed into amp.", :long => :"debug-opts"
  page.option :profile, "Profiles the amp process as it runs the requested command. Deprecated and unwise."
  page.option :R, "The path to the repository to use", :long => "repository", :argument => "repo_dir"
  page.option :"pure-ruby", "Use only pure ruby (no C-extensions)"
  page.option :testing, "Running a test. Don't touch this."
  
  page.synopsis do |synopsis|
    synopsis.argument "command"
  end
  
  page.description do |description|
    description.body = <<-EOF
  Amp is a revolutionary change in how we approach version control systems. Not only does it re-implement
Mercurial's core in Ruby, but re-thinks how we interact with version control. It intends to wrap multiple
VCS systems - git, hg, svn - under the same API, allowing the unique Amp command system to work with all
repositories in the same manner.

  Amp currently implements Mercurial and a large subset of the Mercurial command-set.
EOF
  end
  
  page.see_also do |also|
    also.reference "hg", 1
    also.reference "git", 1
    also.reference "ruby", 1
    also.reference "amprc", 5
  end
  
  page.authors do |authors|
    authors.add "Michael Edgar", "adgar@carboni.ca"
    authors.add "Ari Brown", "seydar@carboni.ca"
  end
end