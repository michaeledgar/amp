#!/usr/bin/ruby
ARGV.collect! {|x| x.sub(/^--with-bz2-prefix=/, "--with-bz2-dir=") }

require 'mkmf'

if RUBY_VERSION =~ /1.9/ then  
    $CPPFLAGS += " -DRUBY_19"  
end

if unknown = enable_config("unknown")
   libs = if CONFIG.key?("LIBRUBYARG_STATIC")
	     Config::expand(CONFIG["LIBRUBYARG_STATIC"].dup).sub(/^-l/, '')
	  else
	     Config::expand(CONFIG["LIBRUBYARG"].dup).sub(/^lib([^.]*).*/, '\\1')
	  end
   unknown = find_library(libs, "ruby_init", 
			  Config::expand(CONFIG["archdir"].dup))
end

dir_config('bz2')
if !have_library('bz2', 'BZ2_bzWriteOpen')
   raise "libz2 not found"
end

if enable_config("shared", true)
   $static = nil
end

create_makefile('bz2')

begin
   make = open("Makefile", "a")
   if unknown
      make.print <<-EOF

unknown: $(DLLIB)
\t@echo "main() {}" > /tmp/a.c
\t$(CC) -static /tmp/a.c $(OBJS) $(CPPFLAGS) $(LIBPATH) $(LIBS) $(LOCAL_LIBS)
\t@-rm /tmp/a.c a.out

EOF
   end
   make.print <<-EOF

%.html: %.rd
\trd2 $< > ${<:%.rd=%.html}

   EOF
   make.print "HTML = bz2.html"
   docs = Dir['docs/*.rd']
   docs.each {|x| make.print " \\\n\t#{x.sub(/\.rd$/, '.html')}" }
   make.print "\n\nRDOC = docs/bz2.rb"
   make.puts
   make.print <<-EOF

rdoc: docs/doc/index.html

docs/doc/index.html: $(RDOC)
\t@-(cd docs; rdoc bz2.rb)

ri: docs/bz2.rb
\t@-(cd docs; rdoc -r bz2.rb)

ri-site:
\t@-(cd docs; rdoc -R bz2.rb)

rd2: html

html: $(HTML)

test: $(DLLIB)
   EOF
   Dir.foreach('../../../test') do |x|
      next if /^\./ =~ x || /(_\.rb|~)$/ =~ x
      next if FileTest.directory?(x)
      make.print "\t-$(RUBY) tests/#{x}\n"
   end
ensure
   make.close
end

