;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Regenerates the reports from the "main" test results storage:
;;;; syncs a local replica of it, then writes every report that
;;;; test-grid-reporting::generate-reports produces, plus the static
;;;; files the reports need and an index page, into one directory
;;;; that a web server publishes.  run-reports-docker.sh runs this
;;;; file in a container; it can also be loaded into a CCL or SBCL
;;;; that has Quicklisp.
;;;;
;;;; Settings, from the environment:
;;;;
;;;;   TEST_GRID_REPORTS_DIR    required: where the reports go (the
;;;;                            web server's directory)
;;;;   TEST_GRID_WORK_DIR       the replica snapshot and the Quicklisp
;;;;                            used to load the reporting code; the
;;;;                            default is work-dir/reports/ beside this
;;;;                            file
;;;;   CL_TEST_GRID_STORE_URL   the storage server; the default is the
;;;;                            public one

(defparameter *this-dir*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun env (name &optional default)
  (let ((value #+ccl (ccl:getenv name)
               #+sbcl (sb-ext:posix-getenv name)
               #-(or ccl sbcl) (error "env is written for CCL and SBCL")))
    (if (and value (plusp (length value)))
        value
        default)))

(defun as-directory (string)
  (pathname (if (char= #\/ (char string (1- (length string))))
                string
                (concatenate 'string string "/"))))

(defparameter *work-dir*
  (let ((dir (env "TEST_GRID_WORK_DIR")))
    (if dir
        (as-directory dir)
        (merge-pathnames "work-dir/reports/" *this-dir*))))

(defparameter *reports-dir*
  (as-directory (or (env "TEST_GRID_REPORTS_DIR")
                    (error "TEST_GRID_REPORTS_DIR is not set"))))

(ensure-directories-exist *work-dir*)
(ensure-directories-exist *reports-dir*)

;; Quicklisp for the reporting code itself, kept in the work directory
(load (merge-pathnames "agent/require-quicklisp.lisp" *this-dir*))
(tg-require-quicklisp:require :agent-work-dir *work-dir*)

(let ((asdf:*central-registry* (cons *this-dir* asdf:*central-registry*)))
  (ql:quickload '(:test-grid-storage :test-grid-reporting)))

;;; The replica of "main", synced incrementally; the snapshot stays in
;;; the work directory between runs, so a daily run fetches only the
;;; new transactions.
(format t "~&Syncing the replica of \"main\" from ~A ...~%" tg-utils:*store-url*)
(finish-output)
(defparameter *replica* (tg-storage:get-replica "main" :snapshot-directory *work-dir*))
(tg-storage:sync *replica*)
(format t "~&Replica at version ~A, ~A test runs.~%"
        (tg-storage:version *replica*)
        (length (getf (tg-storage:data *replica*) :runs)))
(finish-output)

;;; The static files the reports link to (style sheet, scripts, the
;;; old all-pivots page), kept in reports-generated/ in the source
;;; tree.  index.html is not among them: it is written below.
(defun copy-directory-tree (from to)
  (ensure-directories-exist to)
  (dolist (file (uiop:directory-files from))
    (uiop:copy-file file (merge-pathnames (file-namestring file) to)))
  (dolist (subdir (uiop:subdirectories from))
    (copy-directory-tree subdir
               (merge-pathnames (make-pathname :directory (list :relative
                                                                (car (last (pathname-directory subdir)))))
                                to))))

(let ((static-dir (merge-pathnames "reports-generated/" *this-dir*)))
  (dolist (name '("style.css" "testgrid-lib.js" "jquery.thead-1.1.min.js" "testsuites-pivots.html"))
    (uiop:copy-file (merge-pathnames name static-dir)
                    (merge-pathnames name *reports-dir*)))
  (copy-directory-tree (merge-pathnames "tablesorter/" static-dir)
                       (merge-pathnames "tablesorter/" *reports-dir*)))

;;; The reports
(setf test-grid-reporting::*reports-dir* *reports-dir*)
(test-grid-reporting::generate-reports (tg-storage:data *replica*))

(defun polyfill-summaries ()
  "What generate-reports wrote about the polyfill manifests, for the index."
  (let ((file (merge-pathnames "polyfills/summary.sexp" *reports-dir*)))
    (when (probe-file file)
      (with-open-file (in file)
        (let ((*read-eval* nil)
              (*package* (find-package :cl-user)))
          (read in nil nil))))))

;;; An index page pointing at them
(defun write-index ()
  (let* ((db (tg-storage:data *replica*))
         (runs (getf db :runs))
         (all-lib-worlds (remove-duplicates
                          (mapcar (lambda (run) (getf (getf run :descr) :lib-world)) runs)
                          :test #'string=))
         (lib-worlds (sort (remove-if #'test-grid-reporting::overlay-lib-world-p all-lib-worlds)
                           #'string>))
         (overlays (sort (remove-if-not #'test-grid-reporting::overlay-lib-world-p all-lib-worlds)
                         #'string<))
         (lisps (sort (remove-duplicates
                       (mapcar (lambda (run) (getf (getf run :descr) :lisp)) runs)
                       :test #'string=)
                      #'string<)))
    (with-open-file (out (merge-pathnames "index.html" *reports-dir*)
                         :direction :output :if-exists :supersede
                         :external-format tg-utils:*utf-8-external-format*)
      (format out "<!DOCTYPE html>
<html>
<head>
  <meta charset=\"utf-8\"/>
  <meta name=\"robots\" content=\"INDEX, NOFOLLOW\">
  <title>CL Test Grid</title>
  <link href=\"style.css\" rel=\"stylesheet\"/>
</head>
<body>
<h1>CL Test Grid</h1>
<p>Collaborative testing of Common Lisp libraries: every Quicklisp
project, on every Common Lisp implementation the volunteer agents run.
The project: <a href=\"https://github.com/cl-test-grid/cl-test-grid\">cl-test-grid on GitHub</a>.</p>
<h2>Reports</h2>
<ul>
  <li><a href=\"quicklisp-diff.html\">Quicklisp diff</a>: what changed between the two latest Quicklisp versions</li>
  <li><a href=\"quicklisp-diff2.html\">Quicklisp diff, by library</a></li>
  <li><a href=\"test-runs-report.html\">Test runs</a>: every submitted run</li>
  <li><a href=\"library/\">Library reports</a>: one page per library, across implementations and Quicklisp versions</li>
  <li><a href=\"testsuites-pivots.html\">Pivot tables</a> of the test suite results</li>
  <li><a href=\"export.csv\">CSV export</a> of the test suite results</li>
</ul>
~:[~;<h2>Branches under test</h2>
<p>A branch of a project's repository tested in place of the dist's
release of it; each page is the diff against the lib-world under it.</p>
<ul>~:*~{
  <li><a href=\"overlays/~A-diff.html\">~A</a></li>~}
</ul>
~]~:[~;<h2>Polyfills</h2>
<p>The projects an implementation still needs a patched source for: each
is tested on the stock dist and on the dist with the polyfill installed,
and an entry is retirable once the stock release passes.  The number to
watch is the entries still needed.</p>
<ul>~:*~{
  <li><a href=\"~A\">~A</a>: ~D entries, ~D still needed, ~D retirable, ~D untested, ~D without a public source</li>~}
</ul>
~]<h2>In the database</h2>
<p>~A test runs, Quicklisp versions:~{ ~A~^,~}.</p>
<p>Implementations:</p>
<ul>~{
  <li>~A</li>~}
</ul>
<p>Regenerated ~A.</p>
</body>
</html>
"
              (loop for overlay in overlays
                 collect (test-grid-reporting::file-safe-name overlay)
                 collect overlay)
              (loop for summary in (polyfill-summaries)
                 collect (getf summary :file)
                 collect (getf summary :lisp)
                 collect (getf summary :entries)
                 collect (getf summary :needed)
                 collect (getf summary :retirable)
                 collect (getf summary :untested)
                 collect (getf summary :candidates))
              (length runs) lib-worlds lisps
              (multiple-value-bind (s m h day month year) (decode-universal-time (get-universal-time) 0)
                (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D UTC" year month day h m s))))))

(write-index)

(format t "~&Reports written to ~A~%" *reports-dir*)
