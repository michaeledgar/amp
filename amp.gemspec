# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
#require "ruby_speech/version"

Gem::Specification.new do # |s|
  name        = "amp"
  developer "Michael Edgar", "adgar@carboni.ca"
  developer "Ari Brown", "seydar@carboni.ca"
  self.url = "http://amp.carboni.ca/"
  self.spec_extras = {:extensions => ["ext/amp/mercurial_patch/extconf.rb",
                                 "ext/amp/priority_queue/extconf.rb",
                                 "ext/amp/support/extconf.rb",
                                 "ext/amp/bz2/extconf.rb"]}
  self.need_rdoc = false
  self.summary = "Version Control in Ruby. Mercurial Compatible. Big Ideas."
  extra_dev_deps << ["rtfm", ">= 0.5.1"] << ["yard", ">= 0.4.0"] << ["minitest", ">= 1.5.0"]
end

# #  s.version     = RubySpeech::VERSION
#   s.authors     = ["Ben Langfeld"]
#   s.email       = ["ben@langfeld.me"]
#   s.homepage    = "https://github.com/benlangfeld/ruby_speech"
#   s.summary     = %q{A ruby library for TTS & ASR document preparation}
#   s.description = %q{Prepare SSML and GRXML documents with ease}

#   s.rubyforge_project = "ruby_speech"

#   s.files         = `git ls-files`.split("\n")
#   s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
#   s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
#   s.require_paths = ["lib"]

#   s.add_runtime_dependency %q<niceogiri>, [">= 0.1.0"]
#   s.add_runtime_dependency %q<activesupport>, [">= 3.0.7"]

#   s.add_development_dependency %q<bundler>, ["~> 1.0.0"]
#   s.add_development_dependency %q<rspec>, [">= 2.7.0"]
#   s.add_development_dependency %q<ci_reporter>, [">= 1.6.3"]
#   s.add_development_dependency %q<yard>, ["~> 0.7.0"]
#   s.add_development_dependency %q<rake>, [">= 0"]
#   s.add_development_dependency %q<mocha>, [">= 0"]
#   s.add_development_dependency %q<i18n>, [">= 0"]
# end