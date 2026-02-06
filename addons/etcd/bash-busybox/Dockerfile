FROM debian:bookworm-slim AS builder
ARG TARGETARCH

RUN apt-get update && apt-get install -y bash-static curl ca-certificates

RUN case "${TARGETARCH}" in \
    "amd64") DOWNLOAD_FILE="curl-amd64" ;; \
    "arm64") DOWNLOAD_FILE="curl-armhf" ;; \
    *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    echo "Downloading ${DOWNLOAD_FILE} for ${TARGETARCH}" && \
    curl -L "https://github.com/moparisthebest/static-curl/releases/download/v8.17.0/${DOWNLOAD_FILE}" \
         -o /usr/bin/curl-static && \
    chmod +x /usr/bin/curl-static && \
    /usr/bin/curl-static --version

FROM busybox:1.37.0-musl
COPY --from=builder /bin/bash-static /bin/bash
COPY --from=builder /usr/bin/curl-static /bin/curl
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

CMD ["/bin/bash"]