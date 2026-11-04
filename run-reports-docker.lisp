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
;;; Overlay lib-worlds on the index.  "<base> + <segment>": the segment
;;; is either "polyfill-<lisp> <version>" (a polyfilled dist) or the
;;; members of a branch set, "gendl@devo 594f2082+batten@devo 06d7ccd6".
;;; On the index a branch is one line, not a heading per commit: the
;;; latest commit per base, a diff link each, and the project's library
;;; page, where the branch worlds are columns beside the dist's.

(defun split-on (char string)
  (loop with start = 0
        for pos = (position char string :start start)
        collect (subseq string start pos)
        while pos
        do (setf start (1+ pos))))

(defun last-segment (lib-world)
  (let ((pos (search " + " lib-world :from-end t)))
    (and pos (subseq lib-world (+ pos 3)))))

(defun polyfill-world-p (lib-world)
  (let ((segment (last-segment lib-world)))
    (and segment
         (>= (length segment) 9)
         (string= "polyfill-" segment :end2 9))))

(defun branch-world-p (lib-world)
  (and (test-grid-reporting::overlay-lib-world-p lib-world)
       (not (polyfill-world-p lib-world))))

(defun branch-members (lib-world)
  "((project branch commit) ...) of a branch world's last segment."
  (loop for member in (split-on #\+ (last-segment lib-world))
        collect (let ((at (position #\@ member))
                      (space (position #\Space member)))
                  (list (subseq member 0 at)
                        (subseq member (1+ at) space)
                        (subseq member (1+ space))))))

(defun branch-key (lib-world)
  "The set without its commits: gendl@devo+batten@devo."
  (format nil "~{~A~^+~}"
          (mapcar (lambda (m) (format nil "~A@~A" (first m) (second m)))
                  (branch-members lib-world))))

(defun branch-commits (lib-world)
  (format nil "~{~A~^+~}" (mapcar #'third (branch-members lib-world))))

(defun polyfill-world-lisp (lib-world)
  "egcl for \"... + polyfill-egcl 2026-11-03.c16adc\"."
  (let ((segment (last-segment lib-world)))
    (subseq segment 9 (position #\Space segment))))

(defun diff-link (lib-world)
  (format nil "overlays/~A-diff.html" (test-grid-reporting::file-safe-name lib-world)))

(defun latest-lib-world (lib-worlds latest-time)
  "The lib-world among LIB-WORLDS with the newest run."
  (first (sort (copy-list lib-worlds) #'>
               :key (lambda (lw) (gethash lw latest-time 0)))))

(defun branches-html (lib-worlds latest-time)
  "The Branches under test section, or nil when there are none."
  (let ((groups (make-hash-table :test 'equal))   ; key -> (base -> worlds)
        (keys '()))
    (dolist (lw lib-worlds)
      (when (branch-world-p lw)
        (let ((key (branch-key lw))
              (base (test-grid-reporting::overlay-base lw)))
          (unless (gethash key groups)
            (setf (gethash key groups) (make-hash-table :test 'equal))
            (push key keys))
          (push lw (gethash base (gethash key groups))))))
    (when keys
      (with-output-to-string (out)
        (format out "<h2>Branches under test</h2>
<p>A branch of a project's repository tested in place of the dist's
release of it, on every implementation.  Its results are columns on the
project's library page beside the dist's; each line below is the latest
commit tested on each lib-world, with the diff against that lib-world.
A new commit on the branch is tested afresh and replaces the previous one here.</p>
<ul>~%")
        (dolist (key (sort keys #'string<))
          (let* ((by-base (gethash key groups))
                 (bases (sort (loop for base being the hash-keys of by-base collect base)
                              #'string<))
                 (projects (mapcar #'first (branch-members (first (gethash (first bases) by-base))))))
            (format out "  <li><b>~A</b>" key)
            (format out "~{ &mdash; <a href=\"library/~(~A~).html\">~:*~A</a>~}"
                    (remove-if-not (lambda (p)
                                     (probe-file (merge-pathnames (format nil "library/~(~A~).html" p)
                                                                  *reports-dir*)))
                                   projects))
            (format out "~%    <ul>~%")
            (dolist (base bases)
              (let* ((worlds (gethash base by-base))
                     (latest (latest-lib-world worlds latest-time))
                     (earlier (1- (length worlds))))
                (format out "      <li>on ~A: ~A (<a href=\"~A\">diff</a>~[~;, 1 earlier commit~:;, ~:*~D earlier commits~])</li>~%"
                        base (branch-commits latest) (diff-link latest) earlier)))
            (format out "    </ul></li>~%")))
        (format out "</ul>~%")))))

(defun polyfills-html (lib-worlds latest-time)
  "The Polyfills section, or nil when no manifest was reported on."
  (let ((summaries (polyfill-summaries)))
    (when summaries
      (with-output-to-string (out)
        (format out "<h2>Polyfills</h2>
<p>The projects an implementation still needs a patched source for: each
is tested on the stock dist and on the dist with the polyfill installed,
and an entry is retirable once the stock release passes.  The number to
watch is the entries still needed.  The diff is the polyfilled dist
against the stock one, on that implementation.</p>
<ul>~%")
        (dolist (summary summaries)
          (let* ((lisp (getf summary :lisp))
                 (worlds (remove-if-not (lambda (lw)
                                          (and (polyfill-world-p lw)
                                               (string= (polyfill-world-lisp lw) lisp)))
                                        lib-worlds))
                 (latest (and worlds (latest-lib-world worlds latest-time))))
            (format out "  <li><a href=\"~A\">~A</a>: ~D entries, ~D still needed, ~D retirable, ~D untested, ~D without a public source~@[ (<a href=\"~A\">diff</a>)~]</li>~%"
                    (getf summary :file) lisp
                    (getf summary :entries) (getf summary :needed) (getf summary :retirable)
                    (getf summary :untested) (getf summary :candidates)
                    (and latest (diff-link latest)))))
        (format out "</ul>~%")))))

(defun write-index ()
  (let* ((db (tg-storage:data *replica*))
         (runs (getf db :runs))
         (latest-time (make-hash-table :test 'equal))
         (all-lib-worlds (remove-duplicates
                          (mapcar (lambda (run) (getf (getf run :descr) :lib-world)) runs)
                          :test #'string=))
         (lib-worlds (sort (remove-if #'test-grid-reporting::overlay-lib-world-p all-lib-worlds)
                           #'string>))
         (lisps (sort (remove-duplicates
                       (mapcar (lambda (run) (getf (getf run :descr) :lisp)) runs)
                       :test #'string=)
                      #'string<)))
    (dolist (run runs)
      (let* ((descr (getf run :descr))
             (lib-world (getf descr :lib-world)))
        (setf (gethash lib-world latest-time)
              (max (gethash lib-world latest-time 0)
                   (or (getf descr :time) 0)))))
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
~@[~A~]~@[~A~]<h2>In the database</h2>
<p>~A test runs, Quicklisp versions:~{ ~A~^,~}.</p>
<p>Implementations:</p>
<ul>~{
  <li>~A</li>~}
</ul>
<p>Regenerated ~A.</p>
</body>
</html>
"
              (branches-html all-lib-worlds latest-time)
              (polyfills-html all-lib-worlds latest-time)
              (length runs) lib-worlds lisps
              (multiple-value-bind (s m h day month year) (decode-universal-time (get-universal-time) 0)
                (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D UTC" year month day h m s))))))

(write-index)

(format t "~&Reports written to ~A~%" *reports-dir*)
