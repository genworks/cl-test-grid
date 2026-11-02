;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8;  -*-
;;; See LICENSE for details.

#|

Implementation of a transaction log kept by the test grid server
(server/server.lisp) over HTTP.

The layout is the one of AWS-TRANSACTION-LOG: every transaction is an
object holding the serialized and gzipped function call, plus a record
saying which object is version N of the log.  The server refuses to
record a version that is already taken - the compare-and-set that the
conditional SimpleDB PutAttributes gave AWS-TRANSACTION-LOG.

Reading is public; writing needs a token, sent in the X-Test-Grid-Token
header.

|#

(in-package #:sptm)

(defclass http-transaction-log ()
  ((name :type string
         :accessor name
         :initarg :name
         :initform (error ":name is required"))
   (base-url :type string
             :accessor base-url
             :initarg :base-url
             :initform (error ":base-url is required"))
   (token :type (or null string)
          :accessor token
          :initarg :token
          :initform nil)))

(defmethod print-object ((log http-transaction-log) stream)
  (print-unreadable-object (log stream :type t :identity t)
    (format stream "~A at ~A" (name log) (base-url log))))

(defmethod serialize-to-string ((log http-transaction-log) object)
  (with-standard-io-syntax
    ;; Readable printing would show SBCL's base-strings as #A(...),
    ;; which other lisps can't read.
    (let ((*print-readably* nil))
      (with-output-to-string (s)
        (prin1 object s)))))

(defmethod deserialize-from-string ((log http-transaction-log) string)
  (with-input-from-string (s string)
    (test-grid-utils::safe-read s)))

(defmethod unique-s3-object-name ((log http-transaction-log))
  (format nil "~A-~A.~A" (name log) (short-timestamp) (random-suffix)))

(defun store-request (log path &key (method :get) parameters content (ok-codes '(200)))
  "Sends a request to the server; returns the response body (an octet
vector) and the status code.  Signals an error unless the status code
is one of OK-CODES."
  (multiple-value-bind (body status headers uri stream must-close reason-phrase)
      (apply #'drakma:http-request
             (format nil "~A~A" (string-right-trim "/" (base-url log)) path)
             :method method
             :parameters parameters
             :additional-headers (when (token log)
                                   (list (cons "X-Test-Grid-Token" (token log))))
             :force-binary t
             (when content
               (list :content content
                     :content-type "application/octet-stream")))
    (declare (ignore headers uri stream must-close))
    (unless (member status ok-codes)
      (error "The test grid server answered ~A ~A to ~A ~A: ~A"
             status reason-phrase method path
             (babel:octets-to-string body :encoding :utf-8 :errorp nil)))
    (values body status)))

(defun store-read (log path &rest args &key &allow-other-keys)
  "Sends a request and reads the Lisp data the server answers with."
  (deserialize-from-string log
                           (babel:octets-to-string (apply #'store-request log path args)
                                                   :encoding :utf-8)))

(defun log-path (log operation)
  (format nil "/sptm/logs/~A/~A" (name log) operation))

(defun put-object (log name bytes &key (ok-codes '(200)))
  (store-request log (format nil "/sptm/objects/~A" name)
                 :method :put
                 :content bytes
                 :ok-codes ok-codes))

(defun get-object (log name)
  (deserialize-from-string log
                           (gunzip-string (store-request log (format nil "/sptm/objects/~A" name)))))

(defmethod persist-funcall ((log http-transaction-log) func-symbol args-without-data-arg)
  (let ((name (unique-s3-object-name log)))
    (put-object log name (gzip-string (serialize-to-string log (list func-symbol args-without-data-arg))))
    name))

(defmethod commit-version ((log http-transaction-log) version-number object-name)
  (multiple-value-bind (body status)
      (store-request log (log-path log "commit")
                     :method :post
                     :parameters (list (cons "version" (princ-to-string version-number))
                                       (cons "object" object-name))
                     :ok-codes '(200 409))
    (declare (ignore body))
    (= 200 status)))

(defclass http-transaction ()
  ((transaction-log :type http-transaction-log
                    :accessor transaction-log
                    :initarg :transaction-log
                    :initform (error ":transaction-log is required"))
   (version :type fixnum
            :accessor version
            :initarg :version
            :initform (error ":version is required"))
   (object-name :type string
                :accessor object-name
                :initarg :object-name
                :initform (error ":object-name is required"))
   (object-content :type t
                   :initform nil)))

(defmethod print-object ((tx http-transaction) stream)
  (print-unreadable-object (tx stream :type t :identity t)
    (format stream "~A ~S ..." (version tx) (func tx))))

(defun object-content (http-transaction)
  (when (null (slot-value http-transaction 'object-content))
    (setf (slot-value http-transaction 'object-content)
          (get-object (transaction-log http-transaction)
                      (object-name http-transaction))))
  (slot-value http-transaction 'object-content))

(defmethod func ((transaction http-transaction))
  (first (object-content transaction)))

(defmethod args ((transaction http-transaction))
  (second (object-content transaction)))

(defmethod list-transactions ((log http-transaction-log) after-version)
  (mapcar (lambda (record)
            (make-instance 'http-transaction
                           :transaction-log log
                           :version (car record)
                           :object-name (cdr record)))
          (store-read log (log-path log "transactions")
                      :parameters (list (cons "after" (princ-to-string after-version))))))

(defun log-bounds (log)
  "(:min <version> :max <version> :snapshot <version>), NIL where absent."
  (store-read log (log-path log "bounds")))

(defmethod min-transaction-version ((log http-transaction-log) &key (if-absent :error))
  (or (getf (log-bounds log) :min)
      (handle-if-absent if-absent "Unable to return min transaction version as there is no transaction records for the transaction log ~A" log)))

(defmethod max-transaction-version ((log http-transaction-log) &key (if-absent :error))
  (or (getf (log-bounds log) :max)
      (handle-if-absent if-absent "Unable to return max transaction version as there is no transaction records for the transaction log ~A" log)))

(defmethod snapshot-version ((log http-transaction-log) &key (if-absent :error))
  (or (getf (log-bounds log) :snapshot)
      (handle-if-absent if-absent "Unable to return snapshot version as there is no shapshot for the transaction log ~A" log)))

(defmethod get-snapshot ((log http-transaction-log))
  (let ((record (or (store-read log (log-path log "snapshot"))
                    (error "There is no snapshot for the transaction log ~A" log))))
    (make-instance 'versioned-data
                   :version (car record)
                   :data (get-object log (cdr record)))))

(defmethod save-snapshot ((log http-transaction-log) versioned-data)
  (let ((object-name (format nil "~A-snapshot-~A"
                             (name log)
                             (version-str (version versioned-data)))))
    ;; Objects are never overwritten: a 409 here means this version's
    ;; snapshot was saved before, and holds the same data.
    (put-object log
                object-name
                (gzip-string (serialize-to-string log (data versioned-data)))
                :ok-codes '(200 409))
    (store-request log (log-path log "snapshot")
                   :method :post
                   :parameters (list (cons "version" (princ-to-string (version versioned-data)))
                                     (cons "object" object-name)))))
