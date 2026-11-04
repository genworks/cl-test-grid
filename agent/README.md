Running Tests
=============

`test-grid-agent:agent` is a lisp object able
to manage test execution by subordinate lisp
implementations (executables) and submit test
results to server.

It is created with function `test-grid-agent:make-agent`
and has 3 required configuration properties:

- `lisps` - Paths to the lisp implementations
            that should be used to run tests.

- `preferred-lisp` - The lisp implementation used when
               it is necessary to perform an auxiliary task
               requiring a separate lisp process, for example
               downloading libraries to be tested.
               It is therefore desirable to specify here 
               a lisp implementation known to work reliably
               on your platform.

- `user-email` - Your email so that we know who is contributing
               the test results and can contact you. The
               email is also published in the test results
               reports so that library authors or other interested
               parties can contact you with questions about your platform.
               If you are strongly opposed to publish your email,
               you can specify just some nickname here.

Function `test-grid-agent:main` runs the agent.

It is necessary to perform `git pull` on agent sources
often.

There are template scripts demonstrating how to
load, configure and run agent by a single command.

Please use [CCL](http://ccl.clozure.com/) - it is the development platform and the only
lisp known to run agent successfully.

So, the steps:

1. `git clone git://github.com/cl-test-grid/cl-test-grid.git`
2. `cd cl-test-grid`
3. `cp run-agent.sh.sample run-agent.sh; chmod +x run-agent.sh`
4. `cp run-agent.sample.lisp run-agent.lisp`
5. Edit the _run-agent.sh_ (edit one line - the path to CCL).
6. Edit the _run-agent.lisp_ (paths to the lisp implementations, your email)
7. `./run-agent.sh`

Next time all you need is to just invoke `./run-agent.sh`. It will update the 
`cl-test-grid` from git, run tests and upload the results.

Agent keeps log files in the _cl-test-grid/work-dir/agent/logs/_,
where you can control what it has done.

Example crontab record to run agent at 10 o'clock every day:   
``` shell
  # minute hour day_of_month month day_of_week command
  0 10 * * * cd /home/testgrid/cl-test-grid/ && ./run-agent.sh
```

Where the results go
--------------------

The agent uploads logs and test results to the test grid server
(_server/server.lisp_). Two environment variables configure it:

- `CL_TEST_GRID_STORE_URL` - the server's base URL; the default
  is in `tg-utils:*store-url*`.
- `CL_TEST_GRID_TOKEN` - your agent's upload token. Reading is
  public, writing needs a token; ask on the mailing list for one.

Lisps in Docker containers
--------------------------

A lisp implementation can be run from a Docker image, a fresh
container for every child process, for example the images at
https://hub.docker.com/u/clfoundation:

``` common-lisp
(make-instance 'lisp-exe:docker
               :image "clfoundation/sbcl:2.6.10"
               :docker-lisp (make-instance 'lisp-exe:sbcl :exe-path "sbcl")
               :volumes (list #p"/home/testgrid/cl-test-grid/"))
```

Ready-made: _run-agent-docker.sh_ at the top of the source tree runs
the agent in a container with every lisp from the clfoundation images,
needing only docker on the machine; _run-agent-docker.lisp_ holds the
catalog of images and reads the settings (your email, your token, which
lisps, which projects) from the environment or from an _agent.env_ file
beside it.

The clfoundation images carry one implementation each and none of the C
libraries that some Quicklisp systems load through CFFI, so those
systems fail there on a missing library rather than on the lisp. Set
`TEST_GRID_DEVEL_IMAGE` to a tag of `clfoundation/cl-devel` (for
example `cl-devel:58097950`, a commit tag, so the environment of a run is
known) and every lisp that image carries runs from it instead: it holds
SBCL, CCL, ECL, ABCL, CLISP, Clasp, EGCL and, on amd64, CMUCL, beside
the package list of Quicklisp's own build host. dotcl and Allegro keep
their own images. CMUCL is a 32-bit lisp and still cannot load those
64-bit libraries.

A branch of a project's repository can be tested in place of the
dist's release of it: set `TEST_GRID_OVERLAYS` to one or more
`<project>=<git url>#<branch>`, comma-separated, for example
`gendl=https://gitlab.common-lisp.net/gendl/gendl.git#devo`. After the
dist's pass, each overlay is tested as a lib-world of its own, named
like `quicklisp 2026-01-01 + gendl@devo e8f10597`, with the branch
cloned into the private Quicklisp's `local-projects/` for that pass
only. The results sit beside the dist's in the storage, so the reports
compare them (a Quicklisp-diff of the two lib-worlds is the branch
against the release), and a new commit on the branch is a new
lib-world, tested afresh. The systems tested are those the branch's
own .asd files define, so a system the branch retired is not asked
for and a new one is. Members joined by `+` form a set tested together
in one lib-world, for a branch that needs a project the dist lacks:
`gendl=...#devo+batten=https://github.com/genworks/batten.git#devo` is
`quicklisp 2026-01-01 + gendl@devo de9fb09b+batten@devo 06d7ccd6`.

A lisp the stock dist does not serve well yet can carry a polyfill: a
manifest, `polyfills/<lisp>.sexp`, listing the projects that need a
patched source on that lisp for now, each as a git URL and a pinned
commit, with the reason, the upstream status and the condition for
retiring the entry. The catalog names it (`:polyfill
"polyfills/egcl.sexp"`). Such a lisp gets an agent and a private
Quicklisp of its own, and is tested twice: on the stock dist, and on the
stock dist with the polyfill dist installed over it, as the lib-world
`quicklisp 2026-01-01 + polyfill-egcl 2026-11-03.8d1d0e` (the manifest's
version and six hex of its hash). `build-polyfill-dist.lisp` makes that
dist on the agent host (a real Quicklisp dist: archives, releases.txt,
systems.txt, distinfo.txt, under `<work dir>/polyfill/<version>/`) and
`agent/proc-install-dist.lisp` installs it from `file://` URLs, through
a file scheme added to the Quicklisp client's fetch table, so nothing
is served. The overlays run on both lib-worlds. The reports put every
entry's stock and polyfilled results side by side in
`polyfills/<lisp>.html` and mark an entry retirable once the stock
release passes: the manifest is meant to shrink to nothing as the
patches reach upstream.

A lisp whose vendor publishes a dist of patched libraries that the
lisp installs into any Quicklisp it touches (dotcl) names that dist in
its manifest (`:vendor-dist`) as the base its entries are layered on,
and gives the forms that keep the dist out (`:stock-forms`, evaluated
ahead of everything in each of its children during the stock pass).
Its stock and polyfilled worlds then live in two private Quicklisps,
`quicklisp/` and `polyfilled/quicklisp/` under the agent's work
directory, since a home that once took the vendor dist keeps it; the
lib-world carries both versions, `quicklisp 2026-01-01 + polyfill-dotcl
2026-10-27+2026-11-03.eec61f`.

A pass over a whole dist runs every system in a fresh process, some
6,000 of them for a Quicklisp dist, so it takes a day or so per lisp.
Three things keep that in hand.  `TEST_GRID_PARALLEL=N` makes
_run-agent-docker.sh_ run the lisps of `TEST_GRID_LISPS` as N agents at
a time, one container and one work directory (so one private Quicklisp
and one record of what was tested) per lisp, under
`<work dir>/parallel/<lisp>/`, each writing _run.log_ there.  A
`closure:<project>` entry in `TEST_GRID_PROJECTS` stands for that project
and every release it needs, transitively, as the dist's index has it:
`closure:gendl` is the slice of the dist Gendl's users meet, hours
rather than a day, and a natural first pass for a lisp or a polyfill
before the whole dist.  And agents coordinate through the server: before
a run that would count as the lisp tested on the lib-world, the agent
syncs a replica of the results and leaves the pair alone when a full run
of it is there already, or another agent's claim of it not two days old;
otherwise it records a claim of its own and goes ahead.  So several
machines, ours and volunteers', share the catalog without doing the same
lisp on the same dist twice, and a machine that joins late finds only
what is left.  `TEST_GRID_COORDINATE=no` switches that off, which a
host must say to redo a pair it already has in the storage.

Volunteering a machine
----------------------

Any Linux machine with docker and a few spare cores can join the grid
and shorten the pass over a dist: clone this repository, put your email,
your upload token (ask on the mailing list) and the lisps you want to
run in _agent.env_, and run _run-agent-docker.sh_ from cron.  The
coordination above means your agent takes only pairs nobody has done,
and the reports credit the results to your email.  The branches under
test (`TEST_GRID_OVERLAYS`) and the polyfills are configuration too:
a volunteer who sets neither tests the dist as published, and nothing
else.

`:docker-lisp` is the lisp-exe of the implementation inside the image.
`:volumes` must list the cl-test-grid source directory and the agent's
work directory (if it is not under the source directory): they are
mounted into the container at the same paths. If the agent itself runs
in a container, talking to the Docker daemon through its socket, those
directories must have the same paths on the Docker host too. On a timeout
the agent stops the container with `docker kill`.

Details of what agent actually does
-----------------------------------

Simplified, the agent mode of operation may be represented
by the following pseudo code:

``` common-lisp
   (let ((current-quicklisp (update-quicklisp)))
     (loop for lisp in my-lisp-implementations
        (when (not (tested-already lisp current-quicklisp))
           (let ((results-dir (complete-test-run lisp (or (find-unfinished-test-run lisp current-quicklisp)
                                                          (make-new-test-run lisp current-quicklisp)))))
              (submit-results results-dir)
              (remember-tested lisp current-quicklisp)
              (cl-fad:delete-directory-and-files results-dir)))))
```

As you can see, the agent submits test results after
completing full test set on a single lisp implementation. 

The code, including the internal implementation
of `complete-test-run` is organized so that agent can
be interrupted (computer rebooted or hibernated,
agent process killed). When started again, it continues
the work from the point of interruption.

Testing single lisp implementation may take from 1-2
hours up to 10 hours or more (for ABCL - ABCL has long
startup time, which becomes significant in our use case
as we run every test suite or ASDF system compilation
in a fresh lisp process).

**Caveat of killing the agent:** if you killed the agent process
(without rebooting the machine), the subordinate process
running current testsuite or compiling current ASDF system
remains alive. Typically it takes less than a minute for
it to finish, but sometimes it may take longer (the
testsuite or library compilation may require longer
time; or, in the worst case, test suite may hang).
If you start agent again, it spawns new test running
process, which can interfere with the old one via file
system (.fasl files, output logs). Therefore it's better
to give the old child process time to finish before
starting the agent again.

Parallel execution of multiple agents
-------------------------------------

Agent operates sequentially.

During its work, agent keeps its working data in
a directory specified by the configuration property
- `work-dir` - Defaults to the _&lt;cl-test-grid source code root&gt;/work-dir/agent/_

The agent takes measures to ensure there is only
one agent instance using this working directory.

This is achieved by using a TCP port as an inter-process
lock. When started, agent tries to open a socket on
the port. If it is successful, the agent continues.
If the port is busy, the agent deduces there is
another agent instance running, logs a warning
and exists.

The port number is specified by the configuration
property
- `singleton-lock-port` defaults to 7685.

If you want to run several agent processes
and distribute testing work between them,
you can assign each agent different set 
of lisp implementations and give each
agent different working directory and lock
port.

Getting assistance
------------------

Feel free to contact us if you have any questions or
difficulties (see the mailing list address below).

Source Code Guide
=================

The key components, from bottom up:
- [`lisp-exe`](lisp-exe.lisp) Represents lisp implementation executable and allows to start
  child lisp process to execute some lisp code. Supports timeouts: if the child
  lisp process exceeds the specified timeout, it is killed and corresponding
  condition is signalled.
- On top of it the function [`complete-test-run`](complete-test-run.lisp) is built.
  It runs tests on the specified `lisp-exe` and quicklisp installation,
  and stores test results in a directory. If the testing process is
  interrupted and started again with the same output directory, it continues
  from the point of interruption.
- [`submit-test-run-results`](submit-results.lisp) submits log files and test
  results from test run output directory to online storage.
- Finally, on top of these components [`agent`](agent.lisp) object is build. It maintains
  private quicklisp installation in working directory and updates it to the
  latest version every time when started. It also remembers what lisp implementations
  were tested on what quicklisp version. This information kept in 
  [`persistence`](persistence.lisp) - a simple plist saved in file.
  Also agent checks the configuration parameters provided by user and ensures only
  one agent instance is run at time, using a TCP port, as described above.
  The agent public API is specified in the [_package.lisp_](package.lisp).

The source files naming convention _proc-*.lisp_ is used for files executed
by child lisp processes started via `lisp-exe`.


  
