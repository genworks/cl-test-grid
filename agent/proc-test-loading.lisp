;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; Copyright (C) 2011 Anton Vodonosov (avodonosov@yandex.ru)
;;;; See LICENSE for details.

;;;; This file is loaded into a child lisp process to test
;;;; whether particular ASDF system can be quickloaded on
;;;; this lisp implementation.

(in-package :cl-user)

;;; Configure away the normal ASDF source registry, so we only use Quicklisp.
(asdf:initialize-source-registry `(:source-registry :ignore-inherited-configuration))

(defun system-project (name)
  "The project NAME belongs to: its release's in the dist, or its
primary system's name for one the dist does not know (local-projects)."
  (let ((system (ignore-errors (ql-dist:find-system name))))
    (string-downcase (if system
                         (ql-dist:name (ql-dist:release system))
                         (asdf:primary-system-name name)))))

(defun loaded-projects (systems-before system-name)
  "The projects of the systems ASDF has loaded since SYSTEMS-BEFORE,
other than SYSTEM-NAME's own project: what the load pulled in."
  (let ((own (system-project system-name))
        (projects '()))
    (dolist (name (set-difference (asdf:already-loaded-systems) systems-before :test #'string=))
      (let ((project (system-project name)))
        (unless (string= project own)
          (pushnew project projects :test #'string=))))
    (sort projects #'string<)))

(defun test-loading (system-name)
  (let* ((before (asdf:already-loaded-systems))
         (status (wrap-status
                   (ql:quickload system-name :verbose t)
                   :ok)))
    ;; what the load pulled in, on success or on the way to a failure
    (append status (list :loaded (ignore-errors (loaded-projects before system-name))))))

(defun test-loading-main (log-file system-name private-quicklisp-dir asdf-output-root-dir)
  (let ((quicklisp-output-dir (merge-pathnames (make-pathname :directory '(:relative "ql"))
                                               asdf-output-root-dir)))

    (add-asdf-output-translation private-quicklisp-dir quicklisp-output-dir))
  (capturing-io log-file
                (lambda ()
                  (let ((*package* (find-package :keyword)))
                    (format t "  *features*:        ~(~S~)~%" (sort (copy-list *features*) #'string<)))
                  (format t "  ASDF version:      ~A~%" (asdf:asdf-version))
                  (format t "============================================================~%~%")
                  (test-loading system-name))))
