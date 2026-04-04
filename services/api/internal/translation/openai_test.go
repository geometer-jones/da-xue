package translation

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"daxue/services/api/internal/books"
)

func TestOpenAITranslatorTranslateChapter(t *testing.T) {
	var capturedRequest openAIResponsesRequest

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/responses" {
			t.Fatalf("expected /responses path, got %s", r.URL.Path)
		}

		if authHeader := r.Header.Get("Authorization"); authHeader != "Bearer test-key" {
			t.Fatalf("expected bearer auth header, got %q", authHeader)
		}

		if err := json.NewDecoder(r.Body).Decode(&capturedRequest); err != nil {
			t.Fatalf("failed to decode request body: %v", err)
		}

		response := openAIResponsesResponse{
			Output: []openAIOutputMessage{
				{
					Content: []openAIOutputContent{
						{
							Type: "output_text",
							Text: `{"translations":["Study and practice it regularly.","Friends come from far away."]}`,
						},
					},
				},
			},
		}

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(response); err != nil {
			t.Fatalf("failed to encode response: %v", err)
		}
	}))
	defer server.Close()

	translator := NewOpenAITranslator("test-key", server.URL, "gpt-5-mini", server.Client())

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

	if capturedRequest.Model != "gpt-5-mini" {
		t.Fatalf("expected model gpt-5-mini, got %q", capturedRequest.Model)
	}

	if capturedRequest.Text.Format.Type != "json_schema" {
		t.Fatalf("expected json_schema output format, got %q", capturedRequest.Text.Format.Type)
	}

	if len(capturedRequest.Input) != 2 {
		t.Fatalf("expected 2 input messages, got %d", len(capturedRequest.Input))
	}

	prompt := capturedRequest.Input[1].Content[0].Text
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

func TestOpenAITranslatorReturnsLengthMismatchError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		response := openAIResponsesResponse{
			Output: []openAIOutputMessage{
				{
					Content: []openAIOutputContent{
						{
							Type: "output_text",
							Text: `{"translations":["Only one line."]}`,
						},
					},
				},
			},
		}

		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(response); err != nil {
			t.Fatalf("failed to encode response: %v", err)
		}
	}))
	defer server.Close()

	translator := NewOpenAITranslator("test-key", server.URL, "gpt-5-mini", server.Client())

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
