module Amp
  
  ##
  # This deals with the configuration file for amp that is located in the top of
  # the Ampfile. The hierarchy of config files now is as such:
  # 
  #  LEAST
  #  /etc/
  #  ~/
  #  /your_repo/.hg/hgrc
  #  /your_repo/Ampfile
  #  MOST
  # =======================
  # 
  # The Ampfile's config-ness is simple: it's a header, some content, and a
  # footer. Simple. Easy. Sleek. It is Blue Steel in code form. Just fyi, I
  # just got to watch a movie with two hot twins. Be proud.
  # 
  # NOW, Mike said that he didn't want to be restricted to just YAML. I'm not
  # going to bake in three levels of abstraction to get a nice way to switch
  # out between YAML and PythonConfig and Diffie-Hellmann encoding. Instead,
  # I'm going to just document this really well and make it very simple to
  # write your own extension for this.
  class AmpfileConfig
    require 'yaml' # suck it bitches this will always load
    
    # The header and footer are content-agnostic.
    # You can change them as you please, even though they are constants.
    #  Amp::AmpfileConfig::Header.replace "# lolcat"
    HEADER = "########\n" # 8 #s
    FOOTER = "########\n" # 8 #s
    
    attr_accessor :file
    attr_accessor :config
    
    def initialize(filename)
      @file = filename
      
      # basically all we do here is move the index of where we are in the file
      Kernel::open filename, 'r' do |f|
        header f # chew the header
        cntnt = content f # get the content. can be an empty string
        interpret cntnt # assign the interpreted content to @config
      end # and bail the fuck out of there
    end
    
    ##
    # We'll start by chewing up the header.
    # 
    # @param  [IO, #read] open_file An already opened file handle from which
    #   we'll read.
    # @return [nil]
    def header(open_file)
      until open_file.readline == HEADER # this is becoming a bad habit of tonight
      end                                # (timeline hint: #content was written first)
    end
    
    ##
    # Next up in this kitchen, we need to deal with the content. Shall we?
    # For those counting at home, this is content-agnostic. Easy with that
    # delete key, there, eeeeeeeeasy girl...
    # 
    # This method takes the content AND THE FOOTER from an open file
    # handle +open_file+.
    # 
    # @param  [IO, #read] open_file An already opened file handle from which
    #   we'll read.
    # @return [String] The content that needs to be parsed somehow.
    def content(open_file)
      lines = []
      
      # Sup coolkid. We're taking advantage of the side effect here. It's generally
      # unwise, but what can I say, I like to take risks; I ride my bike without a
      # helmet.
      until (lines << open_file.readline) == FOOTER
      end
      
      lines.pop     # I figure this is overall cheaper than doing lines[0..-2].join ''
      lines.join '' # The world may never know
    end
    
    ##
    # This is the only content-dependent part. If you were to override a method,
    # pick this one. This interprets the content (+cntnt+) and stores it in the
    # @config variable.
    # 
    # @param [String] cntnt The content that we need to interpret.
    def interpret(cntnt)
      @config = YAML::load cntnt
      #@config = 
    end
    
    def [](*args)
      @config[*args]
    end
    
    def []=(*args)
      @config.send :[]=, *args # due to syntax oddities
    end
    
    def save!
      # Do nothing, because we can't really save back to the Ampfile. Adjustable
      # length heading? I should hope not. Let's just perform a O(lm) insertion
      # where l is the difference in the size of the headers and m is the length
      # of the rest of the Ampfile. Worst case is O(n^2) is l = m. Let's take a
      # note from Google on this one: if you want shit to be fast, don't let
      # anything slow be introduced.
      
      # Ah, fuck it, let's just get this feature in there anyways and see if it
      # actually slows shit down.
      
      data    = File.read @file
      pointer = nil
      
      Kernel::open @file, 'r' do |f|
        header  f
        content f # throw it away, we're just looking for the index pointer
        pointer = f.pos
      end # gtfo
      
      # yeah, fuck it, i just want to get to bed. change the #to_yaml to whatever you want
      text = HEADER + @config.to_yaml + FOOTER + data[pointer..-1]
      Kernel::open(@file, 'w') {|f| f.write text } # write it in place
      
      true # success marker
    end
    
  end
end
