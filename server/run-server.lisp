;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Starts the test grid server and keeps the process running.
;;;; Quicklisp must be loaded first, for example:
;;;;
;;;;   sbcl --non-interactive --load ~/quicklisp/setup.lisp --load server/run-server.lisp
;;;;
;;;; Settings come from the environment:
;;;;
;;;;   TEST_GRID_SERVER_DATA_DIR   where everything is stored (required);
;;;;                               tokens.lisp in it lists the write tokens
;;;;   TEST_GRID_SERVER_PORT       default 8080
;;;;   TEST_GRID_SERVER_ADDRESS    default: all addresses
;;;;
;;;; and, to mail the notifications as well as logging them:
;;;;
;;;;   TEST_GRID_SMTP_HOST, TEST_GRID_SMTP_PORT, TEST_GRID_SMTP_USER,
;;;;   TEST_GRID_SMTP_PASSWORD, TEST_GRID_MAIL_FROM, TEST_GRID_MAIL_TO

(let ((src-dir (merge-pathnames "../" (make-pathname :name nil :type nil
                                                     :defaults *load-truename*))))
  (pushnew (truename src-dir) asdf:*central-registry* :test #'equal))

(ql:quickload :test-grid-server)

(flet ((env (name &optional default)
         (let ((value (uiop:getenv name)))
           (if (and value (plusp (length value)))
               value
               default))))
  (funcall (read-from-string "tg-server:start")
           :data-dir (or (env "TEST_GRID_SERVER_DATA_DIR")
                         (error "TEST_GRID_SERVER_DATA_DIR is not set"))
           :port (parse-integer (env "TEST_GRID_SERVER_PORT" "8080"))
           :address (env "TEST_GRID_SERVER_ADDRESS")
           :smtp-host (env "TEST_GRID_SMTP_HOST")
           :smtp-port (parse-integer (env "TEST_GRID_SMTP_PORT" "587"))
           :smtp-user (env "TEST_GRID_SMTP_USER")
           :smtp-password (env "TEST_GRID_SMTP_PASSWORD")
           :mail-from (env "TEST_GRID_MAIL_FROM")
           :mail-to (env "TEST_GRID_MAIL_TO")))

(format t "~&The test grid server is running.~%")
(finish-output)
(loop (sleep 3600))
