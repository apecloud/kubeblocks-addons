# rdr (Redis Data Reveal) image used by the redis-rdr-keys-analysis
# OpsDefinition.
#
# The image is based on the official Redis image so that it ships redis-cli
# (including TLS support). This lets the analysis pod trigger BGSAVE on the
# target Redis pod and then parse the resulting RDB file.
#
# Build and push a multi-arch image (amd64 + arm64) in one command:
#   docker buildx build --platform linux/amd64,linux/arm64 \
#     -t apecloud-registry-vpc.cn-zhangjiakou.cr.aliyuncs.com/apecloud/rdr:1.1.9 \
#     --push .
#
# Multi-platform builds cannot be loaded into the local image store; --push is
# required. If needed, create a builder first:
#   docker buildx create --name rdr-builder --use --bootstrap

ARG GOLANG_IMAGE=golang:1.26-alpine
ARG BASE_IMAGE=redis:7.4-bookworm

# Build natively on the build host and cross-compile for the target platform.
# This avoids running the Go compiler under QEMU on multi-arch builders.
FROM --platform=${BUILDPLATFORM} ${GOLANG_IMAGE} AS builder

ARG TARGETOS
ARG TARGETARCH
# SHA256 of the v1.1.9 source tarball; update it when bumping RDR_VERSION.
ARG RDR_VERSION=v1.1.9
ARG RDR_SHA256=8b3ba520620af8f83fb9594317901b73e4dd35c188edaa9939c56b4a5440d5e2

RUN set -eux; \
    apk add --no-cache ca-certificates; \
    wget -qO /tmp/rdr.tar.gz "https://codeload.github.com/919927181/rdr/tar.gz/refs/tags/${RDR_VERSION}"; \
    echo "${RDR_SHA256}  /tmp/rdr.tar.gz" | sha256sum -c -; \
    mkdir -p /src; \
    tar -xzf /tmp/rdr.tar.gz -C /src --strip-components=1; \
    cd /src; \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
        go build -mod=vendor -trimpath -ldflags="-s -w" -o /out/rdr .

FROM ${BASE_IMAGE}

COPY --from=builder /out/rdr /usr/local/bin/rdr
COPY rdr-analyze.sh /usr/local/bin/rdr-analyze.sh
RUN chmod +x /usr/local/bin/rdr /usr/local/bin/rdr-analyze.sh

# The OpsDefinition passes an explicit command. This CMD makes the image
# usable standalone as well, e.g.:
#   docker run --env-file redis.env <image>
CMD ["/usr/local/bin/rdr-analyze.sh"]
