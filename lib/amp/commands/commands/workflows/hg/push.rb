#######################################################################
#                  Licensing Information                              #
#                                                                     #
#  The following code is a derivative work of the code from the       #
#  Mercurial project, which is licensed GPLv2. This code therefore    #
#  is also licensed under the terms of the GNU Public License,        #
#  verison 2.                                                         #
#                                                                     #
#  For information on the license of this code when distributed       #
#  with and used in conjunction with the other modules in the         #
#  Amp project, please see the root-level LICENSE file.               #
#                                                                     #
#  © Michael J. Edgar and Ari Brown, 2009-2010                        #
#                                                                     #
#######################################################################

command :push do |c|
  c.workflow :hg
  c.desc "Pushes the latest revisions to the remote repository."
  c.opt :remote, "The remote repository's URL", :short => "-R"
  c.opt :revs, "The revisions to push", :short => "-r", :type => :string
  c.opt :force, "Ignore remote heads", :short => "-f"
  
  c.on_run do |opts, args|
    repo                 = opts[:repository]
    dest                 = opts[:remote] || repo.config["paths","default-push"] || repo.config["paths","default"]
    opts[:revs]        ||= nil
    remote               = Amp::Support.parse_hg_url(dest, opts[:revs])
    dest, revs, checkout = remote[:url], remote[:revs], remote[:head]
    remote_repo          = Amp::Repositories.pick(repo.config, dest, false)
    revs                 = revs.map {|rev| repo.lookup rev } if revs
    
    result = repo.push remote_repo, :force => opts[:force], :revs => revs
  end
end
