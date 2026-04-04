package books

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestBundledReadingUnitsHaveEnglishTranslations(t *testing.T) {
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("failed to resolve current file path")
	}

	booksRoot := filepath.Clean(filepath.Join(filepath.Dir(currentFile), "..", "..", "..", "..", "content", "books"))
	chapterPaths, err := filepath.Glob(filepath.Join(booksRoot, "*", "chapters", "*.json"))
	if err != nil {
		t.Fatalf("glob chapter files: %v", err)
	}

	type unit struct {
		ID                  string `json:"id"`
		TranslationEn       string `json:"translation_en"`
		GeneratedAnnotation *struct {
			Layers struct {
				TranslationEn string `json:"translation_en"`
			} `json:"layers"`
		} `json:"generated_annotation"`
	}
	type document struct {
		Chapter struct {
			ReadingUnits []unit `json:"reading_units"`
		} `json:"chapter"`
	}

	var missing []string
	for _, chapterPath := range chapterPaths {
		contents, err := os.ReadFile(chapterPath)
		if err != nil {
			t.Fatalf("read %s: %v", chapterPath, err)
		}

		var chapter document
		if err := json.Unmarshal(contents, &chapter); err != nil {
			t.Fatalf("decode %s: %v", chapterPath, err)
		}

		for _, readingUnit := range chapter.Chapter.ReadingUnits {
			generated := ""
			if readingUnit.GeneratedAnnotation != nil {
				generated = readingUnit.GeneratedAnnotation.Layers.TranslationEn
			}
			if strings.TrimSpace(readingUnit.TranslationEn) == "" && strings.TrimSpace(generated) == "" {
				missing = append(missing, chapterPath+"#"+readingUnit.ID)
			}
		}
	}

	if len(missing) > 0 {
		limit := len(missing)
		if limit > 20 {
			limit = 20
		}
		t.Fatalf("missing English translations for %d reading units; sample: %v", len(missing), missing[:limit])
	}
}
