;;;; -*- Mode: LISP; Syntax: COMMON-LISP; coding: utf-8 -*-
;;;;
;;;; Polyfill manifest for dotcl.  dotcl's polyfill BASE is its author's
;;;; published dist (:vendor-dist), which dotcl installs into a
;;;; Quicklisp by itself at the first quickload or (ql:setup) unless
;;;; told not to; the entries below are layered over it.  So the stock
;;;; lib-world needs dotcl told to leave its dist out: :stock-forms are
;;;; evaluated in every dotcl child of the stock pass before anything
;;;; else (the QL-SETUP package made ahead with the variable bound,
;;;; which dotcl's client tolerates; proven on 0.1.36, 2026-11-03), and
;;;; the stock and polyfilled worlds use two private Quicklisps, since a
;;;; home that once took the dist keeps it.
;;;;
;;;; The lib-world is "<dist> + polyfill-dotcl <vendor dist version>+<version>.<hash>".

(:lisp "dotcl"
 :version "2026-11-03"
 :feature :dotcl
 :vendor-dist "https://dotcl.github.io/dist/dotcl.txt"
 :stock-forms ("(defpackage \"QL-SETUP\" (:use \"CL\"))"
               "(defvar ql-setup::*offer-dotcl-dist* nil)"
               "(defvar ql-setup::*use-dist-packages* nil)")
 :note "The author's dist (2026-10-27: patched cffi, usocket, babel, flexi-streams, trivial-gray-streams, ..., and the 2026 zacl and aserve) is the base; dotcl's own fixes live in dotcl, not in libraries."
 :entries
 (;; --- candidates without a public home yet (listed, not built) ---
  (:project "lift" :source nil :commit "/projects/tmp/dotcl-work/polyfills/lift-dotcl-backtrace.patch against hraban/lift a7941845"
   :why "LIFT has no get-backtrace-as-string for dotcl, so a LIFT run aborts with UNDEFINED-FUNCTION at the first test that signals instead of recording the failure; the patch adds the #+dotcl arm calling (dotcl:print-backtrace stream); proven on 0.1.36" :upstream :not-submitted
   :retire-when "LIFT upstream, or the author's dist, carries a #+dotcl arm")))
