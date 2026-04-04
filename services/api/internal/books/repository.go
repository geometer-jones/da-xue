package books

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
)

var ErrNotFound = errors.New("books: not found")

type Repository interface {
	ListBooks() ([]BookSummary, error)
	GetBook(bookID string) (BookDetail, error)
	GetChapter(ctx context.Context, bookID string, chapterID string) (ChapterDetail, error)
}

type Translator interface {
	TranslateChapter(ctx context.Context, request TranslationRequest) ([]string, error)
}

type TranslationRequest struct {
	BookID       string
	BookTitle    string
	ChapterID    string
	ChapterTitle string
	Lines        []string
}

type BookSummary struct {
	ID             string `json:"id"`
	Title          string `json:"title"`
	ChapterCount   int    `json:"chapterCount"`
	SourceURL      string `json:"sourceUrl"`
	SourceProvider string `json:"sourceProvider"`
}

type ChapterSummary struct {
	ID               string `json:"id"`
	Order            int    `json:"order"`
	Title            string `json:"title"`
	Summary          string `json:"summary"`
	CharacterCount   int    `json:"characterCount"`
	ReadingUnitCount int    `json:"readingUnitCount"`
}

type BookDetail struct {
	BookSummary
	Chapters []ChapterSummary `json:"chapters"`
}

type ReadingUnit struct {
	ID             string `json:"id"`
	Order          int    `json:"order"`
	Text           string `json:"text"`
	Category       string `json:"category,omitempty"`
	TranslationEn  string `json:"translationEn,omitempty"`
	CharacterCount int    `json:"characterCount"`
}

type ChapterDetail struct {
	ID               string        `json:"id"`
	Order            int           `json:"order"`
	Title            string        `json:"title"`
	Summary          string        `json:"summary"`
	Text             string        `json:"text"`
	CharacterCount   int           `json:"characterCount"`
	ReadingUnitCount int           `json:"readingUnitCount"`
	ReadingUnits     []ReadingUnit `json:"readingUnits"`
}

type FSRepository struct {
	repositoryRoot   string
	booksRoot        string
	translator       Translator
	translationMu    sync.RWMutex
	translationCache map[string]map[string]string
}

func NewFSRepository(root string, translator Translator) *FSRepository {
	cleanRoot := filepath.Clean(root)
	booksRoot := filepath.Join(cleanRoot, "books")

	if info, err := os.Stat(booksRoot); err == nil && info.IsDir() {
		return &FSRepository{
			repositoryRoot:   cleanRoot,
			booksRoot:        booksRoot,
			translator:       translator,
			translationCache: make(map[string]map[string]string),
		}
	}

	return &FSRepository{
		repositoryRoot:   filepath.Dir(cleanRoot),
		booksRoot:        cleanRoot,
		translator:       translator,
		translationCache: make(map[string]map[string]string),
	}
}

func (r *FSRepository) ListBooks() ([]BookSummary, error) {
	entries, err := os.ReadDir(r.booksRoot)
	if err != nil {
		return nil, fmt.Errorf("read books root %q: %w", r.booksRoot, err)
	}

	books := make([]BookSummary, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		bookID := entry.Name()
		catalog, err := r.readCatalog(bookID)
		if err != nil {
			if errors.Is(err, ErrNotFound) {
				continue
			}
			return nil, err
		}

		books = append(books, mapBookSummary(bookID, catalog))
	}

	sort.Slice(books, func(i int, j int) bool {
		if books[i].Title == books[j].Title {
			return books[i].ID < books[j].ID
		}
		return books[i].Title < books[j].Title
	})

	return books, nil
}

func (r *FSRepository) GetBook(bookID string) (BookDetail, error) {
	catalog, err := r.readCatalog(bookID)
	if err != nil {
		return BookDetail{}, err
	}

	chapters := make([]ChapterSummary, 0, len(catalog.Chapters))
	for _, chapter := range catalog.Chapters {
		chapters = append(chapters, ChapterSummary{
			ID:               chapter.ID,
			Order:            chapter.Order,
			Title:            r.resolveCatalogChapterTitle(bookID, chapter),
			Summary:          chapter.Summary,
			CharacterCount:   chapter.CharacterCount,
			ReadingUnitCount: chapter.ReadingUnitCount,
		})
	}

	sort.Slice(chapters, func(i int, j int) bool {
		return chapters[i].Order < chapters[j].Order
	})

	return BookDetail{
		BookSummary: mapBookSummary(bookID, catalog),
		Chapters:    chapters,
	}, nil
}

