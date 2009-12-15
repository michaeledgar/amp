command :verify do |c|
  c.workflow :hg
  
  c.desc "Verifies the mercurial repository, checking for integrity errors"
  c.on_run do |opts, args|
    results = opts[:repository].verify
    
    Amp::UI.tell "#{results.files} file#{results.files == 1 ? '' : 's' }, "
    Amp::UI.tell "#{results.changesets} changeset#{results.changesets == 1 ? '' : 's' }, "
    Amp::UI.tell "#{results.revisions} revision#{results.revisions == 1 ? '' : 's' }"
    
    if results.errors > 0 || results.warnings > 0
      Amp::UI.tell ", #{results.errors} integrity error#{results.errors == 1 ? '' : 's' }, "
      Amp::UI.tell "#{results.warnings} warning#{results.warnings == 1 ? '' : 's' }."
    end
    
    Amp::UI.say
  end
end