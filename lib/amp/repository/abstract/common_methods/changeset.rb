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

module Amp
  module Repositories
    
    ##
    # = CommonVersionedFileMethods
    #
    # These methods are common to all repositories, and this module is mixed into
    # the AbstractLocalRepository class. This guarantees that all repositories will
    # have these methods.
    #
    # No methods should be placed into this module unless it relies on methods in the
    # general API for repositories.
    module CommonChangesetMethods
      
      ##
      # A hash of the files that have been changed and their most recent diffs.
      # The diffs are lazily made upon access. To just get the files, use #altered_files
      # or #changed_files.keys
      # Checks whether this changeset included a given file or not.
      # 
      # @return [Hash<String => String>] a hash of {filename => the diff}
      def changed_files
        h = {}
        class << h
          def [](*args)
            super(*args).call # we expect a proc
          end
        end
        
        altered_files.inject(h) do |s, k|
          s[k] = proc do
            other = parents.first[k]
            self[k].unified_diff other
          end
          s
        end
      end
      
      ##
      # Is +file+ being tracked at this point in time?
      # 
      # @param [String] file the file to lookup
      # @return [Boolean] whether the file is in this changeset's manifest
      def include?(file)
        all_files.include? file
      end
      
      ##
      # recursively walk
      # 
      # @param [Amp::Matcher] match this is a custom object that knows files
      #   magically. Not your grampa's proc!
      def walk(match)
        # just make it so the keys are there
        results = []
        
        hash = Hash.with_keys match.files
        hash.delete '.'
        
        each do |file|
          hash.each {|f, val| (hash.delete file and break) if f == file }
          
          results << file if match.call file # yield file if match.call file
        end
        
        hash.keys.sort.each do |file|
          if match.bad file, "No such file in revision #{revision}" and match[file]
            results << file # yield file
          end
        end
        results
      end
      
    end
  end
end
