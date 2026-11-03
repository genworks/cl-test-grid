;;;; -*- Mode: LISP; Syntax: COMMON-LISP; indent-tabs-mode: nil; coding: utf-8; show-trailing-whitespace: t -*-
;;;; See LICENSE for details.
;;;;
;;;; Runs the agent with every lisp taken from a Docker image: the
;;;; clfoundation images, one implementation each, a fresh container
;;;; for every child process.  run-agent-docker.sh runs this file
;;;; itself in a container; it can also be loaded into a CCL that has
;;;; Quicklisp and the docker command.
;;;;
;;;; Settings, from the environment:
;;;;
;;;;   TEST_GRID_USER_EMAIL     required: published with your results
;;;;   CL_TEST_GRID_TOKEN       required: your upload token for the server
;;;;   CL_TEST_GRID_STORE_URL   the server; the default is the public one
;;;;   TEST_GRID_LISPS          comma-separated names from *CATALOG*; the
;;;;                            default is every lisp built for this machine
;;;;   TEST_GRID_PROJECTS       comma-separated Quicklisp projects, to test
;;;;                            only those (for trying the setup out)
;;;;   TEST_GRID_WORK_DIR       default work-dir/agent/ beside this file
;;;;   TEST_GRID_MEMORY         --memory of each child container, default 4g
;;;;   TEST_GRID_IMAGE_PREFIX   where the images are pulled from; the default
;;;;                            is Docker Hub, "clfoundation/".  The same
;;;;                            tags are on common-lisp.net's registry:
;;;;                            "containers.common-lisp.net/cl-docker-images/"
;;;;   TEST_GRID_ALLEGRO_LICENSE_AGREED
;;;;                            "yes" once you have read and agreed to the
;;;;                            Allegro CL Free Express Edition license
;;;;                            (the image prints where it is); without it
;;;;                            allegro is left out

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
        (merge-pathnames "work-dir/agent/" *this-dir*))))

;; Quicklisp for the agent itself, kept in the work directory
(load (merge-pathnames "agent/require-quicklisp.lisp" *this-dir*))
(tg-require-quicklisp:require :agent-work-dir *work-dir*)

(let ((asdf:*central-registry* (cons *this-dir* asdf:*central-registry*)))
  (ql:quickload :test-grid-agent))

