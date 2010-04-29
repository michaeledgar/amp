# _Amp_ Commands

Amp's commands are the driving force behind what makes _amp_ unique. Most VCS users are programmers, and yet programming existing VCS systems isn't a simple, well-documented task. In _git_ you might write a shell script, yet with _hg_ you'll find yourself writing a python module and adding it through arcane INI file wizardry. With _amp_ you just add Ruby code directly to your _ampfile_, which is _not_ a hidden file in some strange directory.

All of _amp_'s commands have access to a first-class options parser and command line arguments. You don't have to parse options yourself, of course - you just declare them. Now, we've got some really simple commands littered throughout the site to illustrate how simple commands are. But if you're at this page, you probably want a little bit more. So here's the `amp log` command in _amp_ - unmodified:
  
      command :log do |c|
        c.workflow :hg
        c.desc "Prints the commit history."
        c.opt :verbose,  "Verbose output", {:short => "-v"}
        c.opt :limit,    "Limit how many revisions to show", 
                         {:short => "-l", :type => :integer, :default => -1}
        c.opt :template, "Which template to use while printing", 
                         {:short => "-t", :type => :string, :default => "default"}
        c.opt :no_output, "Doesn't print output (useful for benchmarking)"
        c.on_run do |options, args|
          repo = options[:repository]
          limit = options[:limit]
          limit = repo.size if limit == -1

          start = repo.size - 1
          stop  = start - limit + 1

          options.merge! :template_type => :log
          start.downto stop do |x|
            puts repo[x].to_templated_s(options) unless options[:no_output]
          end
        end
      end

There's a lot going on here. Let's break it down:

    command :log do |c|

This line creates a command called `:log`, and passes it to the block as **c**. **If the command `:log` exists already, then the existing command is passed to the block as _c_**. The inside of the block is where we declare our command. This is where things get interesting!

    c.workflow :hg

The `workflow` method specifies which `workflow` the command belongs to. We use it here to specify that the `:log` command we're defining belongs to the `:hg` workflow, and shouldn't appear if the user is using the git workflow (or any other). If you specify `:all` as the workflow (or don't specify one), the command will be available to all workflows.

    c.desc "Prints the commit history."

The `desc` method declares a small description of the command, which shows up when the user runs `amp help` to get a list of all available commands. It should fit on one line and be succinct. You may also use `desc=` if you prefer that style.

    c.opt :verbose,  "Verbose output", {:short => "-v"}
    c.opt :limit,    "Limit how many revisions to show",
                     {:short => "-l", :type => :integer, :default => -1}
    c.opt :template, "Which template to use while printing",
                     {:short => "-t", :type => :string, :default => "default"}

Now that's what we're talking about! We're declaring some options here, and can see a small portion of _amp_'s option parser at work. Take a look at the `:verbose` line. 

By declaring `c.opt :verbose`, we create a `--verbose` option for our `amp log` command. The first argument is the name of the option - it can be a string, or a symbol. The second argument is a short description - these first two arguments are required. After that come the nifty options! (Note - _amp_ uses trollop under-the-hood, so its options are identical to trollop's.) 

* short - By setting `:short` to "-v", we can now use `amp log -v` as well as `amp log --verbose`
* type - The type of the option. This defaults to `:flag`, which is a normal on-or-off switch, like `--verbose`. You'll notice the `:limit` option has `:type` => `:integer`. This makes the `:limit` option require an argument, and forces it into an integer during parsing. Easy, eh?
* default - The default value of the option. If the user doesn't specify the option, it will normally be parsed as `nil` - you can set a default value here.

For more ways to configure your options, see the documentation for the `opt` method in the Command class..

    c.on_run do |options, args|
      repo = options[:repository]
      limit = options[:limit]
      limit = repo.size if limit == -1
  
      start = repo.size - 1
      stop  = start - limit + 1
  
      options.merge! :template_type => :log
      start.downto stop do |x|
        puts repo[x].to_templated_s(options) unless options[:no_output]
      end
    end

Last, but not least, we have the `on_run` method. This is how we declare what _happens_ when our command is run - which is what we really care about! You specify what the command does in `on_run`'s block, which takes two arguments: `options` and `args`. These are, respectively, the command-line options passed in plus amp's additions, and the arguments provided by the user. For example: `amp log --verbose --limit=3 arg1 arg2` would provide `{:verbose => true, :limit => 3, :repository => repo}` as `options` and `["arg1", "arg2"]` as `args`.

Our command is getting changeset information, so it needs a repository to interact with. Unless told to do otherwise, _amp_ will look for a repository and store it in `options[:repository]`. This will always be an object of the class LocalRepository.

Once we extract our repository, we decide which changesets to print based on the options. To get a given changeset, we simply use `repo[x]`, where `x` can be a revision number, a partial node ID, "tip", and so on. See the documentation for `LocalRepository#[]` for more details.

This is just a quick once-over of some of the more obvious features of _Amp's_ command system - there are far more features to discuss. Until those pages are written, take a look at the Documentation for the Command class.