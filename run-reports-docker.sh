#!/bin/sh
# Regenerates the reports in a container (clfoundation/ccl): see
# run-reports-docker.lisp for the settings, taken from the environment
# or from reports.env beside this file.  Needs docker on this machine
# and nothing else; no token, the storage is read.
#
# Example crontab line, once a day, after the agents' runs:
#   0 9 * * * /home/testgrid/cl-test-grid/run-reports-docker.sh >> /home/testgrid/cl-test-grid/work-dir/reports.log 2>&1

set -e
cd "$(dirname "$0")"
SRC=$(pwd)

[ -f reports.env ] && . ./reports.env
: "${TEST_GRID_WORK_DIR:=$SRC/work-dir/reports}"
: "${TEST_GRID_REPORTS_DIR:?set TEST_GRID_REPORTS_DIR to the directory the web server publishes}"
: "${TEST_GRID_AGENT_IMAGE:=clfoundation/ccl:1.14-trixie}"
: "${DOCKER:=docker}"
mkdir -p "$TEST_GRID_WORK_DIR" "$TEST_GRID_WORK_DIR/home" "$TEST_GRID_REPORTS_DIR"

# The open-files limit is pinned for the reason given in
# run-agent-docker.sh.  --user keeps the files it writes owned by the
# user running this, since the reports directory and the work
# directory are theirs.
exec "$DOCKER" run --rm --name test-grid-reports \
    --ulimit nofile=1024:1048576 \
    --user "$(id -u):$(id -g)" \
    --volume "$SRC:$SRC" \
    --volume "$TEST_GRID_WORK_DIR:$TEST_GRID_WORK_DIR" \
    --volume "$TEST_GRID_REPORTS_DIR:$TEST_GRID_REPORTS_DIR" \
    --env HOME="$TEST_GRID_WORK_DIR/home" \
    --env TEST_GRID_WORK_DIR="$TEST_GRID_WORK_DIR" \
    --env TEST_GRID_REPORTS_DIR="$TEST_GRID_REPORTS_DIR" \
    --env CL_TEST_GRID_STORE_URL \
    "$TEST_GRID_AGENT_IMAGE" \
    ccl --batch --load "$SRC/run-reports-docker.lisp" --eval "(ccl:quit)"
