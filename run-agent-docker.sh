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

set -e
cd "$(dirname "$0")"
SRC=$(pwd)

[ -f agent.env ] && . ./agent.env
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

exec "$DOCKER" run --rm --name test-grid-agent \
    --volume "$TEST_GRID_DAEMON_SOCKET:/var/run/docker.sock" \
    --volume "$CLI:/usr/local/bin/docker:ro" \
    --volume "$SRC:$SRC" \
    --volume "$TEST_GRID_WORK_DIR:$TEST_GRID_WORK_DIR" \
    --env HOME="$TEST_GRID_WORK_DIR/home" \
    --env TEST_GRID_WORK_DIR="$TEST_GRID_WORK_DIR" \
    --env TEST_GRID_USER_EMAIL --env TEST_GRID_LISPS --env TEST_GRID_PROJECTS \
    --env TEST_GRID_MEMORY --env TEST_GRID_ALLEGRO_LICENSE_AGREED --env TEST_GRID_IMAGE_PREFIX \
    --env CL_TEST_GRID_STORE_URL --env CL_TEST_GRID_TOKEN \
    "$TEST_GRID_AGENT_IMAGE" \
    ccl --batch --load "$SRC/run-agent-docker.lisp" --eval "(ccl:quit)"
