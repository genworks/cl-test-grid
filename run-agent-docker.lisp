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
;;;;   TEST_GRID_WORK_DIR       default work-dir/agent/ beside this file; a
;;;;                            lisp that needs a Quicklisp of its own
;;;;                            (:own-quicklisp in *CATALOG*: dotcl) runs
;;;;                            from an agent of its own under <work dir>/<name>/
;;;;   TEST_GRID_MEMORY         --memory of each child container, default 4g
;;;;   TEST_GRID_IMAGE_PREFIX   where the images are pulled from; the default
;;;;                            is Docker Hub, "clfoundation/".  The same
;;;;                            tags are on common-lisp.net's registry:
;;;;                            "containers.common-lisp.net/cl-docker-images/"
;;;;   TEST_GRID_DEVEL_IMAGE    an image carrying many lisps and the foreign
;;;;                            libraries Quicklisp's own build host has,
;;;;                            under the prefix, e.g. "cl-devel:58097950"
;;;;                            (clfoundation/cl-devel; prefer its commit
;;;;                            tag to trixie or latest, so a run's
;;;;                            environment is known).  Every lisp marked
;;;;                            :in-devel below runs from it instead of its
;;;;                            own image, so systems that load a C library
;;;;                            through CFFI find it; the others keep theirs.
;;;;   TEST_GRID_ALLEGRO_LICENSE_AGREED
;;;;                            "yes" once you have read and agreed to the
;;;;                            Allegro CL Free Express Edition license
;;;;                            (the image prints where it is); without it
;;;;                            allegro is left out
;;;;   TEST_GRID_OVERLAYS       comma-separated <project>=<git url>#<branch>,
;;;;                            e.g. gendl=https://gitlab.common-lisp.net/gendl/gendl.git#devo
;;;;                            After the dist, each is tested as a lib-world
;;;;                            of its own, "<dist> + <project>@<branch> <commit>",
;;;;                            with that branch in place of the dist's
;;;;                            release of the project; a new commit on the
;;;;                            branch is a new lib-world, tested afresh.
;;;;                            TEST_GRID_LISPS applies; TEST_GRID_PROJECTS
;;;;                            does not (an overlay tests its project).
;;;;
;;;; Polyfills (no setting; the catalog).  A lisp whose entry names a
;;;; manifest (:polyfill "polyfills/<lisp>.sexp") is tested twice: on
;;;; the stock dist, and on the stock dist with the polyfill dist built
;;;; from the manifest installed over it, as the lib-world
;;;; "<dist> + polyfill-<lisp> <version>"; the overlays run on both.
;;;; The manifest lists the projects that need a patched source on that
;;;; lisp for now, one pinned commit each; build-polyfill-dist.lisp
;;;; makes the dist on this host and agent/proc-install-dist.lisp
;;;; installs it from file:// URLs.  Such a lisp gets an agent of its
;;;; own (as :own-quicklisp does), so the polyfill never reaches the
;;;; other lisps' Quicklisp.  With TEST_GRID_PROJECTS set, the
;;;; polyfilled pass covers those projects without marking the lisp
;;;; tested on that lib-world, so the full pass still happens.

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

(load (merge-pathnames "build-polyfill-dist.lisp" *this-dir*))

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
;;; :arches says where the image is built; :in-devel that cl-devel
;;; carries the lisp too.
(defparameter *image-prefix* (env "TEST_GRID_IMAGE_PREFIX" "clfoundation/"))

(defparameter *devel-image* (env "TEST_GRID_DEVEL_IMAGE"))

