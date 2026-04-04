package books

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestGetChapterTranslatesOnlyMissingReadingUnits(t *testing.T) {
	translator := &stubTranslator{
		translations: []string{"The second line is newly translated."},
	}

	repository := NewFSRepository(createBooksFixtureRoot(t), translator)

	chapter, err := repository.GetChapter(
		context.Background(),
		"demo-book",
		"chapter-001",
	)
	if err != nil {
		t.Fatalf("GetChapter returned error: %v", err)
	}

	if len(chapter.ReadingUnits) != 2 {
		t.Fatalf("expected 2 reading units, got %d", len(chapter.ReadingUnits))
	}

	if chapter.ReadingUnits[0].TranslationEn != "The first line was already translated." {
		t.Fatalf("expected stored translation to be preserved, got %q", chapter.ReadingUnits[0].TranslationEn)
	}

	if chapter.ReadingUnits[1].TranslationEn != "The second line is newly translated." {
		t.Fatalf("expected generated translation, got %q", chapter.ReadingUnits[1].TranslationEn)
	}

	if translator.calls != 1 {
		t.Fatalf("expected 1 translation call, got %d", translator.calls)
	}

	if len(translator.requests) != 1 {
		t.Fatalf("expected 1 recorded request, got %d", len(translator.requests))
	}

	if translator.requests[0].BookTitle != "Demo Book" {
		t.Fatalf("expected book title Demo Book, got %q", translator.requests[0].BookTitle)
	}

	if translator.requests[0].ChapterTitle != "Chapter One" {
		t.Fatalf("expected chapter title Chapter One, got %q", translator.requests[0].ChapterTitle)
	}

	if len(translator.requests[0].Lines) != 1 || translator.requests[0].Lines[0] != "第二行。" {
		t.Fatalf("expected only the untranslated line to be sent, got %#v", translator.requests[0].Lines)
	}
}

func TestGetChapterCachesGeneratedTranslations(t *testing.T) {
	translator := &stubTranslator{
		translations: []string{"The second line is newly translated."},
	}

	repository := NewFSRepository(createBooksFixtureRoot(t), translator)

	for range 2 {
		chapter, err := repository.GetChapter(
			context.Background(),
			"demo-book",
			"chapter-001",
		)
		if err != nil {
			t.Fatalf("GetChapter returned error: %v", err)
		}

		if chapter.ReadingUnits[1].TranslationEn != "The second line is newly translated." {
			t.Fatalf("expected cached translation, got %q", chapter.ReadingUnits[1].TranslationEn)
		}
	}

	if translator.calls != 1 {
		t.Fatalf("expected cached chapter translation to avoid a second call, got %d calls", translator.calls)
	}
}

func TestGetBookDerivesZhongYongChapterTitlesFromFirstLines(t *testing.T) {
	repository := NewFSRepository(createZhongYongFixtureRoot(t), nil)

	book, err := repository.GetBook("zhong-yong")
	if err != nil {
		t.Fatalf("GetBook returned error: %v", err)
	}

	if len(book.Chapters) != 3 {
		t.Fatalf("expected 3 chapters, got %d", len(book.Chapters))
	}

	if book.Chapters[0].Title != "天命之謂性" {
		t.Fatalf("expected chapter 1 title to be derived, got %q", book.Chapters[0].Title)
	}

	if book.Chapters[1].Title != "君子中庸" {
		t.Fatalf("expected chapter 2 title to strip speaker framing, got %q", book.Chapters[1].Title)
	}

	if book.Chapters[2].Title != "衣錦尚絅" {
		t.Fatalf("expected chapter 33 title to strip quote framing, got %q", book.Chapters[2].Title)
	}
}

func TestGetChapterDerivesZhongYongChapterTitleFromFirstLine(t *testing.T) {
	repository := NewFSRepository(createZhongYongFixtureRoot(t), nil)

	chapter, err := repository.GetChapter(
		context.Background(),
		"zhong-yong",
		"chapter-033",
	)
	if err != nil {
		t.Fatalf("GetChapter returned error: %v", err)
	}

	if chapter.Title != "衣錦尚絅" {
		t.Fatalf("expected derived chapter title, got %q", chapter.Title)
	}
}

type stubTranslator struct {
	calls        int
	requests     []TranslationRequest
	translations []string
	err          error
}

func (s *stubTranslator) TranslateChapter(
	_ context.Context,
	request TranslationRequest,
) ([]string, error) {
	s.calls++
	s.requests = append(s.requests, request)

	return s.translations, s.err
}

