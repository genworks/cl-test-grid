;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; How much a library is used by the rest of the dist, two ways.
;;;;
;;;; Static: the dist's own index says which systems depend on which,
;;;; so for a project we can count the projects that depend on it,
;;;; directly and transitively.  dependencies-and-blockers.lisp has the
;;;; tables and the blockers logic, loaded from a snapshot of a 2017
;;;; dist; USE-DIST-INDEX rebuilds them from the dist this image has,
;;;; updated first, so the counts are the current dist's.
;;;;
;;;; Dynamic: since 2026-11-04 every load test records the projects
;;;; ASDF actually loaded on the way (:loaded in the load result,
;;;; agent/proc-test-loading.lisp), so for a project we can count how
;;;; many fresh-process loads pulled it in, on which lisps and
;;;; lib-worlds, and how many of those loads failed.  A library with
;;;; no test suite of its own is still exercised that way, thousands of
;;;; times over a dist.

(in-package #:test-grid-reporting)

(defun ql-call (name &rest args)
  (apply (read-from-string name) args))

(defvar *dist-index-version* nil
  "The version of the dist the dependency tables were built from.")

(defvar *project->systems* (make-hash-table :test #'equal))

(defun use-dist-index ()
  "Rebuilds the dependency tables from this image's Quicklisp dist,
after updating it; returns the dist version."
  (let ((dist (ql-call "ql-dist:dist" "quicklisp")))
    (handler-case (ql-call "ql:update-dist" dist :prompt nil)
      (error (e) (format t "~&The dist could not be updated (~A); using the index as it is.~%" e)))
    (let* ((dist (ql-call "ql-dist:dist" "quicklisp"))
           (file (ql-call "ql:qmerge" "dists/quicklisp/systems.txt"))
           (info (meta-info-from-quicklisp::extract-meta-info file)))
      (setf +direct-dependencies+ (alexandria:alist-hash-table (getf info :system->dependencies) :test #'equal)
            +system->project+ (alexandria:alist-hash-table (getf info :system->project) :test #'equal)
            +direct-dependents+ (reverse-dependencies +direct-dependencies+)
            *dist-index-version* (ql-call "ql-dist:version" dist))
      (clrhash *project->systems*)
      (maphash (lambda (system project) (push system (gethash project *project->systems*)))
               +system->project+)
      (dolist (fn '(dependencies dependents blockers root-blockers blocked blocked-exclusively))
        (fare-memoization:unmemoize fn)
        (fare-memoization:memoize fn))
      (format t "~&Dependency tables from Quicklisp ~A: ~D systems.~%"
              *dist-index-version* (hash-table-count +direct-dependencies+))
      *dist-index-version*)))

(defun transitive-dependent-systems (systems)
  "Every system that depends, directly or through others, on one of SYSTEMS."
  (let ((seen (make-hash-table :test #'equal))
        (queue (copy-list systems)))
    (loop while queue
          do (dolist (dependent (gethash (pop queue) +direct-dependents+))
               (unless (gethash dependent seen)
                 (setf (gethash dependent seen) t)
                 (push dependent queue))))
    (loop for system being the hash-keys of seen collect system)))

(defun dependent-projects (project &key (transitive t))
  "The projects whose systems depend on a system of PROJECT, sorted;
only the direct ones when TRANSITIVE is NIL."
  (let* ((systems (gethash project *project->systems*))
         (dependents (if transitive
                         (transitive-dependent-systems systems)
                         (loop for system in systems append (gethash system +direct-dependents+))))
         (projects '()))
    (dolist (system dependents)
      (let ((p (gethash system +system->project+)))
        (when (and p (not (string= p project)))
          (pushnew p projects :test #'string=))))
    (sort projects #'string<)))

(defun dependents-html (libname)
  "The paragraph on a library page about who depends on it."
  (let* ((project (string-downcase libname))
         (direct (dependent-projects project :transitive nil))
         (all (dependent-projects project)))
    (cond ((null *dist-index-version*)
           "<p>No dist index at hand.</p>")
          ((null (gethash project *project->systems*))
           (format nil "<p>Not in Quicklisp ~A.</p>" *dist-index-version*))
          ((null all)
           (format nil "<p>In Quicklisp ~A no other project depends on it.</p>" *dist-index-version*))
          (t
           (let ((shown (subseq direct 0 (min 40 (length direct)))))
             (format nil "<p>In Quicklisp ~A, ~D project~:P depend~:[s~;~] on it directly and ~D transitively: a failure of it on an implementation blocks those.</p>~%<p>Directly: ~{~A~^, ~}~[~:;, and ~:*~D more~].</p>"
                     *dist-index-version* (length direct) (/= 1 (length direct)) (length all)
                     (mapcar (lambda (p)
                               (if (probe-file (report-file (format nil "library/~A.html" p)))
                                   (format nil "<a href=\"~A.html\">~A</a>" p p)
                                   p))
                             shown)
                     (- (length direct) (length shown))))))))

;;; Dynamic

(defclass exercise ()
  ((lisp :initarg :lisp :reader lisp)
   (lib-world :initarg :lib-world :reader lib-world)
   (loader :initarg :loader :reader loader
           :documentation "The library whose load pulled this one in.")
   (outcome :initarg :outcome :reader outcome
            :documentation "The status of that load.")))

(defun exercise-table (all-results)
  "project name -> the exercises of it: one per load result that
recorded it among what it loaded."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (result all-results)
      (let ((load-result (load-result result)))
        (when load-result
          (dolist (project (loaded-projects load-result))
            (push (make-instance 'exercise
                                 :lisp (lisp result)
                                 :lib-world (lib-world result)
                                 :loader (libname result)
                                 :outcome (load-status load-result))
                  (gethash (string-downcase project) table))))))
    table))

(defun exercises (table libname)
  (gethash (string-downcase libname) table))

(defun exercised-html (exercises)
  "The table on a library page: per lisp and lib-world, how many loads
of other systems pulled the library in, and how many of those failed."
  (if (null exercises)
      "<p>No load of another system has recorded pulling this library in. Loads record what they pulled in since 2026-11-04; a lib-world tested before that has no such counts.</p>"
      (let ((loaders (sort (remove-duplicates (mapcar #'loader exercises)) #'string< :key #'string)))
        (format nil "<p>Pulled in by ~D load~:P of ~D other project~:P.</p>~%~A"
                (length exercises) (length loaders)
                (pivot-table-html4 exercises
                                   :rows '((lisp string<))
                                   :cols '((lib-world string<))
                                   :cell-printer (lambda (out cell)
                                                   (let ((failed (count-if-not (lambda (e) (eq (outcome e) :ok)) cell)))
                                                     (format out "~D load~:P~@[, ~D failed~]"
                                                             (length cell)
                                                             (and (plusp failed) failed)))))))))