(defparameter *catalog*
  `(("sbcl"    :image "sbcl:2.6.10-trixie" :arches ("amd64" "arm64") :in-devel t
               :lisp ,(make-instance 'lisp-exe:sbcl :exe-path "sbcl"))
    ("ccl"     :image "ccl:1.14-trixie" :arches ("amd64" "arm64") :in-devel t
               :lisp ,(make-instance 'lisp-exe:ccl :exe-path "ccl"))
    ("ecl"     :image "ecl:26.5.5-trixie" :arches ("amd64" "arm64") :in-devel t
               :lisp ,(make-instance 'lisp-exe:ecl :exe-path "ecl" :compiler :lisp-to-c))
    ("abcl"    :image "abcl:1.9.3-noble-jdk-21" :arches ("amd64" "arm64") :in-devel t
               :lisp ,(make-instance 'lisp-exe:abcl-launcher :exe-path "abcl"))
    ("clisp"   :image "clisp:2.49.92-trixie" :arches ("amd64" "arm64") :in-devel t
               :lisp ,(make-instance 'lisp-exe:clisp :exe-path "clisp"))
    ("clasp"   :image "clasp:3.0.1-trixie" :arches ("amd64" "arm64") :in-devel t
               :lisp ,(make-instance 'lisp-exe:clasp :exe-path "clasp")
               :memory "6g")
    ;; dotcl installs its own Quicklisp dist (patched libraries, served
    ;; over https) into any Quicklisp it loads, and that dist then takes
    ;; precedence for every lisp sharing the directory, whose Quicklisp
    ;; client cannot fetch https: so dotcl gets an agent and a
    ;; Quicklisp of its own (see *AGENTS* below).
    ("dotcl"   :image "dotcl:0.1.36-noble" :arches ("amd64" "arm64") :own-quicklisp t
               :lisp ,(make-instance 'lisp-exe:dotcl :exe-path "dotcl"))
    ("cmucl"   :image "cmucl:21f-trixie" :arches ("amd64") :in-devel t
               :lisp ,(make-instance 'lisp-exe:cmucl :exe-path "cmucl"))
    ;; The glibc build of EGCL: the musl one is static and cannot
    ;; dlopen, so nothing over CFFI loads there.  Both report the same
    ;; implementation identifier.  Its polyfill manifest carries Green's
    ;; EGCL forks of the libraries the stock dist refuses it.  (A
    ;; "no primary method found" from every quickload on 2026-11-03 was
    ;; not this image but Quicklisp's client rebuilding the
    ;; local-projects index on a lisp it has no DIRECTORY-ENTRIES for;
    ;; the preferred lisp rebuilds it now, see TEST-OVERLAY.)
    ("egcl"    :image "egcl:0.0.11-trixie-gnu" :arches ("amd64" "arm64") :in-devel t
               :polyfill "polyfills/egcl.sexp"
               :lisp ,(make-instance 'lisp-exe:egcl :exe-path "egcl"))
    ("allegro" :image "allegro:11.0express-trixie" :arches ("amd64" "arm64")
               :lisp ,(make-instance 'lisp-exe:acl :exe-path "alisp")
               :run-args ("--env" "I_AGREE_TO_ALLEGRO_EXPRESS_LICENSE=yes")
               :needs-license t)))

(defun devel-p (entry)
  "True when ENTRY's lisp runs from *DEVEL-IMAGE*."
  (and *devel-image* (getf (rest entry) :in-devel)))

(defun entry-image (entry)
  (concatenate 'string *image-prefix*
               (if (devel-p entry) *devel-image* (getf (rest entry) :image))))

(defun docker-lisp (entry)
  (destructuring-bind (name &key lisp (memory (env "TEST_GRID_MEMORY" "4g")) run-args
                       &allow-other-keys)
      entry
    (declare (ignore name))
    (make-instance 'lisp-exe:docker
                   :image (entry-image entry)
                   :docker-lisp lisp
                   :volumes (list *this-dir* *work-dir*)
                   ;; The open-files limit is pinned because CCL starts a
                   ;; child by closing every descriptor up to the soft
                   ;; limit, one close() each, before the exec; a daemon
                   ;; whose default is a billion makes every run-program
                   ;; take an hour (see run-agent-docker.sh).
                   :docker-run-args (append (list "--memory" memory
                                                  "--ulimit" "nofile=1024:1048576")
                                            ;; cl-devel runs as its user cl (uid
                                            ;; 1000); the work directory belongs
                                            ;; to root, as in the other images
                                            (when (devel-p entry)
                                              (list "--user" "0:0"))
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
  (let ((image (entry-image entry)))
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

;;; Agents.  The lisps share one agent, one work directory and one
;;; private Quicklisp, except those marked :own-quicklisp in the
;;; catalog: each of those gets an agent of its own under
;;; <work dir>/<name>/, with a lock port of its own (Anton's rule for
;;; several agents on one machine: different ports, different work
;;; directories).  They run one after the other.

(defparameter *user-email*
  (or (env "TEST_GRID_USER_EMAIL")
      (error "TEST_GRID_USER_EMAIL is not set")))

(defparameter *projects* (env-list "TEST_GRID_PROJECTS"))

(when *projects*
  (format t "~&Testing only the projects ~{~A~^, ~}~%" *projects*))

(unless (env "CL_TEST_GRID_TOKEN")
  (error "CL_TEST_GRID_TOKEN is not set; the results could not be uploaded"))

(defun make-agent (entries work-dir lock-port)
  (let* ((lisps (mapcar #'docker-lisp entries))
         ;; SBCL does the auxiliary work (updating Quicklisp, listing
         ;; its projects) when it is among the lisps; otherwise one is
         ;; made for the purpose.
         (preferred (or (let ((sbcl (position "sbcl" entries :key #'first :test #'string=)))
                          (and sbcl (nth sbcl lisps)))
                        (docker-lisp (find "sbcl" *catalog* :key #'first :test #'string=))))
         (agent (test-grid-agent:make-agent
                 :lisps lisps
                 :preferred-lisp preferred
                 :user-email *user-email*
                 :work-dir work-dir
                 :singleton-lock-port lock-port)))
    (when *projects*
      (setf (test-grid-agent::custom-project-names agent) *projects*))
    (list :names (mapcar #'first entries) :agent agent
          ;; the manifest of a lisp alone in its agent, if it has one
          :polyfill (let ((manifest (and (null (rest entries)) (getf (rest (first entries)) :polyfill))))
                      (and manifest (merge-pathnames manifest *this-dir*))))))

(defun own-agent-p (entry)
  "An entry whose lisp runs from an agent and a Quicklisp of its own."
  (or (getf (rest entry) :own-quicklisp)
      (getf (rest entry) :polyfill)))

(defparameter *agents*
  (let ((shared (remove-if #'own-agent-p *entries*))
        (own (remove-if-not #'own-agent-p *entries*))
        (port 7685))
    (append (when shared
              (list (make-agent shared *work-dir* port)))
            (loop for entry in own
               collect (make-agent (list entry)
                                   (merge-pathnames (format nil "~A/" (first entry)) *work-dir*)
                                   (incf port))))))

;;; Overlays: a branch of a project's repository in place of the
;;; dist's release of it, tested as a lib-world of its own.  The
;;; clone is kept under the agent's private Quicklisp, so the
;;; children's fasl translation covers it, and is moved into
;;; local-projects/ for its pass only: Quicklisp prefers
;;; local-projects over the dist, and nothing else ever puts anything
;;; there.

(defun quicklisp-dir (agent)
  (merge-pathnames "quicklisp/" (test-grid-agent:work-dir agent)))

(defun overlays-dir (agent)
  (merge-pathnames "overlays/" (quicklisp-dir agent)))

(defun local-projects-dir (agent)
  (merge-pathnames "local-projects/" (quicklisp-dir agent)))

(defun parse-overlay (spec)
  (let ((eq (position #\= spec))
        (hash (position #\# spec :from-end t)))
    (unless (and eq hash (< eq hash))
      (error "TEST_GRID_OVERLAYS entry ~S: expected <project>=<git url>#<branch>" spec))
    (list :project (string-downcase (subseq spec 0 eq))
          :url (subseq spec (1+ eq) hash)
          :branch (subseq spec (1+ hash)))))

(defparameter *overlays* (mapcar #'parse-overlay (env-list "TEST_GRID_OVERLAYS")))

(defun run (&rest command)
  (string-trim '(#\Newline #\Return #\Space)
               (uiop:run-program command :output :string :error-output t)))

(defun overlay-clone-dir (agent overlay)
  (merge-pathnames (format nil "~A@~A/" (getf overlay :project) (getf overlay :branch))
                   (overlays-dir agent)))

(defun fetch-overlay (agent overlay)
  "Clones the branch, or brings the clone up to date; returns the commit."
  (let ((dir (overlay-clone-dir agent overlay))
        (branch (getf overlay :branch)))
    (ensure-directories-exist (overlays-dir agent))
    (if (probe-file (merge-pathnames ".git/" dir))
        (progn
          (run "git" "-C" (namestring dir) "fetch" "--depth" "1" "origin" branch)
          (run "git" "-C" (namestring dir) "reset" "--hard" "--quiet" "FETCH_HEAD"))
        (uiop:run-program (list "git" "clone" "--depth" "1" "--branch" branch
                                (getf overlay :url) (namestring dir))
                          :output t :error-output t))
    (run "git" "-C" (namestring dir) "rev-parse" "--short=8" "HEAD")))

(defun dist-lib-world (agent)
  "The lib-world name of the agent's Quicklisp dist, as the agent names it."
  (let (name version)
    (with-open-file (in (merge-pathnames "dists/quicklisp/distinfo.txt" (quicklisp-dir agent)))
      (loop for line = (read-line in nil)
         while line
         do (cond ((uiop:string-prefix-p "name: " line) (setf name (subseq line 6)))
                  ((uiop:string-prefix-p "version: " line) (setf version (subseq line 9))))))
    (format nil "~A ~A" name version)))

(defun clear-local-projects (agent)
  "Nothing of ours stays in local-projects/ between passes; a pass that
died mid-way may have left its clone there, and it must not be taken
for the dist."
  (let ((local-projects (local-projects-dir agent)))
    (when (probe-file local-projects)
      (dolist (dir (uiop:subdirectories local-projects))
        (format t "~&Removing ~A left in local-projects/~%" dir)
        (uiop:delete-directory-tree dir :validate t))
      (uiop:delete-file-if-exists (merge-pathnames "system-index.txt" local-projects)))))

(defun test-overlay (agent overlay &key (base (dist-lib-world agent)))
  "Tests OVERLAY's project from its branch as a lib-world over BASE, the
dist's lib-world or a polyfilled one."
  (let* ((project (getf overlay :project))
         (commit (fetch-overlay agent overlay))
         (lib-world (format nil "~A + ~A@~A ~A" base project (getf overlay :branch) commit))
         (clone (overlay-clone-dir agent overlay))
         (local-projects (local-projects-dir agent))
         (in-place (merge-pathnames (format nil "~A/" project) local-projects)))
    (format t "~&Testing ~A from ~A, branch ~A at ~A, as the lib-world ~S~%"
            project (getf overlay :url) (getf overlay :branch) commit lib-world)
    (finish-output)
    (ensure-directories-exist local-projects)
    (run "mv" (string-right-trim "/" (namestring clone)) (string-right-trim "/" (namestring in-place)))
    ;; Quicklisp rebuilds local-projects/system-index.txt in whichever
    ;; lisp next looks, through DIRECTORY-ENTRIES, which its client
    ;; implements for a fixed list of lisps (not EGCL): so the preferred
    ;; lisp rebuilds it now, while the directory is newer than the index.
    (refresh-local-projects agent)
    (unwind-protect
         (test-grid-agent:test-patched-quicklisp agent (quicklisp-dir agent) lib-world
                                                 :project-names (list project))
      (run "mv" (string-right-trim "/" (namestring in-place)) (string-right-trim "/" (namestring clone)))
      (uiop:delete-file-if-exists (merge-pathnames "system-index.txt" local-projects)))))

;;; Polyfills: the dist built from the lisp's manifest, installed over
;;; the stock one in the agent's private Quicklisp by a child of the
;;; preferred lisp (the Quicklisp client's work; see
;;; agent/proc-install-dist.lisp), removed again before the next stock
;;; pass.

(defun run-in-preferred-lisp (agent timeout &rest forms)
  "Runs FORMS in a child of the agent's preferred lisp with the private
Quicklisp and agent/proc-install-dist.lisp loaded; the last form's
value is returned (through a response file, as the agent does it)."
  ;; the response file must be where the child can write it: under
  ;; the work directory, mounted into the child's container (the agent
  ;; binds this the same way around its own children)
  (let ((lisp-exe:*temp-dir* (test-grid-agent:work-dir agent)))
    (test-grid-agent::with-response-file (response-file)
      (apply #'lisp-exe:run-with-timeout timeout
             (test-grid-agent::preferred-lisp agent)
             `(load ,(merge-pathnames "setup.lisp" (quicklisp-dir agent)))
             `(load ,(truename (test-grid-agent::src-file "proc-common.lisp")))
             `(load ,(truename (test-grid-agent::src-file "proc-install-dist.lisp")))
             (append (butlast forms)
                     (list `(cl-user::set-response ,response-file ,(car (last forms)))))))))

(defun refresh-local-projects (agent)
  "Rebuilds the private Quicklisp's local-projects index in the preferred lisp."
  (when (probe-file (merge-pathnames "setup.lisp" (quicklisp-dir agent)))
    (run-in-preferred-lisp agent 600 '(progn (ql:register-local-projects) t))))

(defun remove-polyfill (agent manifest-file)
  "Takes the polyfill dist out of the agent's Quicklisp, if it is there."
  (when (probe-file (merge-pathnames "setup.lisp" (quicklisp-dir agent)))
    (let ((name (tg-polyfill:dist-name (tg-polyfill:read-manifest manifest-file))))
      (when (run-in-preferred-lisp agent 600 `(cl-user::remove-polyfill-dist ,name))
        (format t "~&Removed the ~A dist before the stock pass.~%" name)))))

