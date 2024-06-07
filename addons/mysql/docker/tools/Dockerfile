FROM docker.io/netdata/wget:latest as build

ARG TARGETOS
ARG TARGETARCH

RUN if [ $TARGETARCH == "amd64" ]; then \
    wget https://github.com/moparisthebest/static-curl/releases/download/v8.7.1/curl-amd64; \
    mv ./curl-amd64 /usr/local/bin/curl; \
  else \
    wget https://github.com/moparisthebest/static-curl/releases/download/v8.7.1/curl-aarch64; \
    mv ./curl-aarch64 /usr/local/bin/curl; \
  fi

RUN chmod +x /usr/local/bin/curl

RUN wget https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${TARGETARCH}
RUN mv ./jq-linux-${TARGETARCH} /usr/bin/jq
RUN chmod +x /usr/bin/jq

RUN mkdir /scripts
COPY orchestrator-client.sh /scripts/orchestrator-client
RUN chmod +x /scripts/orchestrator-client


