FROM golang:1.26.5-alpine3.23 AS builder

WORKDIR /src
COPY go.mod go.sum ./
COPY vendor ./vendor
RUN --network=none go list -mod=vendor all >/dev/null
COPY . .
RUN --network=none CGO_ENABLED=0 GOOS=linux go build -mod=vendor -trimpath -ldflags="-s -w" -o /out/hugegraph-exporter ./cmd/hugegraph-exporter

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/hugegraph-exporter /hugegraph-exporter
EXPOSE 9404
ENTRYPOINT ["/hugegraph-exporter"]
