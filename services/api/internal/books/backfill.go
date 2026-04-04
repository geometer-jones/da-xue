package books

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type BackfillOptions struct {
	BookID    string
	ChapterID string
}

type BackfillReport struct {
	BooksScanned    int
	ChaptersScanned int
	ChaptersUpdated int
	LinesTranslated int
}

type chapterDocument struct {
	Chapter       chapterDocumentPayload `json:"chapter"`
	ChapterPath   string                 `json:"chapter_path"`
	Provider      string                 `json:"provider"`
	SchemaVersion int                    `json:"schema_version"`
	SourceTitle   string                 `json:"source_title"`
	SourceURL     string                 `json:"source_url"`
}

type chapterDocumentPayload struct {
	CharacterCount        int                   `json:"character_count"`
	ID                    string                `json:"id"`
	Order                 int                   `json:"order"`
	ReadingUnitCount      int                   `json:"reading_unit_count"`
	ReadingUnits          []chapterDocumentUnit `json:"reading_units"`
	Summary               string                `json:"summary"`
	SupplementalText      string                `json:"supplemental_text"`
	SupplementalUnitCount int                   `json:"supplemental_unit_count"`
	SupplementalUnits     json.RawMessage       `json:"supplemental_units"`
	Text                  string                `json:"text"`
	Title                 string                `json:"title"`
}

type chapterDocumentUnit struct {
	CharacterCount      int                         `json:"character_count"`
	GeneratedAnnotation *generatedAnnotationPayload `json:"generated_annotation,omitempty"`
	ID                  string                      `json:"id"`
	Order               int                         `json:"order"`
	SourceBlockChunk    int                         `json:"source_block_chunk,omitempty"`
	SourceBlockOrder    int                         `json:"source_block_order,omitempty"`
	Text                string                      `json:"text"`
	TranslationEn       string                      `json:"translation_en,omitempty"`
}

func (r *FSRepository) BackfillMissingTranslations(
	ctx context.Context,
	options BackfillOptions,
) (BackfillReport, error) {
	if r.translator == nil {
		return BackfillReport{}, fmt.Errorf("translator is not configured")
	}

	bookIDs, err := r.resolveBackfillBookIDs(options.BookID)
	if err != nil {
		return BackfillReport{}, err
	}

	report := BackfillReport{}
	for _, bookID := range bookIDs {
		if err := ctx.Err(); err != nil {
			return report, err
		}

		catalog, err := r.readCatalog(bookID)
		if err != nil {
			return report, err
		}

		report.BooksScanned++
		for _, chapter := range catalog.Chapters {
			if options.ChapterID != "" && chapter.ID != options.ChapterID {
				continue
			}

			report.ChaptersScanned++

			updated, translatedCount, err := r.backfillChapterTranslations(
				ctx,
				bookID,
				catalog.Title,
				chapter,
			)
			if err != nil {
				return report, fmt.Errorf("backfill %s/%s: %w", bookID, chapter.ID, err)
			}

			if !updated {
				continue
			}

			report.ChaptersUpdated++
			report.LinesTranslated += translatedCount
		}
	}

	return report, nil
}

func (r *FSRepository) resolveBackfillBookIDs(bookID string) ([]string, error) {
	if trimmedBookID := strings.TrimSpace(bookID); trimmedBookID != "" {
		return []string{trimmedBookID}, nil
	}

	entries, err := os.ReadDir(r.booksRoot)
	if err != nil {
		return nil, fmt.Errorf("read books root %q: %w", r.booksRoot, err)
	}

	bookIDs := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			bookIDs = append(bookIDs, entry.Name())
		}
	}

	sort.Strings(bookIDs)

	return bookIDs, nil
}

func (r *FSRepository) backfillChapterTranslations(
	ctx context.Context,
	bookID string,
	bookTitle string,
	chapter catalogChapter,
) (bool, int, error) {
	chapterPath := filepath.Join(r.repositoryRoot, filepath.FromSlash(chapter.ChapterPath))
	contents, err := os.ReadFile(chapterPath)
	if err != nil {
		return false, 0, fmt.Errorf("read chapter file: %w", err)
	}

	var document chapterDocument
	if err := json.Unmarshal(contents, &document); err != nil {
		return false, 0, fmt.Errorf("decode chapter file: %w", err)
	}

	if len(document.Chapter.ReadingUnits) == 0 {
		return false, 0, nil
	}

	missingIndexes := make([]int, 0, len(document.Chapter.ReadingUnits))
	missingLines := make([]string, 0, len(document.Chapter.ReadingUnits))

	for index, unit := range document.Chapter.ReadingUnits {
		if unit.translationEn() != "" {
			continue
		}

		missingIndexes = append(missingIndexes, index)
		missingLines = append(missingLines, unit.Text)
	}

	if len(missingLines) == 0 {
		return false, 0, nil
	}

	translations, err := r.translator.TranslateChapter(ctx, TranslationRequest{
		BookID:       bookID,
		BookTitle:    bookTitle,
		ChapterID:    document.Chapter.ID,
		ChapterTitle: document.Chapter.Title,
		Lines:        missingLines,
	})
	if err != nil {
		return false, 0, err
	}

	if len(translations) != len(missingIndexes) {
		return false, 0, fmt.Errorf(
			"translator returned %d lines for %d inputs",
			len(translations),
			len(missingIndexes),
		)
	}

	translatedCount := 0
	for index, unitIndex := range missingIndexes {
		translation := strings.TrimSpace(translations[index])
		if translation == "" {
			continue
		}

		document.Chapter.ReadingUnits[unitIndex].setGeneratedTranslation(translation)
		translatedCount++
	}

	if translatedCount == 0 {
		return false, 0, nil
	}

	formatted, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return false, 0, fmt.Errorf("encode chapter file: %w", err)
	}

	info, err := os.Stat(chapterPath)
	if err != nil {
		return false, 0, fmt.Errorf("stat chapter file: %w", err)
	}

	formatted = append(formatted, '\n')
	if err := os.WriteFile(chapterPath, formatted, info.Mode().Perm()); err != nil {
		return false, 0, fmt.Errorf("write chapter file: %w", err)
	}

	return true, translatedCount, nil
}

func (u chapterDocumentUnit) translationEn() string {
	if u.GeneratedAnnotation != nil {
		if translation := strings.TrimSpace(u.GeneratedAnnotation.Layers.TranslationEn); translation != "" {
			return translation
		}
	}

	return strings.TrimSpace(u.TranslationEn)
}

func (u *chapterDocumentUnit) setGeneratedTranslation(translation string) {
	if u.GeneratedAnnotation == nil {
		u.GeneratedAnnotation = &generatedAnnotationPayload{}
	}

	u.GeneratedAnnotation.Layers.TranslationEn = translation
}
