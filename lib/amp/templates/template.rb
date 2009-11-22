module Amp
  module Support
    ##
    # = Template
    # @author Michael Edgar
    #
    # Class representing a template in the amp system
    class Template
      
      @all_templates = {}
      class << self
        attr_accessor :all_templates
        
        ##
        # Returns the template with the given name.
        #
        # @param [String, Symbol, #to_sym] template the name of the template to retrieve
        # @return [Template] the template with the given name
        def [](template)
          ensure_templates_loaded
          return all_templates[template.to_sym]
        end
        
        ##
        # Registers a template with the Amp system. Should have a unique name.
        #
        # @param [String, Symbol, #to_sym] name the name of the template. Should be unique.
        # @param [Template] template the template to register.
        def register(name, template)
          all_templates[name.to_sym] = template
        end
        
        ##
        # Unregisters a template with the Amp system. If the name is not found, an exception
        # is thrown.
        #
        # @param [String, Symbol, #to_sym] name the name of the template to remove from
        #   the system.
        def unregister(name)
          raise ArgumentError.new("Unknown template: #{name}") unless all_templates[name.to_sym]
          all_templates.delete name.to_sym
        end
        
        ##
        # Returns whether any templates have been loaded. Used for lazy loading of templates.
        #
        # @return [Boolean] have the default templates, or any templates, been loaded?
        def templates_loaded?
          all_templates.any?
        end
        
        ##
        # Registers the default templates. Separated into a method (instead of automatically
        # run) because templates aren't used enough to justify the IO hit from loading them in.
        def load_default_templates
          Dir[File.expand_path(File.join(File.dirname(__FILE__), "*.erb"))].each do |f|
            name = f.split('/').last.chomp('.erb').sub('.','-')
            FileTemplate.new(name, f)
          end
        end
        
        ##
        # Makes sure the default templates have been loaded.
        #
        # About the use of instance_eval - this method could potentially be run more than once. There
        # is no reason for it to ever run more than once. So we'll redefine it to do nothing.
        def ensure_templates_loaded
          load_default_templates
          instance_eval do
            def ensure_templates_loaded; end
          end
        end
      end
      
      attr_accessor :name, :renderer, :text
      
      ##
      # Creates a new template with the given values. The name is how you will reference the
      # template using the --template option from the command line, so choose it wisely!
      #
      # @param [String, Symbol, #to_s] name the name of the template, which is invoked
      #   using --template
      # @param [Symbol] type the type of the template. Indicates the renderer used.
      # @param [String] text the text of the template, which presumably has some templating
      #   code to substitute in local variables and make a nice output system.
      def initialize(name, renderer = :erb, text = "")
        @name, @renderer, @text = name, renderer, text
        Template.register(name, self)
      end
      
      ##
      # Renders the template with the given local variables. Uses whichever templating engine
      # you set. Note: if you use HAML, you'll need to have HAML installed. This is why none
      # of the default templates use HAML.
      #
      # @param [Hash] locals the local variables passed to the template. Works for HAML so far,
      #   not for erb.
      # @return [String] the parsed template
      # @todo make locals work for ERb without bootleg hax
      def render(locals = {}, render_binding = binding)
        # expose this local to make it easier, even if it's nil
        
        case renderer.to_sym
        when :erb
          require 'erb'
          locals_assigns = locals.to_a.collect { |k,v| "#{k} = locals[:#{k}]" }
          eval locals_assigns.join("\n"), render_binding
          
          erb = ERB.new(text, 0, "-")
          erb.result render_binding
        when :haml
          require 'rubygems'
          require 'haml'
          haml = Haml::Engine.new(text)
          haml.render render_binding, locals
        end
      end
      
      private
      
    end
    
    ##
    # = FileTemplate
    # Class for loading a template from a file and registering it in the system.
    # Is smart enough that if the filename ends in a known extension, the appropriate
    # renderer will be used. Otherwise, you will have to specify the renderer.
    class FileTemplate < Template
      KNOWN_EXTENSIONS = ["erb", "haml"]
    
      attr_accessor :file        
      
      ##
      # Initializes a new FileTemplate with different 
      def initialize(name, file, renderer = nil)
        if renderer.nil?
          renderer = KNOWN_EXTENSIONS.select {|ext| file.end_with? ext}.first
        end
        raise ArgumentError.new("No renderer specified for #{file.inspect}") if renderer.nil?
        @file = file
        super(name, renderer, File.read(file))
      end
      
      def save!
        File.open(file, "w") { |out| out.write text }
      end
    end
    
    
    
  end
end

module Amp
  module KernelMethods
    def template(name, *args)
      if args.size > 2 || args.empty?
        raise ArgumentError.new('Usage of template: template(name, text)'+
                                'or template(name, renderer, text)')
      end
      template = (args.size > 1) ? args[0] : :erb
      Support::Template.new(name, template, args.last)
    end
  end
end