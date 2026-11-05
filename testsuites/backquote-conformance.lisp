;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; A check of the implementation rather than of a library: what the
;;;; host Lisp's own backquote evaluates to.  Only values are compared,
;;;; never how a form reads or prints, which the standard leaves open.
;;;;
;;;; The cases come from fare-quasiquote's quasiquote-test.lisp
;;;; (Francois-Rene Rideau, MIT license), which carries cases from
;;;; SBCL's backq.impure.lisp, filtered at his suggestion to what is
;;;; portable; a few are adapted to bind their variables.
;;;;
;;;; Loaded as source by the LIBTEST method in testsuites.lisp, in the
;;;; child process, with no dependencies.  A case is one of:
;;;;
;;;;   :clhs       the value follows from CLHS 2.4.6; a failure is a failure
;;;;   :contested  nested splicing of several forms, where the result
;;;;               turns on how the inner backquote expands; reported as
;;;;               a known failure (K in the reports) until someone rules
;;;;   :open       CLHS leaves it open; written to the log, not reported

(defpackage #:backquote-conformance
  (:use :cl)
  (:export #:run-checks))

(in-package #:backquote-conformance)

(defparameter a '(vector 0))
(defparameter b 11)
(defparameter c (list 22 33))
(defparameter d (list 44 55))
(defparameter x 1)
(defparameter y 2)
(defparameter @c 7)
(defparameter .c 8)
(defparameter *k '((list :x x) (list :y y)))
(defparameter *qq* '(*rr* *ss*))
(defparameter *rr* '(3 5))
(defparameter *ss* '(4 6))
(defun *rr* (x) (reduce #'* x))
(defparameter *x* '(a b))
(defparameter *y* '(c))
(defparameter *p* '(append *x* *y*))
(defparameter *q* '((append *x* *y*) (list 'sqrt 9)))
(defparameter *r* '(append *x* *y*))
(defparameter *s* '((append *x* *y*)))

(defparameter *cases*
  ;; (class evals string expected): the form read from STRING, evaluated
  ;; EVALS times, must be EQUALP to EXPECTED
  '((:clhs 1 "`a" a)
    (:clhs 2 "``a" a)
    (:clhs 1 "`(a ,b)" (a 11))
    (:clhs 2 "``(a ,b)" (a 11))
    (:clhs 1 "`(a ,@c)" (a 22 33))
    (:clhs 1 "`(,@c)" (22 33))
    (:clhs 1 "`,`a" a)
    (:clhs 1 "`(a . ,b)" (a . 11))
    (:clhs 1 "`(a ,b ,@c)" (a 11 22 33))
    (:clhs 1 "`(1 2 3)" (1 2 3))
    (:clhs 1 "`(a ,@c . 4)" (a 22 33 . 4))
    (:clhs 1 "`(a ,b ,@c . ,d)" (a 11 22 33 44 55))
    (:clhs 1 "`(,@c . ,d)" (22 33 44 55))
    (:clhs 3 "```(,,a ,',',b)" (#(0) 11))
    (:clhs 1 "`#(a ,b)" #(a 11))
    (:clhs 1 "`#(,@c)" #(22 33))
    (:clhs 1 "`#()" #())
    (:clhs 1 "`(foobar a b ,c ,'(e f g) d ,@'(e f g) (h i j) ,@c)"
     (foobar a b (22 33) (e f g) d e f g (h i j) 22 33))
    (:clhs 2 "``(, @c)" (7))
    (:clhs 2 "``(, .c)" (8))
    (:clhs 1 "`(1 ,b)" (1 11))
    (:clhs 1 "`(,'foo ,b)" (foo 11))
    (:clhs 1 "(let ((c (list 2 3)) (d (list 44 55))) `(x ,b ,@a ,.c ,.d))"
     (x 11 vector 0 2 3 44 55))
    (:clhs 1 "`#.#(1 2 3)" #(1 2 3))
    (:clhs 2 "``,,`,3" 3)
    ;; SBCL's double-backquote table, as Fare's file keeps it
    (:clhs 2 "``(,,*qq*)" (24))
    (:clhs 2 "``(,,@*qq*)" ((3 5) (4 6)))
    (:clhs 2 "``(foo ,,*p*)" (foo (a b c)))
    (:clhs 2 "``(foo ,',*r*)" (foo (append *x* *y*)))
    (:clhs 2 "``(foo ,',@*s*)" (foo (append *x* *y*)))
    (:clhs 2 "``(foo ,@,*p*)" (foo a b c))
    (:clhs 2 "``(foo ,@',*r*)" (foo append *x* *y*))
    (:clhs 2 "``(foo ,@',@*s*)" (foo append *x* *y*))
    ;; one form becoming several under an inner backquote
    (:contested 2 "``(f ,@,@*k)" (f :x 1 :y 2))
    (:contested 2 "``(foo ,@,@*q*)" (foo a b c sqrt 9))
    (:contested 2 "``(,@,@*qq*)" (3 5 4 6))
    (:contested 2 "``(,,@(list 1 2 3) 10)" (1 2 3 10))
    ;; #n( under backquote, and cases Fare's file comments out
    (:open 1 "`#3(a ,b)" #(a 11 11))
    (:open 1 "`#5(a ,@c)" #(a 22 33 33 33))
    (:open 2 "``(foo ,,@*q*)" (foo (a b c) (sqrt 9)))
    (:open 2 "``(foo . ,,@*q*)" (foo a b c sqrt 9))))

(defun run-case (evals string)
  (let ((v (let ((*package* (find-package '#:backquote-conformance))
                 (*readtable* (copy-readtable nil))
                 (*read-eval* t))
             (read-from-string string))))
    (dotimes (i evals v)
      (setf v (eval v)))))

(defun check-case (class evals string expected)
  "True when the case gives EXPECTED; says so in the log when it does not."
  (let* ((result (handler-case (list :value (run-case evals string))
                   (serious-condition (e)
                     (list :error (type-of e)))))
         (ok (and (eq (first result) :value)
                  (equalp (second result) expected)))
         (*print-pretty* nil))
    (unless ok
      (format t "~&~(~A~) ~A gave ~S, expected ~S~%" class string result expected))
    ok))

(defun run-checks ()
  "The extended status of the checks: see TEST-GRID-TESTSUITES:LIBTEST."
  (let ((failed '())
        (known '())
        (total 0))
    (dolist (case *cases*)
      (destructuring-bind (class evals string expected) case
        (unless (eq class :open)
          (incf total))
        (unless (check-case class evals string expected)
          (let ((name (string-downcase string)))
            (case class
              (:clhs (push name failed))
              (:contested (push name failed)
               (push name known)))))))
    (format t "~&~D of ~D backquote checks as expected on ~A ~A.~%"
            (- total (length failed)) total
            (lisp-implementation-type) (lisp-implementation-version))
    (list :failed-tests failed :known-to-fail known)))
