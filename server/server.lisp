;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.

;;;; The test grid server.
;;;;
;;;; Keeps what the agents upload, in place of the hosted services
;;;; the agent used to depend on: the GAE blobstore for log files,
;;;; the Amazon S3 bucket and SimpleDB domain for the sptm
;;;; transaction logs, and the Heroku notification relay.
;;;;
;;;; Everything is stored as files under DATA-DIR:
;;;;
;;;;   blobs/<key>                         a gzipped log file
;;;;   sptm/objects/<name>                 a gzipped serialized transaction or snapshot
;;;;   sptm/logs/<log>/<version>-tx        the name of the transaction's object
;;;;   sptm/logs/<log>/<version>-snapshot  the name of the snapshot's object
;;;;   notifications.log
;;;;   tokens.lisp                         ((<token> <who>) ...)
;;;;
;;;; Reading is open to everyone.  Writing requires an
;;;; X-Test-Grid-Token header carrying one of the tokens listed in
;;;; tokens.lisp.  The file is read again on every write, so a token
;;;; is added or revoked by editing it, without a restart.
;;;;
;;;; The HTTP interface:
;;;;
;;;;   POST /upload2                   multipart/form-data, one gzipped file per field;
;;;;                                   answers (("<field>" . "<key>") ...)
;;;;   GET  /blob?key=<key>            the log, as text/plain
;;;;   PUT  /sptm/objects/<name>       stores an object; never overwrites
;;;;   GET  /sptm/objects/<name>       the object as stored (gzipped)
;;;;   POST /sptm/logs/<log>/commit    version=<n>&object=<name>: records the object
;;;;                                   as version <n>; 409 if <n> is taken
;;;;   GET  /sptm/logs/<log>/transactions?after=<n>
;;;;                                   ((<version> . "<object>") ...), ascending
;;;;   GET  /sptm/logs/<log>/bounds    (:min <n> :max <n> :snapshot <n>), NIL where absent
;;;;   POST /sptm/logs/<log>/snapshot  version=<n>&object=<name>: records the object
;;;;                                   as the snapshot of version <n>
;;;;   GET  /sptm/logs/<log>/snapshot  (<version> . "<object>") of the newest snapshot, or NIL
;;;;   GET or POST /send-notification  subject=...&body=...

(defpackage :test-grid-server
  (:nicknames :tg-server)
  (:use :cl)
  (:export :start
           :main))

(in-package :tg-server)

