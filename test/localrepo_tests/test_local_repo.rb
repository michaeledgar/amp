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

require File.join(File.expand_path(File.dirname(__FILE__)), '../testutilities')
require 'fileutils'
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp"))

class TestLocalRepo < AmpTestCase
  REPO_PATH = File.expand_path(File.join(File.dirname(__FILE__)))
  EXISTING_REPO_PATH = File.expand_path(File.join(File.dirname(__FILE__), "testrepo"))
  
  def setup
    @config = Amp::AmpConfig.new
    @repo = Amp::Repositories::Mercurial::LocalRepository.new(EXISTING_REPO_PATH, false, @config)
  end
  
  def join(*args)
    File.join(REPO_PATH, *args)
  end
  
  def hg_join(*args)
    File.join(REPO_PATH, ".hg", *args)
  end
  
  def teardown
    FileUtils.rm_rf join(".hg")
  end
    
  def test_create_repo
    Amp::Repositories::Mercurial::LocalRepository.new(REPO_PATH, true, @config)
    assert File.directory?(join(".hg"))
    assert File.exists?(hg_join("00changelog.i"))
    assert File.exists?(hg_join("requires"))
    assert File.directory?(hg_join("store"))
    assert_file_contents hg_join("requires"),"revlogv1\nstore\nfncache\n"
  end
  
  def test_open_existing_repo
    refute_nil @repo
  end
  
  def test_repo_size
    assert_equal 4, @repo.size
  end
  
  def test_initial_changeset_manifest
    changeset = @repo[0]
    # manifest check
    expected_list = ["readme","silly/code"]
    actual = []
    changeset.each do |k,v|
      actual << k
    end
    assert_equal expected_list.sort, actual.sort
  end
    
  def test_initial_readme
    changeset = @repo[0]
    
    changeset.manifest_entry.inspect # force load of manifest
    
    file = changeset["readme"]
    # data check on a file
    expected_readme = "this is the readme. I hope you like it.\nAmp is "+
                      "totally sweet. We're gonna do awesome stuff.\nI hope "+
                      "you lik it.\n"
                      
    expected = expected_readme
    actual = file.data
    assert_equal expected, actual
    
    expected = Zlib::Deflate.deflate(file.data).size
    actual = file.size # compressed size
    assert_equal expected, actual
    
    assert_false file.cmp(expected_readme)
  end
  
  def test_second_readme
    expected_readme = "this is the readme. I hope you like it.\nAmp is "+
                      "totally sweet. We're gonna do awesome stuff.\nI hope "+
                      "you like it.\n" # typo fixed
    changeset = @repo[1]
    changeset.manifest_entry # force load of manifest
    file = changeset["readme"]
    
    expected = expected_readme
    actual = file.data
    assert_equal expected, actual
  end
  
  def test_status
    
    actual = @repo.status(:ignored => true, :clean => true, :unknown => true,
                          :node_1 => @repo["."].node, :node_2 => nil)
    
    
    
    modified = ["readme"]
    clean    = ["emptyfile", "fileididcopy", "silly/code", "silly/ignoredfile"]
    ignored  = ["silly/unknownfile"]
    unknown  = [".hgignore"]
    added    = []
    deleted  = []
    removed  = []
    #copied   = []
    #moved    = []
    expected = { :modified => modified.sort,
                 :added    => added.sort,
                 :removed  => removed.sort,
                 :deleted  => deleted.sort,
                 :unknown  => unknown.sort,
                 :ignored  => ignored.sort,
                 :clean    => clean.sort  ,
                 #:copied   => copied,
                 #:moved    => moved,
                 :delta    => 19
               }
      
    assert_equal expected, actual
    
  end
end