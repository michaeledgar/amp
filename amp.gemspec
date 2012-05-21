# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

#require "amp"

Gem::Specification.new do |s|
  s.name        = "amp"
  s.authors     = ["Michael Edgar", "Ari Brown"]
  s.email       = ["adgar@carboni.ca", "seydar@carboni.ca"]
  s.version     = '0.5.3' #Amp::VERSION
  s.homepage = "http://amp.carboni.ca/"
  s.summary = "Version Control in Ruby. Mercurial Compatible. Big Ideas."
  s.rubyforge_project = 'amp'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency %q<bundler>, ["~> 1.0.0"]
  s.add_development_dependency %q<rtfm>, ["~> 0.5.1"]
  s.add_development_dependency %q<yard>, [">= 0.4.0"]
  s.add_development_dependency %q<minitest>, [">= 1.5.0"]

  # self.spec_extras = {:extensions => ["ext/amp/mercurial_patch/extconf.rb",
  #                                "ext/amp/priority_queue/extconf.rb",
  #                                "ext/amp/support/extconf.rb",
  #                                "ext/amp/bz2/extconf.rb"]}
  # self.need_rdoc = false

end
