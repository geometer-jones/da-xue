package hanzi

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
)

var ErrNotFound = errors.New("hanzi: not found")

const componentsRelativePath = "references/hanzi/modern-common-components-gf0014-2009-grouped.json"

type Repository interface {
	GetCharacterComponents() (CharacterComponentsDataset, error)
}

type CharacterComponentsDataset struct {
	Title                 string                    `json:"title"`
	Standard              string                    `json:"standard"`
	GroupedComponentCount int                       `json:"groupedComponentCount"`
	RawComponentCount     int                       `json:"rawComponentCount"`
	Entries               []CharacterComponentEntry `json:"entries"`
}

type CharacterComponentEntry struct {
	GroupID                 int      `json:"groupId"`
	FrequencyRank           int      `json:"frequencyRank"`
	GroupOccurrenceCount    int      `json:"groupOccurrenceCount"`
	GroupConstructionCount  int      `json:"groupConstructionCount"`
	CanonicalForm           string   `json:"canonicalForm"`
	CanonicalName           string   `json:"canonicalName"`
	Forms                   []string `json:"forms"`
	VariantForms            []string `json:"variantForms"`
	Names                   []string `json:"names"`
	SourceExampleCharacters []string `json:"sourceExampleCharacters"`
	MemberCount             int      `json:"memberCount"`
}

type FSRepository struct {
	root string
}

func NewFSRepository(root string) *FSRepository {
	return &FSRepository{
		root: filepath.Clean(root),
	}
}

func (r *FSRepository) GetCharacterComponents() (CharacterComponentsDataset, error) {
	filePath := filepath.Join(r.root, filepath.FromSlash(componentsRelativePath))

	var payload componentsFile
	if err := readJSONFile(filePath, &payload); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return CharacterComponentsDataset{}, ErrNotFound
		}
		return CharacterComponentsDataset{}, fmt.Errorf("read character components: %w", err)
	}

	entries := make([]CharacterComponentEntry, 0, len(payload.Entries))
	for _, entry := range payload.Entries {
		entries = append(entries, CharacterComponentEntry{
			GroupID:                 entry.GroupID,
			FrequencyRank:           entry.FrequencyRank,
			GroupOccurrenceCount:    entry.GroupOccurrenceCount,
			GroupConstructionCount:  entry.GroupConstructionCount,
			CanonicalForm:           entry.CanonicalForm,
			CanonicalName:           entry.CanonicalName,
			Forms:                   entry.Forms,
			VariantForms:            entry.VariantForms,
			Names:                   entry.Names,
			SourceExampleCharacters: entry.SourceExampleCharacters,
			MemberCount:             len(entry.Members),
		})
	}

	sort.Slice(entries, func(i int, j int) bool {
		if entries[i].FrequencyRank == entries[j].FrequencyRank {
			return entries[i].GroupID < entries[j].GroupID
		}

		return entries[i].FrequencyRank < entries[j].FrequencyRank
	})

	return CharacterComponentsDataset{
		Title:                 payload.Title,
		Standard:              payload.Standard,
		GroupedComponentCount: payload.GroupedComponentCount,
		RawComponentCount:     payload.RawComponentCount,
		Entries:               entries,
	}, nil
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

type componentsFile struct {
	Title                 string               `json:"title"`
	Standard              string               `json:"standard"`
	GroupedComponentCount int                  `json:"grouped_component_count"`
	RawComponentCount     int                  `json:"raw_component_count"`
	Entries               []componentFileEntry `json:"entries"`
}

type componentFileEntry struct {
	GroupID                 int        `json:"group_id"`
	FrequencyRank           int        `json:"frequency_rank"`
	GroupOccurrenceCount    int        `json:"group_occurrence_count"`
	GroupConstructionCount  int        `json:"group_construction_count"`
	CanonicalForm           string     `json:"canonical_form"`
	CanonicalName           string     `json:"canonical_name"`
	Forms                   []string   `json:"forms"`
	VariantForms            []string   `json:"variant_forms"`
	Names                   []string   `json:"names"`
	SourceExampleCharacters []string   `json:"source_example_characters"`
	Members                 []struct{} `json:"members"`
}
