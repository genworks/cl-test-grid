;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; Copyright (C) 2011 Anton Vodonosov (avodonosov@yandex.ru)
;;;; See LICENSE for details.

(in-package #:test-grid-reporting)

(defun result-spec-test (result)
  "Consider result-spec as a pair of test and outcome.
For example (:load \"some-system\" :ok),
here (:load \"some-system\") is the test and :ok is the outcome.
Or (:whole-test-suite :ok) - :whole-test-suite is a test
and :ok is an outcome.

Returns test part of the result-spec."

  (case (car (result-spec result))
    (:whole-test-suite :whole-test-suite)
    (otherwise (subseq (result-spec result) 0 2)))

  ;; TODO: the result-spec syntax is irregular
  ;; because test is sometime specified by two values -
  ;; (:load "some-system"), and sometimes just as
  ;; :whole-test-suite. For better regularity
  ;; it would be good to add test suite name
  ;; (actuall the project name, because
  ;; we merge all the test suites of a project
  ;; into a single testsuite).
  ;;
  ;; In short. Consider changing
  ;; (:whole-test-site :ok) to
  ;; (:whole-test-suite :alexandria :ok).
  )

(defun print-quicklisp-diff-report (report-file
                                    all-results
                                    old-quicklisp
                                    new-quicklisp)
  (multiple-value-bind (diff compared)
      (quicklisp-diff-items all-results old-quicklisp new-quicklisp)
    (my-time ("print-pivot...")
      (print-pivot report-file
                   diff
                   :rows '((lisp string<) (libname string<))
                   :cols `((lib-world ,(tg-utils::ordering-comparator (list old-quicklisp new-quicklisp) #'string=)))
                   :cell-printer #'results-cell-printer
                   :note (diff-note old-quicklisp new-quicklisp diff compared)))))
