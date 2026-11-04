;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; Copyright (C) 2011 Anton Vodonosov (avodonosov@yandex.ru)
;;;; See LICENSE for details.

(in-package #:test-grid-reporting)

(defun library-report (results libname &optional (reports-root-dir-relative-path "") exercises)
  (let* ((test-case-results (subset results (lambda (r)
                                              (eq :test-case (first (result-spec r)))))))
    (with-output-to-string (str)
      (let ((html-template:*string-modifier* #'cl:identity))
        (html-template:fill-and-print-template
         (src-file "library-report-template.html")
         (list :library-name (html-template:escape-string (string-downcase libname))
               :results-table (pivot-table-html4 results
                                                 :cols '((lib-world string<))
                                                 :rows '((lisp string<))
                                                 :cell-printer #'results-cell-printer)
               :resuts-by-testcases (cond ((not (member libname test-grid-testsuites:*all-libs*))
                                           "The library does not have a <a href=\"https://github.com/cl-test-grid/cl-test-grid#adding-testsuite-of-your-library\">testsuite adapter</a> for CL Test Grid.")
                                          ((null test-case-results)
                                           "There are no failed tescases.")
                                          (t (pivot-table-html4 test-case-results
                                                                :cols '((lib-world string>))
                                                                :rows `((,(lambda (r)
                                                                                  (format nil "~A"
                                                                                          (result-spec r)))
                                                                          string<))
                                                                :cell-printer (lambda (out cell-data)
                                                                                (results-cell-printer out cell-data #'lisp)))))
               :dependents (dependents-html libname)
               :exercised (exercised-html exercises)
               :time (test-grid-agent::pretty-fmt-time (get-universal-time))
               :reports-root-dir-relative-path reports-root-dir-relative-path)
         :stream str)))))

(defun print-library-index (libnames status-icon-input-by-lib lisp-count lib-world-count
                            &optional (usage (constantly nil)))
  "USAGE: a function of a libname returning a short string about how
used the library is, or NIL."
  (let* (;; part of the status icon for results
         ;; on a single lisp and a single lib-world
         (status-cell-height 1)
         (status-cell-width 30)
         ;; status icon dimensions
         (status-height (* status-cell-height lisp-count))
         (status-width (* status-cell-width lib-world-count)))
    (tg-rep/status-icon-png::statuses-png status-icon-input-by-lib
                                          libnames
                                          lisp-count
                                          lib-world-count
                                          (report-file "library/status-icons.png")
                                          :cell-width status-cell-width
                                          :cell-height status-cell-height)
    (let ((report
           (with-output-to-string (s)
             (format s "<html>~%")
             (format s "  <head>~%")
             (format s "    <meta charset=\"utf-8\"/>~%")
             (format s "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">~%")
             (format s "    <title>Library Reports | CL Test Grid</title>~%")
             (format s "    <style>~%")
             (format s "      .status {~%")
             (format s "        display: inline-block;~%")
             (format s "        height: ~Apx;~%" status-height)
             (format s "        width: ~Apx;~%" status-width)
             (format s "        background: url(status-icons.png);~%")
             (format s "        background-repeat: no-repeat;~%")
             (format s "        background-size: auto;~%")
             (format s "        margin-right: 0.5ex;~%")
             (format s "      }~%")
             (format s "      .usage { color: #666; font-size: 90%; margin-left: 1ex; }~%")
             (format s "    </style>~%")
             (format s "  </head>~%")
             (format s "  <body>~%")
             (format s "    <h2>Library Reports</h2>~%")
             (format s "    <p>Every library with results on the last two Quicklisp versions; beside each, how many projects of the dist depend on it and how many loads of other systems pulled it in.</p>~%")
             (format s "    <ol>~%")
             (my-time ("library index body")
               (let ((status-sprite-offset 0))
                 (dolist (libname libnames)
                   (format s "      <li>")
                   (format s " <a href=\"~(~a~).html\">" libname)
                   (format s "<span class=\"status\" style=\"background-position-y: -~Apx\"></span>"
                           status-sprite-offset)
                   (format s "~(~a~)</a>"libname)
                   (let ((note (funcall usage libname)))
                     (when (and note (plusp (length note)))
                       (format s "<span class=\"usage\">~A</span>" note)))
                   (format s "</li>~%")
                   (incf status-sprite-offset status-height))))
             (format s "    </ol>~%")
             (format s "  </body>~%")
             (format s "</html>~%"))))
      (save-report "library/index.html"
                   report))))

(defun print-library-reports (all-results)
  (let* ((last-quicklisps (sort (largest #'lib-world (dist-results all-results) :count 2)
                                #'string<))
         ;; the last two dists, and the overlays tested on them
         (recent-results (subset all-results
                                 (lambda (r)
                                   (let ((lib-world (lib-world r)))
                                     (member (if (overlay-lib-world-p lib-world)
                                                 (overlay-base lib-world)
                                                 lib-world)
                                             last-quicklisps
                                             :test #'string=)))))
         (results-by-libname (group-by recent-results '(libname)))
         (libnames (sort (distinct1 recent-results #'libname) #'string<))
         (lisps (sort (distinct1 recent-results #'lisp) #'string<))
         ;; what every load pulled in, over all results: a library is
         ;; exercised by loads of any lib-world
         (exercise-table (my-time ("exercise table") (exercise-table all-results)))
         (status-icon-input-by-lib (make-hash-table :test 'eq
                                                    :size (length libnames))))
    (dolist (libname libnames)
      (let ((lib-results (gethash `(,libname) results-by-libname)))
        (save-report (format nil "library/~(~A~).html" libname)
                     (library-report lib-results libname "../" (exercises exercise-table libname)))
        (setf (gethash libname status-icon-input-by-lib)
              (tg-rep/status-icon::status-icon-input lib-results
                                                     lisps
                                                     last-quicklisps))))
    (print-library-index libnames
                         status-icon-input-by-lib
                         (length lisps)
                         (length last-quicklisps)
                         (lambda (libname)
                           (let* ((dependents (and *dist-index-version*
                                                   (length (dependent-projects (string-downcase libname)))))
                                  (dependents (and dependents (plusp dependents) dependents))
                                  (exercised (length (exercises exercise-table libname))))
                             (format nil "~@[~D dependent~:P~]~:[~;, ~]~[~:;~:*pulled in by ~D load~:P~]"
                                     dependents (and dependents (plusp exercised)) exercised))))))

