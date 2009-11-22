##
# Stolen/heavily modified from 
# http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-talk/140603
# Thanks man

##
# Example generator. Note that we put +nil+ at the end to indicate the end of generation.
# class Fibonacci < Generator
#   def generator_loop
#     previous, current=0,1
#     10.times do
#  
#       # works
#       yield_gen current
#       previous, current = current, previous + current
#     end
#     nil
#   end
# end

##
# Generic generator. woo. Implement +generator_loop+ to make a concrete subclass.
#
# Allows you to create an object that lazily generates values and yields them 
# when the next() method is called. 
class Generator
  
  ##
  # Generic initializer for a Generator. If you subclass, you must caller super
  # to initialize the continuation ivars.
  def initialize
	  @current_context = nil
	  reset
  end
  
  ##
  # Runs the next iteration of the generator. Uses continuations to jump across
  # the stack all willy-nilly like.
  #
  # @return [Object] the next generated object.
  def next
    # by setting @current_context to +here+, when @current_context is called, next() will
    # return to its caller.
    callcc do |here|
      @current_context = here
      if @yield_context
        # Run next iteration of the running loop
        @yield_context.call
      else
        # Start the loop
        generator_loop
	    end
    end
  end
  
  ##
  # Resets the generator from the beginning
  def reset
    @yield_context = nil
  end
  
  private
  
  ##
  # Yields a value from within the generator_loop method to the caller of +next+.
  # This method actually is what returns a value from a call to next through the
  # roundabout nature of continuations.
  #
  # @param value the value to return from +next+
  def yield_gen(value)
    callcc do |cont|
      @yield_context = cont
      @current_context.call value # causes next() to immediately return +value+
    end
  end
  
end