(defun install-polyfill (agent manifest-file)
  "Builds the manifest's dist and installs it over the stock one;
returns the lib-world name of the polyfilled Quicklisp."
  (multiple-value-bind (distinfo-url version name)
      (tg-polyfill:build-dist manifest-file (merge-pathnames "polyfill/" (test-grid-agent:work-dir agent))
                              :stock-systems-file (merge-pathnames "dists/quicklisp/systems.txt" (quicklisp-dir agent)))
    (format t "~&Installing ~A ~A into ~A~%" name version (quicklisp-dir agent))
    (finish-output)
    (let ((installed (run-in-preferred-lisp agent 1800 `(cl-user::install-polyfill-dist ,name ,distinfo-url))))
      (unless (string= installed version)
        (error "~A: installed version ~A, built ~A" name installed version))
      (format nil "~A + ~A ~A" (dist-lib-world agent) name version))))

(defun overlay-dependencies (agent overlay feature)
  "The systems the overlay's branch depends on, read from its .asd
files with FEATURE (the lisp's) among the features: a branch may want
releases the dist's release of the project does not (devo's glisp
wants cl-smtp), and the prefetch must know."
  (let ((clone (overlay-clone-dir agent overlay)))
    (when (probe-file (merge-pathnames ".git/" clone))
      (remove-duplicates
       (loop for asd in (tg-polyfill:asd-files clone)
          append (loop for system in (tg-polyfill:read-asd-systems asd feature)
                    append (rest system)))
       :test #'string=))))

(defun prefetch (agent manifest-file)
  "Has the preferred lisp fetch and unpack what the coming pass needs
into the agent's Quicklisp (installing the Quicklisp first if need
be): the lisp under test may not be able to download for itself.
The overlays are cloned here too, so their branches' dependencies
are among what is fetched."
  (let ((lisp-exe:*temp-dir* (test-grid-agent:work-dir agent)))
    (test-grid-agent::update-testing-quicklisp agent "quicklisp"))
  (dolist (overlay *overlays*)
    (fetch-overlay agent overlay))
  (let* ((feature (getf (tg-polyfill:read-manifest manifest-file) :feature))
         (names (when *projects*
                  (remove-duplicates
                   (append *projects*
                           (mapcar (lambda (overlay) (getf overlay :project)) *overlays*)
                           (loop for overlay in *overlays* append (overlay-dependencies agent overlay feature)))
                   :test #'string=))))
    (format t "~&Prefetching ~:[the whole dist~;~:*~{~A~^, ~} and their dependencies~] ...~%" names)
    (finish-output)
    (format t "~&Prefetched: ~A releases installed.~%"
            (run-in-preferred-lisp agent 7200
                                   ;; and a fresh local-projects index (see TEST-OVERLAY)
                                   '(ql:register-local-projects)
                                   `(cl-user::prefetch-releases ',names)))))

(defun test-polyfilled (agent lib-world)
  "The whole dist on the polyfilled Quicklisp, or TEST_GRID_PROJECTS
without marking the lisp tested (the full pass is still owed)."
  (format t "~&Testing the lib-world ~S~%" lib-world)
  (finish-output)
  (test-grid-agent:test-patched-quicklisp agent (quicklisp-dir agent) lib-world
                                          :project-names *projects*
                                          :mark-tested (null *projects*)))

;;; The runs: for each agent, the dist, then the overlays; then, for a
;;; lisp with a polyfill, the polyfilled dist and the overlays again.

(dolist (entry *agents*)
  (let ((agent (getf entry :agent))
        (manifest (getf entry :polyfill)))
    (format t "~&Agent for ~{~A~^, ~}, work directory ~A~@[, polyfill ~A~]~%"
            (getf entry :names) (test-grid-agent:work-dir agent) manifest)
    (finish-output)
    (clear-local-projects agent)
    (when manifest
      (remove-polyfill agent manifest)
      (prefetch agent manifest))
    (test-grid-agent:main agent)
    (dolist (overlay *overlays*)
      (test-overlay agent overlay))
    (when manifest
      (let ((lib-world (install-polyfill agent manifest)))
        (prefetch agent manifest)
        (test-polyfilled agent lib-world)
        (dolist (overlay *overlays*)
          (test-overlay agent overlay :base lib-world))))))
