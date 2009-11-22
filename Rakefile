# -*- ruby -*-

require 'rubygems'
require 'rake'
require 'rake/tasklib'
require 'rake/testtask'
require 'yard'
require 'hoe'

Rake::TaskManager.class_eval do
  def remove_task(*task_names)
    task_names.each do |task_name|
      @tasks.delete(task_name.to_s)
    end
  end
end

def remove_task(*task_names)
  task_names.each do |task_name|
    Rake.application.remove_task(task_name)
  end
end
# 
# 
Hoe.spec "amp" do
  developer "Michael Edgar", "adgar@carboni.ca"
  developer "Ari Brown", "seydar@carboni.ca"
  self.url = "http://amp.carboni.ca/"
  self.spec_extras = {:extensions => ["ext/amp/mercurial_patch/extconf.rb",
                                      "ext/amp/priority_queue/extconf.rb",
                                      "ext/amp/support/extconf.rb",
                                      "ext/amp/bz2/extconf.rb"]}
  self.need_rdoc = false
  self.flog_threshold = 50000
end



remove_task 'test_deps', 'publish_docs', 'post_blog', 
            'deps:fetch', 'deps:list', 'deps:email', 'flay', 'clean', 'test'

load 'tasks/yard.rake'
load 'tasks/stats.rake'

desc "Build the C extensions"
task :build do
  curdir = File.expand_path(File.dirname(__FILE__))
  ruby_exe = RUBY_VERSION < "1.9" ? "ruby" : "ruby1.9"
  Dir['ext/amp/*', 'ext/bz2'].each do |target|
    sh "cd #{File.join(curdir, target)}; #{ruby_exe} #{File.join(curdir, target, "extconf.rb")}" # this is necessary because ruby will build the Makefile in '.'
    sh "cd #{File.join(curdir, target)}; make"
  end
end

desc "Clean out the compiled code"
task :clean do
  sh "rm -rf ext/**/*.o"
  sh "rm -rf ext/**/Makefile"
  sh "rm -rf ext/**/*.bundle"
  sh "rm -rf ext/**/*.so"
  sh "rm -rf ext/amp/**/*.o"
  sh "rm -rf ext/amp/**/Makefile"
  sh "rm -rf ext/amp/**/*.bundle"
  sh "rm -rf ext/amp/**/*.so"
end

desc "Clean and buld the C-extensions"
task :rebuild => [:clean, :build]

desc "Prepares for testing"
task :prepare do
  `tar -C test/store_tests/ -xzf test/store_tests/store.tar.gz`
  `tar -C test/localrepo_tests/ -xzf test/localrepo_tests/testrepo.tar.gz`
end

# liberally modified from Hoe's
desc 'Test the amp AWESOMENESS.'
task :test do
  framework = "test/unit"
  test_globs = ['test/**/test_*.rb']
  ruby_flags = ENV['RUBY_FLAGS'] || "-w -I#{%w(lib ext bin test).join(File::PATH_SEPARATOR)}" +
    (ENV['RUBY_DEBUG'] ? " #{ENV['RUBY_DEBUG']}" : '')
  tests = [ framework] +
    test_globs.map { |g| Dir.glob(g) }.flatten
  tests.map! {|f| %(require "#{f}")}
  cmd = "#{ruby_flags} -e '$amp_testing = true; #{tests.join("; ")}' "
  
  ruby cmd
end

# vim: syntax=Ruby
