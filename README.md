Amp Release v0.5.0 (John Locke)
==============================

**Homepage**:   [http://amp.carboni.ca](http://amp.carboni.ca)   
**IRC**:        **#amp-vcs on irc.freenode.net**  
**Git**:        [http://github.com/michaeledgar/amp](http://github.com/michaeledgar/amp)   
**Mercurial**:  [http://bitbucket.org/carbonica/amp](http://bitbucket.org/carbonica/amp)   
**Author**:     Michael Edgar & Ari Brown  
**Copyright**:  2009  
**License**:    GPLv2 (inherited from Mercurial)  


Description:
------------

A ruby interface to Mercurial repositories, from the command line or a program.

Features:
------------------

* Supports Mercurial repositories completely!
* Extremely flexible command system.
* Ampfiles allow easy command creation/modification.
* Customizable workflows allow multiple command interfaces to the same operations

Known Issues:
------------------

* No Windows support.
* Importing git patches is untested and likely won't run.
* creating bundles (the `bundle` command) likely fails.

Synopsis:
---------

    % amp add file.txt
    edit...
    % amp commit -m "updated the file"
    % amp push
  
Nothing really changes from using the hg command. There are a few differences
here and there (see `amp help [COMMAND]`), but really, it's pretty much the same.

Right now, we're trying to simplify the docs, to make it easier to tell what things
are relevant to someone working with Amp. Most of our documentation is on our website,
but here's an example of some Ampfile code:

    command "stats" do |c|
      c.workflow :hg
      c.desc "Prints how many commits each user has contributed"
      c.on_run do |opts, args|
        repo = opts[:repository]
        users = Hash.new {|h, k| h[k] = 0}
        repo.each do |changeset|
          users[changeset.user.split("@").first] += 1
        end
        users.to_a.sort {|a,b| b[1] <=> a[1]}.each do |u,c|
          puts "#{u}: #{c}"
        end
      end
    end
    
In the on\_run handler, _repo_ is a LocalRepository object. Its #each method iterates over
ChangeSet objects, which store information about that particular commit, including which user
committed it. These objects will be most relevant to users, but we'll try to make things more
obvious as we refine our documentation. At the very least, we've tried to provide a useful
description of every method we can.
  
Example:
________

    % amp add file.txt
    edit...
    % amp commit -m "leethaxness"
    % amp push
  
Nothing really changes from using the hg command. There are a few differences
here and there (see `amp help [COMMAND]`), but really, it's pretty much the same.
  
Using amp as a library:
  
  require "amp"
  include Amp
  
  repo = Repositories::pick "/Users/ari/src/amp.code"
  remote = Repositories::pick "https://user:password@bitbucket.org/carbonica/amp"
  
make a file...

  Dir.chdir "/Users/ari/src/amp.code/"
  open "test.txt", "w" {|f| f.puts "hello, world!" }
  
and add it to the repo!

  repo.add "test.txt"
  
commit

  repo.commit :message => 'blah'
  
do some more things, pull and update...

  result = repo.pull remote
  result = repo.update if result.success?
  
  (puts "You need to fix things!"; new_irb_session binding) unless result.success?
  # type result[:unresolved] to get a list of conflicts
  
and push!

  repo.push remote
  
Everything here is really straight forward. Plus, if it's not, we've taken
the liberty to document as much as possible.
  
Requirements:
-------------
* Ruby
* Nothing else! (except rubygems to install - for now)

Install:
--------

    sudo gem install amp --no-wrappers

License:
--------

See the LICENSE file.