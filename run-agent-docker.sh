#!/bin/sh
# Runs the test grid agent in a container (clfoundation/ccl), testing
# every lisp from its Docker image: see run-agent-docker.lisp for the
# settings, taken from the environment or from agent.env beside this
# file.  Needs docker on this machine and nothing else.
#
# The agent container reaches this machine's Docker daemon through its
# socket and starts the lisps as sibling containers, so the source and
# work directories must be visible to the daemon under the same paths
# as here (true on Linux, and under colima or Docker Desktop for paths
# in your home directory).
#
# Example crontab line, once a day:
#   0 3 * * * /home/testgrid/cl-test-grid/run-agent-docker.sh >> /home/testgrid/cl-test-grid/work-dir/cron.log 2>&1
#
# One agent tests its lisps one after the other.  TEST_GRID_PARALLEL=N
# runs the lisps of TEST_GRID_LISPS as N agents at a time instead, one
# container per lisp (test-grid-agent-<lisp>), each with a work
# directory of its own under $TEST_GRID_WORK_DIR/parallel/<lisp>/ --
# so a private Quicklisp each, and its own record of what it has
# tested -- and its output in run.log there.  A full pass over a dist
# takes a day or so per lisp (every system in a fresh process), so this
# is how a machine with the memory for it gets through the catalog in
# days rather than weeks.  The children's memory is capped per lisp
# (TEST_GRID_MEMORY, 4g by default); allow for N of them.

set -e
cd "$(dirname "$0")"
SRC=$(pwd)

# agent.env holds this machine's settings; a setting given on the
# command line (TEST_GRID_LISPS=egcl ./run-agent-docker.sh, or
# TEST_GRID_DEVEL_IMAGE= to leave cl-devel out for one run) wins over
# it, so the values already in the environment are kept across the
# sourcing.  (Plain if/then: under set -e an && list whose test fails
# ends the script, silently, at the first setting agent.env leaves
# unset -- which is how two runs on 2026-11-03 died with nothing but
# nohup's line in their log.)
SETTINGS="TEST_GRID_USER_EMAIL TEST_GRID_LISPS TEST_GRID_PROJECTS TEST_GRID_WORK_DIR TEST_GRID_MEMORY TEST_GRID_IMAGE_PREFIX TEST_GRID_DEVEL_IMAGE TEST_GRID_OVERLAYS TEST_GRID_ALLEGRO_LICENSE_AGREED TEST_GRID_AGENT_IMAGE TEST_GRID_DAEMON_SOCKET TEST_GRID_PARALLEL TEST_GRID_COORDINATE CL_TEST_GRID_STORE_URL CL_TEST_GRID_TOKEN DOCKER DOCKER_HOST"
if [ -f agent.env ]; then
    for v in $SETTINGS; do
        eval "if [ -n \"\${$v+set}\" ]; then keep_$v=\"\$$v\"; kept_$v=1; fi"
    done
    . ./agent.env
    for v in $SETTINGS; do
        eval "if [ -n \"\${kept_$v:-}\" ]; then $v=\"\$keep_$v\"; fi"
    done
fi
# Every setting goes to the container as an environment variable, so a
# line in agent.env counts with or without `export` (a bare
# TEST_GRID_DEVEL_IMAGE=... line once ran a whole pass on the bare images).
for v in $SETTINGS; do
    eval "if [ -n \"\${$v+set}\" ]; then export $v; fi"
done
: "${TEST_GRID_WORK_DIR:=$SRC/work-dir/agent}"
: "${TEST_GRID_AGENT_IMAGE:=clfoundation/ccl:1.14-trixie}"
: "${DOCKER_CLI_VERSION:=28.5.1}"
: "${DOCKER:=docker}"
mkdir -p "$TEST_GRID_WORK_DIR" "$TEST_GRID_WORK_DIR/home"

# A Linux docker client for the agent container, matching this
# machine's architecture (this machine's own client may be a Mac one).
case "$(uname -m)" in
    arm64|aarch64) CLI_ARCH=aarch64 ;;
    *) CLI_ARCH=x86_64 ;;
