package characters

import (
	"context"
	"strings"
	"testing"

	"daxue/services/api/internal/zai"
)

type stubExplosionClient struct {
	lastRequest zai.ChatCompletionRequest
	response    zai.ChatCompletionResponse
	err         error
}

func (s *stubExplosionClient) ChatCompletion(
	_ context.Context,
	request zai.ChatCompletionRequest,
) (zai.ChatCompletionResponse, error) {
	s.lastRequest = request
	return s.response, s.err
}

func TestBuildExplosionGenerationPromptDoesNotIncludeExistingExplosion(t *testing.T) {
	prompt := buildExplosionGenerationPrompt("學", &Entry{
		Character:   "学",
		Simplified:  "学",
		Traditional: "學",
		Pinyin:      []string{"xué"},
		Zhuyin:      []string{"ㄒㄩㄝˊ"},
		English:     []string{"study"},
		Explosion: Explosion{
			Analysis: ExplosionAnalysis{
				Expression: "OLD + BROKEN",
				Parts:      []string{"OLD", "BROKEN"},
			},
			MeaningMap: ExplosionMeaningMap{
				Synonyms: []string{"old synonym"},
			},
		},
	})

	if !strings.Contains(prompt, `"character": "学"`) {
		t.Fatalf("expected prompt to include the canonical character context, got %q", prompt)
	}

	if strings.Contains(prompt, "existingExplosion") {
		t.Fatalf("expected prompt to omit any previous explosion payload, got %q", prompt)
	}

	if strings.Contains(prompt, "OLD + BROKEN") || strings.Contains(prompt, "old synonym") {
		t.Fatalf("expected prompt to avoid seeding prior explosion content, got %q", prompt)
	}

	if !strings.Contains(prompt, "fully replace it") {
		t.Fatalf("expected prompt to require full replacement, got %q", prompt)
	}
}

func TestGenerateExplosionReplacesExistingExplosionContent(t *testing.T) {
	client := &stubExplosionClient{
		response: zai.ChatCompletionResponse{
			Model: "glm-5-turbo",
			Choices: []zai.ChatCompletionChoice{
				{
					Message: zai.ChatCompletionMessage{
						Role: "assistant",
						Content: `{
  "explosion": {
    "analysis": {
      "expression": "子 + 冖",
      "parts": ["子", "冖"]
    },
    "synthesis": {
      "phraseUse": ["新學"]
    },
    "meaningMap": {
      "synonyms": ["新義"]
    }
  }
}`,
					},
				},
			},
		},
	}

	generator := NewZAIExplosionGenerator(client, "glm-5-turbo")
	entry, err := generator.GenerateExplosion(context.Background(), "學", &Entry{
		Character:   "学",
		Simplified:  "学",
		Traditional: "學",
		Pinyin:      []string{"xué"},
		Zhuyin:      []string{"ㄒㄩㄝˊ"},
		English:     []string{"study"},
		Explosion: Explosion{
			Analysis: ExplosionAnalysis{
				Expression: "OLD + BROKEN",
				Parts:      []string{"OLD", "BROKEN"},
			},
			Synthesis: ExplosionSynthesis{
				ContainingCharacters: []string{"舊"},
				PhraseUse:            []string{"舊學"},
				Homophones: ExplosionHomophones{
					SameTone: []string{"旧"},
				},
			},
			MeaningMap: ExplosionMeaningMap{
				Synonyms: []string{"old synonym"},
				Antonyms: []string{"old antonym"},
			},
		},
	})
	if err != nil {
		t.Fatalf("GenerateExplosion returned error: %v", err)
	}

	if entry.Character != "学" {
		t.Fatalf("expected canonical character 学, got %q", entry.Character)
	}

	if len(entry.English) != 1 || entry.English[0] != "study" {
		t.Fatalf("expected non-explosion metadata to be preserved, got %#v", entry.English)
	}

	if entry.Explosion.Analysis.Expression != "子 + 冖" {
		t.Fatalf("expected fresh analysis expression, got %q", entry.Explosion.Analysis.Expression)
	}

	if len(entry.Explosion.Synthesis.PhraseUse) != 1 || entry.Explosion.Synthesis.PhraseUse[0] != "新學" {
		t.Fatalf("expected fresh phrase use, got %#v", entry.Explosion.Synthesis.PhraseUse)
	}

	if len(entry.Explosion.Synthesis.ContainingCharacters) != 0 {
		t.Fatalf("expected old containing characters to be replaced, got %#v", entry.Explosion.Synthesis.ContainingCharacters)
	}

	if len(entry.Explosion.Synthesis.Homophones.SameTone) != 0 {
		t.Fatalf("expected old homophones to be replaced, got %#v", entry.Explosion.Synthesis.Homophones.SameTone)
	}

	if len(entry.Explosion.MeaningMap.Synonyms) != 1 || entry.Explosion.MeaningMap.Synonyms[0] != "新義" {
		t.Fatalf("expected fresh synonyms, got %#v", entry.Explosion.MeaningMap.Synonyms)
	}

	if len(entry.Explosion.MeaningMap.Antonyms) != 0 {
		t.Fatalf("expected old antonyms to be replaced, got %#v", entry.Explosion.MeaningMap.Antonyms)
	}

	if strings.Contains(client.lastRequest.Messages[1].Content, "OLD + BROKEN") {
		t.Fatalf("expected request prompt to avoid prior explosion content, got %q", client.lastRequest.Messages[1].Content)
	}
}
