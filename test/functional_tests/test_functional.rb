##################################################################
#                  Licensing Information                         #
#                                                                #
#  The following code is licensed, as standalone code, under     #
#  the Ruby License, unless otherwise directed within the code.  #
#                                                                #
#  For information on the license of this code when distributed  #
#  with and used in conjunction with the other modules in the    #
#  Amp project, please see the root-level LICENSE file.          #
#                                                                #
#  © Michael J. Edgar and Ari Brown, 2009-2010                   #
#                                                                #
##################################################################

require 'stringio'
require File.join(File.expand_path(File.dirname(__FILE__)), '../testutilities')
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp"))
include Amp::KernelMethods
# easyness
class String
  def fun_local; File.join($current_basedir, self); end
end

class TestFunctional < AmpTestCase
  
  AMP_FILE   = (RUBY_VERSION < "1.9") ? "amp" : "amp1.9"
  AMP_BINARY = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'bin', AMP_FILE))
  
  def setup
    $current_dir = Dir.pwd
    $current_basedir = File.expand_path(File.dirname(__FILE__))
    FileUtils.safe_unlink(File.join($current_basedir, "test.log"))
    clean_dir "testrepo" #just in case
    clean_dir "newrepo"
    clean_dir "conflictrepo"
  end
  
  ##
  # This is the big functional test. Since we will be building this repo up
  # from scratch, every single test must pass in order - we can't hope a certain
  # order is followed. So it all goes in one method. Sorry.
  def test_init
    
    require       "amp/commands/command.rb"
    require_dir { "amp/commands/*.rb"              }
    require_dir { "amp/commands/commands/*.rb"     }
    
    ENV["HGUSER"] = "tester"
    
    assert_command_match(/#{Amp::VERSION_TITLE}/, "version")
    assert_command_match(/#{Amp::VERSION}/, "version")
    
    
    # Create the mainline repository! Woo!
    amp "init", "testrepo".fun_local
    
    File.safe_unlink "testrepo/ampfile.rb".fun_local
    # Make sure we've correctly initialized the repository
    assert_file 'testrepo'
    assert_file 'testrepo/.hg'
    assert_file 'testrepo/.hg/requires'
    assert_file 'testrepo/.hg/store'
    
    # Enter the repository. Time to take care of business
    enter_repo "testrepo"
    
    # Adds the first file, make sure it was successfully added to the dirstate
    add_file_ensure_added "STYLE.txt"
    
    # Commit the first file!
    commit :message => "First commit."
    
    # Make sure the first file made it into the manifest
    assert_files_in_manifest "STYLE.txt"
    
    # Run basic tests on the `head`, `log`, and `tip` commands
    confirm_head_is_first_commit
    confirm_head_equals_log_limit_one
    confirm_head_equals_tip
    
    # Get ready for revision 2: add a bunch of files!
    # Make sure they were successfully added, too.
    add_file_ensure_added "command.rb"
    add_file_ensure_added "commands/annotate.rb"
    add_file_ensure_added "commands/heads.rb"
    add_file_ensure_added "commands/manifest.rb"
    add_file_ensure_added "commands/status.rb"
    
    # Copy a file into the repo, but don't add it. This is so we can check
    # if `status` picks up unknown files.
    copy_resource          "commands/experimental/lolcats.rb", "commands/experimental/lolcats.rb"
    
    # Make sure the file got copied
    assert_file            "testrepo/commands/experimental/lolcats.rb"
    
    # Make sure status sees it and recognizes it as an unknown file.
    assert_file_has_status "commands/experimental/lolcats.rb", :unknown
    
    # Commit the second round of files
    commit :message => "Second commit, added commands\nInteresting stuff."
    
    # Make sure the second set of files are all in the manifest now
    assert_files_in_manifest "command.rb", "commands/annotate.rb", "commands/heads.rb",
                             "commands/manifest.rb", "commands/status.rb", "STYLE.txt"
    
    # Add our .hgignore file so we can test for ignored status
    add_file_ensure_added  ".hgignore"
    
    # Make sure it picks up on lolcats.rb being an ignored file
    assert_file_has_status "commands/experimental/lolcats.rb", :ignored
    
    # Make sure we can see which files are clean
    assert_file_has_status "STYLE.txt", :clean
    
    ## Let's move the repo to version 2. woot! This copies the version2
    ## resources into the working directory
    replace_resources_with_version "version2"
    
    # Version 2 modifies STYLE.txt and commands/annotate.rb.
    # So let's run some status checks, making sure that those 2 files are marked
    # as modified, .hgignore is still marked as added (we added it above), and
    # an unmodified file is still marked as clean.
    assert_file_has_status "STYLE.txt", :modified
    assert_file_has_status "commands/annotate.rb", :modified
    assert_file_has_status ".hgignore", :added #it's modified, but still should be added
    assert_file_has_status "commands/manifest.rb", :clean
    
    # Commit version 2, and specify a custom user. 
    commit :message => "Changed a couple files!", :user => "medgar"
    
    # Make sure .hgignore got successfully added to the repo
    assert_file_in_manifest ".hgignore"
    
    # Make sure our custom user worked
    assert_command_match(/user\: +medgar/, "log", nil, :limit => 1)
    # Make sure the repo's still spiffy
    assert_verify
    
    # We're done with testrepo. Time to try some more advanced stuff. Exit testrepo.
    exit_repo
    
    # Clone testrepo to create "newrepo".
    amp "clone", ["testrepo".fun_local,"newrepo".fun_local]
    # Enter the newrepo repository.
    enter_repo "newrepo"
    
    # Update this child repo to version 3
    replace_resources_with_version "version3"
    # Make sure command.rb was successfully modified
    assert_file_has_status "command.rb", :modified
    # Commit the modification
    commit :message => "demonic infestation in command.rb", :user => "seydar"
    
    # Add the curently ignored file
    add_file_ensure_added "commands/experimental/lolcats.rb"
    # And make sure it shows up as added, even though it falls under ignore rules
    assert_file_has_status "commands/experimental/lolcats.rb", :added
    # Commit our lolcats command
    commit :message => "experimental branch with the lolcats command", :user => "seydar"
    # Make sure that the custom user is still peachy
    assert_command_match(/user\: +seydar/, "log", nil, :limit => 1)
    
    assert_command_match(/demonic infestation/, amp("outgoing"))
    assert_command_match(/experimental branch/, amp("outgoing"))
    
    # Push upstream to testrepo
    amp "push"
    # Switch to testrepo
    exit_repo
    enter_repo "testrepo"
    
    # Make sure we didn't corrupt the upstream repo with our push
    assert_verify
    # Update to the newly pushed changesets
    assert_command_match(/3 files updated/, "update")
    # Verify that the head changeset is the correct one (about the lolcats branch)
    assert_command_match(/experimental branch/, "head")
    
    # Remove a file from the repo (using `amp remove`)
    remove_file "commands/annotate.rb"
    # And make sure it's marked as removed in the status
    assert_file_is_removed "commands/annotate.rb"
    # Update to version 4
    replace_resources_with_version "version4"
    # Add a file from version4 that we didn't have before, and make sure it gets
    # added to the dirstate
    add_file_ensure_added "version4/commands/stats.rb", "commands/stats.rb"
    # Commit the file removal and the new addition
    commit :message => "removed stupid annotate command. added stats!", :date => "1/1/2009"
    
    # Make sure stats is marked as clean
    assert_file_has_status "commands/stats.rb", :clean
    
    # We have to do some juggling here because Ruby 1.9 will produce a different string for
    # the date. So just hand-parse the input string and see if the result is in the changelog.
    require 'time'
    t = Time.parse("1/1/2009")
    assert_command_match(/#{t.to_s}/, "log", ["-l", "1"])
    
    # Over-zealous verification never hurt anyone
    assert_verify
    
    # Switch to our child repo, so we can pull that new changeset!
    exit_repo
    enter_repo "newrepo"
    
    # Pull! wooooo!
    assert_command_match(/added 1 changesets/, "pull")
    # Update it
    update_result = amp "update"
    # And check to see if the 2 things we did were both in the update
    assert_match(/1 files updated/, update_result)
    assert_match(/1 files removed/, update_result)
    
    # Make sure that commands/annotate.rb was removed by the update
    assert_false File.exist?(File.expand_path(File.join(Dir.pwd,"commands/annotate.rb")))
    
    # ok, so right now, newrepo is the same as testrepo.
    # now to generate a conflict, so we can test merging. we'll need a second child repo.
    exit_repo
    amp "clone", ["testrepo".fun_local, "conflictrepo".fun_local]
    
    # create one branch in conflictrepo
    enter_repo "conflictrepo"
    replace_resources_with_version "version5_1"
    amp "status"
    commit :message => "conflict, part 1"
    exit_repo
    
    # and create a conflicting branch in newrepo
    enter_repo "newrepo"
    remove_file_without_amp "commands/heads.rb"
    replace_resources_with_version "version5_2"
    
    # test addremove, while we're at it!
    addremove_result = amp "addremove"
    assert_match(/Adding commands\/newz.rb/, addremove_result)
    assert_match(/Removing commands\/heads.rb/, addremove_result)
    amp "status"
    commit :message => "conflict, part 2"
    
    # push our conflicting commit to testrepo from the "newrepo" child.
    push_results = amp "push"
    
    assert_match(/1 changeset/, push_results)
    assert_match(/3 changes/, push_results)
    assert_match(/3 files/, push_results)
    
    exit_repo
    
    # Ok, so conflictrepo wants to push its local commits, but they cross
    # the branch that testrepo's at. So we'll need to pull newrepo's commit,
    # merge, and then push.
    enter_repo "conflictrepo"
    # push should fail
    assert_command_match(/new remote heads?/, "push")
    # pull in newrepo's conflicting commit (it will yell at us for the extra head)
    assert_command_match(/\+1 heads?/, "pull")
    # Try to merge the 2 changesets
    result = amp "merge"
    
    # Expected results from the merge
    assert_match(/1 files? unresolved/, result)
    assert_match(/1 files? removed/,    result)
    assert_match(/2 files? updated/,    result)
    
    # Ok, so we have one file that conflicts: STYLE.txt. We want to keep conflictrepo's
    # version of the file. So we'll suck out the local portion of the conflicted summary.
    data = File.read("STYLE.txt")
    vers1_groups = data.scan(/<<<<<<<.*?\n(.*?)=======/).first
    File.open("STYLE.txt","w") {|f| f.write vers1_groups.first}
    
    # mark STYLE.txt as resolved, and make sure it successfully was marked
    resolve_result = amp("resolve", ["--mark", "STYLE.txt"])
    assert_match(/STYLE.txt marked/, resolve_result)
    assert_match(/resolved/, resolve_result)
    
    # commit the branch merge
    commit :message => "conflict resolved!"
    
    # push to testrepo
    amp "push"
    assert_verify
    # make sure we're still intact in conflictrepo
    
    # let's go back to testrepo, and make sure our push was successful!
    exit_repo
    enter_repo "testrepo"
    
    # did that push sparkle with testrepo?
    assert_verify
    
    # Test the copy command
    amp("copy", ["-v", "STYLE.txt", "STYLE_copied.txt"])
    assert_file_has_status "STYLE_copied.txt", :added
    assert_equal File.read("STYLE.txt"), File.read("STYLE_copied.txt")
    
    # Test the move command
    amp("move", ["command.rb", "command_moved.rb"])
    assert_false File.exist?("command.rb")
    assert       File.exist?("command_moved.rb")
    assert_file_has_status "command.rb", :removed
    assert_file_has_status "command_moved.rb", :added
    
    # Test the "root" command
    assert_command_match(/#{Dir.pwd}/, "root")
    
    # We should be in the "default" branch right now.
    assert_command_match(/default/, "branches")
    assert_command_match(/default/, "branch")
    # Let's change branches.
    assert_command_match(/branch newbranch/, "branch", ["newbranch"])
    assert_command_match(/newbranch/, "branch")
    
    # Only 1 tag, which is the tip
    result = amp("tags").split("\n")
    result = result.select {|entry| entry =~ /[0-9a-f]{10}/}
    assert_equal 1, result.size
    assert_match(/tip/, result.first)
    
    # Tag revision 3 as "noobsauce", by "medgar", with commit message "silly commit!"
    amp("tag", ["noobsauce"], {:rev => 3, :user => "medgar", :message => "silly commit!"})
    
    # Let's make sure our tag went in smoothly.
    result = amp("tags").split("\n")
    
    result = result.select {|entry| entry =~ /[0-9a-f]{10}/}
    assert_equal 2, result.size
    
    # Can't guarantee order, ruby 1.9 switches them, should investigate.
    noobed = result.first =~ /noobsauce/ ? 0 : 1
    tip = 1 - noobed
    
    # First listed tag should be noobsauce:3
    assert_match(/noobsauce/, result[noobed])
    assert_match(/3/, result[noobed])
    # second listed tag should be tip:9
    assert_match(/tip/, result[tip])
    assert_match(/9/, result[tip])
    
    # And we should make sure the options were passed into the commit correctly.
    head_result = amp("head")
    assert_match(/medgar/, head_result)
    assert_match(/silly commit!/, head_result)
    
    # Commit that baby and make sure we're still rockin'.
    commit :message => "moves and copies"
    assert_verify
    
    assert_command_match(/newbranch/, "identify", [], {:branch => true})
    
    exit_repo
    enter_repo 'testrepo'
    
    assert_equal get_resource("command.rb", "version3"), amp("view", ["command.rb"], :rev => 3)
    
    annotate_output = amp("annotate", ["STYLE.txt"], :user => true, :number => true).strip
    correct_annotation = read_supporting_file("annotate.out").strip
    assert_equal correct_annotation, annotate_output
    
    # Create a dummy commit
    File.open('used_in_bundle', 'w') {|f| f.write "monkay" }
    amp "add", ["used_in_bundle"]
    amp "commit", [], :message => 'monkey'
    assert_verify
    
    # test that the commands work if we go into a subdir
    Dir.chdir("commands")
    assert_command_runs "status"
    Dir.chdir("..")
    
    assert_command_match(/monkey/, "info", "11")
    assert_command_match(/conflict resolved/, "info", ["11", "8"])
    
    assert_command_match(/10/, "identify", [], :rev => "10", :num => true)
    
    # Run identify on the current node should mention that the tag is "tip"
    assert_command_match(/tip/, "identify")
    
    diff_out = amp("diff", ["command.rb", "--rev", "2", "--rev", "3"])
    assert_match(/\+\s+def silly_namespace\(name\)/, diff_out)
    assert_match(/\-\s+def volt_namespace\(name\)/, diff_out)
    
    # needs two args
    assert_command_fails "move", ["STYLE.txt"]
    # last argument must be directory if moving multiple files
    assert_command_fails "move", ["STYLE.txt", "command.rb", "STYLE.txt"]
    assert_command_fails "c"
    # # Create and compare bundles of ALL revisions
    # assert_amp_hg_bundle_same 'bundle_all.bundle', :all => true
    # 
    # # Now go only up to the 3rd revision.
    # assert_amp_hg_bundle_same 'bundle_up_to_3.bundle', :rev => 3, :all => true
    # 
    # # We shall now test types 'none', 'bzip2', and 'gzip'
    # ['none', 'bzip2', 'gzip'].each do |type|
    #   assert_amp_hg_bundle_same "bundle_up_to_7_with_type_#{type}.bundle",
    #                             :rev => 7, :type => type, :all => true
    # end
    # 
    # # Test making bundles with --base
    # assert_amp_hg_bundle_same 'bundle_up_to_3.bundle', :rev => 3, :base => 2
    # assert_amp_hg_bundle_same 'bundle_up_to_3.bundle', :base => 3
  ensure
    # cleanup
    exit_repo
    clean_dir "testrepo"
    clean_dir "newrepo"
    clean_dir "conflictrepo"
  end
  
  private ##################################
  
  def assert_command_runs(command, args=[], opts = {})
    assert run_amp_command_with_code(command, args, opts)[1]
  end
  
  def assert_command_fails(command, args = [], opts = {})
    assert_false run_amp_command_with_code(command, args, opts)[1]
  end
    
  
  def assert_amp_hg_bundle_same(fname, opts={})
    amp "bundle", ["amp_#{fname}"], opts
    hg  "bundle", ["hg_#{fname}"],  opts
    assert_files_are_same "amp_#{fname}", "hg_#{fname}"
    ["amp_#{fname}", "hg_#{fname}"].each {|f| File.delete f }
  end
  
  ##
  # Asserts that the repo is in perfect working order. This requires the
  # hg binary, since we trust them above all when it comes to verifying our
  # stuff. Fails if there are any integrity errors in our files.
  def assert_verify
    assert_command_no_match(/integrity errors/, "verify")
  end
  
  ##
  # 
  def confirm_head_is_first_commit
    heads_result = amp("heads")
    assert_match(/changeset\: +0\:/, heads_result)
    assert_match(/First commit\./, heads_result)
  end
  
  ##
  # Asserts that a) heads returns the most recent revision, b) log -l 1 returns only
  # one revision.
  def confirm_head_equals_log_limit_one
    assert_equal amp("heads").strip, amp("log", ["-l","1"]).strip
  end
  
  ##
  # Asserts that a) heads returns the most recent revision, b) tip returns the correct
  # revision.
  def confirm_head_equals_tip
    assert_equal amp("heads").strip, amp("tip").strip
  end
  
  ##########################################
  ##      MAJOR HELPER METHODS
  ###########################################
  
  def add_file_ensure_added(source, dest=source)
    copy_resource(source, dest)
    assert_file "#{@current_repo}/#{dest}"
    amp "add", dest
    
    assert_file_is_added dest
  end
  
  def remove_file(source)
    amp "remove", source
  end
  
  def assert_files_in_manifest(*files)
    manifest_result = amp("manifest")
    [*files].each do |file|
      assert_match(/#{file}/, manifest_result)
    end
  end
  alias_method :assert_file_in_manifest, :assert_files_in_manifest
  
  def assert_file_is_added(file)
    assert_file_has_status(file, :added)
  end
  
  def assert_file_is_removed(file)
    assert_file_has_status(file, :removed)
  end
  
  def assert_files_are_same(file1, file2)
    flunk "Tried to compare #{file1} but it doesn't exist" unless File.exist? file1
    flunk "Tried to compare #{file2} but it doesn't exist" unless File.exist? file2
      
    output1 = `md5 #{file1}`.strip.match(/MD5 (?:.+) = (.*)/)
    output2 = `md5 #{file2}`.strip.match(/MD5 (?:.+) = (.*)/)
    assert_equal output1[1], output2[1]
  end
  
  def assert_command_match(regex, command, args=[], opts={})
    result = amp command, args, opts
    assert_match regex, result
  end
  
  def assert_command_no_match(regex, command, args=[], opts={})
    result = amp command, args, opts
    refute_match regex, result
  end
  
  def assert_hg_command_match(regex, command, args=[], opts={})
    result = hg command, args, opts
    assert_match regex, result
  end
  
  def assert_hg_command_no_match(regex, command, args=[], opts={})
    result = hg command, args, opts
    refute_match regex, result
  end
  
  def assert_file_has_status(file, status)
    stat_letter = case status
                  when :added
                    "A"
                  when :removed
                    "R"
                  when :unknown
                    "\\?"
                  when :ignored
                    "I"
                  when :clean
                    "C"
                  when :modified
                    "M"
                  end
    result = amp("status", nil, status.to_sym => true, :hg => true, :"no-color" => true)
    
    assert_match(/#{stat_letter} #{file}/, result)
  end
  
  def commit(options = {})
    amp "commit", [], options
  end
  
  ###########################################
  #      OTHER HELPER METHODS
  ##########################################
  
  def read_supporting_file(filename)
    File.read(File.join($current_basedir, filename))
  end
  
  def get_resource(file_name, version="")
    File.read(File.join($current_basedir, "resources", version, file_name)) 
  end
  
  def replace_resources_with_version(version_string)
    resource_folder = File.join($current_basedir, "resources", version_string)
    list = Dir["#{resource_folder}/**/.*","#{resource_folder}/**/*"]
    list.reject! do |a| 
      b = File.basename(a)
      b == "." || b == ".."
    end
    list.each do |file|
      unless File.directory?(file)
        new_dest = File.join($current_basedir, @current_repo, file[(resource_folder.size+1)..-1])
        File.copy(file, new_dest)
      end
    end
  end
  
  def options_hash_to_string(options = {})
    options_hash_to_array(options).join(" ")
  end
  
  def options_hash_to_array(options = {})
    opt_arr = []
    options.each do |k, v|
      case v
      when Integer
        opt_arr << "--#{k}=#{v}"
      when TrueClass
        opt_arr << "--#{k}"
      else
        opt_arr << "--#{k}" << v
      end
    end
    opt_arr
  end
  
  ##
  # Enters the given repository's working directory. Changes the program's working directory
  # to the repo, so relative paths can be used
  #
  # @param [String] which_repo the name of the repository to enter. Must be a directory in the
  #   test/functional_tests directory.
  def enter_repo(which_repo)
    @current_repo = which_repo
    Dir.chdir File.join($current_basedir, which_repo)
  end
  
  ##
  # Exits the current repository (changes the program's current working directory)
  def exit_repo
    Dir.chdir $current_dir
  end
  
  ##
  # Executes the given command using the amp binary. Backbone of the functional tests.
  #
  # @example
  #   amp(:commit, "STYLE.txt", :user => "seydar", :date => "1/1/2001")
  #   will run
  #   `amp commit --user="seydar" --date="1/1/2001" STYLE.txt`
  #
  # @param [String] command the command to execute
  # @param [Array<String>] args the arguments to supply to the command.
  # @param [Hash<#to_s => #to_s>] opts the options to pass to the command, such as :user => "seydar"
  #   for a commit command.
  def run_amp_command_with_code(command, args = [], opts = {})
    out = $stdout
    argv = ARGV.dup
    ARGV.clear.concat([command])
    ARGV.concat([*args]) if args
    ARGV.concat(options_hash_to_array(opts)) if opts
    s = StringIO.new
    $display = true
    $stdout = s
    result = ""
    success = false
    begin
      success = Amp::Dispatch.run
    rescue StandardError => err
      $stdout = out
      message = ["***** Left engine failure *****",
                 "***** Ejection system error *****",
                 "***** Vaccuum in booster engine *****"
                ][rand(3)]
      Amp::UI.say message
      Amp::UI.say err.to_s
      err.backtrace.each {|e| Amp::UI.say "\tfrom #{e}" }
      raise
    ensure
      ARGV.clear.concat(argv)
      $stdout = out
      result = s.string
    end
    
    [result, success]
  end
  
  def run_amp_command(command, args = [], opts = {})
    result, success = *run_amp_command_with_code(command, args, opts)
    
    result
  end
  alias_method :amp, :run_amp_command
  
  ##
  # Executes the given command using the hg binary (mercurial's binary). Used for when
  # we don't trust amp's output (i.e. for "verify" - that'd be like grading your own math exam).
  #
  # @see run_amp_command
  def run_hg_command(command, args = [], opts = {})
    args = [args] unless args.kind_of?(Array)
    %x(hg #{command} #{options_hash_to_string(opts)} #{args.join(" ")})
  end
  alias_method :hg, :run_hg_command
  
  ##
  # Copies a file, relative to "functional_tests/resources", to the destination, relative to
  # the current repository's root. Creates any directories necessary to copy into the
  # destination.
  #
  # @param [String] resource the path, relative to the resources root, of the file we wish
  #   to copy into the working directory
  # @param [String] destination the destination, relative to the working repo's root, where
  #   we wish to move the file
  def copy_resource(resource, destination)
    # make sure the parent directories exist
    FileUtils.makedirs File.dirname(File.join($current_basedir, @current_repo, destination))
    File.copy(File.join($current_basedir, "resources", resource), 
              File.join($current_basedir, @current_repo, destination))
  end
  
  ##
  # Removes a file, without using amp to mark it as removed from the working directory.
  # This method allows us to use relative path names without keeping track of which
  # repo we're in, as well.
  #
  # @param [String] file a path to a file (relative to the repo's root) we wish to delete.
  def remove_file_without_amp(file)
    File.unlink File.join($current_basedir, @current_repo, file)
  end
  
  ##
  # Asserts that a file exists. Expects a path relative to the functional_tests directory.
  #
  # @param [String] file a path to a file relative to the functional_tests directory.
  def assert_file(file)
    assert File.exist?(file.fun_local)
  rescue => e
    puts "#{file.fun_local.inspect} does not exist!"
    raise e # this kills e's backtrace
  end
  
  ##
  # Destroys a directory. rm -rf, motherfuckers.
  #
  # @param [String] file the directory to completely erase
  def clean_dir(file)
    FileUtils::rm_rf file.fun_local
  end
  
end
