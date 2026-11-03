;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Removes test runs from the "main" storage: records a
;;;; remove-test-runs transaction (the log keeps every version; the
;;;; runs are gone from the database as of the new one).  For results
;;;; that should never have been submitted, such as runs made with a
;;;; broken setup.  store-remove-runs.sh runs this in a container.
;;;;
;;;; Settings, from the environment:
;;;;
;;;;   TEST_GRID_REMOVE_LIB_WORLD   required: the lib-world of the runs
;;;;                                to remove, e.g. "quicklisp 2026-01-01 + gendl@master bfa9fc5c"
;;;;   TEST_GRID_REMOVE_LISP        optional: only that implementation
;;;;                                identifier's runs in it
;;;;   TEST_GRID_REMOVE_EMAIL       optional: only the runs with that
;;;;                                contact email
;;;;   CL_TEST_GRID_TOKEN           required: a write token
;;;;   CL_TEST_GRID_STORE_URL       the server; the default is the public one
;;;;   TEST_GRID_WORK_DIR           where Quicklisp is kept for this program

(defparameter *this-dir*
  (make-pathname :name nil :type nil :defaults *load-truename*))

(defun env (name &optional default)
  (let ((value #+ccl (ccl:getenv name)
               #+sbcl (sb-ext:posix-getenv name)
               #-(or ccl sbcl) (error "env is written for CCL and SBCL")))
    (if (and value (plusp (length value)))
        value
        default)))

(defparameter *work-dir*
  (let ((dir (env "TEST_GRID_WORK_DIR")))
    (if dir
        (pathname (if (char= #\/ (char dir (1- (length dir)))) dir (concatenate 'string dir "/")))
        (merge-pathnames "work-dir/reports/" *this-dir*))))

(load (merge-pathnames "agent/require-quicklisp.lisp" *this-dir*))
(tg-require-quicklisp:require :agent-work-dir *work-dir*)

(let ((asdf:*central-registry* (cons *this-dir* asdf:*central-registry*)))
  (ql:quickload '(:test-grid-storage) :silent t))

(unless (env "CL_TEST_GRID_TOKEN")
  (error "CL_TEST_GRID_TOKEN is not set"))

(defparameter *matcher*
  (append (list :lib-world (or (env "TEST_GRID_REMOVE_LIB_WORLD")
                               (error "TEST_GRID_REMOVE_LIB_WORLD is not set")))
          (let ((lisp (env "TEST_GRID_REMOVE_LISP")))
            (when lisp (list :lisp lisp)))
          (let ((email (env "TEST_GRID_REMOVE_EMAIL")))
            (when email (list :contact-email email)))))

;;; What it will remove, from a replica synced first
(defparameter *replica* (tg-storage:get-replica "main" :snapshot-directory *work-dir*))
(tg-storage:sync *replica*)
(let ((matching (remove-if-not (test-grid-data::test-run-matcher *matcher*)
                               (getf (tg-storage:data *replica*) :runs))))
  (format t "~&Store at version ~A; ~A run~:P match ~S:~%"
          (tg-storage:version *replica*) (length matching) *matcher*)
  (dolist (run matching)
    (let ((descr (getf run :descr)))
      (format t "  ~A  ~A  ~A~%" (getf descr :lisp) (getf descr :contact-email)
              (length (getf run :results)))))
  (if matching
      (let ((log (tg-storage::make-transaction-log "main")))
        (sptm:record-transaction log 'test-grid-data:remove-test-runs *matcher*)
        (format t "~&Removed; the store is at version ~A.~%" (sptm::max-transaction-version log)))
      (format t "~&Nothing to remove.~%")))
