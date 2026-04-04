package characters

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

var ErrNotFound = errors.New("characters: not found")

const indexRelativePath = "references/characters/index.json"

type Repository interface {
	ListCharacters() (Index, error)
	GetCharacter(character string) (Entry, error)
}

type Index struct {
	EntryCount int     `json:"entryCount"`
	Entries    []Entry `json:"entries"`
}

type Entry struct {
	Character   string    `json:"character"`
	Simplified  string    `json:"simplified"`
	Traditional string    `json:"traditional"`
	Aliases     []string  `json:"aliases"`
	Pinyin      []string  `json:"pinyin"`
	Zhuyin      []string  `json:"zhuyin"`
	English     []string  `json:"english"`
	Explosion   Explosion `json:"explosion"`
}

type Explosion struct {
	Analysis   ExplosionAnalysis   `json:"analysis"`
	Synthesis  ExplosionSynthesis  `json:"synthesis"`
	MeaningMap ExplosionMeaningMap `json:"meaningMap"`
}

type ExplosionAnalysis struct {
	Expression string   `json:"expression"`
	Parts      []string `json:"parts"`
}

type ExplosionSynthesis struct {
	ContainingCharacters []string            `json:"containingCharacters"`
	PhraseUse            []string            `json:"phraseUse"`
	Homophones           ExplosionHomophones `json:"homophones"`
}

type ExplosionHomophones struct {
	SameTone      []string `json:"sameTone"`
	DifferentTone []string `json:"differentTone"`
}

type ExplosionMeaningMap struct {
	Synonyms []string `json:"synonyms"`
	Antonyms []string `json:"antonyms"`
}

type FSRepository struct {
	root string
}

func NewFSRepository(root string) *FSRepository {
	return &FSRepository{
		root: filepath.Clean(root),
	}
}

func (r *FSRepository) ListCharacters() (Index, error) {
	entries, err := r.readEntries()
	if err != nil {
		return Index{}, err
	}

	return Index{
		EntryCount: len(entries),
		Entries:    entries,
	}, nil
}

func (r *FSRepository) GetCharacter(character string) (Entry, error) {
	needle := strings.TrimSpace(character)
	if needle == "" {
		return Entry{}, ErrNotFound
	}

	entries, err := r.readEntries()
	if err != nil {
		return Entry{}, err
	}

	for _, entry := range entries {
		if entry.Character == needle || entry.Simplified == needle || entry.Traditional == needle || containsString(entry.Aliases, needle) {
			return entry, nil
		}
	}

	return Entry{}, ErrNotFound
}

func (r *FSRepository) readEntries() ([]Entry, error) {
	filePath := filepath.Join(r.root, filepath.FromSlash(indexRelativePath))

	var payload filePayload
	if err := readJSONFile(filePath, &payload); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, ErrNotFound
		}

		return nil, fmt.Errorf("read character index: %w", err)
	}

	entries := make([]Entry, 0, len(payload.Entries))
	for _, rawEntry := range payload.Entries {
		entry := normalizeEntry(rawEntry)
		if entry.Character == "" {
			continue
		}
		entries = append(entries, entry)
	}

	sort.Slice(entries, func(i int, j int) bool {
		return entries[i].Character < entries[j].Character
	})

	return entries, nil
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

func normalizeEntry(entry Entry) Entry {
	entry.Character = strings.TrimSpace(entry.Character)
	entry.Simplified = strings.TrimSpace(entry.Simplified)
	entry.Traditional = strings.TrimSpace(entry.Traditional)
	if entry.Character == "" {
		entry.Character = firstNonEmpty(entry.Simplified, entry.Traditional)
	}

	entry.Aliases = normalizeStringList(entry.Aliases)
	entry.Pinyin = normalizeStringList(entry.Pinyin)
	entry.Zhuyin = normalizeStringList(entry.Zhuyin)
	entry.English = normalizeStringList(entry.English)
	entry.Explosion.Analysis.Expression = strings.TrimSpace(entry.Explosion.Analysis.Expression)
	entry.Explosion.Analysis.Parts = normalizeStringList(entry.Explosion.Analysis.Parts)
	entry.Explosion.Synthesis.ContainingCharacters = normalizeStringList(entry.Explosion.Synthesis.ContainingCharacters)
	entry.Explosion.Synthesis.PhraseUse = normalizeStringList(entry.Explosion.Synthesis.PhraseUse)
	entry.Explosion.Synthesis.Homophones.SameTone = normalizeStringList(entry.Explosion.Synthesis.Homophones.SameTone)
	entry.Explosion.Synthesis.Homophones.DifferentTone = normalizeStringList(entry.Explosion.Synthesis.Homophones.DifferentTone)
	entry.Explosion.MeaningMap.Synonyms = normalizeStringList(entry.Explosion.MeaningMap.Synonyms)
	entry.Explosion.MeaningMap.Antonyms = normalizeStringList(entry.Explosion.MeaningMap.Antonyms)

	return entry
}

func normalizeStringList(values []string) []string {
	if len(values) == 0 {
		return nil
	}

	normalized := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" {
			continue
		}
		if _, exists := seen[trimmed]; exists {
			continue
		}
		seen[trimmed] = struct{}{}
		normalized = append(normalized, trimmed)
	}

	if len(normalized) == 0 {
		return nil
	}

	return normalized
}

func containsString(values []string, needle string) bool {
	for _, value := range values {
		if value == needle {
			return true
		}
	}

	return false
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}

	return ""
}

type filePayload struct {
	Entries []Entry `json:"entries"`
}
