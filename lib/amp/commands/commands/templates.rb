# Create an anonymous module so that the extra methods in the templates aren't
# entered into the global namespace
# 
# This bears explanation:
# The `command` method operates regardless of location and communicates back to
# command HQ (command.rb). We use some helper methods here, which are defined at
# the bottom, and we want them to be hidden for everyone else. To do this, we wrap
# the entire `command` method call in an anonymous module so that `command`, which
# will operate anywhere, will work, but all extraneous data (the helper methods)
# is lost in memory.
Module.new do
  command :templates do |c|
    c.workflow :all
    c.add_opt :list, "Lists all templates", :short => "-l"
    c.desc "Starts an interactive template editor"
    c.maybe_repo
    c.on_run do |opts, args|
      
      
      
      repo = opts[:repository]
      
      if opts[:list]
        print_templates(repo)
        next
      end
      begin
        Amp::UI.say "Welcome to the Amp template editor."
        
        scope = 0
        Amp::UI.choose do |menu|
          menu.prompt = "Which kind of template do you want to modify?"
          menu.choice("Global Templates") { scope = TEMPLATE_GLOBAL_SCOPE }
          menu.choice("Local Templates (this Repo Only)") { scope = TEMPLATE_LOCAL_SCOPE }
          menu.choice("Quit") { exit(0) }
          menu.index = :number
        end
        
        if scope == TEMPLATE_LOCAL_SCOPE && !repo
          puts "No local repository found! Sorry."
          next
        end
        
        template_directory = File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "templates"))
        Amp::UI.say "\n"
        mode = 0
        Amp::UI.choose do |menu|
          menu.prompt = "Do you want to edit, add, or remove a template?"
          menu.choice("Edit") { mode = TEMPLATE_EDIT_MODE }
          menu.choice("Add") { mode = TEMPLATE_ADD_MODE }
          menu.choice("Remove") { mode = TEMPLATE_DELETE_MODE }
          menu.choice("Start Over") { }
          menu.index = :number
        end
        Amp::UI.say "\n"
        case mode
        when TEMPLATE_EDIT_MODE
          filename = nil
          Amp::UI.choose do |menu|
            menu.prompt = "Which template would you like to edit?"
            templates_for_scope(scope, repo).each do |template|
              menu.choice(template.name) { filename = template.file }
            end
            menu.choice("Start Over") { } #do nothing
            menu.index = :number
          end
          Amp::UI.edit_file(filename) if filename
        when TEMPLATE_ADD_MODE
          filename = Amp::UI.ask("What would you like to name your template? ", String)
          type = Amp::UI.ask("What kind of template? (log, commit) ", String) {|q| q.in = ["log","commit"]}
          old_file = Amp::Support::Template["blank-#{type}"].file
          new_file = File.join(template_directory, filename + ".erb")
          File.copy(old_file, new_file)
          Amp::UI.edit_file new_file
          Amp::Support::FileTemplate.new(filename, new_file)
        when TEMPLATE_DELETE_MODE
          filename = nil
          Amp::UI.choose do |menu|
            menu.prompt = "Which template would you like to delete?"
            templates_for_scope(scope, repo).each do |template|
              menu.choice(template.name) do 
                Amp::Support::Template.unregister template.name
                filename = template.file
              end
            end
            menu.choice("Start Over") {  }  #do nothing
            menu.index = :number
          end
          if filename # didn't start over
            shortname = filename.split("/").last.gsub(/\.erb/,"")
            sure = Amp::UI.agree "Are you sure you want to delete the template \"#{shortname}\"? (y/n/yes/no) "
            if sure
              File.safe_unlink(filename)
            end
          end
        end
        Amp::UI.say "\n"
      end while true
      
    end
    
    
  end
  TEMPLATE_GLOBAL_SCOPE = 1
  TEMPLATE_LOCAL_SCOPE  = 2

  TEMPLATE_EDIT_MODE = 1
  TEMPLATE_ADD_MODE = 2
  TEMPLATE_DELETE_MODE = 3
  # This is how we scope methods such that the command has access to them, but nobody else, without
  # defining nested methods.
  class << self
    
    def templates_for_scope(scope, repo)
      case scope
      when TEMPLATE_GLOBAL_SCOPE
        Amp::Support::Template.all_templates.values
      when TEMPLATE_LOCAL_SCOPE
        path = repo.join("templates")
        FileUtils.makedirs path unless File.exists? path
        Dir.entries(path).reject {|e| e =~ /^\./}.map {|f| File.join(dir, f)}
      end
    end
    
    def print_templates(repo)
      Amp::UI.say "Global Templates"
      Amp::UI.say "================"
      templates_for_scope(TEMPLATE_GLOBAL_SCOPE, repo).each {|template| Amp::UI.say template.name}
      if repo
        Amp::UI.say "\nLocal Templates"
        Amp::UI.say "================"
        # templates_for_scope(TEMPLATE_LOCAL_SCOPE, repo).each {|f| Amp::UI.say f.split("/").last.gsub(/\.erb/,"")}
      end
      Amp::UI.say "\n"
    end
  end
end
