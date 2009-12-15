require 'tempfile'

module Amp
  module Merges
    module Mercurial
      
      ##
      # This module handles figuring out how to merge files using the user's
      # preferences. It is mixed into the UI class. The UI class must implement
      # the "config" method.
      module MergeUI
        extend self
        
        ##
        # Performs a 3-way merge in the working directory from vf_local to vf_other,
        # using the common ancestor vf_ancestor.
        #
        # @todo change 1s and 0s to bools
        # @todo consistent return type
        #
        # @param [Repository] repo the repository in which we are merging files
        # @param [String] parent_node the node_id of the parent node before the merge
        # @param [String] original_fn the original local filename before the merge
        # @param [WorkingVersionedFile] vf_local the current, working-directory versioned file
        # @param [VersionedFile] vf_other the file's changeset to which we are migrating
        # @param [VersionedFile] vf_ancestor the common ancestor between vf_local and vf_other
        # @return [Boolean] true if there were conflicts during the merge
        def file_merge(repo, parent_node, original_fn, vf_local, vf_other, vf_ancestor)
          is_binary = proc {|ctx| ctx.data.binary? rescue false}
          
          return nil if !(vf_other.cmp vf_local.data)
          
          path = vf_local.path
          binary = is_binary[vf_local] || is_binary[vf_other] || is_binary[vf_ancestor]
          symlink = (vf_local.flags + vf_other.flags).include? "l"
          
          tool, tool_path = pick_tool(repo, path, binary, symlink)
          UI.status("Picked tool #{tool} for #{path} (binary #{binary} symlink #{symlink})")
          
          unless tool
            tool = "internal:local"
            if UI.ask("no tool found to merge #{path}\n"+
                      "keep (l)ocal or take (o)ther?") != "l"
              tool = "internal:other"
            end
          end
          
          case tool
          when "internal:local"
            return 0
          when "internal:other"
            repo.working_write(path, vf_other.data, vf_other.flags)
            return 0
          when "internal:fail"
            return 1
          end
          
          a = repo.working_join(path)
          b_file = save_versioned_file_temp("base", vf_ancestor)
          c_file = save_versioned_file_temp("other", vf_other)
          b, c = b_file.path, c_file.path
          
          out = ""
          back = a + ".orig" + File.extname(a)
          File.copy(a, back)
          
          if original_fn != vf_other.path
            UI.status("merging #{original_fn} and #{vf_other.path} to #{path}")
          else
            UI.status("merging #{path}")
          end
          
          if tool_setting(tool, "premerge", !(binary || symlink))
            ret = ThreeWayMerger.three_way_merge(a, b, c, :quiet => true)
            unless ret
              UI.debug("premerge successful")
              File.unlink(back)
              File.safe_unlink(b)
              File.safe_unlink(c)
              return false
            end
            File.copy(back, a) # restore frmo backup and try again
          end
          
          environment = {"HG_FILE" => path,
                         "HG_MY_NODE" => parent_node.hexlify[0..11],
                         "HG_OTHER_NODE" => vf_other.changeset.to_s,
                         "HG_MY_ISLINK" => vf_local.flags.include?("l"),
                         "HG_OTHER_ISLINK" => vf_other.flags.include?("l"),
                         "HG_BASE_ISLINK" => vf_ancestor.flags.include?("l")}
          if tool == "internal:merge"
            ret = ThreeWayMerger.three_way_merge(a, b, c, :label => ['local', 'other'])
          else
            args = tool_setting_string(tool, "args", "$local $base $other")
            if args.include?("$output")
              out, a = a, back # read input from backup, write to original
            end
            replace = {"local" => a, "base" => b, "other" => c, "output" => out}
            args.gsub!(/\$(local|base|other|output)/) { replace[$1]}
            # shelling out
            ret = Amp::Support::system(tool_path+" "+args, :chdir => repo.root, :environ => environment)
          end
          ret = (ret == true ? 1 : (ret == false ? 0 : ret))
          if ret == 0 && tool_setting(tool, "checkconflicts")
            if vf_local.data =~ /^(<<<<<<< .*|=======|>>>>>>> .*)$/
              ret = 1
            end
          end
          
          if ret == 0 && tool_setting(tool, "checkchanged")
            if File.stat(repo.working_join(path)) === File.stat(back)
              if UI::yes_or_no "output file #{path} appears unchanged\nwas merge successful?"
                r = 1
              end
            end
          end
          
          fix_end_of_lines(repo.working_join(path), back) if tool_setting(tool, "fixeol")
          
          if ret == 1
            UI::warn "merging #{path} failed!"
          else
            File.unlink back
          end
          File.unlink b
          File.unlink c
          
          !ret.zero? # return
        end
        
        private
        
        def save_versioned_file_temp(prefix, versioned_file)
          prefix = "#{File.basename versioned_file.path}~#{prefix}"
          
          tempfile = Tempfile.new prefix
          path = tempfile.path
          tempfile.write versioned_file.data
          tempfile.close false # DON'T unlink it
          
          tempfile
        end
        
        ##
        # Converts the end-of-line characters in a file to match the original file.
        # Thus, if we merge from our copy to a new one, and there foreign
        # end-of-line characters got merged in, we want to nuke them and put in our own!
        #
        # @param [String] new_file the path to the newly merged file
        # @param [String] original_file the path to the original file
        def fix_end_of_lines(new_file, original_file)
          new_eol = guess_end_of_line(File.read(original_file))
          if new_eol
            data = File.read(new_file)
            old_eol = guess_end_of_line(data)
            if old_eol
              new_data = data.gsub(old_eol, new_eol)
              
              File.open(file, "w") {|f| f.write new_data } if new_data != data
            end
          end
        end
        
        
        ##
        # Guesses the end-of-line character for a file in a very lazy fashion.
        #
        # @param [String] data the file data to guess from
        # @return [String, nil] the guessed end-of-line character(s).
        def guess_end_of_line(data)
          return nil if data.include?("\0")       # binary
          return "\r\n" if data.include?("\r\n")  # windows
          return "\r"   if data.include?("\r")    # old mac
          return "\n"   if data.include?("\n")    # *nix
          return nil                              # wtf?
        end
        
        def config; UI.config; end
        
        ##
        # Picks a merge tool based on the user's settings in hgrc files and environment
        # variables. Returns a hash specifying both the name and path of the
        # merge tool's executable.
        #
        # @todo merge-patterns, line 56 of filemerge.py
        # @param [Repository] repo the repository we are performing a merge upon
        # @param [String] path the path to the file we're merging
        # @param [Boolean] binary is the file a binary file?
        # @param [Boolean] symlink is the file a symlink?
        # @return [Hash] keyed as follows:
        #   :name => the name of the chosen tool
        #   :path => the path to the tool (if an executable is to be used)
        def pick_tool(repo, path, binary, symlink)
          hgmerge = ENV["HGMERGE"]
	  			return [hgmerge, hgmerge] if hgmerge
          
          # @todo: add merge-patterns support
          
          # scan the merge-tools section
          tools = {}
          config["merge-tools"].each do |k, v|
            t = k.split(".").first
            unless tools[t]
              tools[t] = tool_setting_string(t, "priority", "0").to_i
            end
          end
          
          # go through the list of tools and sort by priority
          tool_names = tools.keys
          tools = tools.map {|tool, prio| [-prio, tool]}.sort
          # check the [ui] section for a "merge" setting
          uimerge = config["ui","merge"]
          if uimerge
            unless tool_names.include?(uimerge)
              return [uimerge, uimerge]
            end
            tools.unshift([nil, uimerge]) # highest priority
          end
          
          # add the "hgmerge" binary
          tools << [nil, "hgmerge"] # the old default, if found
          # check everything in our list, and if we actually find one that works,
          # return it
          tools.each do |priority, tool|
            if check_tool(tool, nil, symlink, binary)
              tool_path = find_tool(tool)
              return [tool, "\"#{tool_path}\""]
            end
          end
          # last but not least, do a simple_merge.
          return (!symlink && !binary) ? "internal:merge" : [nil, nil]
        end
        
        ##
        # Quick access to the merge-tools section of the configuration files.
        # A merge tool will set it up with data like this:
        #     [merge-tools]
        #     awesometool.executable = /usr/bin/awesometool
        #     awesometool.regkey = HKEY_USELESS_INFO
        # and so on. This method abstracts away the scheme for encoding this information
        # gets string values from the configuration.
        #
        # @param [String] tool the name of the tool to look up data for
        # @param [String] part the specific information about the tool to look up
        # @param [String] default the default value, if the configuration setting
        #   can't be found
        # @return [String] the setting for the given merge tool we're looking up, as
        #   as a string.
        def tool_setting_string(tool, part, default="")
          config["merge-tools", "#{tool}.#{part}", String, default]
        end
        
        ##
        # Quick access to the merge-tools section of the configuration files.
        # Returns boolean values.
        #
        # @see check_tool_string
        # @param [String] tool the name of the tool to look up data for
        # @param [String] part the specific information about the tool to look up
        # @param [Boolean] default the default value, if the configuration setting
        #   can't be found
        # @return [Boolean] the setting for the given merge tool we're looking up, as
        #   as a string.
        def tool_setting(tool, part, default=false)
          config["merge-tools", "#{tool}.#{part}", Boolean, default]
        end
        
        ##
        # Given the name of a merge tool, attempt to locate an executable file
        # for the tool.
        #
        # @param [String] tool the name of the merge tool to locate
        # @return [String] the path to the executable for the merge tool, or nil
        #   if the tool cannot be found
        def find_tool(tool)
          if ["internal:fail", "internal:local", "internal:other"].include?(tool)
            return tool
          end
          # windows stuff
          k = tool_setting_string(tool, "regkey")
          if k && k.any?
            p = File.amp_lookup_reg(k, tool_setting_string(tool, "regname"))
            if p && p.any?
              p = File.amp_find_executable(p + check_tool_string(tool, "regappend"))
              if p
                return p
              end
            end
          end
          # normal *nix lookup
          return File.amp_find_executable(tool_setting_string(tool, "executable", tool))
        end
        
        ##
        # Checks to see if a given tool is available given the necessary settings.
        # 
        # @todo add GUI check
        # @param [String] tool the name of the tool we want to check
        # @param [String] pat the pattern we matched to get here. Could be nil.
        # @param [Boolean] symlink are we merging across a symlink here?
        # @param [Boolean] binary are we merging a binary file? you crazy?!
        # @return [Boolean] is the given tool available?
        def check_tool(tool, pat, symlink, binary)
          tool_msg = tool
          tool_msg += " specified for " + pat if pat
          
          if !(find_tool tool)
            if pat
              UI.warn("couldn't find merge tool #{tool}")
            else
              UI.note("couldn't find merge tool #{tool}")
            end
          elsif symlink && !(tool_setting(tool, "symlink"))
            UI.warn("tool #{tool} can't handle symlinks")
          elsif binary  && !(tool_setting(tool, "binary"))
            UI.warn("tool #{tool} can't handle binary files")
          elsif false # TODO: add GUI check
          else
            return true
          end
          return false # we're here if any of the previous checks created a warning
        end
        
      end
    end
  end
end
