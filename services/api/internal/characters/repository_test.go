package characters

import (
	"os"
	"path/filepath"
	"testing"
)

func TestListCharactersReturnsSortedIndex(t *testing.T) {
	repository := NewFSRepository(createFixtureRoot(t))

	index, err := repository.ListCharacters()
	if err != nil {
		t.Fatalf("ListCharacters returned error: %v", err)
	}

	if index.EntryCount != 2 {
		t.Fatalf("expected 2 entries, got %d", index.EntryCount)
	}

	if index.Entries[0].Character != "学" {
		t.Fatalf("expected first character 学, got %q", index.Entries[0].Character)
	}

	if len(index.Entries[0].English) != 2 {
		t.Fatalf("expected normalized english senses, got %#v", index.Entries[0].English)
	}

	if index.Entries[0].Explosion.Analysis.Expression != "子 + 冖 + 爻" {
		t.Fatalf("unexpected analysis expression %q", index.Entries[0].Explosion.Analysis.Expression)
	}
}

func TestGetCharacterMatchesTraditionalOrSimplified(t *testing.T) {
	repository := NewFSRepository(createFixtureRoot(t))

	entry, err := repository.GetCharacter("學")
	if err != nil {
		t.Fatalf("GetCharacter returned error: %v", err)
	}

	if entry.Character != "学" {
		t.Fatalf("expected canonical character 学, got %q", entry.Character)
	}

	if entry.Explosion.Analysis.Expression != "子 + 冖 + 爻" {
		t.Fatalf("unexpected analysis expression %q", entry.Explosion.Analysis.Expression)
	}
}

func TestGetCharacterMatchesAliases(t *testing.T) {
	repository := NewFSRepository(createFixtureRoot(t))

	entry, err := repository.GetCharacter("斈")
	if err != nil {
		t.Fatalf("GetCharacter returned error: %v", err)
	}

	if entry.Character != "学" {
		t.Fatalf("expected canonical character 学, got %q", entry.Character)
	}
}

func TestGetCharacterReturnsNotFound(t *testing.T) {
	repository := NewFSRepository(createFixtureRoot(t))

	if _, err := repository.GetCharacter("無"); err == nil {
		t.Fatal("expected not found error")
	}
}

func createFixtureRoot(t *testing.T) string {
	t.Helper()

	root := t.TempDir()
	charactersDir := filepath.Join(root, "references", "characters")
	if err := os.MkdirAll(charactersDir, 0o755); err != nil {
		t.Fatalf("failed to create character fixture directory: %v", err)
	}

	payload := `{
  "entries": [
    {
      "character": "道",
      "simplified": "道",
      "traditional": "道",
      "pinyin": ["dào"],
      "zhuyin": ["ㄉㄠˋ"],
      "english": ["way", "path"],
      "explosion": {
        "analysis": {
          "expression": "辶 + 首",
          "parts": ["辶", "首"]
        },
        "synthesis": {
          "containingCharacters": ["導"],
          "phraseUse": ["大道"],
          "homophones": {
            "sameTone": ["到"],
            "differentTone": ["刀"]
          }
        },
        "meaningMap": {
          "synonyms": ["路"],
          "antonyms": ["迷"]
        }
      }
    },
    {
      "character": "学",
      "simplified": "学",
      "traditional": "學",
      "aliases": ["斈", "學"],
      "pinyin": ["xué", "xué"],
      "zhuyin": ["ㄒㄩㄝˊ"],
      "english": ["to study", "", "learning"],
      "explosion": {
        "analysis": {
          "expression": "子 + 冖 + 爻",
          "parts": ["子", "冖", "爻", "爻"]
        },
        "synthesis": {
          "containingCharacters": ["覺"],
          "phraseUse": ["大学"],
          "homophones": {
            "sameTone": ["穴"],
            "differentTone": ["雪"]
          }
        },
        "meaningMap": {
          "synonyms": [],
          "antonyms": []
        }
      }
    }
  ]
}`

	if err := os.WriteFile(filepath.Join(charactersDir, "index.json"), []byte(payload), 0o644); err != nil {
		t.Fatalf("failed to write character fixture: %v", err)
	}

	return root
}
