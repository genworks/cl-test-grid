;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Starts the test grid server and keeps the process running.
;;;; Quicklisp must be loaded first, for example:
;;;;
;;;;   sbcl --non-interactive --load ~/quicklisp/setup.lisp --load server/run-server.lisp
;;;;
;;;; The settings come from the environment; see the docstring of
;;;; TG-SERVER:MAIN.  server/Dockerfile builds an image instead.

(let ((src-dir (merge-pathnames "../" (make-pathname :name nil :type nil
                                                     :defaults *load-truename*))))
  (pushnew (truename src-dir) asdf:*central-registry* :test #'equal))

(ql:quickload :test-grid-server)

(funcall (read-from-string "tg-server:main"))
