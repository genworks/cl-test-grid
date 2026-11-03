;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Builds a Quicklisp dist from a polyfill manifest (polyfills/<lisp>.sexp),
;;;; on this host, for the agent: each entry's source is checked out at
;;;; its pinned commit, archived, and indexed, and the result is a
;;;; complete dist (distinfo.txt, releases.txt, systems.txt, archives/)
;;;; that Quicklisp's client installs from file:// URLs (see
;;;; agent/proc-install-dist.lisp for the file scheme).  Nothing is
;;;; served: the agent host builds the same bytes from the same commits
;;;; wherever it runs.
;;;;
;;;; The dist is named polyfill-<lisp> and versioned
;;;; "<manifest :version>.<6 hex of the manifest file's sha1>", so an
;;;; edited manifest is a new version (a new lib-world for the agent),
;;;; and an unchanged one is reused from disk.
;;;;
;;;; Needs git, tar, gzip, sha1sum and md5sum (the clfoundation/ccl
;;;; image has them).

(defpackage :tg-polyfill
  (:use :cl)
  (:export #:read-manifest
           #:manifest-version
           #:dist-name
           #:buildable-entries
           #:build-dist
           #:asd-files
           #:read-asd-systems))

(in-package :tg-polyfill)

(defun read-manifest (file)
  (with-open-file (in file)
    (let ((*read-eval* nil)
          ;; keywords read as keywords, NIL as NIL
          (*package* (find-package :cl-user)))
      (read in))))

(defun run (command &key directory)
  "Runs COMMAND (a list), returning its output as a string without the trailing newline."
  (string-right-trim '(#\Newline #\Return)
                     (uiop:run-program command :output :string :error-output :output
                                       :directory directory)))

(defun sha1-of-file (file)
  (subseq (run (list "sha1sum" (namestring file))) 0 40))

(defun md5-of-file (file)
  (subseq (run (list "md5sum" (namestring file))) 0 32))

(defun file-size (file)
  (with-open-file (in file :element-type '(unsigned-byte 8))
    (file-length in)))

(defun dist-name (manifest)
  (format nil "polyfill-~A" (getf manifest :lisp)))

(defun manifest-version (manifest-file manifest)
  (format nil "~A.~A" (getf manifest :version) (subseq (sha1-of-file manifest-file) 0 6)))

(defun buildable-entries (manifest)
  "The entries with a public source; the others are candidates, listed by the reports only."
  (remove-if-not (lambda (entry) (getf entry :source)) (getf manifest :entries)))

;;; Checkouts.  A full clone, kept between runs under src/<project>/,
;;; because a pinned commit is an abbreviated SHA and git can fetch
;;; only full ones by name; the checkout is detached at the commit.

(defun ensure-checkout (entry src-dir)
  "Returns the checkout directory of ENTRY at its commit, and the commit's 8-character form."
  (let* ((project (getf entry :project))
         (dir (merge-pathnames (format nil "~A/" project) src-dir))
         (commit (getf entry :commit)))
    (flet ((git (&rest args)
             (run (list* "git" "-C" (namestring dir) args)))
           (has-commit-p ()
             (zerop (nth-value 2 (uiop:run-program (list "git" "-C" (namestring dir) "cat-file" "-e"
                                                         (format nil "~A^{commit}" commit))
                                                   :ignore-error-status t :output nil :error-output nil)))))
      (unless (probe-file (merge-pathnames ".git/" dir))
        (ensure-directories-exist dir)
        (format t "~&  cloning ~A from ~A~%" project (getf entry :source))
        (finish-output)
        (run (list "git" "clone" "--quiet" "--no-checkout" (getf entry :source) (namestring dir))))
      (unless (has-commit-p)
        (git "fetch" "--quiet" "--all")
        (unless (has-commit-p)
          ;; a commit no branch or tag reaches any more (a force-push
          ;; behind it): GitHub still serves it by its full SHA
          (unless (= 40 (length commit))
            (error "~A: commit ~A is not on any branch of ~A, and only a full SHA can be fetched by name"
                   project commit (getf entry :source)))
          (git "fetch" "--quiet" "origin" commit)
          (unless (has-commit-p)
            (error "~A: commit ~A is not in ~A" project commit (getf entry :source)))))
      (git "checkout" "--quiet" "--force" "--detach" commit)
      (git "clean" "-fdxq")
      (values dir (git "rev-parse" "--short=8" "HEAD")))))

;;; The system index, read from the .asd files without evaluating them.

(defun asd-files (dir)
  (sort (remove-if (lambda (p) (search "/.git/" (namestring p)))
                   (directory (merge-pathnames "**/*.asd" dir)))
        #'string< :key #'namestring))

(defun dependency-name (spec)
  (typecase spec
    ((or string symbol) (string-downcase (string spec)))
    (cons (case (first spec)
            (:version (dependency-name (second spec)))
            (:feature (dependency-name (third spec)))
            (t nil)))))

(defun read-asd-systems (asd-file feature &optional fallback)
  "Returns ((system-name dependency-name...)...) for the DEFSYSTEM forms of
ASD-FILE, read with FEATURE among *FEATURES* and nothing evaluated.  A
file the reader cannot take (#. at top level, a package of its own)
gets FALLBACK, the stock dist's index lines for that system file, or
its name as a system without dependencies; Quicklisp finds the rest at
load time."
  (let ((*package* (or (find-package :asdf-user) (find-package :cl-user)))
        (*read-eval* nil)
        (*features* (adjoin feature *features*))
        (systems '()))
    (handler-case
        (with-open-file (in asd-file)
          (loop for form = (read in nil in)
             until (eq form in)
             do (when (and (consp form)
                           (symbolp (first form))
                           (string-equal (symbol-name (first form)) "DEFSYSTEM")
                           (cdr form))
                  (let* ((name (string-downcase (string (second form))))
                         (options (cddr form))
                         (deps (append (and (listp (getf options :depends-on)) (getf options :depends-on))
                                       (and (listp (getf options :defsystem-depends-on)) (getf options :defsystem-depends-on)))))
                    (push (cons name (remove-duplicates (remove nil (mapcar #'dependency-name deps))
                                                        :test #'string=))
                          systems)))))
      (error (e)
        (setf systems (or fallback (list (list (pathname-name asd-file)))))
        (format t "~&  ~A: not readable (~A); ~:[listed without dependencies~;the stock dist's index lines used~]~%"
                (file-namestring asd-file)
                (let ((text (princ-to-string e))) (subseq text 0 (min 80 (length text))))
                fallback)))
    (nreverse systems)))

;;; The stock dist's systems.txt, as a fallback for the .asd files the
;;; reader cannot take: project -> system-file -> ((system dep...)...)

(defun read-stock-index (systems-file)
  (let ((index (make-hash-table :test 'equal)))
    (when (and systems-file (probe-file systems-file))
      (with-open-file (in systems-file)
        (loop for line = (read-line in nil)
           while line
           unless (or (zerop (length line)) (char= #\# (char line 0)))
           do (let ((fields (uiop:split-string line :separator " ")))
                (when (>= (length fields) 3)
                  (push (cons (third fields) (cdddr fields))
                        (gethash (cons (first fields) (second fields)) index)))))))
    index))

(defun stock-fallback (index project asd-file)
  (gethash (cons project (pathname-name asd-file)) index))

;;; Archives: GNU tar with every source of variation pinned, so a
;;; rebuilt release has the same checksums.

(defun make-archive (checkout prefix archives-dir)
  (let ((tgz (merge-pathnames (format nil "~A.tgz" prefix) archives-dir)))
    (ensure-directories-exist tgz)
    (run (list "sh" "-c"
               (format nil "tar --format=ustar --exclude=.git --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --transform 's,^\\./,~A/,' -cf - -C ~A . | gzip -n > ~A"
                       prefix (namestring checkout) (namestring tgz))))
    tgz))

(defun relative-namestring (file dir)
  (enough-namestring file dir))

(defun build-dist (manifest-file out-dir &key stock-systems-file)
  "Builds the dist of MANIFEST-FILE under OUT-DIR (src/ for the checkouts,
<version>/ for the dist) unless that version is there already.
STOCK-SYSTEMS-FILE is the stock dist's systems.txt, whose lines stand
in for a system file the reader cannot take.  Returns the distinfo
file's file:// URL, the version and the dist name."
  (let* ((manifest (read-manifest manifest-file))
         (name (dist-name manifest))
         (version (manifest-version manifest-file manifest))
         (feature (getf manifest :feature))
         (stock-index (read-stock-index stock-systems-file))
         (src-dir (merge-pathnames "src/" out-dir))
         (dist-dir (merge-pathnames (format nil "~A/" version) out-dir))
         (archives-dir (merge-pathnames "archives/" dist-dir))
         (distinfo (merge-pathnames "distinfo.txt" dist-dir))
         (url (lambda (file) (format nil "file://~A" (namestring file)))))
    (cond
      ((probe-file distinfo)
       (format t "~&Polyfill dist ~A ~A is built already.~%" name version))
      (t
       (format t "~&Building polyfill dist ~A ~A from ~A (~A entries)~%"
               name version manifest-file (length (buildable-entries manifest)))
       (finish-output)
       (ensure-directories-exist archives-dir)
       (let ((releases '())
             (systems '()))
         (dolist (entry (buildable-entries manifest))
           (multiple-value-bind (checkout commit) (ensure-checkout entry src-dir)
             (let* ((project (getf entry :project))
                    (prefix (format nil "~A-~A-polyfill" project commit))
                    (tgz (make-archive checkout prefix archives-dir))
                    (asds (asd-files checkout)))
               (push (format nil "~A ~A ~D ~A ~A ~A~{ ~A~}"
                             project (funcall url tgz) (file-size tgz) (md5-of-file tgz) (sha1-of-file tgz)
                             prefix (mapcar (lambda (asd) (relative-namestring asd checkout)) asds))
                     releases)
               (dolist (asd asds)
                 (dolist (system (read-asd-systems asd feature (stock-fallback stock-index project asd)))
                   (push (format nil "~A ~A ~A~{ ~A~}" project (pathname-name asd) (first system) (rest system))
                         systems)))
               (format t "~&  ~A at ~A: ~D system file~:P~%" project commit (length asds))
               (finish-output))))
         (with-open-file (out (merge-pathnames "releases.txt" dist-dir) :direction :output :if-exists :supersede)
           (format out "# project url size file-md5 content-sha1 prefix [system-file1..system-fileN]~%~{~A~%~}"
                   (nreverse releases)))
         (with-open-file (out (merge-pathnames "systems.txt" dist-dir) :direction :output :if-exists :supersede)
           (format out "# project system-file system-name [dependency1..dependencyN]~%~{~A~%~}"
                   (nreverse systems)))
         (with-open-file (out distinfo :direction :output :if-exists :supersede)
           (format out "name: ~A~%version: ~A~%system-index-url: ~A~%release-index-url: ~A~%archive-base-url: ~A~%canonical-distinfo-url: ~A~%distinfo-subscription-url: ~A~%"
                   name version
                   (funcall url (merge-pathnames "systems.txt" dist-dir))
                   (funcall url (merge-pathnames "releases.txt" dist-dir))
                   (funcall url archives-dir)
                   (funcall url distinfo)
                   (funcall url distinfo))))
       (format t "~&Built ~A ~A in ~A~%" name version dist-dir)))
    (values (funcall url distinfo) version name)))
