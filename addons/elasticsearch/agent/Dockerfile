FROM golang:1.23-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o agent main.go

FROM alpine:3.21

COPY --from=builder /app/agent /usr/local/bin/agent
RUN chmod +x /usr/local/bin/agent

EXPOSE 8080

CMD ["/usr/local/bin/agent"]
