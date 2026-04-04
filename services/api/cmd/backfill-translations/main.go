package main

import (
	"context"
	"flag"
	"log"

	"daxue/services/api/internal/books"
	"daxue/services/api/internal/config"
	"daxue/services/api/internal/translation"
	"daxue/services/api/internal/zai"
)

func main() {
	bookID := flag.String("book", "", "limit translation backfill to a single book id")
	chapterID := flag.String("chapter", "", "limit translation backfill to a single chapter id")
	flag.Parse()

	cfg := config.Load()
	if cfg.GLMAPIKey == "" {
		log.Fatal("GLM_API_KEY must be configured to backfill translations")
	}

	zaiClient := zai.NewClient(cfg.GLMAPIKey, cfg.GLMBaseURL, nil)
	translator := translation.NewZAITranslator(zaiClient, cfg.GLMModel)
	repository := books.NewFSRepository(cfg.ContentRoot, translator)

	report, err := repository.BackfillMissingTranslations(context.Background(), books.BackfillOptions{
		BookID:    *bookID,
		ChapterID: *chapterID,
	})
	if err != nil {
		log.Fatal(err)
	}

	log.Printf(
		"backfill complete: %d books scanned, %d chapters scanned, %d chapters updated, %d lines translated",
		report.BooksScanned,
		report.ChaptersScanned,
		report.ChaptersUpdated,
		report.LinesTranslated,
	)
}
