require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../../lib/amp"))

class TestFilenameCacheStore < Test::Unit::TestCase
  STORE_PATH = File.expand_path(File.join(File.dirname(__FILE__)))
  def setup
    @store = Amp::Repositories::Stores.pick(['store','fncache'], STORE_PATH, Amp::Opener)
  end
  
  def test_load_manifest
    assert_not_nil @store
    assert_instance_of Amp::Repositories::Stores::FilenameCacheStore, @store
  end
  
  def test_hybrid_encode
    result = Amp::Repositories::Stores.hybrid_encode("data/ABCDEFGHIJKLMNOPQRSTUVWXYZ/HAHAH"+
                                       "A????WHHHHHHHHHHHAAAAAAAAATTTTTTTTTT/"+
                                       "lolzorZ?.rb")
    expected = "dh/abcdefgh/hahaha~3/lolzorz~3f.rb0d132fe8aa79af42d3d3c11038"+
               "3007e9f5bd43d4.rb"
    assert_equal expected, result
    
    result = Amp::Repositories::Stores.hybrid_encode("data/ABCDEFGHIJKLMNOPQRSTUVWXYZ/HAHAH"+
                                       "A????WHHHHTT/lolzorZ?.rb")
    expected = "data/_a_b_c_d_e_f_g_h_i_j_k_l_m_n_o_p_q_r_s_t_u_v_w_x_y_z/_h"+
               "_a_h_a_h_a~3f~3f~3f~3f_w_h_h_h_h_t_t/lolzor_z~3f.rb"
    assert_equal expected, result
    
    result = Amp::Repositories::Stores.hybrid_encode("data///../.././//lolzorZ?.rb")
    expected = "data///.~2e/.~2e/~2e///lolzor_z~3f.rb"
    assert_equal expected, result
  end
  
  def test_normal_encode
    result = Amp::Repositories::Stores.encode_filename("data/ABCDEFGHIJKLMNOPQRSTUVWXYZ/HAHAH"+
                                       "A????WHHHHHHHHHHHAAAAAAAAATTTTTTTTTT/"+
                                       "lolzorZ?.rb")
    expected = "data/_a_b_c_d_e_f_g_h_i_j_k_l_m_n_o_p_q_r_s_t_u_v_w_x_y_z/_h_"+
               "a_h_a_h_a~3f~3f~3f~3f_w_h_h_h_h_h_h_h_h_h_h_h_a_a_a_a_a_a_a_a"+
               "_a_t_t_t_t_t_t_t_t_t_t/lolzor_z~3f.rb"
    assert_equal expected, result
    
    result = Amp::Repositories::Stores.encode_filename("data/ABCDEFGHIJKLMNOPQRSTUVWXYZ/HAHAH"+
                                       "A????WHHHHTT/lolzorZ?.rb")
    expected = "data/_a_b_c_d_e_f_g_h_i_j_k_l_m_n_o_p_q_r_s_t_u_v_w_x_y_z/_h_"+
               "a_h_a_h_a~3f~3f~3f~3f_w_h_h_h_h_t_t/lolzor_z~3f.rb"
    assert_equal expected, result
    
    result = Amp::Repositories::Stores.encode_filename("data///../.././//lolzorZ?.rb")
    expected = "data///../.././//lolzor_z~3f.rb"
    assert_equal expected, result
  end
  
  def test_normal_decode
    result = Amp::Repositories::Stores.decode_filename(
               "data/_a_b_c_d_e_f_g_h_i_j_k_l_m_n_o_p_q_r_s_t_u_v_w_x_y_z/_h_"+
               "a_h_a_h_a~3f~3f~3f~3f_w_h_h_h_h_h_h_h_h_h_h_h_a_a_a_a_a_a_a_a"+
               "_a_t_t_t_t_t_t_t_t_t_t/lolzor_z~3f.rb")
               
    expected =  "data/ABCDEFGHIJKLMNOPQRSTUVWXYZ/HAHAH"+
                "A????WHHHHHHHHHHHAAAAAAAAATTTTTTTTTT/"+
                "lolzorZ?.rb"
    assert_equal expected, result
    
    result = Amp::Repositories::Stores.decode_filename(
                "data/_a_b_c_d_e_f_g_h_i_j_k_l_m_n_o_p_q_r_s_t_u_v_w_x_y_z/_h_"+
                           "a_h_a_h_a~3f~3f~3f~3f_w_h_h_h_h_t_t/lolzor_z~3f.rb")
    expected = "data/ABCDEFGHIJKLMNOPQRSTUVWXYZ/HAHAHA????WHHHHTT/lolzorZ?.rb"
    assert_equal expected, result
    
    result = Amp::Repositories::Stores.decode_filename("data///../.././//lolzor_z~3f.rb")
    expected = "data///../.././//lolzorZ?.rb"
    assert_equal expected, result
  end
  
  def test_custom_pathjoiner
    tempstore = @store.path_joiner
    @store.path_joiner = proc {|*args| args.join "LOLCATS"}
    result = @store.join "teh_file_namez"
    expected = TestFilenameCacheStore::STORE_PATH + "/store" + "LOLCATS" + "teh_file_namez"
    assert_equal expected, result
  end
  
  def test_walk
    # alright.... the list is just too fucking huge to have it compare
    # against the whole thing. So we're going to pick 10 and make sure
    # that they're in there. These are some pretty good edge cases, too.
    expected = [['data/lib/commands/dispatch.rb.i', 'data/lib/commands/dispatch.rb.i', 1500],
                ['data/test/test_support.rb.i', 'data/test/test__support.rb.i', 640],
                ['data/AUTHORS.i', 'data/_a_u_t_h_o_r_s.i', 64],
                ['data/test/manifest_tests/test_manifest.rb.i', 'data/test/manifest__tests/test__manifest.rb.i', 1865],
                ['data/lib/revlogs/changelog.rb.i', 'data/lib/revlogs/changelog.rb.i', 5386],
                ['data/test/revlog_tests/00changelog.i.i', 'data/test/revlog__tests/00changelog.i.i', 10285],
                ['00manifest.i', '00manifest.i', 43979],
                ['00changelog.i', '00changelog.i', 28785]
               ]
    result = []
    @store.walk do |arr|
      result << arr
    end
    
    expected.each do |exp|
      flunk "Couldn't find #{exp.inspect} in walked list." unless result.include? exp
    end
    assert true
  end
  
  def test_picker_works
    requirements = []
    store = Amp::Repositories::Stores.pick(requirements, STORE_PATH, Amp::Opener)
    assert_instance_of Amp::Repositories::Stores::BasicStore, store
    
    requirements = ['store']
    store = Amp::Repositories::Stores.pick(requirements, STORE_PATH, Amp::Opener)
    assert_instance_of Amp::Repositories::Stores::EncodedStore, store
    
    requirements = ['store', 'fncache']
    store = Amp::Repositories::Stores.pick(requirements, STORE_PATH, Amp::Opener)
    assert_instance_of Amp::Repositories::Stores::FilenameCacheStore, store
    
  end
end