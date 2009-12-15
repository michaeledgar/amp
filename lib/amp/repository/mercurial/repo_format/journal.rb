module Amp
  class StandardErrorReporter
    def self.report str
      UI.err str
    end
  end
  
  module Mercurial
    
    ##
    # Provides a journal interface so when a large number of transactions
    # are occurring, and any one could fail, we can rollback the changes.
    class Journal
      DEFAULT_OPTS = {:reporter => StandardErrorReporter, :after_close => nil}
      
      attr_accessor :report, :journal, :after_close
      
      ##
      # @return [Amp::Mercurial::Journal]
      def self.start(file, opts=DEFAULT_OPTS)
        journal = Journal.new opts[:reporter], file, &opts[:after_close]
        
        if block_given?
          begin
            yield journal
          rescue
            journal.delete
          ensure
            journal.close
          end
        end
        
        journal
      end
      
      ##
      # Initializes the journal to get ready for some transactions.
      # 
      # @param [#report] reporter an object that will keep track of any alerts
      #   we have to send out. Must respond to #report.
      # @param [String] journal the path to the journal file to use
      # @param [Integer] createmode An octal number that sets the filemode
      #   of the journal file we'll be using
      # @param [Proc] after_close A proc to call (with no args) after we
      #   close (finish) the transaction.
      def initialize(reporter=StandardErrorReporter, journal=".journal#{rand(10000)}", createmode=nil, &after_close)   
        @count = 1
        @reporter = reporter
        @after_close = after_close
        @entries = []
        @map = {}
        @journal_file = journal
        
        @file = Kernel::open(@journal_file, "w")
        
        FileUtils.chmod(createmode & 0666, @journal_file) unless createmode.nil?
      end
      
      ##
      # Kills the journal - used when shit goes down and we gotta give up
      # on the transactions.
      def delete
        if @journal_file
          abort if @entries.any?
          @file.close
          FileUtils.safe_unlink @journal_file
        end
      end
      
      ##
      # Adds an entry to the journal. Since all our files are just being appended
      # to all the time, all we really need is to keep track of how long the file
      # was when we last knew it to be safe. In other words, if the file started
      # off at 20 bytes, then an error happened, we just truncate it to 20 bytes.
      # 
      # All params should be contained in the array
      # 
      # @param file the name of the file we're modifying and need to track
      # @param offset the length of the file we're storing
      # @param data any extra data to hold onto
      def add_entry(array)
        file, offset, data = array[0], array[1], array[2]
        return if @map[file]
        @entries << {:file => file, :offset => offset, :data => data}
        @map[file] = @entries.size - 1
        
        # tell the journal how to truncate this revision
        @file.write("#{file}\0#{offset}\n")
        @file.flush
      end
      
      ##
      # Alias for {add_entry}
      alias :<< :add_entry
      
      ##
      # Finds the entry for a given file's path
      # @param [String] file the path to the file
      # @return [Hash] A hash with the values :file, :offset, and :data, as
      #   they were when they were stored by {add_entry} or {update}
      def find_file(file)
        return @entries[@map[file]] if @map[file]
        nil
      end
      
      ##
      # Alias for {find_file}
      alias :find :find_file
      
      ##
      # Updates an entry's data, based on the filename. The file must already
      # have been journaled.
      # 
      # @param [String] file the file to update
      # @param [Fixnum] offset the new offset to store
      # @param [String] data the new data to store
      def replace(file, offset, data=nil)
        raise IndexError.new("journal lookup failed #{file}") unless @map[file]
        index = @map[file]
        @entries[index] = {:file => file, :offset => offset, :data => data}
        @file.write("#{file}\0#{offset}\n")
        @file.flush
      end
      
      ##
      # Alias for {replace}
      alias :update :replace
      
      ##
      # No godly idea what this is for
      def nest
        @count += 1
        self
      end
      
      ##
      # Is the journal running right now?
      def running?
        @count > 0
      end
      
      ##
      # Closes up the journal. Will call the after_close proc passed
      # during instantiation.
      def close
        UI::status "closing journal"
        @count -= 1
        return if @count != 0
        @file.close
        @entries = []
        if @after_close
          @after_close.call
        else
          FileUtils.safe_unlink(@journal_file)
        end
        @journal_file = nil
      end
      
      ##
      # Abort, abort! abandon ship! This rolls back any changes we've made
      # during the current journalling session.
      def abort
        UI::status "aborting journal"
        return unless @entries && @entries.any?
        @reporter.report "transaction abort!\n"
        @entries.each do |hash|
          file, offset = hash[:file], hash[:offset]
          begin
            fp = open(File.join(".hg","store",file), "a")
            fp.truncate offset
            fp.close
          rescue
            @reporter.report "Failed to truncate #{File.join(".hg","store",file)}\n"
          end
        end
        @entries = []
        @reporter.report "rollback completed\n"
      end
      
      ##
      # If we crashed during an abort, the journal file is gonna be sitting aorund
      # somewhere. So, we should rollback any changes it left lying around.
      # 
      # @param [String] file the journal file to use during the rollback
      def self.rollback(file)
        files = {}
        fp = open(file)
        fp.each_line do |line|
          file, offset = line.split("\0")
          files[file] = offset.to_i
        end
        fp.close
        files.each do |file, offset|
          if o > 0
            fp = open(file, "a")
            fp.truncate o.to_i
            fp.close
          else
            fp = open(f)
            fn = fp.path
            fp.close
            FileUtils.safe_unlink fn
          end
        end
        FileUtils.safe_unlink file
      end
    end
  end
end
          