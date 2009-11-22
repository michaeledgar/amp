require "test/unit"
require File.expand_path(File.join(File.dirname(__FILE__), "../lib/amp"))


class TestDifflib < Test::Unit::TestCase
  include Amp::Diffs
  def test_one_match
    matcher = SequenceMatcher.new("hi there my name is mike i hope you like me", 
                                  "hi there my name is joe i hate you like i hate me")
    assert_equal([0,0,20], matcher.find_longest_match(0,43,0,49))
  end
  
  def test_full_matching
    matcher = SequenceMatcher.new("hi there my name is mike i hope you like me", 
                                  "hi there my name is joe i hate you like i hate me")
    assert_equal([{:start_a => 0, :start_b => 0, :length => 20}, #match for "hi there my name is "
                  {:start_a => 23, :start_b => 22, :length => 5}, #match for "e i ha"
                  {:start_a => 30, :start_b => 29, :length => 11}, #match for "e you like "
                  {:start_a => 41, :start_b => 47, :length => 2}, #match for "me"
                  {:start_a => 43, :start_b => 49, :length => 0}], 
                  matcher.get_matching_blocks.sort {|a1,a2| a1[:start_a] <=> a2[:start_a]}) #last match is terminator
                  
  end
  
  def test_full_example
    matcher = SequenceMatcher.new(
    ['c913df15006c6e06504414acf8acfedd32e5875d\n', 'michaeledgar@michael-edgars-macbook-pro.local\n', 
      '1248396415 14400\n', 'STYLE.txt\n', '\n', 'First commit.'], 
    ['b2a7f7ab636d1dbd06afd90f1bf287dfb92762fb\n', 'michaeledgar@michael-edgars-macbook-pro.local\n', 
      '1248396417 14400\n', 'command.rb\n', 'commands/annotate.rb\n', 'commands/heads.rb\n', 
      'commands/manifest.rb\n', 'commands/status.rb\n', '\n', 'Second commit, added commands'])
    assert_equal([{:start_a => 1, :start_b => 1, :length => 1}, #match for "michaeledgar@..."
                  {:start_a => 4, :start_b => 8, :length => 1}, #match for "\n"
                  {:start_a => 6, :start_b => 10, :length => 0}], 
                  matcher.get_matching_blocks.sort {|a1,a2| a1[:start_a] <=> a2[:start_a]}) #last match is terminator
                  
  end
  
  def test_another_full_example
    matcher = SequenceMatcher.new(
    ['The Amp Commandments Redux:\n', 
      "\t1. This is intended to genreate a conflict. I'm out of witty stuff to put here."], 
    ["\t1. This is intended to genreate a conflict. I'm out of witty stuff to put here."])
    assert_equal([{:start_a => 1, :start_b => 0, :length => 1}, #match for "michaeledgar@..."
                  {:start_a => 2, :start_b => 1, :length => 0}], 
                  matcher.get_matching_blocks.sort {|a1,a2| a1[:start_a] <=> a2[:start_a]}) #last match is terminator
                  
  end
  
end
