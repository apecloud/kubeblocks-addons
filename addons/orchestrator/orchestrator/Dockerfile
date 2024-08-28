# ORC_DB_NAME (default: orchestrator): database named used by orchestrator backend MySQL server
# ORC_USER (default: orc_server_user): username used to login to orchestrator backend MySQL server
# ORC_PASSWORD (default: orc_server_password): password used to login to orchestrator backend MySQL server
ARG GO_VERSION=1.16.6-alpine3.14

FROM golang:1.16.6-alpine3.14 as build
FROM golang:${GO_VERSION} as build
ARG TARGETOS
ARG TARGETARCH

ENV GOPATH=/tmp/go

@@ -23,12 +26,12 @@ RUN apk --no-cache add libcurl rsync gcc g++ build-base bash git
RUN mkdir -p $GOPATH/src/github.com/openark/orchestrator
WORKDIR $GOPATH/src/github.com/openark/orchestrator
COPY . .
RUN bash build.sh -b -P
RUN bash build.sh -b -P -a ${TARGETARCH}
RUN rsync -av $(find /tmp/orchestrator-release -type d -name orchestrator -maxdepth 2)/ /
RUN rsync -av $(find /tmp/orchestrator-release -type d -name orchestrator-client -maxdepth 2)/ /
RUN cp conf/orchestrator-sample-sqlite.conf.json /etc/orchestrator.conf.json

FROM alpine:3.14
FROM alpine:3.14 as dist

RUN apk --no-cache add bash curl jq