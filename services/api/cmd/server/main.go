package main

import (
	"log"
	"net"
	"net/http"

	"daxue/services/api/internal/config"
	"daxue/services/api/internal/httpapi"
)

func main() {
	cfg := config.Load()

	server := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: httpapi.NewHandler(cfg),
	}

	listener, err := net.Listen("tcp", server.Addr)
	if err != nil {
		log.Fatal(err)
	}

	log.Printf(
		"api listening on :%s (%s) using content from %s",
		cfg.Port,
		cfg.AppEnv,
		cfg.ContentRoot,
	)
	if cfg.WebAppRoot != "" {
		log.Printf("serving web app from %s", cfg.WebAppRoot)
	}

	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