func createBooksFixtureRoot(t *testing.T) string {
	t.Helper()

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
    "id": "chapter-001",
    "order": 1,
    "title": "Chapter One",
    "summary": "Opening lines",
    "text": "第一行。第二行。",
    "character_count": 6,
    "reading_unit_count": 2,
    "reading_units": [
      {
        "id": "chapter-001-line-001",
        "order": 1,
        "text": "第一行。",
        "generated_annotation": {
          "layers": {
            "translation_en": "The first line was already translated."
          }
        },
        "character_count": 3
      },
      {
        "id": "chapter-001-line-002",
        "order": 2,
        "text": "第二行。",
        "character_count": 3
      }
    ]
  }
}`

	if err := os.WriteFile(filepath.Join(bookDir, "catalog.json"), []byte(catalog), 0o644); err != nil {
		t.Fatalf("failed to write catalog fixture: %v", err)
	}

	if err := os.WriteFile(filepath.Join(chaptersDir, "chapter-001.json"), []byte(chapter), 0o644); err != nil {
		t.Fatalf("failed to write chapter fixture: %v", err)
	}

	return root
}

func createZhongYongFixtureRoot(t *testing.T) string {
	t.Helper()

	root := t.TempDir()
	bookDir := filepath.Join(root, "books", "zhong-yong")
	chaptersDir := filepath.Join(bookDir, "chapters")

	if err := os.MkdirAll(chaptersDir, 0o755); err != nil {
		t.Fatalf("failed to create fixture directories: %v", err)
	}

	catalog := `{
  "title": "中庸章句",
  "chapter_count": 3,
  "source_url": "https://example.com/zhong-yong",
  "provider": "fixture",
  "chapters": [
    {
      "id": "chapter-001",
      "order": 1,
      "title": "",
      "summary": "",
      "character_count": 15,
      "reading_unit_count": 1,
      "chapter_path": "books/zhong-yong/chapters/chapter-001.json"
    },
    {
      "id": "chapter-002",
      "order": 2,
      "title": "",
      "summary": "",
      "character_count": 12,
      "reading_unit_count": 1,
      "chapter_path": "books/zhong-yong/chapters/chapter-002.json"
    },
    {
      "id": "chapter-033",
      "order": 33,
      "title": "",
      "summary": "",
      "character_count": 14,
      "reading_unit_count": 1,
      "chapter_path": "books/zhong-yong/chapters/chapter-033.json"
    }
  ]
}`

	chapterOne := `{
  "chapter": {
    "id": "chapter-001",
    "order": 1,
    "title": "",
    "summary": "",
    "text": "天命之謂性，率性之謂道，脩道之謂教。",
    "character_count": 15,
    "reading_unit_count": 1,
    "reading_units": [
      {
        "id": "chapter-001-line-001",
        "order": 1,
        "text": "天命之謂性，率性之謂道，脩道之謂教。",
        "character_count": 15
      }
    ]
  }
}`

	chapterTwo := `{
  "chapter": {
    "id": "chapter-002",
    "order": 2,
    "title": "",
    "summary": "",
    "text": "仲尼曰：「君子中庸，小人反中庸。」",
    "character_count": 12,
    "reading_unit_count": 1,
    "reading_units": [
      {
        "id": "chapter-002-line-001",
        "order": 1,
        "text": "仲尼曰：「君子中庸，小人反中庸。」",
        "character_count": 12
      }
    ]
  }
}`

	chapterThirtyThree := `{
  "chapter": {
    "id": "chapter-033",
    "order": 33,
    "title": "",
    "summary": "",
    "text": "《詩》曰：「衣錦尚絅」，惡其文之著也。",
    "character_count": 14,
    "reading_unit_count": 1,
    "reading_units": [
      {
        "id": "chapter-033-line-001",
        "order": 1,
        "text": "《詩》曰：「衣錦尚絅」，惡其文之著也。",
        "character_count": 14
      }
    ]
  }
}`

	if err := os.WriteFile(filepath.Join(bookDir, "catalog.json"), []byte(catalog), 0o644); err != nil {
		t.Fatalf("failed to write catalog fixture: %v", err)
	}

	files := map[string]string{
		"chapter-001.json": chapterOne,
		"chapter-002.json": chapterTwo,
		"chapter-033.json": chapterThirtyThree,
	}

	for name, contents := range files {
		if err := os.WriteFile(filepath.Join(chaptersDir, name), []byte(contents), 0o644); err != nil {
			t.Fatalf("failed to write %s fixture: %v", name, err)
		}
	}

	return root
}
