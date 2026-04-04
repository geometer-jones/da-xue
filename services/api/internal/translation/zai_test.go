package translation

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"daxue/services/api/internal/books"
	"daxue/services/api/internal/zai"
)

func TestZAITranslatorTranslateChapter(t *testing.T) {
	var capturedRequest zai.ChatCompletionRequest

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" {
			t.Fatalf("expected /v1/messages path, got %s", r.URL.Path)
		}

		if authHeader := r.Header.Get("x-api-key"); authHeader != "test-key" {
			t.Fatalf("expected x-api-key header, got %q", authHeader)
		}

		var wireRequest map[string]any
		if err := json.NewDecoder(r.Body).Decode(&wireRequest); err != nil {
			t.Fatalf("failed to decode request body: %v", err)
		}

		capturedRequest.Model, _ = wireRequest["model"].(string)
		if systemPrompt, ok := wireRequest["system"].(string); ok {
			capturedRequest.Messages = append(capturedRequest.Messages, zai.Message{
				Role:    "system",
				Content: systemPrompt,
			})
		}

		rawMessages, _ := wireRequest["messages"].([]any)
		for _, rawMessage := range rawMessages {
			messageMap, ok := rawMessage.(map[string]any)
			if !ok {
				continue
			}

			role, _ := messageMap["role"].(string)
			content, _ := messageMap["content"].(string)
			capturedRequest.Messages = append(capturedRequest.Messages, zai.Message{
				Role:    role,
				Content: content,
			})
		}

		response := map[string]any{
			"id":    "msg_123",
			"model": "glm-5-turbo",
			"content": []map[string]any{
				{
					"type": "text",
					"text": `{"translations":["Study and practice it regularly.","Friends come from far away."]}`,
				},
			},
		}

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(response); err != nil {
			t.Fatalf("failed to encode response: %v", err)
		}
	}))
	defer server.Close()

	client := zai.NewClient("test-key", server.URL, server.Client())
	translator := NewZAITranslator(client, "glm-5-turbo")

	translations, err := translator.TranslateChapter(context.Background(), books.TranslationRequest{
		BookID:       "lunyu",
		BookTitle:    "四書章句集注 : 論語集注",
		ChapterID:    "chapter-001",
		ChapterTitle: "學而第一",
		Lines: []string{
			"學而時習之，不亦說乎？",
			"有朋自遠方來，不亦樂乎？",
		},
	})
	if err != nil {
		t.Fatalf("TranslateChapter returned error: %v", err)
	}

	if len(translations) != 2 {
		t.Fatalf("expected 2 translations, got %d", len(translations))
	}

	if capturedRequest.Model != "glm-5-turbo" {
		t.Fatalf("expected model glm-5-turbo, got %q", capturedRequest.Model)
	}

	if len(capturedRequest.Messages) != 2 {
		t.Fatalf("expected 2 messages, got %d", len(capturedRequest.Messages))
	}

	prompt := capturedRequest.Messages[1].Content
	if !strings.Contains(prompt, "Book ID: lunyu") {
		t.Fatalf("expected prompt to include book id, got %q", prompt)
	}

	if !strings.Contains(prompt, "1. 學而時習之，不亦說乎？") {
		t.Fatalf("expected prompt to include first source line, got %q", prompt)
	}

	if translations[0] != "Study and practice it regularly." {
		t.Fatalf("unexpected first translation %q", translations[0])
	}

	if translations[1] != "Friends come from far away." {
		t.Fatalf("unexpected second translation %q", translations[1])
	}
}

func TestZAITranslatorReturnsLengthMismatchError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		response := map[string]any{
			"id": "msg_123",
			"content": []map[string]any{
				{
					"type": "text",
					"text": `{"translations":["Only one line."]}`,
				},
			},
		}

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(response); err != nil {
			t.Fatalf("failed to encode response: %v", err)
		}
	}))
	defer server.Close()

	translator := NewZAITranslator(
		zai.NewClient("test-key", server.URL, server.Client()),
		"glm-5-turbo",
	)

	_, err := translator.TranslateChapter(context.Background(), books.TranslationRequest{
		BookID:       "lunyu",
		BookTitle:    "四書章句集注 : 論語集注",
		ChapterID:    "chapter-001",
		ChapterTitle: "學而第一",
		Lines: []string{
			"學而時習之，不亦說乎？",
			"有朋自遠方來，不亦樂乎？",
		},
	})
	if err == nil {
		t.Fatal("expected length mismatch error, got nil")
	}

	if !strings.Contains(err.Error(), "returned 1 lines for 2 inputs") {
		t.Fatalf("unexpected error %q", err)
	}
}

func TestExtractJSONObjectStripsMarkdownFence(t *testing.T) {
	raw := "```json\n{\"translations\":[\"One line.\"]}\n```"

	if got := extractJSONObject(raw); got != "{\"translations\":[\"One line.\"]}" {
		t.Fatalf("unexpected extracted json %q", got)
	}
}
