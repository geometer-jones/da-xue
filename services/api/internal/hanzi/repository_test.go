package hanzi

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGetCharacterComponentsReturnsRankOrderedEntries(t *testing.T) {
	repository := NewFSRepository(createFixtureRoot(t))

	dataset, err := repository.GetCharacterComponents()
	if err != nil {
		t.Fatalf("GetCharacterComponents returned error: %v", err)
	}

	if dataset.GroupedComponentCount != 3 {
		t.Fatalf("expected 3 grouped components, got %d", dataset.GroupedComponentCount)
	}

	if len(dataset.Entries) != 3 {
		t.Fatalf("expected 3 entries, got %d", len(dataset.Entries))
	}

	if dataset.Entries[0].CanonicalForm != "口" {
		t.Fatalf("expected first entry to be lowest rank 口, got %q", dataset.Entries[0].CanonicalForm)
	}

	if dataset.Entries[1].CanonicalForm != "木" {
		t.Fatalf("expected tied rank entries to fall back to lower group id, got %q", dataset.Entries[1].CanonicalForm)
	}

	if dataset.Entries[2].CanonicalForm != "卬" {
		t.Fatalf("expected highest group id in tied rank to sort last, got %q", dataset.Entries[2].CanonicalForm)
	}
}

func createFixtureRoot(t *testing.T) string {
	t.Helper()

	root := t.TempDir()
	hanziDir := filepath.Join(root, "references", "hanzi")
	if err := os.MkdirAll(hanziDir, 0o755); err != nil {
		t.Fatalf("failed to create hanzi fixture directory: %v", err)
	}

	payload := `{
  "title": "Modern Common Character Components",
  "standard": "GF0014-2009",
  "grouped_component_count": 3,
  "raw_component_count": 4,
  "entries": [
    {
      "group_id": 9,
      "frequency_rank": 291,
      "group_occurrence_count": 4,
      "group_construction_count": 4,
      "canonical_form": "卬",
      "canonical_name": "昂字底",
      "forms": ["卬"],
      "variant_forms": [],
      "names": ["昂字底"],
      "source_example_characters": ["仰", "昂", "迎"],
      "members": [{}, {}]
    },
    {
      "group_id": 2,
      "frequency_rank": 98,
      "group_occurrence_count": 12,
      "group_construction_count": 8,
      "canonical_form": "口",
      "canonical_name": "口字旁",
      "forms": ["口"],
      "variant_forms": [],
      "names": ["口字旁"],
      "source_example_characters": ["吃", "嗎", "唱"],
      "members": [{}]
    },
    {
      "group_id": 4,
      "frequency_rank": 291,
      "group_occurrence_count": 7,
      "group_construction_count": 5,
      "canonical_form": "木",
      "canonical_name": "木字旁",
      "forms": ["木"],
      "variant_forms": [],
      "names": ["木字旁"],
      "source_example_characters": ["林", "村", "橋"],
      "members": [{}]
    }
  ]
}`

	if err := os.WriteFile(
		filepath.Join(hanziDir, "modern-common-components-gf0014-2009-grouped.json"),
		[]byte(payload),
		0o644,
	); err != nil {
		t.Fatalf("failed to write hanzi fixture: %v", err)
	}

	return root
}
