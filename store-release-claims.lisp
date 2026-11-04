;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Releases claims from the "main" storage: records a release-claims
;;;; transaction, so the pairs an agent claimed are free for others at
;;;; once instead of after the claim's two days.  For an agent that
;;;; died and will not be back (a volunteer's machine gone for good, a
;;;; work directory thrown away).  store-release-claims.sh runs this in
;;;; a container.
;;;;
;;;; Settings, from the environment, at least one of the first three:
;;;;
;;;;   TEST_GRID_RELEASE_AGENT_ID   the agent whose claims to release
;;;;   TEST_GRID_RELEASE_LISP       only claims of that implementation identifier
;;;;   TEST_GRID_RELEASE_LIB_WORLD  only claims of that lib-world
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
  (append (let ((id (env "TEST_GRID_RELEASE_AGENT_ID")))
            (when id (list :agent-id id)))
          (let ((lisp (env "TEST_GRID_RELEASE_LISP")))
            (when lisp (list :lisp lisp)))
          (let ((lib-world (env "TEST_GRID_RELEASE_LIB_WORLD")))
            (when lib-world (list :lib-world lib-world)))))

(unless *matcher*
  (error "Set at least one of TEST_GRID_RELEASE_AGENT_ID, TEST_GRID_RELEASE_LISP, TEST_GRID_RELEASE_LIB_WORLD"))

;;; What it will release, from a replica synced first
(defparameter *replica* (tg-storage:get-replica "main" :snapshot-directory *work-dir*))
(tg-storage:sync *replica*)
(let ((matching (remove-if-not (test-grid-data::claim-matcher *matcher*)
                               (getf (tg-storage:data *replica*) :claims))))
  (format t "~&Store at version ~A; ~A claim~:P match ~S:~%"
          (tg-storage:version *replica*) (length matching) *matcher*)
  (dolist (claim matching)
    (multiple-value-bind (s m h day month year) (decode-universal-time (getf claim :time) 0)
      (format t "  ~A  ~A  ~A  ~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0D UTC~%"
              (getf claim :agent-id) (getf claim :lisp) (getf claim :lib-world)
              year month day h m s)))
  (if matching
      (let ((log (tg-storage::make-transaction-log "main")))
        (sptm:record-transaction log 'test-grid-data:release-claims *matcher*)
        (format t "~&Released; the store is at version ~A.~%" (sptm::max-transaction-version log)))
      (format t "~&Nothing to release.~%")))
