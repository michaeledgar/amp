= This is an interface to the library libbzip2

* Installation
 
   ruby extconf.rb
   make
   make install
 
== You may need to specify :

  --with-bz2-include=<include file directory for libbzip2>

  --with-bz2-lib=<library directory for libbzip2>

  --with-bz2-dir=<prefix for library and include of libbzip2>

== Example :
 
  ruby extconf.rb --with-bz2-dir=/home/ts/local

* Documentation :

    make rd2
    make rdoc
    make ri

* Tests : if you have rubyunit, or testunit

   make test

* Copying
 
 This extension module is copyrighted free software by Guy Decoux
 
 You can redistribute it and/or modify it under the same term as
 Ruby.
 
 
Guy Decoux <ts@moulon.inra.fr>
