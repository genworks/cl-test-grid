;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Loaded by the agent into a child lisp, after the private
;;;; Quicklisp's setup.lisp, to install or remove a polyfill dist
;;;; (build-polyfill-dist.lisp) in that Quicklisp.
;;;;
;;;; The dist lives on this host, so its URLs are file://... .
;;;; Quicklisp's client fetches through QL-HTTP:*FETCH-SCHEME-FUNCTIONS*,
;;;; an alist from URL scheme to a function of (url file &key ...)
;;;; returning (values status pathname); http is its only entry, so
;;;; a file entry is added here.  Every release of the dist is fetched
;;;; and unpacked at install time, so the test children, which load
;;;; setup.lisp without this file, never have to fetch anything.

(defun polyfill-file-fetch (url file &key &allow-other-keys)
  ;; FETCH hands over the URL merged with its defaults, so a host
  ;; (src.quicklisp.org) sits between the scheme and the path
  (let ((path (subseq url (position #\/ url :start (length "file://")))))
    (ensure-directories-exist file)
    (uiop:copy-file path file)
    (values 200 (probe-file file))))

(defun ensure-file-scheme ()
  (let ((table (read-from-string "ql-http:*fetch-scheme-functions*")))
    (unless (assoc "file" (symbol-value table) :test #'string=)
      (push (cons "file" 'polyfill-file-fetch) (symbol-value table)))))

(defmacro fncall (funname &rest args)
  `(funcall (read-from-string ,funname) ,@args))

(defun remove-polyfill-dist (name)
  "Uninstalls the dist NAME if it is installed; returns whether it was."
  (let ((old (fncall "ql-dist:find-dist" name)))
    (when old
      (fncall "ql-dist:uninstall" old)
      t)))

;;; Prefetching.  Quicklisp's own client cannot download on every
;;; lisp (its network layer has no EGCL implementation, for one), and
;;; a lisp alone in its agent has nobody else fetching for it.  So the
;;; preferred lisp fetches and unpacks, ahead of a pass, every release
;;; the pass can need: the named projects' releases and their
;;; dependency closure, or the whole dist when the pass is the whole
;;; dist.  Plumbing, not the thing under test.

(defun release-closure (release-names)
  "The releases of RELEASE-NAMES and of every system they depend on, transitively."
  (let ((seen (make-hash-table :test 'equal))
        (releases (make-hash-table :test 'equal))
        ;; release name -> every system of it, secondary systems
        ;; included: PROVIDED-SYSTEMS of a release lists only the
        ;; primary ones, and frugal-uuid/non-frugal is where
        ;; trivial-clock comes in
        (siblings (make-hash-table :test 'equal)))
    (dolist (dist (fncall "ql-dist:all-dists"))
      (dolist (system (fncall "ql-dist:provided-systems" dist))
        (push system (gethash (fncall "ql-dist:name" (fncall "ql-dist:release" system)) siblings))))
    (labels ((visit-system (system)
               (when (and system (not (gethash (fncall "ql-dist:name" system) seen)))
                 (setf (gethash (fncall "ql-dist:name" system) seen) t)
                 ;; by name: Quicklisp makes a fresh release object per lookup
                 (let ((release (fncall "ql-dist:release" system)))
                   (unless (gethash (fncall "ql-dist:name" release) releases)
                     (setf (gethash (fncall "ql-dist:name" release) releases) release)
                     ;; the release's other systems too: a system loads
                     ;; its siblings at load time (frugal-uuid wants
                     ;; frugal-uuid/non-frugal, which wants trivial-clock)
                     (dolist (sibling (gethash (fncall "ql-dist:name" release) siblings))
                       (visit-system sibling))))
                 (dolist (name (fncall "ql-dist:required-systems" system))
                   (visit-system (fncall "ql-dist:find-system" name))))))
      (dolist (name release-names)
        ;; a release's name, or a system's (an overlay branch's dependency)
        (let ((release (fncall "ql-dist:find-release" name))
              (system (fncall "ql-dist:find-system" name)))
          (cond (release
                 (dolist (system (fncall "ql-dist:provided-systems" release))
                   (visit-system system)))
                (system (visit-system system))
                (t (format t "~&prefetch: no release or system named ~A~%" name))))))
    (loop for release being the hash-values of releases collect release)))

(defun prefetch-releases (release-names)
  "Fetches and unpacks the releases a pass over RELEASE-NAMES (NIL: the
whole stock dist) can need; returns how many are installed."
  (let ((releases (if release-names
                      (release-closure release-names)
                      (fncall "ql-dist:provided-releases" (fncall "ql-dist:dist" "quicklisp")))))
    (dolist (release releases)
      (fncall "ql-dist:ensure-installed" release))
    (length releases)))

(defun install-polyfill-dist (name distinfo-url)
  "Replaces any dist NAME by the one at DISTINFO-URL, unpacks all its
releases, and returns the installed version.  INSTALL-DIST records the
current time as the dist's preference, so it outranks the stock dist."
  (ensure-file-scheme)
  (remove-polyfill-dist name)
  (let ((dist (fncall "ql-dist:install-dist" distinfo-url :prompt nil :replace t)))
    (dolist (release (fncall "ql-dist:provided-releases" dist))
      (fncall "ql-dist:ensure-installed" release))
    (fncall "ql-dist:version" dist)))
