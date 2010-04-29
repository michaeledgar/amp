Here are the things we'd like to do. If you're looking to help out, read on.
We have put them into several categories to trick^H^H^H^H^Hencourage you into
helping.

**RULE NUMBER 1**: It's ok if you break amp. Go ahead and accidentally remove
every file, commit, and then push it. We're not worried; we have immutable history
and multiple copies of the repo and advanced knowledge of `amp/hg revert`. You
can't hurt us.

== Specifics

= Amp config
Write now we save config information is ~/.hgrc. Somebody, please, either
drown me or make this go the fuck away. Config information could (should?)
be saved in the top section of the ampfile. It can be a YAML object serialized
with comments prefixing each line, with the entire section ending with a series
of #s.

= Remote Repositories
They. All. Look. The. Same. At least as far as amp is concerned, at them moment.
We need to fix this shiznizzle because this means you cannot use a foreign
repository for anything other than Mercurial, really (based on how the files
are loaded). Be creative. Be awesome. Be daring. Few in millions can speak like us.
Show the world why you are a programmer. SOLVE THIS PROBLEM!

== Maintenance

= Dependencies
We need these down to zero. Currently we DO need YARD, but flay and flog? We
haven't used these at all yet. Either remove these from the code (well, really
the Rakefiles) or add a way to fail gracefully. We also now need minitest, etc.
Development dependencies are ok, but dependencies for running? Kill them. Kill
them aaaaaaalllllllllllll.

= Multitude of Tests
Tests. We need them. Moar and moar of them. We want every command to be tested
(at least generally), although if every option were also tested that'd be
superb.

= Organization of Tests
We currently have a gigantic test_functional.rb file that has most of the good
tests. However, if there's a failure in the very beginning, the rest of the
tests won't be run. It's true – some of the tests are dependent on each other,
but perjaps there's a way to split them up into clusters that make sense and
can be run independently.

= Code Cleaning
We have ugly code. We try to mark it with comments, we try to eliminate it in
the first place, but seriously, when it comes to programming or doing some
World Religions homework, I'm going to get the homework done first. And then
some girl will have IMed me, and, well, you get the point. If you see ugly
code, kill it. Hopefully it won't require any major architectural changes.

= API Adherence
Make the commands in the workflows stick to the API. If something doesn't adhere,
change the API and change the command until it works. **NOTU BONE (Esperanto)**:
Write a plethora of tests before changing a command, lest you break some
little-known feature of the command and in its stead add a new "feature".

== Expansion

= Faster Bit Structs
We experimented with using bitstructs to represent objects in files. Although
this worked, it was MUCH slower than we could bare. We need a faster form of
a bitstruct. A bitstruct is a standard C struct. If has a format, it has fields
with names, and you can easily read and write them to and from files. Writing
this alone is a task big enough for a young adult. We need these tested and
benchmarked against not using bitstructs. Also, try to keep these pure ruby if
you can.

= Incorporating Bit Structs
Take the bitstructs of the previous paragraph and incorporate them into
everything. If you can, fix up the mercurial revlog API to make it suck a
little less.

= hg Extensions
Start porting over the Mercurial extensions. 'Nuff said.

= Expanding `amp serve`
We'd like it to be more like BitBucket and GitHub. Go crazy. One thing you
could do is implement other methods for storing users besides memory. There
are incomplete frameworks for Sequel and DataMapper storage that need TLC.

== Help

= Pages of info
We need to have specific pages explaining amp-specific features, and helping
users get started using amp. Anything put into lib/amp/help/entries will be
loaded with its filename as the help entry's name. So, if you create a file
called "ampfiles.md", then "amp help ampfiles" will present the file you created.

== Insects (low-low-low-priority bugs)

= Test Reloading
Files get double-loaded when we run tests. Fix this. Kill the fucking insect.

== Documentation

= User guide
We need a guide that will tell new users how to install and use amp. It should
explain what to do if you get a bug. Add this into the help system so it can be
CLI-accessible and browser-accessible. Add it to the man pages as well (see
tasks/man.rake).

= Inline documentation
Go through to big ugly methods (or any method, no matter how dumb) and add
inline comments explaining what the method does and HOW IT INTERACTS WITH
THE REST OF THE SYSTEM. Comments should be formatted according to YARD
documentation format (http://yardoc.org). Key questions to ask and answer:
Who (uses this), What (is passed in), Why (this exists), and How (this
interacts with the rest of the system).

= Wiki
We need to expand out BitBucket wiki so that it is more appeasing and useful.

== Optimization

= StagingArea#file_status
This is called like a million times and it's unnecessary. We can use memoization
alleviate any pains. But be apprised: we have yet to feel any pains from it.