package translation

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"daxue/services/api/internal/books"
)

type OpenAITranslator struct {
	apiKey     string
	baseURL    string
	model      string
	httpClient *http.Client
}

func NewOpenAITranslator(
	apiKey string,
	baseURL string,
	model string,
	httpClient *http.Client,
) *OpenAITranslator {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 45 * time.Second}
	}

	return &OpenAITranslator{
		apiKey:     strings.TrimSpace(apiKey),
		baseURL:    strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		model:      strings.TrimSpace(model),
		httpClient: httpClient,
	}
}

func (t *OpenAITranslator) TranslateChapter(
	ctx context.Context,
	request books.TranslationRequest,
) ([]string, error) {
	if len(request.Lines) == 0 {
		return nil, nil
	}

	if t.apiKey == "" {
		return nil, fmt.Errorf("missing OPENAI_API_KEY")
	}

	if t.baseURL == "" {
		return nil, fmt.Errorf("missing OpenAI base URL")
	}

	if t.model == "" {
		return nil, fmt.Errorf("missing OpenAI translation model")
	}

	requestBody := openAIResponsesRequest{
		Model: t.model,
		Input: []openAIInputMessage{
			{
				Role: "system",
				Content: []openAIInputText{
					{
						Type: "input_text",
						Text: "You translate Classical Chinese and literary Chinese into faithful, natural English for learners. Return exactly one English translation per input line in the same order. Do not omit lines. Do not add commentary, numbering, or notes.",
					},
				},
			},
			{
				Role: "user",
				Content: []openAIInputText{
					{
						Type: "input_text",
						Text: buildTranslationPrompt(request),
					},
				},
			},
		},
		Temperature: 0.2,
		Text: openAITextConfig{
			Verbosity: "low",
			Format: openAIJSONSchemaFormat{
				Type:        "json_schema",
				Name:        "chapter_translations",
				Description: "English translations for each requested reading unit line.",
				Strict:      true,
				Schema: map[string]any{
					"type":                 "object",
					"additionalProperties": false,
					"required":             []string{"translations"},
					"properties": map[string]any{
						"translations": map[string]any{
							"type": "array",
							"items": map[string]any{
								"type": "string",
							},
						},
					},
				},
			},
		},
	}

	payload, err := json.Marshal(requestBody)
	if err != nil {
		return nil, fmt.Errorf("marshal translation request: %w", err)
	}

	httpRequest, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		t.baseURL+"/responses",
		bytes.NewReader(payload),
	)
	if err != nil {
		return nil, fmt.Errorf("create translation request: %w", err)
	}

	httpRequest.Header.Set("Authorization", "Bearer "+t.apiKey)
	httpRequest.Header.Set("Content-Type", "application/json")

	httpResponse, err := t.httpClient.Do(httpRequest)
	if err != nil {
		return nil, fmt.Errorf("call OpenAI responses API: %w", err)
	}
	defer httpResponse.Body.Close()

	responseBody, err := io.ReadAll(httpResponse.Body)
	if err != nil {
		return nil, fmt.Errorf("read translation response: %w", err)
	}

	if httpResponse.StatusCode < 200 || httpResponse.StatusCode >= 300 {
		var apiError openAIErrorResponse
		if err := json.Unmarshal(responseBody, &apiError); err == nil && strings.TrimSpace(apiError.Error.Message) != "" {
			return nil, fmt.Errorf("OpenAI responses API: %s", apiError.Error.Message)
		}

		return nil, fmt.Errorf("OpenAI responses API returned status %d", httpResponse.StatusCode)
	}

	var response openAIResponsesResponse
	if err := json.Unmarshal(responseBody, &response); err != nil {
		return nil, fmt.Errorf("decode translation response: %w", err)
	}

	rawOutput := strings.TrimSpace(response.outputText())
	if rawOutput == "" {
		return nil, fmt.Errorf("translation response did not include structured output text")
	}

	var formattedResponse struct {
		Translations []string `json:"translations"`
	}
	if err := json.Unmarshal([]byte(rawOutput), &formattedResponse); err != nil {
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

func buildTranslationPrompt(request books.TranslationRequest) string {
	var builder strings.Builder
	builder.WriteString("Book ID: ")
	builder.WriteString(request.BookID)
	builder.WriteString("\nBook title: ")
	builder.WriteString(request.BookTitle)
	builder.WriteString("\nChapter ID: ")
	builder.WriteString(request.ChapterID)
	builder.WriteString("\nChapter title: ")
	builder.WriteString(request.ChapterTitle)
	builder.WriteString("\n\nTranslate each line into natural English:\n")

	for index, line := range request.Lines {
		builder.WriteString(fmt.Sprintf("%d. %s\n", index+1, line))
	}

	return builder.String()
}

type openAIResponsesRequest struct {
	Model       string               `json:"model"`
	Input       []openAIInputMessage `json:"input"`
	Temperature float64              `json:"temperature"`
	Text        openAITextConfig     `json:"text"`
}

type openAIInputMessage struct {
	Role    string            `json:"role"`
	Content []openAIInputText `json:"content"`
}

type openAIInputText struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type openAITextConfig struct {
	Format    openAIJSONSchemaFormat `json:"format"`
	Verbosity string                 `json:"verbosity,omitempty"`
}

type openAIJSONSchemaFormat struct {
	Type        string         `json:"type"`
	Name        string         `json:"name"`
	Description string         `json:"description,omitempty"`
	Schema      map[string]any `json:"schema"`
	Strict      bool           `json:"strict"`
}

type openAIResponsesResponse struct {
	Output []openAIOutputMessage `json:"output"`
}

func (r openAIResponsesResponse) outputText() string {
	for _, output := range r.Output {
		for _, content := range output.Content {
			if content.Type == "output_text" && strings.TrimSpace(content.Text) != "" {
				return content.Text
			}
		}
	}

	return ""
}

type openAIOutputMessage struct {
	Content []openAIOutputContent `json:"content"`
}

type openAIOutputContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type openAIErrorResponse struct {
	Error struct {
		Message string `json:"message"`
	} `json:"error"`
}
