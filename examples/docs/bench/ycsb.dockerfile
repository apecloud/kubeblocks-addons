ARG YCSB_VERSION
FROM alpine:3.18 AS ycsb-builder

ARG YCSB_VERSION=0.17.0

WORKDIR /build
RUN apk add --no-cache tar curl
RUN curl -O --location https://github.com/brianfrankcooper/YCSB/releases/download/${YCSB_VERSION}/ycsb-${YCSB_VERSION}.tar.gz
# COPY ycsb-${YCSB_VERSION}.tar.gz .
RUN tar xfvz ycsb-${YCSB_VERSION}.tar.gz
RUN rm ycsb-${YCSB_VERSION}.tar.gz

# Main image
FROM openjdk:17-jdk-slim

ARG YCSB_VERSION=0.17.0

RUN apt update && \
    apt install -y python2
RUN ln -sf /usr/bin/python2.7 /usr/bin/python

WORKDIR /ycsb/

COPY --from=ycsb-builder /build/ycsb-${YCSB_VERSION} /ycsb