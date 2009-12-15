Here are the things we'd like to do. If you're looking to help out, read on.
We put them into several categories to trick^H^H^H^H^Hencourage you to help.

== Maintenance

= Dependencies
We need these down to zero. Currently we DO need YARD, but flay and flog? We
haven't used these at all yet. Either remove these from the code (well, really
the Rakefiles) or add a way to fail gracefully.

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

== Expansion

= Faster Bit Structs
We experimented with using bitstructs to represent objects in files. Although
this worked, it was MUCH slower than we could bear. We need a faster form of
a bitstruct. A bitstruct is a standard C struct. If has a format, it has fields
with names, and you can easily read and write them to and from files. Writing
this alone is a task big enough for a young adult. We need these tested and
benchmarked against not using bitstructs. Also, try to keep these pure ruby if
you can.

= Incorporating Bit Structs
Take the bitstructs of the previous paragraph and incorporate them into
everything. If you can, fix up the revlog API to make it suck a little less.

= hg Extensions
Start porting over the Mercurial extensions. 'Nuff said.

= Expanding `amp serve`
We'd like it to be more like BitBucket and GitHub. Go crazy. One thing you
could do is implement other methods for storing users besides memory. There
are incomplete frameworks for Sequel and DataMapper storage that need TLC.

== Documentation

= User guide
We need a guide that will tell new users how to install and use amp. It should
explain what to do if you get a bug.

= Inline documentation
Go through to big ugly methods (or any method, no matter how dumb) and add
inline comments explaining what the method does and HOW IT INTERACTS WITH
THE REST OF THE SYSTEM. Comments should be formatted according to YARD
documentation format (http://yardoc.org).

= Wiki
We need to expand out BitBucket wiki so that it is more appeasing and useful
