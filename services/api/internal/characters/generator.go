package characters

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"daxue/services/api/internal/zai"
)

type ExplosionGenerator interface {
	GenerateExplosion(ctx context.Context, character string, existing *Entry) (Entry, error)
}

type chatCompletionClient interface {
	ChatCompletion(
		ctx context.Context,
		request zai.ChatCompletionRequest,
	) (zai.ChatCompletionResponse, error)
}

type ZAIExplosionGenerator struct {
	client chatCompletionClient
	model  string
}

func NewZAIExplosionGenerator(
	client chatCompletionClient,
	model string,
) *ZAIExplosionGenerator {
	return &ZAIExplosionGenerator{
		client: client,
		model:  strings.TrimSpace(model),
	}
}

func (g *ZAIExplosionGenerator) GenerateExplosion(
	ctx context.Context,
	character string,
	existing *Entry,
) (Entry, error) {
	trimmedCharacter := strings.TrimSpace(character)
	if trimmedCharacter == "" {
		return Entry{}, ErrNotFound
	}

	if g.client == nil {
		return Entry{}, zai.ErrNotConfigured
	}

	if g.model == "" {
		return Entry{}, fmt.Errorf("missing GLM model")
	}

	response, err := g.client.ChatCompletion(ctx, zai.ChatCompletionRequest{
		Model: g.model,
		Messages: []zai.Message{
			{
				Role: "system",
				Content: "You generate learner-friendly Hanzi explosions for a Classical Chinese reading app. " +
					"Return concise structured output for one character at a time. " +
					"Prefer visible modern component breakdowns over speculative historical etymology when they differ. " +
					"If you are uncertain about any list item, leave it empty instead of inventing obscure facts.",
			},
			{
				Role:    "user",
				Content: buildExplosionGenerationPrompt(trimmedCharacter, existing),
			},
		},
		Temperature: 0.7,
		ResponseFormat: &zai.ResponseFormat{
			Type: "json_object",
		},
	})
	if err != nil {
		return Entry{}, fmt.Errorf("z.ai character explosion request failed: %w", err)
	}

	rawOutput := strings.TrimSpace(response.FirstMessageContent())
	if rawOutput == "" {
		return Entry{}, fmt.Errorf("character explosion response did not include structured output text")
	}

	explosion, err := decodeGeneratedExplosion(rawOutput)
	if err != nil {
		return Entry{}, err
	}

	entry := Entry{
		Character:   trimmedCharacter,
		Simplified:  trimmedCharacter,
		Traditional: trimmedCharacter,
		Explosion:   explosion,
	}
	if existing != nil {
		entry = *existing
		entry.Explosion = explosion
		if strings.TrimSpace(entry.Character) == "" {
			entry.Character = trimmedCharacter
		}
		if strings.TrimSpace(entry.Simplified) == "" {
			entry.Simplified = trimmedCharacter
		}
		if strings.TrimSpace(entry.Traditional) == "" {
			entry.Traditional = trimmedCharacter
		}
	}

	return normalizeEntry(entry), nil
}

func buildExplosionGenerationPrompt(character string, existing *Entry) string {
	type promptEntry struct {
		Character   string   `json:"character"`
		Simplified  string   `json:"simplified,omitempty"`
		Traditional string   `json:"traditional,omitempty"`
		Pinyin      []string `json:"pinyin,omitempty"`
		Zhuyin      []string `json:"zhuyin,omitempty"`
		English     []string `json:"english,omitempty"`
	}

	contextEntry := promptEntry{Character: character}
	if existing != nil {
		contextEntry = promptEntry{
			Character:   firstNonEmpty(existing.Character, character),
			Simplified:  existing.Simplified,
			Traditional: existing.Traditional,
			Pinyin:      existing.Pinyin,
			Zhuyin:      existing.Zhuyin,
			English:     existing.English,
		}
	}

	payload, _ := json.MarshalIndent(contextEntry, "", "  ")

	return "Generate a fresh explosion for this single character from scratch. " +
		"Do not add markdown or prose. " +
		"Keep every string short and mobile-readable. " +
		"Do not reuse or preserve any previous explosion content; the new output should fully replace it. " +
		"If character metadata is provided, you may use it only as glossary context.\n\n" +
		"Character context:\n" + string(payload) + "\n\n" +
		"Return exactly one JSON object in this shape:\n" +
		"{\n" +
		`  "explosion": {` + "\n" +
		`    "analysis": {"expression": "part + part", "parts": ["part", "part"]},` + "\n" +
		`    "synthesis": {` + "\n" +
		`      "containingCharacters": ["..."],` + "\n" +
		`      "phraseUse": ["..."],` + "\n" +
		`      "homophones": {"sameTone": ["..."], "differentTone": ["..."]}` + "\n" +
		"    },\n" +
		`    "meaningMap": {"synonyms": ["..."], "antonyms": ["..."]}` + "\n" +
		"  }\n" +
		"}"
}

func decodeGeneratedExplosion(raw string) (Explosion, error) {
	payload := []byte(extractJSONObject(raw))

	var envelope map[string]json.RawMessage
	if err := json.Unmarshal(payload, &envelope); err != nil {
		return Explosion{}, fmt.Errorf("decode character explosion payload: %w", err)
	}

	if rawExplosion, ok := envelope["explosion"]; ok {
		var explosion Explosion
		if err := json.Unmarshal(rawExplosion, &explosion); err != nil {
			return Explosion{}, fmt.Errorf("decode character explosion payload: %w", err)
		}
		return normalizeExplosion(explosion), nil
	}

	var explosion Explosion
	if err := json.Unmarshal(payload, &explosion); err != nil {
		return Explosion{}, fmt.Errorf("decode character explosion payload: %w", err)
	}

	return normalizeExplosion(explosion), nil
}

func normalizeExplosion(explosion Explosion) Explosion {
	return normalizeEntry(Entry{Explosion: explosion}).Explosion
}

func extractJSONObject(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return trimmed
	}

	if strings.HasPrefix(trimmed, "```") {
		trimmed = strings.TrimPrefix(trimmed, "```json")
		trimmed = strings.TrimPrefix(trimmed, "```JSON")
		trimmed = strings.TrimPrefix(trimmed, "```")
		trimmed = strings.TrimSuffix(trimmed, "```")
		trimmed = strings.TrimSpace(trimmed)
	}

	start := strings.Index(trimmed, "{")
	end := strings.LastIndex(trimmed, "}")
	if start >= 0 && end >= start {
		return trimmed[start : end+1]
	}

	return trimmed
}
