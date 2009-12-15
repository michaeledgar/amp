require 'delegate'
require 'logger'
module Amp
  module Support
    LOGGER_LEVELS = [:warn, :info, :fatal, :error, :debug]
    module SingletonLogger
      attr_accessor :singleton_object
      def global_logger
        singleton_object
      end
      
      LOGGER_LEVELS.each do |message|
        define_method(message) { |*args| global_logger.send(message, *args) }
      end
      
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
      
      LOGGER_LEVELS.each do |message|
        define_method(message) {|input| @output.puts(input) }
      end
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
      
      LOGGER_LEVELS.each do |message|
        define_method(message) { |input| @source.send(message, "\t\t"*@indent + input); self }
      end
      
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