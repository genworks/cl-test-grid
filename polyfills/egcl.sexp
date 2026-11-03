;;;; -*- Mode: LISP; Syntax: COMMON-LISP; coding: utf-8 -*-
;;;;
;;;; Polyfill manifest for EGCL (Evergreen Common Lisp): the Quicklisp
;;;; projects that need a patched source on this lisp until the stock
;;;; release works there.  build-polyfill-dist.lisp turns it into a
;;;; Quicklisp dist on the agent host; the agent installs that dist over
;;;; the stock one and tests the lisp on both, so each entry's
;;;; :retire-when is checked by the reports every run (polyfills/<lisp>.html).
;;;;
;;;; Every entry is temporary by construction.  :commit is a pinned
;;;; revision, never a branch, so a dist version is reproducible; bump
;;;; :version when entries change.  :source nil marks a candidate with
;;;; no public home yet: listed, not built.
;;;;
;;;; Sources: Anthony Green's tested inventory in atgreen/evergreen
;;;; (docs/library-forks.md, tests/audited-forks/forks.json; read
;;;; 2026-11-03 at main e28940db), and Genworks' own forks.  Green's doc:
;;;; publishing to the atgreen forks is authorized, upstream submissions
;;;; are not yet -- so :upstream is :not-submitted throughout.

