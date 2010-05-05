module Amp
  module Statistics
    module_function
    
    ##
    # Generates a histogram with given an array with keys provided
    # as an array and the values provided as a parallel array.
    def histogram(pairs, width = 80, marker = '*')
      keys, values = pairs.map {|x| x[0]}, pairs.map {|x| x[1]}
      
      # we'll be putting the keys in as strings. we need to reserver some
      # space for that - calculate that here.
      max_key_width = keys.max {|a, b| a.size <=> b.size}.size
      width -= max_key_width + 3

      # we'll be putting the values in as strings. we need to reserve some
      # space for that - calculate that space
      vals_as_strings = values.map {|x| x.to_s}
      max_stringval_width = vals_as_strings.max {|a, b| a.size <=> b.size}.size
      width -= max_stringval_width - 1

      # calculate the bar lengths
      total_val = values.inject {|a, b| a + b}
      max_val = values.max.to_f
      bar_sizes = values.map {|val| (val * width / max_val).to_i}
      
      result = ""
      keys.each_with_index do |str, idx|
        # print the key
        result << "#{str.ljust(max_key_width)} "
        # then the raw value
        result << "#{vals_as_strings[idx].rjust(max_stringval_width)} "
        # then a bar for the value
        result << "#{marker * bar_sizes[idx]}\n"
      end
      result
    end
    
  end
end