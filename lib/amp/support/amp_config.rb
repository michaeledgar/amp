require 'amp/dependencies/python_config.rb'

module Amp
  
  ##
  # AmpConfig is the class that handles all configuration for the
  # Amp program. It is different from PythonConfig because there is
  # a sense of hierarchy in the configuration files in Mercurial, and
  # as such, in Amp. Namely, the hgrc in /etc/mercurial/ is of lesser
  # importance as the one in your_repo/.hg/. So, we use "parent configs"
  # to handle this hierarchy - create an AmpConfig with a parent, and it'll
  # copy over all the old configurations. Then, tell it to read the
  # repo-specific hgrc file, and the new settings will override the old ones.
  class AmpConfig
    include PythonConfig
    
    ##
    # The PythonConfig that actually stores all the information
    attr_accessor :config
    attr_reader :parent_config
    ##
    # Initializes the AmpConfig. Takes options to do that.
    # 
    # @param [Hash] opts the options for initialization.
    # @option [AmpConfig] opts :parent_config (nil) The parent configuration
    #   to base this configuration off of. The parent will be duplicated and
    #   then some options in it may be overridden.
    # @option [[String], String] opts :read (nil) A list of files to read for
    #   configuring this AmpConfig, for example repo/.hg/hgrc. Note: if
    #   :parent_config is not provided, this option will default to 
    #   /etc/mercurial/hgrc and ~/.hgrc.
    # All other options are saved in an instance variable for later reference.
    def initialize(opts={})
      @config = nil
      @options = opts
      
      if opts[:parent_config]
        @parent_config = opts.delete :parent_config
        @config = @parent_config.config.dup
      else
        opts[:read] = Support::rc_path
      end
      
      if opts[:read]
        @config = ConfigParser.new
        
        [*opts.delete(:read)].each do |file|
          read_file file
        end
      end
      
      if opts[:parent]
        @config = opts.delete(:parent).dup
      end
      @write_to_file ||= File.expand_path("~/.hgrc")
    end
    
    ##
    # Reads the file provided, and overwrites any settings we've already
    # assigned. Does NOT raise an error if the file isn't found.
    def read_file(file)
      begin
        File.open(file, "r") do |fp|
          newconfig = ConfigParser.new fp
          @config.merge! newconfig
        end
        
        @config.merge! @options[:overlay] if @options[:overlay]
        @write_to_file = file
      rescue Errno::ENOENT
      end
    end
    
    ##
    # Saves to the most recently read-in file
    def save!
      @config.write @write_to_file
    end
    
    ##
    # Updates our options with any settings we provide. 
    def update_options(opts = {})
      if opts[:config]
        config = opts.delete config
        config.each do |section, settings|
          settings.each do |k,v|
            self[section,k] = v
          end
        end
      end
      @options.merge! opts
    end
    
    ##
    # Gets the current username. First it checks some environment variables,
    # then it looks into config files, then it gives up and makes one up.
    # 
    # @return [String] the username for commits and shizz
    def username
      user = nil
      # check the env-var
      user ||= ENV["HGUSER"]
      return user if user
      # check for an email
      user ||= ENV["EMAIL"]
      return user if user
      # check for stored username
      user ||= self["ui","username"]
      return user if user
      #check for a setting
      if self["ui", "askusername", Boolean]
        user = UI.ask("enter a commit username:")
      end
      return user if user
      # figure it out based on the system
      user = "#{Support.get_username}@#{Support.get_fully_qualified_domain_name}"
      return user
    end
    
    ##
    # Access configurations. Params:
    # Section, [Config Key], [Type to convert to], [Default value if not found]
    # 
    # @example myconfig["ui", "askusername", Boolean, false]
    #   this means look in the "ui" section for a key named "askusername". If
    #   we find it, convert it to a Boolean and return it. If not, then just
    #   return false.
    def [](*args)
      section = args[0]
      
      case args.size
      when 1
        @config[section]
      when 2
        key = args[1]
        @config[section][key]
      when 3
        key = args[1]
        force = args[2]
        @config[section][key, force]
      when 4
        key = args[1]
        force = args[2]
        default = args[3]
        @config[section][key, force, default]
      end
    end
    
    ##
    # Assigning section-key values.
    # 
    # @param args the [Section, Key] pair
    # @param value what you assigned it to.
    # @example  config["ui", "askusername"] = false
    def []=(*args) # def []=(*args, value)
      value = args.pop
      section = args[0]
      key = args[1]
      @config[section][key] = value
    end
    
    def to_s; @config.to_s; end
  end
end