func (r *FSRepository) GetChapter(ctx context.Context, bookID string, chapterID string) (ChapterDetail, error) {
	catalog, err := r.readCatalog(bookID)
	if err != nil {
		return ChapterDetail{}, err
	}

	var chapterPath string
	for _, candidate := range catalog.Chapters {
		if candidate.ID == chapterID {
			chapterPath = candidate.ChapterPath
			break
		}
	}

	if chapterPath == "" {
		return ChapterDetail{}, ErrNotFound
	}

	filePath := filepath.Join(r.repositoryRoot, filepath.FromSlash(chapterPath))
	var payload chapterFile
	if err := readJSONFile(filePath, &payload); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return ChapterDetail{}, ErrNotFound
		}
		return ChapterDetail{}, fmt.Errorf("read chapter %q for book %q: %w", chapterID, bookID, err)
	}

	payload.Chapter.Title = deriveChapterTitle(
		bookID,
		payload.Chapter.Title,
		payload.Chapter.ReadingUnits,
	)

	readingUnits := make([]ReadingUnit, 0, len(payload.Chapter.ReadingUnits))
	for _, unit := range payload.Chapter.ReadingUnits {
		readingUnits = append(readingUnits, ReadingUnit{
			ID:             unit.ID,
			Order:          unit.Order,
			Text:           unit.Text,
			Category:       strings.TrimSpace(unit.Category),
			TranslationEn:  unit.translationEn(),
			CharacterCount: unit.CharacterCount,
		})
	}

	sort.Slice(readingUnits, func(i int, j int) bool {
		return readingUnits[i].Order < readingUnits[j].Order
	})

	r.enrichMissingTranslations(
		ctx,
		bookID,
		catalog.Title,
		payload.Chapter,
		readingUnits,
	)

	return ChapterDetail{
		ID:               payload.Chapter.ID,
		Order:            payload.Chapter.Order,
		Title:            payload.Chapter.Title,
		Summary:          payload.Chapter.Summary,
		Text:             payload.Chapter.Text,
		CharacterCount:   payload.Chapter.CharacterCount,
		ReadingUnitCount: payload.Chapter.ReadingUnitCount,
		ReadingUnits:     readingUnits,
	}, nil
}

func (r *FSRepository) resolveCatalogChapterTitle(
	bookID string,
	chapter catalogChapter,
) string {
	if title := strings.TrimSpace(chapter.Title); title != "" {
		return title
	}

	if bookID != "zhong-yong" || strings.TrimSpace(chapter.ChapterPath) == "" {
		return ""
	}

	var payload chapterFile
	filePath := filepath.Join(r.repositoryRoot, filepath.FromSlash(chapter.ChapterPath))
	if err := readJSONFile(filePath, &payload); err != nil {
		return ""
	}

	return deriveChapterTitle(bookID, payload.Chapter.Title, payload.Chapter.ReadingUnits)
}

func (r *FSRepository) enrichMissingTranslations(
	ctx context.Context,
	bookID string,
	bookTitle string,
	chapter chapterPayload,
	readingUnits []ReadingUnit,
) {
	if r.translator == nil || len(readingUnits) == 0 {
		return
	}

	cacheKey := bookID + "/" + chapter.ID
	cachedTranslations := r.getCachedTranslations(cacheKey)
	missingIndexes := make([]int, 0, len(readingUnits))
	missingLines := make([]string, 0, len(readingUnits))

	for index, unit := range readingUnits {
		if unit.TranslationEn != "" {
			continue
		}

		if cachedTranslation, ok := cachedTranslations[unit.ID]; ok && cachedTranslation != "" {
			readingUnits[index].TranslationEn = cachedTranslation
			continue
		}

		missingIndexes = append(missingIndexes, index)
		missingLines = append(missingLines, unit.Text)
	}

	if len(missingLines) == 0 {
		return
	}

	translations, err := r.translator.TranslateChapter(ctx, TranslationRequest{
		BookID:       bookID,
		BookTitle:    bookTitle,
		ChapterID:    chapter.ID,
		ChapterTitle: chapter.Title,
		Lines:        missingLines,
	})
	if err != nil {
		log.Printf("translation fallback failed for %s/%s: %v", bookID, chapter.ID, err)
		return
	}

	if len(translations) != len(missingIndexes) {
		log.Printf(
			"translation fallback returned %d lines for %s/%s; expected %d",
			len(translations),
			bookID,
			chapter.ID,
			len(missingIndexes),
		)
		return
	}

	generatedTranslations := make(map[string]string, len(missingIndexes))
	for index, readingUnitIndex := range missingIndexes {
		translation := strings.TrimSpace(translations[index])
		if translation == "" {
			continue
		}

		readingUnits[readingUnitIndex].TranslationEn = translation
		generatedTranslations[readingUnits[readingUnitIndex].ID] = translation
	}

	if len(generatedTranslations) == 0 {
		return
	}

	r.storeCachedTranslations(cacheKey, generatedTranslations)
}

func (r *FSRepository) getCachedTranslations(cacheKey string) map[string]string {
	r.translationMu.RLock()
	defer r.translationMu.RUnlock()

	if len(r.translationCache[cacheKey]) == 0 {
		return nil
	}

	cachedTranslations := make(map[string]string, len(r.translationCache[cacheKey]))
	for unitID, translation := range r.translationCache[cacheKey] {
		cachedTranslations[unitID] = translation
	}

	return cachedTranslations
}