(defun env-list (name)
  (let ((value (env name)))
    (when value
      (remove "" (mapcar (lambda (s) (string-trim " " s))
                         (uiop:split-string value :separator ","))
              :test #'string=))))

(defparameter *arch*
  ;; the architecture of the machine the containers run on
  (let ((m (string-downcase (machine-type))))
    (cond ((search "arm" m) "arm64")
          ((search "aarch64" m) "arm64")
          (t "amd64"))))

;;; Which image carries each lisp, and how it is started inside.
;;; Image tags are pinned: a new tag is a new implementation
;;; identifier, and the agent tests it afresh on the same Quicklisp.
;;; :image is the name under the prefix (Docker Hub's clfoundation/,
;;; or common-lisp.net's registry, which carries the same tags);
;;; :arches says where the image is built.
(defparameter *image-prefix* (env "TEST_GRID_IMAGE_PREFIX" "clfoundation/"))

(defparameter *catalog*
  `(("sbcl"    :image "sbcl:2.6.10-trixie" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:sbcl :exe-path "sbcl"))
    ("ccl"     :image "ccl:1.14-trixie" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:ccl :exe-path "ccl"))
    ("ecl"     :image "ecl:26.5.5-trixie" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:ecl :exe-path "ecl" :compiler :lisp-to-c))
    ("abcl"    :image "abcl:1.9.3-noble-jdk-21" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:abcl-launcher :exe-path "abcl"))
    ("clisp"   :image "clisp:2.49.92-trixie" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:clisp :exe-path "clisp"))
    ("clasp"   :image "clasp:3.0.1-trixie" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:clasp :exe-path "clasp")
               :memory "6g")
    ("dotcl"   :image "dotcl:0.1.36-noble" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:dotcl :exe-path "dotcl"))
    ("cmucl"   :image "cmucl:21f-trixie" :arches ("amd64")
               :lisp ,(make-instance 'lisp-exe:cmucl :exe-path "cmucl"))
    ("egcl"    :image "egcl:0.0.11-trixie" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:egcl :exe-path "egcl"))
    ("allegro" :image "allegro:11.0express-trixie" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:acl :exe-path "alisp")
               :run-args ("--env" "I_AGREE_TO_ALLEGRO_EXPRESS_LICENSE=yes")
               :needs-license t)))

(defun docker-lisp (entry)
  (destructuring-bind (name &key image lisp (memory (env "TEST_GRID_MEMORY" "4g")) run-args
                       &allow-other-keys)
      entry
    (declare (ignore name))
    (make-instance 'lisp-exe:docker
                   :image (concatenate 'string *image-prefix* image)
                   :docker-lisp lisp
                   :volumes (list *this-dir* *work-dir*)
                   ;; The open-files limit is pinned because CCL starts a
                   ;; child by closing every descriptor up to the soft
                   ;; limit, one close() each, before the exec; a daemon
                   ;; whose default is a billion makes every run-program
                   ;; take an hour (see run-agent-docker.sh).
                   :docker-run-args (append (list "--memory" memory
                                                  "--ulimit" "nofile=1024:1048576")
                                            run-args))))

(defun selected-entries ()
  (let ((wanted (env-list "TEST_GRID_LISPS")))
    (loop for entry in *catalog*
       for name = (first entry)
       when (and (if wanted
                     (member name wanted :test #'string-equal)
                     (member *arch* (getf (rest entry) :arches) :test #'string=))
                 (or (not (getf (rest entry) :needs-license))
                     (string-equal "yes" (env "TEST_GRID_ALLEGRO_LICENSE_AGREED"))
                     (progn (format t "~&~A is left out: TEST_GRID_ALLEGRO_LICENSE_AGREED is not \"yes\".~%" name)
                            nil)))
       collect entry)))

(defparameter *entries* (selected-entries))

(unless *entries*
  (error "No lisps selected: TEST_GRID_LISPS=~S, architecture ~A" (env "TEST_GRID_LISPS") *arch*))

(format t "~&Testing on ~A: ~{~A~^, ~}~%" *arch* (mapcar #'first *entries*))

;; Pull the images first: a pull inside a child's run would count
;; against that child's timeout (the configuration check gives 60 s).
;; An image already here is not pulled again: the tags are pinned, so
;; it is the right one, and a registry's rate limit counts even the
;; pull of an image that is up to date.
(dolist (entry *entries*)
  (let ((image (concatenate 'string *image-prefix* (getf (rest entry) :image))))
    (if (zerop (nth-value 2 (uiop:run-program (list "docker" "image" "inspect" image)
                                              :ignore-error-status t
                                              :output nil :error-output nil)))
        (format t "~&~A is here already.~%" image)
        (progn
          (format t "~&Pulling ~A ...~%" image)
          (finish-output)
          ;; not --quiet: a full image is over a gigabyte, and the layer
          ;; status lines are the only sign of life while it downloads
          ;; and extracts
          (uiop:run-program (list "docker" "pull" image)
                            :output t :error-output t)))))

(defparameter *lisps* (mapcar #'docker-lisp *entries*))

;; SBCL does the auxiliary work (updating Quicklisp, listing its
;; projects) when it is among the lisps; otherwise the first one.
(defparameter *preferred-lisp*
  (or (let ((sbcl (position "sbcl" *entries* :key #'first :test #'string=)))
        (and sbcl (nth sbcl *lisps*)))
      (docker-lisp (find "sbcl" *catalog* :key #'first :test #'string=))))

(defparameter *agent*
  (test-grid-agent:make-agent
   :lisps *lisps*
   :preferred-lisp *preferred-lisp*
   :user-email (or (env "TEST_GRID_USER_EMAIL")
                   (error "TEST_GRID_USER_EMAIL is not set"))
   :work-dir *work-dir*))

(let ((projects (env-list "TEST_GRID_PROJECTS")))
  (when projects
    (format t "~&Testing only the projects ~{~A~^, ~}~%" projects)
    (setf (test-grid-agent::custom-project-names *agent*) projects)))

(unless (env "CL_TEST_GRID_TOKEN")
  (error "CL_TEST_GRID_TOKEN is not set; the results could not be uploaded"))

(test-grid-agent:main *agent*)
