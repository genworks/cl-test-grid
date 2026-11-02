# The test grid server.  Build from the repository root:
#
#   docker build -f server/Dockerfile -t cl-test-grid-server .
#   docker run -d -p 127.0.0.1:8080:8080 -v /srv/cl-test-grid:/data cl-test-grid-server
#
# /data holds everything the server keeps; put the write tokens in
# /data/tokens.lisp as ((<token> <who>) ...).  The docstring of
# TG-SERVER:MAIN lists the other settings.

FROM clfoundation/sbcl:2.6.10 AS build

RUN install-quicklisp

COPY . /cl-test-grid
# TLS is the front web server's job; without it the executable
# needs no libssl.
RUN sbcl --non-interactive \
         --load /root/quicklisp/setup.lisp \
         --eval '(push :hunchentoot-no-ssl *features*)' \
         --eval '(push #p"/cl-test-grid/" asdf:*central-registry*)' \
         --eval '(ql:quickload :test-grid-server)' \
         --eval '(sb-ext:save-lisp-and-die "/tg-server" :executable t :toplevel (function tg-server:main))'

FROM debian:trixie-slim

COPY --from=build /tg-server /usr/local/bin/tg-server

ENV TEST_GRID_SERVER_DATA_DIR=/data
VOLUME /data
EXPOSE 8080

CMD ["tg-server"]