esac
CLI="$TEST_GRID_WORK_DIR/docker-cli/$DOCKER_CLI_VERSION-$CLI_ARCH/docker"
if [ ! -x "$CLI" ]; then
    mkdir -p "$(dirname "$CLI")"
    curl -fsSL "https://download.docker.com/linux/static/stable/$CLI_ARCH/docker-$DOCKER_CLI_VERSION.tgz" \
        | tar -xz -C "$(dirname "$CLI")" --strip-components=1 docker/docker
fi

# The daemon's socket, as a path the DAEMON can bind-mount: under
# colima or Docker Desktop the daemon runs in a VM, where its socket is
# /var/run/docker.sock whatever DOCKER_HOST says on this side.
: "${TEST_GRID_DAEMON_SOCKET:=/var/run/docker.sock}"

# The open-files limit is pinned (soft 1024, hard 1048576, the usual
# Linux defaults) because CCL starts every child process by closing
# each descriptor from 3 up to the soft limit, one close() at a time,
# before the exec.  Some daemons give containers a soft limit of
# 1073741816, and then every docker command the agent runs sits in
# that loop for the best part of an hour, looking hung.  The children
# get the same limit from run-agent-docker.lisp.
#
# run_agent NAME WORK_DIR: the agent container, for the lisps in
# TEST_GRID_LISPS, with WORK_DIR as its work directory.
run_agent() {
    mkdir -p "$2/home"
    "$DOCKER" run --rm --name "$1" \
        --ulimit nofile=1024:1048576 \
        --volume "$TEST_GRID_DAEMON_SOCKET:/var/run/docker.sock" \
        --volume "$CLI:/usr/local/bin/docker:ro" \
        --volume "$SRC:$SRC" \
        --volume "$2:$2" \
        --env HOME="$2/home" \
        --env TEST_GRID_WORK_DIR="$2" \
        --env TEST_GRID_USER_EMAIL --env TEST_GRID_LISPS --env TEST_GRID_PROJECTS \
        --env TEST_GRID_MEMORY --env TEST_GRID_ALLEGRO_LICENSE_AGREED --env TEST_GRID_IMAGE_PREFIX \
        --env TEST_GRID_DEVEL_IMAGE --env TEST_GRID_OVERLAYS --env TEST_GRID_COORDINATE \
        --env CL_TEST_GRID_STORE_URL --env CL_TEST_GRID_TOKEN \
        "$TEST_GRID_AGENT_IMAGE" \
        ccl --batch --load "$SRC/run-agent-docker.lisp" --eval "(ccl:quit)"
}

if [ -z "$TEST_GRID_PARALLEL" ]; then
    run_agent test-grid-agent "$TEST_GRID_WORK_DIR"
    exit $?
fi

# Parallel: one agent per lisp, TEST_GRID_PARALLEL of them at a time.
if [ -z "$TEST_GRID_LISPS" ]; then
    echo "TEST_GRID_PARALLEL needs TEST_GRID_LISPS: the lisps to run, comma-separated." >&2
    exit 2
fi
pids=""
running_count() {
    n=0
    for pid in $pids; do
        kill -0 "$pid" 2>/dev/null && n=$((n + 1))
    done
    echo $n
}
for lisp in $(echo "$TEST_GRID_LISPS" | tr ',' ' '); do
    while [ "$(running_count)" -ge "$TEST_GRID_PARALLEL" ]; do
        sleep 60
    done
    work="$TEST_GRID_WORK_DIR/parallel/$lisp"
    mkdir -p "$work"
    echo "$(date -u +%FT%TZ) Starting the agent for $lisp: work directory $work, output in $work/run.log"
    (
        TEST_GRID_LISPS=$lisp
        export TEST_GRID_LISPS
        run_agent "test-grid-agent-$lisp" "$work" > "$work/run.log" 2>&1
    ) &
    pids="$pids $!"
done
failed=0
for pid in $pids; do
    wait "$pid" || failed=1
done
echo "$(date -u +%FT%TZ) All agents finished$([ $failed = 0 ] || echo ', at least one with an error (see the run.log files)')."
exit $failed
