= amp

* http://bitbucket.org/carbonica/amp

== DESCRIPTION:

A ruby interface to Mercurial repositories, from the command line or a program.

== FEATURES/PROBLEMS:

* Supports Mercurial repositories completely!

== SYNOPSIS:
  First, mad shoutz to those who wrote Mercurial. It's truly fantastic, and
  we based a lot of our code on it. *Peace*
  
  
  % amp add file.txt
  edit...
  % amp commit -m "leethaxness"
  % amp push
  
  Nothing really changes from using the hg command. There are a few differences
  here and there (see `amp help [COMMAND]`), but really, it's pretty much the same.
  
  Using amp as a library:
  
  require "irb"
  require "irb/workspace"
  require "amp"
  include Amp
  
  def new_irb(*args)
    IRB::Irb.new(Workspace.new(*args)).eval_input
  end
  
  repo = Repositories::LocalRepository.new "/Users/ari/src/amp.code"
  
  # makeses a file...
  Dir.chdir "/Users/ari/src/amp.code/"
  open "testy.txt", "w" {|f| f.puts "hello, world!" }
  
  # and add it to the repo!
  repo.add "testy.txt"
  
  # commit
  repo.commit :message => 'blah'
  
  # do some more things...
  
  # pull and update...
  repo.pull
  result = repo.update
  
  (puts "You need to fix shit!"; new_irb binding) unless result.success?
  # type result.unresolved to get a list of conflicts
  
  # and push!
  repo.push
  
  Everything here is really straight forward. Plus, if it's not, we've taken
  the liberty to document the motherfucking shit out of motherfucking everything.
  Hooray!
  
== REQUIREMENTS:

* None! Not even rubygems.

== INSTALL:

* [sudo] gem install amp

== LICENSE:

See the LICENSE file.