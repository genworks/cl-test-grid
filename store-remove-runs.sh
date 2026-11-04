#!/bin/sh
# Removes test runs from the storage: see store-remove-runs.lisp for
# the settings.  Needs a write token: agent.env beside this file is
# read for it.  Usage:
#
#   ./store-remove-runs.sh "<lib-world>" [<implementation identifier>] [<contact email>]

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
TEST_GRID_REMOVE_LIB_WORLD="${1:?usage: $0 \"<lib-world>\" [<lisp>] [<email>]}"
TEST_GRID_REMOVE_LISP="${2:-}"
TEST_GRID_REMOVE_EMAIL="${3:-}"
mkdir -p "$TEST_GRID_WORK_DIR" "$TEST_GRID_WORK_DIR/home"

exec "$DOCKER" run --rm --name test-grid-remove-runs \
    --ulimit nofile=1024:1048576 \
    --user "$(id -u):$(id -g)" \
    --volume "$SRC:$SRC" \
    --volume "$TEST_GRID_WORK_DIR:$TEST_GRID_WORK_DIR" \
    --env HOME="$TEST_GRID_WORK_DIR/home" \
    --env TEST_GRID_WORK_DIR="$TEST_GRID_WORK_DIR" \
    --env TEST_GRID_REMOVE_LIB_WORLD="$TEST_GRID_REMOVE_LIB_WORLD" \
    --env TEST_GRID_REMOVE_LISP="$TEST_GRID_REMOVE_LISP" \
    --env TEST_GRID_REMOVE_EMAIL="$TEST_GRID_REMOVE_EMAIL" \
    --env CL_TEST_GRID_STORE_URL --env CL_TEST_GRID_TOKEN \
    "$TEST_GRID_AGENT_IMAGE" \
    ccl --batch --load "$SRC/store-remove-runs.lisp" --eval "(ccl:quit)"