func (r *FSRepository) storeCachedTranslations(cacheKey string, translations map[string]string) {
	r.translationMu.Lock()
	defer r.translationMu.Unlock()

	if r.translationCache[cacheKey] == nil {
		r.translationCache[cacheKey] = make(map[string]string, len(translations))
	}

	for unitID, translation := range translations {
		r.translationCache[cacheKey][unitID] = translation
	}
}

func (r *FSRepository) readCatalog(bookID string) (catalogFile, error) {
	if !isSafeSegment(bookID) {
		return catalogFile{}, ErrNotFound
	}

	catalogPath := filepath.Join(r.booksRoot, bookID, "catalog.json")
	var catalog catalogFile
	if err := readJSONFile(catalogPath, &catalog); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return catalogFile{}, ErrNotFound
		}
		return catalogFile{}, fmt.Errorf("read catalog for %q: %w", bookID, err)
	}

	return catalog, nil
}

func mapBookSummary(bookID string, catalog catalogFile) BookSummary {
	return BookSummary{
		ID:             bookID,
		Title:          catalog.Title,
		ChapterCount:   catalog.ChapterCount,
		SourceURL:      catalog.SourceURL,
		SourceProvider: catalog.Provider,
	}
}

func deriveChapterTitle(
	bookID string,
	title string,
	readingUnits []readingUnitPayload,
) string {
	if trimmedTitle := strings.TrimSpace(title); trimmedTitle != "" {
		return trimmedTitle
	}

	if bookID != "zhong-yong" || len(readingUnits) == 0 {
		return ""
	}

	candidate := strings.TrimSpace(readingUnits[0].Text)
	for _, prefix := range []string{
		"仲尼曰：",
		"仲尼曰",
		"子曰：",
		"子曰",
		"《詩》曰：",
		"《詩》曰",
		"《詩》云：",
		"《詩》云",
		"詩曰：",
		"詩曰",
		"詩云：",
		"詩云",
	} {
		if strings.HasPrefix(candidate, prefix) {
			candidate = strings.TrimSpace(strings.TrimPrefix(candidate, prefix))
			break
		}
	}

	candidate = strings.TrimLeft(candidate, "「『“”《》〈〉 ")
	parts := strings.FieldsFunc(candidate, func(r rune) bool {
		return strings.ContainsRune("，；。？！：、", r)
	})
	if len(parts) == 0 {
		return strings.Trim(candidate, "「」『』“”《》〈〉 ")
	}

	return strings.TrimSpace(strings.Trim(parts[0], "「」『』“”《》〈〉 "))
}

func readJSONFile(path string, destination any) error {
	contents, err := os.ReadFile(path)
	if err != nil {
		return err
	}

	if err := json.Unmarshal(contents, destination); err != nil {
		return err
	}

	return nil
}

func isSafeSegment(value string) bool {
	return value != "" && !strings.Contains(value, "..") && !strings.ContainsAny(value, `/\`)
}

type catalogFile struct {
	Title        string           `json:"title"`
	ChapterCount int              `json:"chapter_count"`
	Chapters     []catalogChapter `json:"chapters"`
	SourceURL    string           `json:"source_url"`
	Provider     string           `json:"provider"`
}

type catalogChapter struct {
	ID               string `json:"id"`
	Order            int    `json:"order"`
	Title            string `json:"title"`
	Summary          string `json:"summary"`
	CharacterCount   int    `json:"character_count"`
	ReadingUnitCount int    `json:"reading_unit_count"`
	ChapterPath      string `json:"chapter_path"`
}

type chapterFile struct {
	Chapter chapterPayload `json:"chapter"`
}

type chapterPayload struct {
	ID               string               `json:"id"`
	Order            int                  `json:"order"`
	Title            string               `json:"title"`
	Summary          string               `json:"summary"`
	Text             string               `json:"text"`
	CharacterCount   int                  `json:"character_count"`
	ReadingUnitCount int                  `json:"reading_unit_count"`
	ReadingUnits     []readingUnitPayload `json:"reading_units"`
}

type readingUnitPayload struct {
	ID                  string                      `json:"id"`
	Order               int                         `json:"order"`
	Text                string                      `json:"text"`
	Category            string                      `json:"category"`
	TranslationEn       string                      `json:"translation_en"`
	GeneratedAnnotation *generatedAnnotationPayload `json:"generated_annotation"`
	CharacterCount      int                         `json:"character_count"`
}

func (p readingUnitPayload) translationEn() string {
	if p.GeneratedAnnotation != nil {
		if translation := strings.TrimSpace(p.GeneratedAnnotation.Layers.TranslationEn); translation != "" {
			return translation
		}
	}

	return strings.TrimSpace(p.TranslationEn)
}

type generatedAnnotationPayload struct {
	Layers generatedAnnotationLayersPayload `json:"layers"`
}

type generatedAnnotationLayersPayload struct {
	TranslationEn string `json:"translation_en"`
}
