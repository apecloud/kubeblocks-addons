package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/apecloud/kubeblocks-addons/addons/hugegraph/exporter"
)

func main() {
	logger := log.New(os.Stderr, "hugegraph-exporter: ", log.LstdFlags)
	config := exporter.DefaultConfig()
	config.Username = os.Getenv("HUGEGRAPH_USERNAME")
	config.Password = os.Getenv("HUGEGRAPH_PASSWORD")
	metricsExporter, err := exporter.New(config, logger)
	if err != nil {
		logger.Fatal("invalid exporter configuration")
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go metricsExporter.Run(ctx)

	mux := http.NewServeMux()
	mux.Handle("/metrics", metricsExporter.MetricsHandler())
	mux.HandleFunc("/healthz", func(response http.ResponseWriter, _ *http.Request) {
		response.WriteHeader(http.StatusOK)
	})
	server := &http.Server{
		Addr:              ":9404",
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       30 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutdownContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownContext)
	}()

	logger.Printf("serving metrics on %s", server.Addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Fatal("metrics server stopped unexpectedly")
	}
}
