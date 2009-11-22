require 'delegate'
require 'rubygems'
require 'lighthouse'

module Amp
  
  ##
  # = LighthouseHook
  # Makes creating lighthouse-committing hooks extremely easy. It is a
  # delegate to Lighthouse (it requires rubygems)
  #     
  # @example    Amp::LighthouseHook.add_hooks(:commit) do |hook|
  #               hook.token   = 'abcdefghiljklmnopqrstuvxyzabcdefghiljklmnopqrstuvxyz'
  #               hook.account = 'youraccount'
  #               hook.project = 'yourprojectname'
  #             end
  #     
  # @example    hook :commit do |opts|
  #               h = Amp::LighthouseHook.make do |hook|
  #                 hook.token   = 'abcdefghiljklmnopqrstuvxyzabcdefghiljklmnopqrstuvxyz'
  #                 hook.account = 'youraccount'
  #                 hook.project = 'yourprojectname'
  #               end
  #               h.call opts
  #             end
  class LighthouseHook < DelegateClass(Lighthouse.class)
    
    ##
    # Takes a block to configure a hook that can submit changesets to a
    # Lighthouse project. The result is a proc, which when run with an
    # Amp::Hook's options, will submit the changeset.
    #
    # You must provide either a username/password, or an API token to
    # the hook when configuring it. Otherwise, submitting changesets will fail.
    #
    # @example Creating a commit hook
    #     hook :commit do |opts|
    #       h = Amp::LighthouseHook.make do |hook|
    #         hook.token   = 'abcdefghiljklmnopqrstuvxyzabcdefghiljklmnopqrstuvxyz'
    #         hook.account = 'youraccount'
    #         hook.project = 'yourprojectname'
    #       end
    #       h.call(opts)
    #     end
    # @yield the hook, configurable exactly as the Lighthouse gem is configured.
    #   Also, you must specify #project= to set the project to send changesets to.
    # @yieldparam hook the new hook object you must configure
    # @return [Proc] a proc that takes a hook's options, and when called, will
    #   submit the new changeset(s)
    def self.make(&block)
      new(&block).block
    end
    
    ##
    # Takes a block to configure a hook that can submit changesets to a
    # Lighthouse project. The arguments are a list of symbols, which are
    # the events that are automatically hooked into. This provides
    # a terser, though slightly less explicit and less flexible syntax than
    # that used with LighthouseHook.make().
    #
    # You must provide either a username/password, or an API token to
    # the hook when configuring it. Otherwise, submitting changesets will fail.
    #
    # @example Creating a commit hook
    #     Amp::LighthouseHook.add_hooks(:commit) do |hook|
    #       hook.token   = 'abcdefghiljklmnopqrstuvxyzabcdefghiljklmnopqrstuvxyz'
    #       hook.account = 'youraccount'
    #       hook.project = 'yourprojectname'
    #     end
    # @param [Array<Symbol>] events each argument is an event that is hooked into,
    #   such as :commit, :incoming, etc. Currently, only :commit is supported.
    # @yield the hook, configurable exactly as the Lighthouse gem is configured.
    #   Also, you must specify #project= to set the project to send changesets to.
    # @yieldparam hook the new hook object you must configure
    def self.add_hook(*events, &block)
      h = self.make(&block)
      
      events.each do |evt|
        Amp::Hook.new(evt) do |opts|
          h[opts]
        end
      end
    end
    
    ##
    # @see {add_hook}
    def self.add_hooks(*args, &block)
      add_hook(*args, &block)
    end
    
    attr_reader :project
    
    ##
    # Initializes a new LighthouseHook. Delegates all unknown methods to the Lighthouse
    # singleton class, yields itself to the (required!) block, and loads the requested
    # project.
    def initialize
      super(Lighthouse)
      yield self
      load_project
    end
    
    ##
    # Specifies the name of the project to which we will send changesets.
    #
    # @param [String, #to_s] val the name of the project to commit to
    def project=(val)
      @project_name = val.to_s
    end
    
    ##
    # Creates a proc that - when executed, with a hook's options - will send
    # a changeset to Lighthouse.
    #
    # @return [Proc] a proc that will send a changeset to lighthouse
    def block
      proc do |opts|
        cs = Lighthouse::Changeset.new(:project_id => @project.id)
        
        ##
        # Each file must be sent as an array: ["A", file] for an added file,
        # ["M", file] for a modified file, ["D", file] for a removed file.
        # Thus, all changes are an array of these arrays, pairing each changed
        # file with a letter.
        temp_arr = []
        opts[:added].each    {|file| temp_arr << ["A", file]} if opts[:added].any?
        opts[:modified].each {|file| temp_arr << ["M", file]} if opts[:modified].any?
        opts[:removed].each  {|file| temp_arr << ["D", file]} if opts[:removed].any?
        cs.changes    = temp_arr.to_yaml
        
        cs.user       = opts[:user]
        cs.updated_at = opts[:date]
        cs.body       = opts[:text]
        cs.revision   = opts[:revision]
        cs.title      = "#{opts[:user]} committed revision #{opts[:revision]}"
        
        result = cs.save
        
        unless result
          Amp::UI::err cs.errors.errors.inspect
        end
      end
    end
    
    private
    
    ##
    # Loads the project from the user's list of projects, based on its name.
    def load_project
      @project = Lighthouse::Project.find(:all).select {|p| p.name.downcase == @project_name.downcase}.first
    end
  end
end

# hook :commit do |opts|
#   Amp::LighthouseHook.make do |hook|
#     hook.token   = 'e4d6af1951c240e00c216bad3c52cf269cba4a7c'
#     hook.account = 'carbonica'
#     hook.project = 'amp'
#   end
# end

# Amp::LighthouseHook.add_hooks(:commit) do |hook|
#   hook.token   = 'e4d6af1951c240e00c216bad3c52cf269cba4a7c'
#   hook.account = 'carbonica'
#   hook.project = 'amp'
# end
