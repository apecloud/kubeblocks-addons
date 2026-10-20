FROM golang:1.22.12-alpine3.21 AS builder

ARG TARGETOS=linux
ARG TARGETARCH

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/hugegraph-exporter ./cmd/hugegraph-exporter

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/hugegraph-exporter /hugegraph-exporter
EXPOSE 9404
ENTRYPOINT ["/hugegraph-exporter"]