(:lisp "egcl"
 :version "2026-11-03"
 :feature :egcl
 :note "Green's forks pinned at the revisions tested for Evergreen 0.0.12; zacl and zaserve from the live Genworks forks."
 :entries
 (;; --- the portability layer ---
  (:project "trivial-features" :source "https://github.com/atgreen/trivial-features" :commit "651e8ea90db0b143d39b9a414ee382ec62efad2f"
   :why "EGCL's feature set" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "trivial-gray-streams" :source "https://github.com/atgreen/trivial-gray-streams" :commit "e3c675548a9d935fc40860349ed984687c75abe0"
   :why "Gray streams on EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "usocket" :source "https://github.com/atgreen/usocket" :commit "1318d92e817a8912e86233444af63038f37bf621"
   :why "an EGCL backend (binary TCP client and server subset); branch egcl-support" :upstream :not-submitted
   :retire-when "the stock release loads on egcl and zaserve's smoke test answers")
  (:project "trivial-cltl2" :source "https://github.com/atgreen/trivial-cltl2" :commit "cf3253050711277e847a9dc445a45fa7170dc9cb"
   :why "EGCL's environment access" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "trivial-garbage" :source "https://github.com/atgreen/trivial-garbage" :commit "3c4f9c86d4d3454dcd4f8d19113b4101c3add032"
   :why "finalizers and weak objects on EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "trivial-backtrace" :source "https://github.com/atgreen/trivial-backtrace" :commit "650da10abfe4b44c70b58a431aec6d9fe7330406"
   :why "EGCL backtraces" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "bordeaux-threads" :source "https://github.com/atgreen/bordeaux-threads" :commit "2f736ed7ef61d1856f2c6a5aefde9a5ee7b3b66f"
   :why "0.9.4 refuses EGCL at load ('This implementation is unsupported'); the port awaits Green's audit (bliss-59qu), so thread-heavy results are suspect" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "atomics" :source "https://github.com/atgreen/atomics" :commit "738ddccd7a6f3c44e83335ac5e3615e76972dfd2"
   :why "CAS operations on EGCL (ATOMIC-INCF/DECF still unsupported there)" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "cl-fad" :source "https://github.com/atgreen/cl-fad" :commit "6e415a049a2936e614f52108274d7cc016e55694"
   :why "environment lookup" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "precise-time" :source "https://github.com/atgreen/precise-time" :commit "045df7c4cddc84d775610cbecf47b462aaea29d6"
   :why "EGCL clock" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "closer-mop" :source "https://github.com/atgreen/closer-mop" :commit "72d078b5a59070c725232777b52164e111462846"
   :why "class, slot, generic-function and method introspection; callable instances" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "fset" :source "https://github.com/atgreen/fset" :commit "553d6a75f6520ef4435748f16b0f619e71988628"
   :why "EGCL arm" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "cffi" :source "https://github.com/atgreen/cffi" :commit "ee7e4ea5238efce6ce4be7d6f0f29699884ad791"
   :why "the EGCL foreign-function backend (cffi, cffi-grovel, cffi-toolchain, cffi-libffi, cffi-uffi-compat, uffi); needs the glibc egcl image, the musl one cannot dlopen" :upstream :not-submitted
   :retire-when "the stock release loads on egcl and cl+ssl loads over it")
  (:project "iolib" :source "https://github.com/atgreen/iolib" :commit "57bc68250f498d48a6d0a3d07ccd2b36b8a561ea"
   :why "iolib, iolib.base, iolib.conf on EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  ;; --- crypto and compression ---
  (:project "ironclad" :source "https://github.com/atgreen/ironclad" :commit "57db5ee19708a72b9b7a405e5b620bb39f7439b2"
   :why "native AES, GHASH and SHA-256 block functions (needs EGCL with PR #410)" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "chipz" :source "https://github.com/atgreen/chipz" :commit "a48e6e741a353a14ab4430eb1519e2f3d5b94aef"
   :why "decompressing streams on EGCL's Gray streams" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  ;; --- tooling ---
  (:project "slime" :source "https://github.com/atgreen/slime" :commit "69afcb088f6463850c532a2f573d9ec5d875fdb9"
   :why "swank's EGCL backend" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "sly" :source "https://github.com/atgreen/sly" :commit "e81f332eb458e33cd650f8601f655da58be18b98"
   :why "slynk's EGCL backend, moved out of lib/slynk/" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  ;; --- the audited set (branch egcl) ---
  (:project "archive" :source "https://github.com/atgreen/archive" :commit "3e500919b0226c10a848aefe8e57a8cff02b2a6b"
   :why "pathname metadata and stat accessors" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "zip" :source "https://github.com/atgreen/zip" :commit "6f3efd09130475bd43de6efc1f83da8dae0ac7b9"
   :why "native file permissions" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "unix-opts" :source "https://github.com/atgreen/unix-opts" :commit "07e240c4b1ac8d3ade055f770713c995f39b7c4d"
   :why "argv and exit status" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "with-user-abort" :source "https://github.com/atgreen/with-user-abort" :commit "9c0b83eb51cd8553d8b731eef5d6163eb82d0fc8"
   :why "interrupt condition" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "local-time" :source "https://github.com/atgreen/local-time" :commit "0ac828f4c978696298e41d1f86c8af923a240700"
   :why "subsecond wall clock" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "parachute" :source "https://github.com/atgreen/parachute" :commit "99ee47171ec686f7b1d80b1afcd588bb3ed300d5"
   :why "process exit status" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "alexandria" :source "https://github.com/atgreen/alexandria" :commit "ec09d2346f2314fe799cd76002e465b88623417d"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "babel" :source "https://github.com/atgreen/babel" :commit "75fc2911f83711278d1717e5786bbc7cc4a5da7c"
   :why "UTF-8 and Gray-stream output on EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "cl-interpol" :source "https://github.com/atgreen/cl-interpol" :commit "3326c4758ec7f07ed32667a0e82bf261d7b7130e"
   :why "audited for EGCL (cl-unicode's cold data generation times out there, bliss-ks0tt)" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "named-readtables" :source "https://github.com/atgreen/named-readtables" :commit "587960ee3b46e291723aba4bfa8ef74ebd86c151"
   :why "an EGCL readtable iterator (Green's; genworks/quicklisp 5442881b overlaps -- prefer his, and test)" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "cl-utilities" :source "https://github.com/atgreen/cl-utilities" :commit "ef354659a27dc903f638397526d47eab951a019e"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "esrap" :source "https://github.com/atgreen/esrap" :commit "b77d22cbcf49eb8d8b50c64b304d906df315fd7b"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "global-vars" :source "https://github.com/atgreen/global-vars" :commit "cd58cd24bca9615cacdbd54201e3213020b84e86"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "iterate" :source "https://github.com/atgreen/iterate" :commit "73bcbed445417d8b746b0b41b945edd73f48d415"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "split-sequence" :source "https://github.com/atgreen/split-sequence" :commit "289ad9090c45d1eedc0f85e812a615ae8dca8e16"
   :why "audited for EGCL (the stock release's fuzz test runs past the 15-minute limit there)" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl within the limit")
  (:project "string-case" :source "https://github.com/atgreen/string-case" :commit "5f26c530c1bf3d59896516610161d3112929b92e"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "cl-json" :source "https://github.com/atgreen/cl-json" :commit "ec31cbb368ada69444d6fce7d2ef64f97ceb43c8"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "drakma" :source "https://github.com/atgreen/drakma" :commit "d94490cfc29a9822e77fe7baded9f17cfa5c13d3"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "puri" :source "https://github.com/atgreen/puri" :commit "d5c83b66a09cda3dfb79f1f0009017920b87b519"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "quri" :source "https://github.com/atgreen/quri" :commit "93872698b99965b28b63b707e83f99d5cfee55cc"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "trivial-custom-debugger" :source "https://github.com/atgreen/trivial-custom-debugger" :commit "8a35b1980298c3fdf88628129217d945e3c5abd8"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "trivial-file-size" :source "https://github.com/atgreen/trivial-file-size" :commit "a897f75c4ded70249e1a694f38ca45a68d8de492"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "rt" :source "https://github.com/atgreen/rt" :commit "b7bf6c2025541eb7ba3b68ab399d972365fc65c2"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "parse-declarations" :source "https://github.com/atgreen/parse-declarations" :commit "c07a536a11de5321c1cf50c5aba883cbf4950b6a"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "lift" :source "https://github.com/atgreen/lift" :commit "3a940176d0925aaabfd7e443e687a50c4cdb0b77"
   :why "audited for EGCL (the test harness behind Gendl's suite)" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "mgl-pax" :source "https://github.com/atgreen/mgl-pax" :commit "8b55f9ce85ab5a979985055595aeced454b0760c"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "introspect-environment" :source "https://github.com/atgreen/introspect-environment" :commit "1bcd945c2e2a6358557272886c03bd120ecc95f7"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "trivia" :source "https://github.com/atgreen/trivia" :commit "be03bc1ce6b6ad7217c4838a9ef0ea4b9d579d60"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "type-i" :source "https://github.com/atgreen/type-i" :commit "eb2335d44542febcfaaf91adf6d3522787f78f87"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "misc-extensions" :source "https://github.com/atgreen/misc-extensions" :commit "d401b504e55d396e8fa9df7fe9af4ae68651c301"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  (:project "serapeum" :source "https://github.com/atgreen/serapeum" :commit "43b66df1da96578efc90555d4fee1543590295e6"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads and its tests pass on egcl")
  (:project "trivial-macroexpand-all" :source "https://github.com/atgreen/trivial-macroexpand-all" :commit "594238e46b4fbcf5baa35b4e6b1bbb0d2e486f1a"
   :why "audited for EGCL" :upstream :not-submitted
   :retire-when "the stock release loads on egcl")
  ;; --- not Quicklisp projects today; carried so their systems resolve ---
  (:project "pure-tls" :source "https://github.com/atgreen/pure-tls" :commit "480bbab6635d65cb74aa6c66f19f0d249beeb537"
   :why "environment lookup, cached trust stores, native text conversion (not in the stock dist)" :upstream :not-submitted
   :retire-when "pure-tls enters Quicklisp and its release loads on egcl")
  ;; --- Genworks' own forks (public) ---
  (:project "zacl" :source "https://gitlab.common-lisp.net/dcooper/zacl.git" :commit "0aed92b"
   :why "the dist's zacl-20230618 predates the EGCL, ECL and dotcl ports (its MP package collides with ECL's; no EGCL arm)" :upstream "quicklisp-projects: the aserve and zacl sources point at the dead github.com/gendl repositories"
   :retire-when "Quicklisp's zacl source points at the live fork and the stock release loads on egcl")
  (:project "zaserve" :source "https://gitlab.common-lisp.net/dcooper/zaserve.git" :commit "7a3a9bb"
   :why "the dist's aserve-20230618 (project aserve, system zaserve) predates the ports" :upstream "quicklisp-projects: see zacl"
   :retire-when "Quicklisp's aserve source points at the live fork and the stock release loads on egcl")
  ;; --- candidates without a public home yet (listed, not built) ---
  (:project "cl-store" :source nil :commit "genworks/quicklisp 58143f47"
   :why "the stock release refuses EGCL; the port adds an egcl/ backend (slot introspection, structures, floats); zacl needs it" :upstream :not-submitted
   :retire-when "published somewhere public, then: the stock release loads and its tests pass on egcl")
  (:project "cl-pdf" :source nil :commit "genworks/quicklisp fc90a4ad"
   :why "EGCL missing from the per-implementation external-format table, so hyphenation files fail; one line, :latin-1 like every other lisp; cl-typesetting needs it" :upstream :not-submitted
   :retire-when "upstream (mbattyani/cl-pdf) carries the line, or a public fork does")))
