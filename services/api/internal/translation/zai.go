package translation

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"daxue/services/api/internal/books"
	"daxue/services/api/internal/zai"
)

type ZAITranslator struct {
	client *zai.Client
	model  string
}

func NewZAITranslator(client *zai.Client, model string) *ZAITranslator {
	return &ZAITranslator{
		client: client,
		model:  strings.TrimSpace(model),
	}
}

func (t *ZAITranslator) TranslateChapter(
	ctx context.Context,
	request books.TranslationRequest,
) ([]string, error) {
	if len(request.Lines) == 0 {
		return nil, nil
	}

	if t.client == nil {
		return nil, zai.ErrNotConfigured
	}

	if t.model == "" {
		return nil, fmt.Errorf("missing GLM model")
	}

	response, err := t.client.ChatCompletion(ctx, zai.ChatCompletionRequest{
		Model: t.model,
		Messages: []zai.Message{
			{
				Role:    "system",
				Content: "You translate Classical Chinese and literary Chinese into faithful, natural English for learners. Return exactly one English translation per input line in the same order. Do not omit lines. Do not add commentary, numbering, or notes.",
			},
			{
				Role:    "user",
				Content: buildTranslationPrompt(request),
			},
		},
		Temperature: 0.2,
		ResponseFormat: &zai.ResponseFormat{
			Type: "json_object",
		},
	})
	if err != nil {
		return nil, fmt.Errorf("z.ai translation request failed: %w", err)
	}

	rawOutput := strings.TrimSpace(response.FirstMessageContent())
	if rawOutput == "" {
		return nil, fmt.Errorf("translation response did not include structured output text")
	}

	var formattedResponse struct {
		Translations []string `json:"translations"`
	}
	if err := json.Unmarshal([]byte(extractJSONObject(rawOutput)), &formattedResponse); err != nil {
		return nil, fmt.Errorf("decode translation payload: %w", err)
	}

	if len(formattedResponse.Translations) != len(request.Lines) {
		return nil, fmt.Errorf(
			"translation response returned %d lines for %d inputs",
			len(formattedResponse.Translations),
			len(request.Lines),
		)
	}

	return formattedResponse.Translations, nil
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
