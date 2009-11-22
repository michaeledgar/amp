require 'mkmf'
if RUBY_VERSION =~ /1.9/ then  
    $CPPFLAGS += " -DRUBY_19"  
end
create_makefile("Support")
