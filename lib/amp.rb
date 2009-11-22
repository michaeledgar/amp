module Amp; end
# The root directory of this application
Amp::CODE_ROOT = File.expand_path File.dirname(__FILE__)
$: << Amp::CODE_ROOT # now we don't need to do `require "#{curdir}..."

# Timing variable
$start    ||= Time.now
# Should we display anything?
$display  ||= false
# Should we use pure ruby? Default to no.
$USE_RUBY ||= false
# Are we a command-line app? Default to no.
$cl ||= false

require "amp/support/loaders.rb"

#require 'profile'
require 'fileutils'
require 'stringio'

local_start = Time.now


###############
# The Amp Magic
###############
module Amp
  
  autoload :Hook,                      "amp/commands/hooks.rb"
  autoload :Generator,                 "amp/support/generator.rb"
  autoload :Opener,                    "amp/support/openers.rb"
  autoload :Match,                     "amp/support/match.rb"
  autoload :Ignore,                    "amp/support/ignore.rb"
  autoload :AmpConfig,                 "amp/support/amp_config.rb"
  autoload :UI,                        "amp/support/amp_ui.rb"
                                        
  autoload :Journal,                   "amp/repository/journal.rb"
  autoload :VersionedFile,             "amp/repository/versioned_file.rb"
  autoload :VersionedWorkingFile,      "amp/repository/versioned_file.rb"
  
  autoload :Revlog,                    "amp/revlogs/revlog.rb"      
  autoload :Manifest,                  "amp/revlogs/manifest.rb"
  autoload :FileLog,                   "amp/revlogs/file_log.rb"
  autoload :Changeset,                 "amp/revlogs/changeset.rb"
  autoload :WorkingDirectoryChangeset, "amp/revlogs/changeset.rb"
  autoload :ChangeGroup,               "amp/revlogs/changegroup.rb"
  autoload :ChangeLog,                 "amp/revlogs/changelog.rb"
  
  module Bundles
    autoload :BundleChangeLog,         "amp/revlogs/bundle_revlogs.rb"
    autoload :BundleFileLog,           "amp/revlogs/bundle_revlogs.rb"
    autoload :BundleManifest,          "amp/revlogs/bundle_revlogs.rb"
    autoload :BundleRevlog,            "amp/revlogs/bundle_revlogs.rb"
  end                                      
                                           
  module Encoding                          
    autoload :Base85,                  "amp/encoding/base85.rb"
  end                                      
                                           
  module Diffs                             
    autoload :BinaryDiff,              "amp/encoding/binary_diff.rb"
    autoload :MercurialDiff,           "amp/encoding/mercurial_diff.rb"
    autoload :MercurialPatch,          "amp/encoding/mercurial_patch.rb"
    autoload :SequenceMatcher,         "amp/encoding/difflib.rb"
  end
  
  module Graphs
    autoload :AncestorCalculator,      "amp/graphs/ancestor.rb"
    autoload :CopyCalculator,          "amp/graphs/copies.rb"
  end                                      
                                           
  module Merges                            
    autoload :MergeState,              "amp/merges/merge_state.rb"
    autoload :MergeUI,                 "amp/merges/merge_ui.rb"
    autoload :ThreeWayMerger,          "amp/merges/simple_merge.rb"
  end                                      
  
  module Repositories
    autoload :BranchManager,           "amp/repository/branch_manager.rb"
    autoload :BundleRepository,        "amp/repository/repositories/bundle_repository.rb"
    autoload :DirState,                "amp/repository/dir_state.rb"
    autoload :HTTPRepository,          "amp/repository/repositories/http_repository.rb"
    autoload :HTTPSRepository,         "amp/repository/repositories/http_repository.rb"
    autoload :LocalRepository,         "amp/repository/repositories/local_repository.rb"
    autoload :Lock,                    "amp/repository/lock.rb"
    autoload :Stores,                  "amp/repository/store.rb"
    autoload :TagManager,              "amp/repository/tag_manager.rb"
    autoload :Updatable,               "amp/repository/updatable.rb"
    autoload :Verification,            "amp/repository/verification.rb"
  end                                      
                                           
  module RevlogSupport                     
    autoload :ChangeGroup,             "amp/revlogs/changegroup.rb"
    autoload :Index,                   "amp/revlogs/index.rb"
    autoload :IndexInlineNG,           "amp/revlogs/index.rb"
    autoload :IndexVersion0,           "amp/revlogs/index.rb"
    autoload :IndexVersionNG,          "amp/revlogs/index.rb"
    autoload :Node,                    "amp/revlogs/node.rb"
    autoload :Support,                 "amp/revlogs/revlog_support.rb"
  end
  
  module Servers
    autoload :FancyHTTPServer,         "amp/server/fancy_http_server.rb"
    autoload :HTTPServer,              "amp/server/http_server.rb"
    autoload :HTTPAuthorizedServer,    "amp/server/http_server.rb"
    autoload :RepoUserManagement,      "amp/server/repo_user_management.rb"
    autoload :User,                    "amp/server/amp_user.rb"
  end
  
  module Support
    autoload :Logger,                  "amp/support/logger.rb"
    autoload :MultiIO,                 "amp/support/multi_io.rb"
    autoload :Template,                "amp/templates/template.rb"
  end
end

#######################
# Sinatra modifications
#######################
module Sinatra
  autoload :Amp, "amp/server/extension/amp_extension.rb"
end                  


###########################
# Globally accessible tools
###########################
autoload :Archive,       "amp/dependencies/minitar.rb"
autoload :Zip,           "amp/dependencies/zip/zip.rb"
autoload :PriorityQueue, "amp/dependencies/priority_queue.rb"

#############################
# Files we need to just *run*
#############################                 
require "amp/dependencies/trollop.rb"         
require "amp/dependencies/python_config.rb"   
require "amp/dependencies/amp_support.rb"     
require "amp/support/ruby_19_compatibility.rb"
require "amp/support/support.rb"              
require "amp/templates/template.rb"

if $cl # if it's a command line app
  include Amp::KernelMethods
  require       "amp/commands/command.rb"
  require_dir { "amp/commands/*.rb"              }
  require_dir { "amp/commands/commands/*.rb"     }
  
else
  # it's not a command line app
 require     'amp/support/docs.rb' # live documentation access
end
require      "amp/repository/repository.rb"

module Amp
  VERSION = '0.2.0'
  VERSION_TITLE = "Charles Hieronymus Pace"
end

if ENV["TESTING"] == "true"
  paused = Time.now
  puts "Time taken to load all files: #{paused - $start} seconds"
  puts "\t\t local files: #{paused - local_start} seconds"
  puts
  puts
end

# Benchmarking stuff
need { 'profiling_hacks' }
