require 'delegate'
require 'logger'
module Amp
  module Support
    module SingletonLogger
      attr_accessor :singleton_object
      def global_logger
        singleton_object
      end
      
      def warn(*args);  global_logger.warn(*args);  end
      def info(*args);  global_logger.info(*args);  end
      def fatal(*args); global_logger.fatal(*args); end
      def error(*args); global_logger.error(*args); end
      def debug(*args); global_logger.debug(*args); end
      
      def method_missing(meth, *args, &block)
        if global_logger.respond_to?(meth)
          global_logger.__send__(meth, *args, &block)
        else
          super
        end
      end
    end
    
    class IOForwarder
      def initialize(output)
        @output = output
      end
      
      def warn(input); @output.puts(input); end
      def info(input); @output.puts(input); end
      def fatal(input); @output.puts(input); end
      def error(input); @output.puts(input); end
      def debug(input); @output.puts(input); end
    end
    
    class Logger < DelegateClass(::Logger)
      extend SingletonLogger
      
      def initialize(output)
        @show_times = true
        @output = output
        @source = ::Logger.new(output)
        @indent = 0
        super(@source)
        self.class.singleton_object = self
      end
      
      def show_times=(bool)
        if @show_times && !bool # turn off times
          @normal_source = @source
          @source = IOForwarder.new(@output)
        elsif !@show_times && bool # turn it back on
          @source = @normal_source
        end
      end
      
      def section(section_name)
        info("<#{section_name}>").indent
        yield
        outdent.info("</#{section_name}>")
      end
      
      def indent
        @indent += 1
        self
      end
      
      def outdent
        @indent -= 1
        self
      end
      
      def warn(input);  @source.warn( "\t\t"*@indent + input); self; end
      def info(input);  @source.info( "\t\t"*@indent + input); self; end
      def fatal(input); @source.fatal("\t\t"*@indent + input); self; end
      def error(input); @source.error("\t\t"*@indent + input); self; end
      def debug(input); @source.debug("\t\t"*@indent + input); self; end
      
      
      def level=(level)
        receiver = @source
        case level
        when :warn
          receiver.level = ::Logger::WARN
        when :fatal
          receiver.level = ::Logger::FATAL
        when :error
          receiver.level = ::Logger::ERROR
        when :info
          receiver.level = ::Logger::INFO
        when :debug
          receiver.level = ::Logger::DEBUG
        when :none
          receiver.level = ::Logger::UNKNOWN
        else
          receiver.level = level
        end
      end
    end
  end
end