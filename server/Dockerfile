# The test grid server.  Build from the repository root:
#
#   docker build -f server/Dockerfile -t cl-test-grid-server .
#   docker run -d -p 127.0.0.1:8080:8080 -v /srv/cl-test-grid:/data cl-test-grid-server
#
# /data holds everything the server keeps; put the write tokens in
# /data/tokens.lisp as ((<token> <who>) ...).  See server/run-server.lisp
# for the other settings.

FROM clfoundation/sbcl:2.6.10

ENV QUICKLISP_ADD_TO_INIT_FILE=true
RUN install-quicklisp

COPY . /cl-test-grid
RUN sbcl --non-interactive \
         --eval '(push #p"/cl-test-grid/" asdf:*central-registry*)' \
         --eval '(ql:quickload :test-grid-server)'

ENV TEST_GRID_SERVER_DATA_DIR=/data
VOLUME /data
EXPOSE 8080

CMD ["sbcl", "--non-interactive", "--load", "/cl-test-grid/server/run-server.lisp"]
