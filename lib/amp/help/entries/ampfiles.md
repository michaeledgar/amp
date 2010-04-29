# What's an Ampfile?

  _Ampfiles_ are how you load your customizations into _amp_. INI files are handy, and we use them maintain compatibility with the #{hg_link} distribution. However, you can't put code in an INI file. And the files, quite frankly, aren't very pretty. That's why we have ampfiles.

  For those familiar with #{ruby_link}, ampfiles are sort of similar to #{link_to "http://rake.rubyforge.org/", "Rake"}'s Rakefiles. When you run _amp_, amp will look in the current directory for a file called "Ampfile" (or "ampfile", "ampfile.rb", etc.). If it doesn't find one it looks in the folder containing the current one - and up and up until it gives up. If it doesn't find one, that's ok - you don't need an ampfile to use _amp_!

# So how does Amp use Ampfiles?
  The cool thing about ampfiles is that they're just Ruby code. So _amp_ just runs your ampfile as Ruby. "But wait," you say, "what use is running a script every time I use amp?" Well, silly, we give you a bunch of Ruby methods you can use to modify _amp_, and when your ampfile is run, those changes happen!

# ~/.amprc
  A quick note: _amp_ will also run the file located at `~/.amprc` (~ means "your user directory"), right before running any ampfiles. That way, the ampfile in your repository can override any global settings in `.amprc`.

# Example! Now!
  Ok, ok. For starters, you can modify existing commands very simply. In Ruby, you can open a class up, add a method, and close it again. In Amp, you do that like this:


    command "status" do |c|
      c.default :"no-color", true
    end

  If you put that in your Ampfile, the `amp status` command will no longer use color. Why don't we create a new command entirely?


    command "stats" do |c|
      c.workflow :hg
      c.desc "Prints how many commits each user has contributed"
      c.on_run do |opts, args|
        repo = opts[:repository]
        users = Hash.new {|h, k| h[k] = 0}
        repo.each do |changeset|
          users[changeset.user] += 1
        end
        users.to_a.sort {|a,b| b[1] <=> a[1]}.each do |u,c|
          puts "\#{u}: \#{c}"
        end
      end
    end

  You can put that in your ampfile and get commit statistics right away. In fact, it's in _amp_'s ampfile. If you run `amp help`, your new command will be in the list! Why does this work? Well, it's not much of a secret: **You're actually writing the exact same code used to create the built-in amp commands.** If you look at our code, each of the commands you know and love, such as `amp commit`, `amp move` are written using this exact same code style.
# Cool! What now?

  Well, start hacking away! You might find the #{commands_link} section interesting, as well as our "Learn Amp" pages, where you can find the _amp_ API. We'll be setting up a place for useful snippets to be posted soon.