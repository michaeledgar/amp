require 'test/unit'

def assert_false(val)
  assert_equal(false, !!val)
end

def assert_not_nil(val)
  assert_not_equal(nil, val)
end

def assert_file_contents(file, contents)
  File.open(file,"r") do |f|
    assert_equal f.read, contents
  end
end
