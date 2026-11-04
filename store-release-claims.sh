#!/bin/sh
# Releases claims in the storage, for an agent that died and will not
# be back (otherwise its claims expire on their own after two days):
# see store-release-claims.lisp for the settings.  Needs a write token:
# agent.env beside this file is read for it.  Usage, at least one
# argument, an empty one skipped:
#
#   ./store-release-claims.sh <agent-id> [<implementation identifier>] [<lib-world>]
#   ./store-release-claims.sh "" "sbcl-2.6.10-linux-x64" "quicklisp 2026-01-01"

set -e
cd "$(dirname "$0")"
SRC=$(pwd)

# agent.env is read for the token and the server; a value already in
# the environment wins over it (the agent wrapper does the same)
for v in TEST_GRID_WORK_DIR CL_TEST_GRID_TOKEN CL_TEST_GRID_STORE_URL DOCKER DOCKER_HOST; do
    eval "if [ -n \"\${$v+set}\" ]; then keep_$v=\"\$$v\"; kept_$v=1; fi"
done
[ -f agent.env ] && . ./agent.env
for v in TEST_GRID_WORK_DIR CL_TEST_GRID_TOKEN CL_TEST_GRID_STORE_URL DOCKER DOCKER_HOST; do
    eval "if [ -n \"\${kept_$v:-}\" ]; then $v=\"\$keep_$v\"; fi; if [ -n \"\${$v+set}\" ]; then export $v; fi"
done
: "${TEST_GRID_WORK_DIR:=$SRC/work-dir/reports}"
: "${TEST_GRID_AGENT_IMAGE:=clfoundation/ccl:1.14-trixie}"
: "${DOCKER:=docker}"
[ $# -ge 1 ] || { echo "usage: $0 <agent-id> [<lisp>] [<lib-world>]" >&2; exit 2; }
TEST_GRID_RELEASE_AGENT_ID="${1:-}"
TEST_GRID_RELEASE_LISP="${2:-}"
TEST_GRID_RELEASE_LIB_WORLD="${3:-}"
mkdir -p "$TEST_GRID_WORK_DIR" "$TEST_GRID_WORK_DIR/home"

exec "$DOCKER" run --rm --name test-grid-release-claims \
    --ulimit nofile=1024:1048576 \
    --user "$(id -u):$(id -g)" \
    --volume "$SRC:$SRC" \
    --volume "$TEST_GRID_WORK_DIR:$TEST_GRID_WORK_DIR" \
    --env HOME="$TEST_GRID_WORK_DIR/home" \
    --env TEST_GRID_WORK_DIR="$TEST_GRID_WORK_DIR" \
    --env TEST_GRID_RELEASE_AGENT_ID="$TEST_GRID_RELEASE_AGENT_ID" \
    --env TEST_GRID_RELEASE_LISP="$TEST_GRID_RELEASE_LISP" \
    --env TEST_GRID_RELEASE_LIB_WORLD="$TEST_GRID_RELEASE_LIB_WORLD" \
    --env CL_TEST_GRID_STORE_URL --env CL_TEST_GRID_TOKEN \
    "$TEST_GRID_AGENT_IMAGE" \
    ccl --batch --load "$SRC/store-release-claims.lisp" --eval "(ccl:quit)"
