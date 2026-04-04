package books

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestBackfillMissingTranslationsWritesGeneratedAnnotations(t *testing.T) {
	root := t.TempDir()
	bookDir := filepath.Join(root, "books", "demo-book")
	chaptersDir := filepath.Join(bookDir, "chapters")

	if err := os.MkdirAll(chaptersDir, 0o755); err != nil {
		t.Fatalf("failed to create fixture directories: %v", err)
	}

	catalog := `{
  "title": "Demo Book",
  "chapter_count": 1,
  "source_url": "https://example.com/demo-book",
  "provider": "fixture",
  "chapters": [
    {
      "id": "chapter-001",
      "order": 1,
      "title": "Chapter One",
      "summary": "Opening lines",
      "character_count": 6,
      "reading_unit_count": 2,
      "chapter_path": "books/demo-book/chapters/chapter-001.json"
    }
  ]
}`

	chapter := `{
  "chapter": {
    "character_count": 6,
    "id": "chapter-001",
    "order": 1,
    "reading_unit_count": 2,
    "reading_units": [
      {
        "character_count": 3,
        "generated_annotation": {
          "layers": {
            "translation_en": "The first line was already translated."
          }
        },
        "id": "chapter-001-line-001",
        "order": 1,
        "source_block_chunk": 1,
        "source_block_order": 1,
        "text": "第一行。"
      },
      {
        "character_count": 3,
        "id": "chapter-001-line-002",
        "order": 2,
        "source_block_chunk": 1,
        "source_block_order": 2,
        "text": "第二行。"
      }
    ],
    "summary": "Opening lines",
    "supplemental_text": "",
    "supplemental_unit_count": 0,
    "supplemental_units": [],
    "text": "第一行。第二行。",
    "title": "Chapter One"
  },
  "chapter_path": "books/demo-book/chapters/chapter-001.json",
  "provider": "fixture",
  "schema_version": 2,
  "source_title": "Demo Source",
  "source_url": "https://example.com/demo-book/chapter-001"
}`

	if err := os.WriteFile(filepath.Join(bookDir, "catalog.json"), []byte(catalog), 0o644); err != nil {
		t.Fatalf("failed to write catalog fixture: %v", err)
	}

	chapterPath := filepath.Join(chaptersDir, "chapter-001.json")
	if err := os.WriteFile(chapterPath, []byte(chapter), 0o644); err != nil {
		t.Fatalf("failed to write chapter fixture: %v", err)
	}

	translator := &stubTranslator{
		translations: []string{"The second line is newly translated."},
	}

	repository := NewFSRepository(root, translator)

	report, err := repository.BackfillMissingTranslations(context.Background(), BackfillOptions{
		BookID:    "demo-book",
		ChapterID: "chapter-001",
	})
	if err != nil {
		t.Fatalf("BackfillMissingTranslations returned error: %v", err)
	}

	if report.BooksScanned != 1 {
		t.Fatalf("expected 1 scanned book, got %d", report.BooksScanned)
	}

	if report.ChaptersUpdated != 1 {
		t.Fatalf("expected 1 updated chapter, got %d", report.ChaptersUpdated)
	}

	if report.LinesTranslated != 1 {
		t.Fatalf("expected 1 translated line, got %d", report.LinesTranslated)
	}

	if translator.calls != 1 {
		t.Fatalf("expected 1 translation call, got %d", translator.calls)
	}

	contents, err := os.ReadFile(chapterPath)
	if err != nil {
		t.Fatalf("failed to read updated chapter fixture: %v", err)
	}

	var document chapterDocument
	if err := json.Unmarshal(contents, &document); err != nil {
		t.Fatalf("failed to decode updated chapter fixture: %v", err)
	}

	if translation := document.Chapter.ReadingUnits[0].translationEn(); translation != "The first line was already translated." {
		t.Fatalf("expected existing translation to be preserved, got %q", translation)
	}

	if translation := document.Chapter.ReadingUnits[1].translationEn(); translation != "The second line is newly translated." {
		t.Fatalf("expected generated translation to be written, got %q", translation)
	}

	if document.Chapter.ReadingUnits[1].SourceBlockChunk != 1 {
		t.Fatalf("expected source block chunk to be preserved, got %d", document.Chapter.ReadingUnits[1].SourceBlockChunk)
	}

	if document.Provider != "fixture" {
		t.Fatalf("expected provider to be preserved, got %q", document.Provider)
	}
}
