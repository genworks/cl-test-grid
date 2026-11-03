;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Polyfill reports.  A polyfill manifest (polyfills/<lisp>.sexp) lists
;;;; the projects a lisp needs a patched source for, one pinned commit
;;;; each; the agent tests that lisp on the stock dist and on the dist
;;;; with the polyfill installed, as the lib-world
;;;; "<dist> + polyfill-<lisp> <version>" (run-agent-docker.lisp).
;;;; This report puts the two side by side for every entry and says
;;;; which entries the stock dist no longer needs: an entry is
;;;; RETIRABLE when every result for its project on that lisp, on the
;;;; newest stock dist, is a pass.  The manifest is meant to shrink to
;;;; nothing; the summary on the index page is the count still needed.

(in-package #:test-grid-reporting)

(defun polyfill-lib-world-p (lib-world)
  "A polyfilled lib-world, with or without an overlay on top."
  (search " + polyfill-" lib-world))

(defun plain-polyfill-lib-world-p (lib-world)
  "A polyfilled lib-world with nothing on top: its last segment is the polyfill."
  (let ((last-plus (search " + " lib-world :from-end t)))
    (and last-plus
         (string= "polyfill-" (subseq lib-world (+ last-plus 3) (min (length lib-world) (+ last-plus 3 9)))))))

(defun polyfill-lisp-name (lib-world)
  "\"quicklisp 2026-01-01 + polyfill-egcl 2026-11-03.8d1d0e\" => \"egcl\""
  (let* ((start (+ (polyfill-lib-world-p lib-world) (length " + polyfill-")))
         (end (position #\Space lib-world :start start)))
    (subseq lib-world start end)))

(defun read-polyfill-manifest (file)
  (with-open-file (in file)
    (let ((*read-eval* nil)
          (*package* (find-package :cl-user)))
      (read in))))

(defun polyfill-manifest-files ()
  (directory (merge-pathnames "polyfills/*.sexp" (asdf:system-source-directory :test-grid-reporting))))

(defun result-outcome (result)
  (car (last (result-spec result))))

(defun result-pass-p (result)
  (member (result-outcome result) '(:ok :known-fail)))

(defun lisp-named-p (result lisp-name)
  "RESULT comes from an implementation identifier of LISP-NAME (\"egcl-0.0.11-linux-x64\")."
  (let ((lisp (lisp result)))
    (and (> (length lisp) (length lisp-name))
         (string-equal lisp-name lisp :end2 (length lisp-name))
         (char= #\- (char lisp (length lisp-name))))))

(defun project-outcomes (results project)
  "(passes . total) of RESULTS for PROJECT."
  (let ((pass 0) (total 0))
    (dolist (result results)
      (when (string-equal project (symbol-name (libname result)))
        (incf total)
        (when (result-pass-p result) (incf pass))))
    (cons pass total)))

(defun outcomes-cell (outcomes)
  (if (zerop (cdr outcomes))
      "<td class=\"untested\">untested</td>"
      (format nil "<td class=\"~A\">~D / ~D</td>"
              (if (= (car outcomes) (cdr outcomes)) "ok" "fail")
              (car outcomes) (cdr outcomes))))

(defun html-escape (string)
  (with-output-to-string (out)
    (loop for c across (princ-to-string string)
       do (case c
            (#\< (write-string "&lt;" out))
            (#\> (write-string "&gt;" out))
            (#\& (write-string "&amp;" out))
            (#\" (write-string "&quot;" out))
            (t (write-char c out))))))

(defun polyfill-verdict (entry stock polyfilled)
  "One of :candidate (no public source), :retirable, :needed, :untested."
  (cond ((null (getf entry :source)) :candidate)
        ((zerop (cdr stock)) (if (zerop (cdr polyfilled)) :untested :needed))
        ((= (car stock) (cdr stock)) :retirable)
        (t :needed)))

(defun print-polyfill-report (manifest-file all-results newest-dist)
  "Writes polyfills/<lisp>.html; returns the summary plist for the index."
  (let* ((manifest (read-polyfill-manifest manifest-file))
         (lisp-name (getf manifest :lisp))
         (entries (getf manifest :entries))
         (lisp-results (subset all-results (lambda (r) (lisp-named-p r lisp-name))))
         (stock-results (subset lisp-results (lambda (r) (string= (lib-world r) newest-dist))))
         (polyfill-worlds (sort (distinct1 (subset lisp-results
                                                   (lambda (r) (and (plain-polyfill-lib-world-p (lib-world r))
                                                                    (string= lisp-name (polyfill-lisp-name (lib-world r))))))
                                           #'lib-world)
                                #'string>))
         (polyfill-world (first polyfill-worlds))
         (polyfill-results (if polyfill-world
                               (subset lisp-results (lambda (r) (string= (lib-world r) polyfill-world)))
                               '()))
         (verdicts '()))
    (with-report-file (out (format nil "polyfills/~A.html" (file-safe-name lisp-name)))
      (format out "<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\"/>
  <meta name=\"robots\" content=\"INDEX, NOFOLLOW\">
  <title>Polyfills for ~A</title>
  <link href=\"../style.css\" rel=\"stylesheet\"/>
  <style>
    table.polyfills { border-collapse: collapse; }
    table.polyfills th, table.polyfills td { border: 1px solid #ccc; padding: 2px 6px; vertical-align: top; }
    td.ok { background: #cfc; } td.fail { background: #fcc; } td.untested { color: #888; }
    td.retirable { background: #cfc; font-weight: bold; } td.needed { background: #ffd; }
    td.candidate { color: #888; } td.untested { color: #888; }
  </style>
</head>
<body>
<h1>Polyfills for ~A</h1>
<p>The Quicklisp projects ~A needs a patched source for today, from
<code>polyfills/~A.sexp</code> (manifest version ~A).  Each is tested on
the stock dist and on the dist with the polyfill installed; an entry is
<b>retirable</b> once its project passes on the stock dist.</p>
<p>Stock dist: <b>~A</b>.  Polyfilled: <b>~A</b>~@[ (diff against the dist: <a href=\"../overlays/~A-diff.html\">here</a>)~].</p>
<table class=\"polyfills\">
<tr><th>project</th><th>why</th><th>commit</th><th>upstream</th><th>stock</th><th>polyfilled</th><th>verdict</th><th>retire when</th></tr>
"
              (html-escape lisp-name) (html-escape lisp-name) (html-escape lisp-name) (html-escape lisp-name)
              (html-escape (getf manifest :version))
              (html-escape newest-dist)
              (if polyfill-world (html-escape polyfill-world) "no polyfilled run yet")
              (and polyfill-world (file-safe-name polyfill-world)))
      (dolist (entry entries)
        (let* ((project (getf entry :project))
               (stock (project-outcomes stock-results project))
               (polyfilled (project-outcomes polyfill-results project))
               (verdict (polyfill-verdict entry stock polyfilled)))
          (push verdict verdicts)
          (format out "<tr><td>~A</td><td>~A</td><td>~A</td><td>~A</td>~A~A<td class=\"~(~A~)\">~(~A~)</td><td>~A</td></tr>~%"
                  (html-escape project)
                  (html-escape (or (getf entry :why) ""))
                  (if (getf entry :source)
                      (format nil "<a href=\"~A\">~A</a>" (html-escape (getf entry :source)) (html-escape (getf entry :commit)))
                      (html-escape (or (getf entry :commit) "no public source")))
                  (html-escape (let ((u (getf entry :upstream))) (if (keywordp u) (string-downcase u) (or u ""))))
                  (outcomes-cell stock)
                  (outcomes-cell polyfilled)
                  verdict verdict
                  (html-escape (or (getf entry :retire-when) "")))))
      (format out "</table>
<p>~D entries: ~D still needed, ~D retirable, ~D untested, ~D candidates without a public source.</p>
</body>
</html>
"
              (length entries)
              (count :needed verdicts) (count :retirable verdicts) (count :untested verdicts) (count :candidate verdicts)))
    (list :lisp lisp-name
          :file (format nil "polyfills/~A.html" (file-safe-name lisp-name))
          :entries (length entries)
          :needed (count :needed verdicts)
          :retirable (count :retirable verdicts)
          :untested (count :untested verdicts)
          :candidates (count :candidate verdicts)
          :polyfill-world polyfill-world)))

(defun print-polyfill-reports (all-results newest-dist)
  "One page per manifest, and polyfills/summary.sexp for the index."
  (let ((summaries (loop for file in (polyfill-manifest-files)
                      collect (print-polyfill-report file all-results newest-dist))))
    (with-report-file (out "polyfills/summary.sexp")
      (let ((*print-case* :downcase))
        (prin1 summaries out)
        (terpri out)))
    summaries))
