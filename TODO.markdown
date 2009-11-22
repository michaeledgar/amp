Amp::RevlogSupport::IndexInlineNG
=================================

Amp::RevlogSupport::IndexInlineNG#parse\_file
---------------------------------------------
  - "not sure what the 0 is for yet or i'd make this a hash" (see code)


File
====

File.amp\_find\_executable
--------------------------
  - Add Windows Version.

File.amp\_lookup\_reg
---------------------
  - Add Windows Version

File.amp\_set\_executable
-------------------------
  - Windows version


Amp::ChangeLog
==============

Amp::ChangeLog#add
------------------
  - Handle text encodings

Amp::ChangeLog#read
-------------------
  - Text encodings, I hate you. but i must do them


Amp::Revlog
===========

Amp::Revlog#check\_inline\_size
-------------------------------
  - FINISH THIS METHOD
  - FIXME


Amp::Repositories::LocalRepository
==================================

Amp::Repositories::LocalRepository#push\_unbundle
-------------------------------------------------
  - -- add default values for +opts+

Amp::Repositories::LocalRepository#changegroup\_info
----------------------------------------------------
  - add more debug info

Amp::Repositories::LocalRepository#pre\_push
--------------------------------------------
  - -- add default values for +opts+

Amp::Repositories::Updatable#apply\_updates
-------------------------------------------
  - add path auditor

Amp::Repositories::Updatable#update
-----------------------------------
  - add lock

Amp::Repositories::LocalRepository#push\_add\_changegroup
---------------------------------------------------------
  - -- add default values for +opts+

Amp::Repositories::TagManager#read\_tags
----------------------------------------
  - encodings, handle local encodings


Amp::Repositories::DirState
===========================

Amp::Repositories::DirState#normalize
-------------------------------------
  - figure out what this does

Amp::Repositories::DirState#write
---------------------------------
  - watch memory usage - +si+ could grow unrestrictedly which would


Amp::Repositories::HTTPRepository
=================================

Amp::Repositories::HTTPRepository#changegroup
---------------------------------------------
  - figure out what the +kind+ parameter is for