(defparameter *max-log-length* 101000
  "Maximum size of one gzipped log file.  The agent cuts logs to 100000
bytes before gzipping them.")

(defparameter *max-files-per-upload* 500)

(defparameter *max-object-length* (* 256 1024 1024)
  "Maximum size of a gzipped sptm object.  A snapshot of the whole
results database is the largest thing stored.")

(defparameter *max-notification-length* 100000)

(defclass tg-acceptor (hunchentoot:acceptor)
  ((data-dir :type pathname
             :initarg :data-dir
             :accessor data-dir
             :initform (error ":data-dir is required"))
   ;; Notifications are always appended to notifications.log;
   ;; they are mailed as well when SMTP-HOST is given.
   (smtp-host :initarg :smtp-host :accessor smtp-host :initform nil)
   (smtp-port :initarg :smtp-port :accessor smtp-port :initform 587)
   (smtp-user :initarg :smtp-user :accessor smtp-user :initform nil)
   (smtp-password :initarg :smtp-password :accessor smtp-password :initform nil)
   (mail-from :initarg :mail-from :accessor mail-from :initform nil)
   (mail-to :initarg :mail-to :accessor mail-to :initform nil)
   (lock :reader lock :initform (bt:make-lock "test-grid-server"))
   (random-state :reader tg-random-state :initform (make-random-state t))))

;;; Requests and responses

(defun fail (code format-control &rest format-args)
  (setf (hunchentoot:return-code*) code
        (hunchentoot:content-type*) "text/plain; charset=utf-8")
  (hunchentoot:abort-request-handler (apply #'format nil format-control format-args)))

(defun lisp-response (object)
  (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
  (with-standard-io-syntax
    ;; Readable printing would show SBCL's base-strings as #A(...),
    ;; which other lisps can't read.
    (let ((*print-readably* nil))
      (prin1-to-string object))))

(defun require-method (&rest methods)
  (unless (member (hunchentoot:request-method*) methods)
    (fail hunchentoot:+http-method-not-allowed+ "Method ~A is not allowed here."
          (hunchentoot:request-method*))))

(defun read-tokens (acceptor)
  (let ((file (merge-pathnames "tokens.lisp" (data-dir acceptor))))
    (when (probe-file file)
      (with-open-file (in file :external-format :utf-8)
        (with-standard-io-syntax
          (let ((*read-eval* nil))
            (read in nil nil)))))))

(defun require-token (acceptor)
  "Returns the tokens.lisp entry of the request's token, or refuses the request."
  (let* ((token (hunchentoot:header-in* :x-test-grid-token))
         (entry (and token
                     (find token (read-tokens acceptor) :key #'first :test #'string=))))
    (or entry
        (fail hunchentoot:+http-forbidden+
              "Writing requires a valid X-Test-Grid-Token header."))))

(defparameter +name-chars+
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")

(defun valid-name-p (string)
  "Blob keys, object names and log names become file names; allow only
a safe alphabet, starting with a letter or a digit."
  (and (stringp string)
       (< 0 (length string) 256)
       (alphanumericp (char string 0))
       (every (lambda (char) (find char +name-chars+)) string)))

(defun require-name (string what)
  (unless (valid-name-p string)
    (fail hunchentoot:+http-bad-request+ "Invalid ~A: ~S" what string))
  string)

(defun integer-parameter (name &optional default)
  (let ((value (hunchentoot:parameter name)))
    (cond ((and (null value) default) default)
          ((and value (every #'digit-char-p value) (plusp (length value)))
           (parse-integer value))
          (t (fail hunchentoot:+http-bad-request+
                   "Parameter ~A must be a non-negative integer: ~S" name value)))))

(defun request-body ()
  (let ((length (hunchentoot:header-in* :content-length)))
    (unless length
      (fail hunchentoot:+http-length-required+ "Content-Length is required."))
    (when (> (parse-integer length) *max-object-length*)
      (fail hunchentoot:+http-request-entity-too-large+
            "The maximum object size is ~A bytes." *max-object-length*))
    (or (hunchentoot:raw-post-data :force-binary t)
        (make-array 0 :element-type '(unsigned-byte 8)))))

;;; Files

(defun read-bytes (file)
  (with-open-file (in file :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence bytes in)
      bytes)))

(defun string-bytes (string)
  (flexi-streams:string-to-octets string :external-format :utf-8))

(defun random-integer (acceptor limit)
  (bt:with-lock-held ((lock acceptor))
    (random limit (tg-random-state acceptor))))

(defun install-file (acceptor file bytes &key overwrite check)
  "Writes BYTES to FILE through a temporary file renamed into place.
Holding the acceptor's lock, it calls CHECK first, if given: a non-NIL
return value is a refusal (<http code> . <message>), and the file is not
installed.  Unless OVERWRITE, an existing FILE is refused with 409.
Returns NIL when the file is installed, otherwise the refusal."
  (ensure-directories-exist file)
  ;; No dot after the leading one, so the temporary file has no
  ;; pathname type for RENAME-FILE to merge into FILE.
  (let ((tmp (uiop:subpathname (uiop:pathname-directory-pathname file)
                               (format nil ".tmp-~D"
                                       (random-integer acceptor (expt 10 18))))))
    (with-open-file (out tmp
                         :direction :output
                         :element-type '(unsigned-byte 8)
                         :if-exists :supersede)
      (write-sequence bytes out))
    (let ((refusal (bt:with-lock-held ((lock acceptor))
                     (or (and check (funcall check))
                         (and (not overwrite)
                              (probe-file file)
                              (cons hunchentoot:+http-conflict+
                                    (format nil "~A already exists." (file-namestring file))))
                         (progn (rename-file tmp file)
                                nil)))))
      (when refusal
        (delete-file tmp))
      refusal)))

(defun install-or-fail (&rest args)
  (let ((refusal (apply #'install-file args)))
    (when refusal
      (fail (car refusal) "~A" (cdr refusal)))))

;;; Logs (the GAE blobstore's job)

(defun blob-file (acceptor key)
  (uiop:subpathname (data-dir acceptor) (format nil "blobs/~A" key)))

(defun store-blob (acceptor bytes)
  "Stores BYTES under a new random key and returns the key."
  (loop
     (let ((key (string-downcase
                 (write-to-string (random-integer acceptor (expt 36 10))
                                  :base 36 :radix nil))))
       (unless (install-file acceptor (blob-file acceptor key) bytes)
         (return key)))))

(defun handle-upload2 (acceptor)
  (require-method :post)
  (require-token acceptor)
  (let ((params (hunchentoot:post-parameters*)))
    (when (some (lambda (param) (stringp (cdr param))) params)
      (fail hunchentoot:+http-bad-request+
            "Only files are accepted, not plain form fields."))
    (when (> (length params) *max-files-per-upload*)
      (fail hunchentoot:+http-bad-request+
            "The maximum number of files in one request is ~A." *max-files-per-upload*))
    ;; A file parameter is (<field> <temporary path> <file name> <content type>).
    (dolist (param params)
      (let ((size (with-open-file (in (second param) :element-type '(unsigned-byte 8))
                    (file-length in))))
        (when (> size *max-log-length*)
          (fail hunchentoot:+http-bad-request+
                "The maximum file size is ~A bytes; ~A has ~A."
                *max-log-length* (third param) size))))
    (lisp-response
     (mapcar (lambda (param)
               (cons (first param)
                     (store-blob acceptor (read-bytes (second param)))))
             params))))

(defun handle-blob (acceptor)
  (require-method :get :head)
  (let* ((key (require-name (hunchentoot:get-parameter "key") "blob key"))
         (file (blob-file acceptor key)))
    (unless (probe-file file)
      (fail hunchentoot:+http-not-found+ "There is no log ~A." key))
    (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
    (let ((bytes (read-bytes file)))
      (if (search "gzip" (or (hunchentoot:header-in* :accept-encoding) ""))
          (progn
            (setf (hunchentoot:header-out :content-encoding) "gzip")
            bytes)
          (gzip-stream:gunzip-sequence bytes)))))

;;; sptm transaction logs (the S3 bucket's and the SimpleDB domain's job)

(defun object-file (acceptor name)
  (uiop:subpathname (data-dir acceptor) (format nil "sptm/objects/~A" name)))

(defun log-dir (acceptor log)
  (uiop:subpathname (data-dir acceptor) (format nil "sptm/logs/~A/" log)))

(defun version-str (version)
  (format nil "~9,'0D" version))

(defun record-file (acceptor log version kind)
  (uiop:subpathname (log-dir acceptor log)
                    (format nil "~A-~A" (version-str version) kind)))

(defun list-records (acceptor log kind)
  "((<version> . <record file>) ...) of the log's records of KIND,
\"tx\" or \"snapshot\", ascending by version."
  (let ((suffix (format nil "-~A" kind))
        (records '()))
    (dolist (file (uiop:directory-files (log-dir acceptor log)))
      (let ((name (file-namestring file)))
        (when (and (= (length name) (+ 9 (length suffix)))
                   (every #'digit-char-p (subseq name 0 9))
                   (string= suffix name :start2 9))
          (push (cons (parse-integer name :end 9) file) records))))
    (sort records #'< :key #'car)))

(defun record-object (record-file)
  (string-trim '(#\Space #\Tab #\Newline #\Return)
               (uiop:read-file-string record-file :external-format :utf-8)))

(defun handle-object (acceptor name)
  (require-name name "object name")
  (let ((file (object-file acceptor name)))
    (case (hunchentoot:request-method*)
      ((:get :head)
       (unless (probe-file file)
         (fail hunchentoot:+http-not-found+ "There is no object ~A." name))
       (setf (hunchentoot:content-type*) "application/octet-stream")
       (read-bytes file))
      (:put
       (require-token acceptor)
       (install-or-fail acceptor file (request-body))
       (lisp-response t))
      (t (require-method :get :head :put)))))

(defun handle-commit (acceptor log)
  (require-method :post)
  (require-token acceptor)
  (let ((version (integer-parameter "version"))
        (object (require-name (hunchentoot:parameter "object") "object name")))
    (unless (probe-file (object-file acceptor object))
      (fail hunchentoot:+http-bad-request+ "There is no object ~A; PUT it first." object))
    ;; Versions are taken in order and never twice, so that the log
    ;; has no gaps: a version already taken is a concurrency collision
    ;; (409, the client rolls forward and retries), one beyond the
    ;; next free version is a client error.
    (install-or-fail acceptor
                     (record-file acceptor log version "tx")
                     (string-bytes object)
                     :check (lambda ()
                              (let ((next (1+ (or (car (car (last (list-records acceptor log "tx"))))
                                                  0))))
                                (cond ((< version next)
                                       (cons hunchentoot:+http-conflict+
                                             (format nil "Version ~A of ~A is already committed."
                                                     version log)))
                                      ((> version next)
                                       (cons hunchentoot:+http-bad-request+
                                             (format nil "The next version of ~A is ~A, not ~A."
                                                     log next version)))))))
    (lisp-response t)))

(defun handle-transactions (acceptor log)
  (require-method :get :head)
  (let ((after (integer-parameter "after" 0)))
    (lisp-response
     (loop for (version . file) in (list-records acceptor log "tx")
        when (> version after)
        collect (cons version (record-object file))))))

(defun handle-bounds (acceptor log)
  (require-method :get :head)
  (let ((transactions (list-records acceptor log "tx"))
        (snapshots (list-records acceptor log "snapshot")))
    (lisp-response (list :min (car (first transactions))
                         :max (car (car (last transactions)))
                         :snapshot (car (car (last snapshots)))))))

(defun handle-snapshot (acceptor log)
  (case (hunchentoot:request-method*)
    ((:get :head)
     (let ((newest (car (last (list-records acceptor log "snapshot")))))
       (lisp-response (and newest
                           (cons (car newest) (record-object (cdr newest)))))))
    (:post
     (require-token acceptor)
     (let ((version (integer-parameter "version"))
           (object (require-name (hunchentoot:parameter "object") "object name")))
       (unless (probe-file (object-file acceptor object))
         (fail hunchentoot:+http-bad-request+ "There is no object ~A; PUT it first." object))
       (install-or-fail acceptor
                        (record-file acceptor log version "snapshot")
                        (string-bytes object)
                        :overwrite t)
       (lisp-response t)))
    (t (require-method :get :head :post))))

;;; Notifications (the Heroku server's job)

(defun handle-notification (acceptor)
  (require-method :get :post)
  (let ((who (second (require-token acceptor)))
        (subject (or (hunchentoot:parameter "subject") ""))
        (body (or (hunchentoot:parameter "body") "")))
    (when (> (+ (length subject) (length body)) *max-notification-length*)
      (fail hunchentoot:+http-request-entity-too-large+
            "The maximum notification size is ~A characters." *max-notification-length*))
    (bt:with-lock-held ((lock acceptor))
      (with-open-file (out (merge-pathnames "notifications.log" (data-dir acceptor))
                           :direction :output
                           :if-exists :append
                           :if-does-not-exist :create
                           :external-format :utf-8)
        (with-standard-io-syntax
          (let ((*print-readably* nil))
            (prin1 (list :time (get-universal-time) :from who :subject subject :body body) out)
            (terpri out)))))
    (when (smtp-host acceptor)
      (handler-case
          (cl-smtp:send-email (smtp-host acceptor)
                              (mail-from acceptor)
                              (mail-to acceptor)
                              subject
                              body
                              :authentication (list :login
                                                    (smtp-user acceptor)
                                                    (smtp-password acceptor))
                              :ssl t
                              :port (smtp-port acceptor))
        (error (e)
          (hunchentoot:log-message* :warning "Notification not mailed: ~A" e))))
    (lisp-response t)))

;;; Dispatch

(defmethod hunchentoot:acceptor-dispatch-request ((acceptor tg-acceptor) request)
  (declare (ignore request))
  (let ((parts (remove "" (uiop:split-string (hunchentoot:script-name*) :separator "/")
                       :test #'string=)))
    (cond
      ((null parts)
       (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
       "CL Test Grid storage server.")
      ((equal parts '("upload2")) (handle-upload2 acceptor))
      ((equal parts '("blob")) (handle-blob acceptor))
      ((equal parts '("send-notification")) (handle-notification acceptor))
      ((and (= 3 (length parts))
            (string= "sptm" (first parts))
            (string= "objects" (second parts)))
       (handle-object acceptor (third parts)))
      ((and (= 4 (length parts))
            (string= "sptm" (first parts))
            (string= "logs" (second parts)))
       (let ((log (require-name (third parts) "log name"))
             (operation (fourth parts)))
         (cond
           ((string= operation "commit") (handle-commit acceptor log))
           ((string= operation "transactions") (handle-transactions acceptor log))
           ((string= operation "bounds") (handle-bounds acceptor log))
           ((string= operation "snapshot") (handle-snapshot acceptor log))
           (t (fail hunchentoot:+http-not-found+ "Not found.")))))
      (t (fail hunchentoot:+http-not-found+ "Not found.")))))

(defun start (&key (port 8080) address data-dir
                smtp-host (smtp-port 587) smtp-user smtp-password mail-from mail-to)
  "Starts the server and returns the acceptor (stop it with HUNCHENTOOT:STOP)."
  (unless data-dir
    (error ":data-dir is required"))
  (let ((dir (uiop:ensure-directory-pathname data-dir)))
    (ensure-directories-exist dir)
    (hunchentoot:start (make-instance 'tg-acceptor
                                      :port port
                                      :address address
                                      :data-dir dir
                                      :smtp-host smtp-host
                                      :smtp-port smtp-port
                                      :smtp-user smtp-user
                                      :smtp-password smtp-password
                                      :mail-from mail-from
                                      :mail-to mail-to))))

(defun main ()
  "Starts the server with the settings in the environment and never returns:

  TEST_GRID_SERVER_DATA_DIR   where everything is stored (required);
                              tokens.lisp in it lists the write tokens
  TEST_GRID_SERVER_PORT       default 8080
  TEST_GRID_SERVER_ADDRESS    default: all addresses

and, to mail the notifications as well as logging them:

  TEST_GRID_SMTP_HOST, TEST_GRID_SMTP_PORT, TEST_GRID_SMTP_USER,
  TEST_GRID_SMTP_PASSWORD, TEST_GRID_MAIL_FROM, TEST_GRID_MAIL_TO"
  (flet ((env (name &optional default)
           (let ((value (uiop:getenv name)))
             (if (and value (plusp (length value)))
                 value
                 default))))
    (start :data-dir (or (env "TEST_GRID_SERVER_DATA_DIR")
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
  (loop (sleep 3600)))
