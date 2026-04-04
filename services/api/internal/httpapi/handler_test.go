package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"daxue/services/api/internal/books"
	"daxue/services/api/internal/characters"
	"daxue/services/api/internal/config"
	"daxue/services/api/internal/hanzi"
	"daxue/services/api/internal/zai"
)

func TestHealthEndpoint(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/api/v1/health", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload healthResponse
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if payload.Status != "ok" {
		t.Fatalf("expected healthy status, got %q", payload.Status)
	}

	if payload.Environment != "test" {
		t.Fatalf("expected test environment, got %q", payload.Environment)
	}
}

func TestWebAppRootServesIndexAtRoot(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
		WebAppRoot:     createFixtureWebAppRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	if contentType := response.Header().Get("Content-Type"); !strings.Contains(contentType, "text/html") {
		t.Fatalf("expected html content type, got %q", contentType)
	}

	if !strings.Contains(response.Body.String(), "Da Xue Web") {
		t.Fatalf("expected web app index html, got %q", response.Body.String())
	}
}

func TestWebAppRootServesIndexForSPADeepLinks(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
		WebAppRoot:     createFixtureWebAppRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/library/demo-book", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	if !strings.Contains(response.Body.String(), "Da Xue Web") {
		t.Fatalf("expected SPA fallback index html, got %q", response.Body.String())
	}
}

func TestWebAppRootReturnsNotFoundForMissingAssets(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
		WebAppRoot:     createFixtureWebAppRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/main.dart.js", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("expected status %d, got %d", http.StatusNotFound, response.Code)
	}
}

func TestOptionsRequestReturnsNoContent(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"http://localhost:3000"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	request := httptest.NewRequest(http.MethodOptions, "/api/v1/health", nil)
	request.Header.Set("Origin", "http://localhost:3000")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("expected status %d, got %d", http.StatusNoContent, response.Code)
	}

	if allowOrigin := response.Header().Get("Access-Control-Allow-Origin"); allowOrigin != "http://localhost:3000" {
		t.Fatalf("expected allow origin header to be preserved, got %q", allowOrigin)
	}
}

func TestGuidedChatEndpointOverHTTPReturnsServiceUnavailableWithoutChatClient(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	server := httptest.NewServer(handler)
	defer server.Close()

	response, err := http.Post(
		server.URL+"/api/v1/guided-chat",
		"application/json",
		bytes.NewBufferString(`{
  "context": {
    "bookId": "demo-book",
    "chapterId": "chapter-001"
  },
  "messages": [
    {
      "role": "user",
      "content": "What should I focus on?"
    }
  ]
}`),
	)
	if err != nil {
		t.Fatalf("failed to post guided chat request: %v", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusServiceUnavailable {
		body, _ := io.ReadAll(response.Body)
		t.Fatalf("expected status %d, got %d with body %q", http.StatusServiceUnavailable, response.StatusCode, string(body))
	}

	var payload errorResponse
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if !strings.Contains(payload.Error, "unavailable") {
		t.Fatalf("expected guided chat unavailable error, got %q", payload.Error)
	}
}

func TestBooksEndpointListsAvailableBooks(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/api/v1/books", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload struct {
		Books []struct {
			ID           string `json:"id"`
			Title        string `json:"title"`
			ChapterCount int    `json:"chapterCount"`
		} `json:"books"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if len(payload.Books) != 1 {
		t.Fatalf("expected 1 book, got %d", len(payload.Books))
	}

	if payload.Books[0].ID != "demo-book" {
		t.Fatalf("expected demo-book, got %q", payload.Books[0].ID)
	}
}

func TestBookChapterEndpointReturnsContent(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/api/v1/books/demo-book/chapters/chapter-001", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload struct {
		Chapter struct {
			ID           string `json:"id"`
			Title        string `json:"title"`
			Text         string `json:"text"`
			ReadingUnits []struct {
				ID            string `json:"id"`
				Text          string `json:"text"`
				TranslationEn string `json:"translationEn"`
			} `json:"readingUnits"`
		} `json:"chapter"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if payload.Chapter.ID != "chapter-001" {
		t.Fatalf("expected chapter-001, got %q", payload.Chapter.ID)
	}

	if payload.Chapter.Text != "天地玄黃。宇宙洪荒。" {
		t.Fatalf("unexpected chapter text %q", payload.Chapter.Text)
	}

	if len(payload.Chapter.ReadingUnits) != 2 {
		t.Fatalf("expected 2 reading units, got %d", len(payload.Chapter.ReadingUnits))
	}

	if payload.Chapter.ReadingUnits[0].TranslationEn != "Heaven and earth are dark and yellow." {
		t.Fatalf("unexpected first reading unit translation %q", payload.Chapter.ReadingUnits[0].TranslationEn)
	}
}

func TestBookEndpointDerivesZhongYongChapterTitles(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createZhongYongLibraryRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/api/v1/books/zhong-yong", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload struct {
		Book struct {
			Chapters []struct {
				Title string `json:"title"`
			} `json:"chapters"`
		} `json:"book"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if len(payload.Book.Chapters) != 3 {
		t.Fatalf("expected 3 chapters, got %d", len(payload.Book.Chapters))
	}

	if payload.Book.Chapters[0].Title != "天命之謂性" {
		t.Fatalf("expected chapter 1 title to be derived, got %q", payload.Book.Chapters[0].Title)
	}

	if payload.Book.Chapters[1].Title != "君子中庸" {
		t.Fatalf("expected chapter 2 title to be derived, got %q", payload.Book.Chapters[1].Title)
	}

	if payload.Book.Chapters[2].Title != "衣錦尚絅" {
		t.Fatalf("expected chapter 33 title to be derived, got %q", payload.Book.Chapters[2].Title)
	}
}

func TestCharacterComponentsEndpointReturnsDataset(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/api/v1/character-components", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload struct {
		Dataset struct {
			GroupedComponentCount int `json:"groupedComponentCount"`
			Entries               []struct {
				GroupID       int    `json:"groupId"`
				CanonicalForm string `json:"canonicalForm"`
				CanonicalName string `json:"canonicalName"`
				MemberCount   int    `json:"memberCount"`
			} `json:"entries"`
		} `json:"dataset"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if payload.Dataset.GroupedComponentCount != 2 {
		t.Fatalf("expected 2 grouped components, got %d", payload.Dataset.GroupedComponentCount)
	}

	if len(payload.Dataset.Entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(payload.Dataset.Entries))
	}

	if payload.Dataset.Entries[0].CanonicalForm != "口" {
		t.Fatalf("expected first canonical form 口, got %q", payload.Dataset.Entries[0].CanonicalForm)
	}
}

func TestCharactersEndpointReturnsIndex(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/api/v1/characters", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload struct {
		Index struct {
			EntryCount int `json:"entryCount"`
			Entries    []struct {
				Character   string   `json:"character"`
				Simplified  string   `json:"simplified"`
				Traditional string   `json:"traditional"`
				Pinyin      []string `json:"pinyin"`
				Zhuyin      []string `json:"zhuyin"`
				English     []string `json:"english"`
				Explosion   struct {
					Analysis struct {
						Expression string   `json:"expression"`
						Parts      []string `json:"parts"`
					} `json:"analysis"`
				} `json:"explosion"`
			} `json:"entries"`
		} `json:"index"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if payload.Index.EntryCount != 2 {
		t.Fatalf("expected 2 entries, got %d", payload.Index.EntryCount)
	}

	if payload.Index.Entries[0].Character != "学" {
		t.Fatalf("expected first character 学, got %q", payload.Index.Entries[0].Character)
	}

	if payload.Index.Entries[0].Explosion.Analysis.Expression != "子 + 冖 + 爻" {
		t.Fatalf("unexpected analysis expression %q", payload.Index.Entries[0].Explosion.Analysis.Expression)
	}
}

func TestCharacterEndpointReturnsExactEntry(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	request := httptest.NewRequest(http.MethodGet, "/api/v1/characters/學", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload struct {
		Character struct {
			Character   string   `json:"character"`
			Simplified  string   `json:"simplified"`
			Traditional string   `json:"traditional"`
			English     []string `json:"english"`
		} `json:"character"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if payload.Character.Character != "学" {
		t.Fatalf("expected canonical character 学, got %q", payload.Character.Character)
	}

	if payload.Character.Traditional != "學" {
		t.Fatalf("expected traditional 學, got %q", payload.Character.Traditional)
	}

	if len(payload.Character.English) == 0 || payload.Character.English[0] != "to study" {
		t.Fatalf("unexpected english senses %#v", payload.Character.English)
	}
}

func TestCharacterExplosionEndpointReturnsFreshExplosion(t *testing.T) {
	libraryRoot := createFixtureLibraryRoot(t)
	chatClient := &stubGuidedChatClient{
		response: zai.ChatCompletionResponse{
			RequestID: "req-character-explosion",
			Model:     "glm-5-turbo",
			Choices: []zai.ChatCompletionChoice{
				{
					Message: zai.ChatCompletionMessage{
						Role: "assistant",
						Content: `{
  "explosion": {
    "analysis": {
      "expression": "子 + 冖 + 爻",
      "parts": ["子", "冖", "爻"]
    },
    "synthesis": {
      "containingCharacters": ["覺", "斆"],
      "phraseUse": ["學問", "學習", "學習"],
      "homophones": {
        "sameTone": ["穴"],
        "differentTone": ["雪"]
      }
    },
    "meaningMap": {
      "synonyms": ["習"],
      "antonyms": ["忘"]
    }
  }
}`,
					},
				},
			},
		},
	}

	handler := newHandler(
		config.Config{
			AppEnv:         "test",
			AllowedOrigins: []string{"*"},
			ContentRoot:    libraryRoot,
			GLMModel:       "glm-5-turbo",
		},
		books.NewFSRepository(libraryRoot, nil),
		characters.NewFSRepository(libraryRoot),
		hanzi.NewFSRepository(libraryRoot),
		characters.NewZAIExplosionGenerator(chatClient, "glm-5-turbo"),
		nil,
	)

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/characters/%E5%AD%B8/explosion",
		nil,
	)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload struct {
		Character struct {
			Character   string `json:"character"`
			Traditional string `json:"traditional"`
			Explosion   struct {
				Analysis struct {
					Expression string   `json:"expression"`
					Parts      []string `json:"parts"`
				} `json:"analysis"`
				Synthesis struct {
					PhraseUse []string `json:"phraseUse"`
				} `json:"synthesis"`
				MeaningMap struct {
					Synonyms []string `json:"synonyms"`
				} `json:"meaningMap"`
			} `json:"explosion"`
		} `json:"character"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if payload.Character.Character != "学" {
		t.Fatalf("expected canonical character 学, got %q", payload.Character.Character)
	}

	if payload.Character.Traditional != "學" {
		t.Fatalf("expected traditional 學, got %q", payload.Character.Traditional)
	}

	if payload.Character.Explosion.Analysis.Expression != "子 + 冖 + 爻" {
		t.Fatalf("unexpected generated analysis expression %q", payload.Character.Explosion.Analysis.Expression)
	}

	if len(payload.Character.Explosion.Analysis.Parts) != 3 {
		t.Fatalf("expected 3 analysis parts, got %#v", payload.Character.Explosion.Analysis.Parts)
	}

	if len(payload.Character.Explosion.Synthesis.PhraseUse) != 2 {
		t.Fatalf("expected duplicate phrase use values to be normalized, got %#v", payload.Character.Explosion.Synthesis.PhraseUse)
	}

	if len(payload.Character.Explosion.MeaningMap.Synonyms) != 1 || payload.Character.Explosion.MeaningMap.Synonyms[0] != "習" {
		t.Fatalf("unexpected generated synonyms %#v", payload.Character.Explosion.MeaningMap.Synonyms)
	}

	if len(chatClient.requests) != 1 {
		t.Fatalf("expected one character explosion request, got %d", len(chatClient.requests))
	}

	if chatClient.requests[0].ResponseFormat == nil || chatClient.requests[0].ResponseFormat.Type != "json_object" {
		t.Fatalf("expected character explosion request to require json_object response format")
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Generate a fresh explosion") {
		t.Fatalf("expected prompt to ask for a fresh explosion, got %q", chatClient.requests[0].Messages[1].Content)
	}
}

func TestCharacterExplosionEndpointReturnsServiceUnavailableWithoutGenerator(t *testing.T) {
	handler := NewHandler(config.Config{
		AppEnv:         "test",
		AllowedOrigins: []string{"*"},
		ContentRoot:    createFixtureLibraryRoot(t),
	})

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/characters/%E5%9C%B0/explosion",
		nil,
	)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected status %d, got %d", http.StatusServiceUnavailable, response.Code)
	}

	var payload errorResponse
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if !strings.Contains(payload.Error, "unavailable") {
		t.Fatalf("expected character explosion unavailable error, got %q", payload.Error)
	}
}

func TestGuidedChatEndpointReturnsAssistantReply(t *testing.T) {
	libraryRoot := createFixtureLibraryRoot(t)
	chatClient := &stubGuidedChatClient{
		response: zai.ChatCompletionResponse{
			RequestID: "req-guided",
			Model:     "glm-5-turbo",
			Choices: []zai.ChatCompletionChoice{
				{
					Message: zai.ChatCompletionMessage{
						Role:    "assistant",
						Content: "Focus on how the line pairs cosmic images before you move on.",
					},
				},
			},
		},
	}

	handler := newHandler(
		config.Config{
			AppEnv:         "test",
			AllowedOrigins: []string{"*"},
			ContentRoot:    libraryRoot,
			GLMModel:       "glm-5-turbo",
		},
		books.NewFSRepository(libraryRoot, nil),
		characters.NewFSRepository(libraryRoot),
		hanzi.NewFSRepository(libraryRoot),
		nil,
		chatClient,
	)

  request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/guided-chat",
		strings.NewReader(`{
  "context": {
    "bookId": "demo-book",
    "chapterId": "chapter-001",
    "readingUnitId": "chapter-001-line-002",
    "openLine": "宇宙洪荒。",
    "characterComponent": "口",
    "learnerTranslation": "The cosmos begins in wild expansion.",
    "learnerResponse": "The scale suddenly opens from earth to the whole cosmos."
  },
  "previousLines": [
    {
      "readingUnitId": "chapter-001-line-001",
      "order": 1,
      "text": "天地玄黃。",
      "translationEn": "Heaven and earth are dark and yellow.",
      "learnerTranslation": "Heaven and earth begin in mystery.",
      "learnerResponse": "The paired images feel like a compressed opening frame."
    }
  ],
  "messages": [
    {
      "role": "user",
      "content": "What changes in the second line?"
    }
  ]
}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	var payload struct {
		Reply struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"reply"`
		Model    string `json:"model"`
		Provider string `json:"provider"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if payload.Reply.Role != "assistant" {
		t.Fatalf("expected assistant reply role, got %q", payload.Reply.Role)
	}

	if payload.Provider != "z.ai" {
		t.Fatalf("expected z.ai provider, got %q", payload.Provider)
	}

	if payload.Reply.Content == "" {
		t.Fatal("expected non-empty assistant reply")
	}

	if len(chatClient.requests) != 1 {
		t.Fatalf("expected one guided chat request, got %d", len(chatClient.requests))
	}

	if chatClient.requests[0].Model != "glm-5-turbo" {
		t.Fatalf("expected glm-5-turbo model, got %q", chatClient.requests[0].Model)
	}

	if len(chatClient.requests[0].Messages) < 3 {
		t.Fatalf("expected prompt context plus history, got %d messages", len(chatClient.requests[0].Messages))
	}

	if !strings.Contains(chatClient.requests[0].Messages[0].Content, "prioritize fidelity to the text") {
		t.Fatalf("expected guided chat system prompt to prioritize fidelity to text, got %q", chatClient.requests[0].Messages[0].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Chinese text: 宇宙洪荒。") {
		t.Fatalf("expected guided chat context to include the current line, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Learner translation: The cosmos begins in wild expansion.") {
		t.Fatalf("expected guided chat context to include the current learner translation, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Learner response: The scale suddenly opens from earth to the whole cosmos.") {
		t.Fatalf("expected guided chat context to include the current learner response, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Line 1 (chapter-001-line-001): 天地玄黃。") {
		t.Fatalf("expected guided chat context to include the previous line, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "\nOpen line: 宇宙洪荒。") {
		t.Fatalf("expected guided chat context to include the open line, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Character component focus: 口") {
		t.Fatalf("expected guided chat context to include the character component focus, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "You are helping a learner understand how the character component ") {
		t.Fatalf("expected guided chat context to include the character-component pedagogical guidance, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Learner translation: Heaven and earth begin in mystery.") {
		t.Fatalf("expected guided chat context to include the learner translation, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Learner response: The paired images feel like a compressed opening frame.") {
		t.Fatalf("expected guided chat context to include the learner response, got %q", chatClient.requests[0].Messages[1].Content)
	}
}

func TestGuidedChatEndpointSupportsChapterLevelContext(t *testing.T) {
	libraryRoot := createFixtureLibraryRoot(t)
	chatClient := &stubGuidedChatClient{
		response: zai.ChatCompletionResponse{
			RequestID: "req-chapter-chat",
			Model:     "glm-5-turbo",
			Choices: []zai.ChatCompletionChoice{
				{
					Message: zai.ChatCompletionMessage{
						Role:    "assistant",
						Content: "Stay with the chapter opening and compare how the paired images set the scale.",
					},
				},
			},
		},
	}

	handler := newHandler(
		config.Config{
			AppEnv:         "test",
			AllowedOrigins: []string{"*"},
			ContentRoot:    libraryRoot,
			GLMModel:       "glm-5-turbo",
		},
		books.NewFSRepository(libraryRoot, nil),
		characters.NewFSRepository(libraryRoot),
		hanzi.NewFSRepository(libraryRoot),
		nil,
		chatClient,
	)

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/guided-chat",
		strings.NewReader(`{
  "context": {
    "bookId": "demo-book",
    "chapterId": "chapter-001"
  },
  "messages": [
    {
      "role": "user",
      "content": "What sets up the chapter?"
    }
  ]
}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, response.Code)
	}

	if len(chatClient.requests) != 1 {
		t.Fatalf("expected one guided chat request, got %d", len(chatClient.requests))
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Current focus: chapter-level discussion") {
		t.Fatalf("expected chapter-level context in prompt, got %q", chatClient.requests[0].Messages[1].Content)
	}

	if !strings.Contains(chatClient.requests[0].Messages[1].Content, "Chapter text: 天地玄黃。宇宙洪荒。") {
		t.Fatalf("expected chapter text in prompt, got %q", chatClient.requests[0].Messages[1].Content)
	}
}

func TestGuidedChatEndpointRejectsAssistantFinalMessage(t *testing.T) {
	libraryRoot := createFixtureLibraryRoot(t)
	handler := newHandler(
		config.Config{
			AppEnv:         "test",
			AllowedOrigins: []string{"*"},
			ContentRoot:    libraryRoot,
			GLMModel:       "glm-5-turbo",
		},
		books.NewFSRepository(libraryRoot, nil),
		characters.NewFSRepository(libraryRoot),
		hanzi.NewFSRepository(libraryRoot),
		nil,
		&stubGuidedChatClient{},
	)

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/guided-chat",
		strings.NewReader(`{
  "context": {
    "bookId": "demo-book",
    "chapterId": "chapter-001",
    "readingUnitId": "chapter-001-line-001"
  },
  "messages": [
    {
      "role": "assistant",
      "content": "Hello"
    }
  ]
}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, response.Code)
	}
}

func TestGuidedChatEndpointReturnsServiceUnavailableWhenChatClientIsOverloaded(t *testing.T) {
	libraryRoot := createFixtureLibraryRoot(t)
	handler := newHandler(
		config.Config{
			AppEnv:         "test",
			AllowedOrigins: []string{"*"},
			ContentRoot:    libraryRoot,
			GLMModel:       "glm-5-turbo",
		},
		books.NewFSRepository(libraryRoot, nil),
		characters.NewFSRepository(libraryRoot),
		hanzi.NewFSRepository(libraryRoot),
		nil,
		&stubGuidedChatClient{err: zai.ErrOverloaded},
	)

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/v1/guided-chat",
		strings.NewReader(`{
  "context": {
    "bookId": "demo-book",
    "chapterId": "chapter-001"
  },
  "messages": [
    {
      "role": "user",
      "content": "What should I focus on?"
    }
  ]
}`),
	)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected status %d, got %d", http.StatusServiceUnavailable, response.Code)
	}

	var payload errorResponse
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("failed to decode response body: %v", err)
	}

	if !strings.Contains(payload.Error, "busy") {
		t.Fatalf("expected busy overload error, got %q", payload.Error)
	}
}

type stubGuidedChatClient struct {
	requests []zai.ChatCompletionRequest
	response zai.ChatCompletionResponse
	err      error
}

func (s *stubGuidedChatClient) ChatCompletion(
	_ context.Context,
	request zai.ChatCompletionRequest,
) (zai.ChatCompletionResponse, error) {
	s.requests = append(s.requests, request)
	return s.response, s.err
}

func createFixtureLibraryRoot(t *testing.T) string {
	t.Helper()

	root := t.TempDir()
	bookDir := filepath.Join(root, "books", "demo-book")
	chaptersDir := filepath.Join(bookDir, "chapters")
	charactersDir := filepath.Join(root, "references", "characters")
	hanziDir := filepath.Join(root, "references", "hanzi")

	if err := os.MkdirAll(chaptersDir, 0o755); err != nil {
		t.Fatalf("failed to create fixture directories: %v", err)
	}

	if err := os.MkdirAll(hanziDir, 0o755); err != nil {
		t.Fatalf("failed to create hanzi fixture directory: %v", err)
	}

	if err := os.MkdirAll(charactersDir, 0o755); err != nil {
		t.Fatalf("failed to create character fixture directory: %v", err)
	}

	catalog := `{
  "title": "Demo Book",
  "chapter_count": 1,
  "source_url": "https://example.com/demo-book",
  "provider": "fixture",
  "chapters": [
    {
      "id": "chapter-001",
      "order": 1,
      "title": "Chapter One",
      "summary": "Opening lines",
      "character_count": 10,
      "reading_unit_count": 2,
      "chapter_path": "books/demo-book/chapters/chapter-001.json"
    }
  ]
}`

	chapter := `{
  "chapter": {
    "id": "chapter-001",
    "order": 1,
    "title": "Chapter One",
    "summary": "Opening lines",
    "text": "天地玄黃。宇宙洪荒。",
    "character_count": 10,
    "reading_unit_count": 2,
    "reading_units": [
      {
        "id": "chapter-001-line-001",
        "order": 1,
        "text": "天地玄黃。",
        "generated_annotation": {
          "layers": {
            "translation_en": "Heaven and earth are dark and yellow."
          }
        },
        "character_count": 5
      },
      {
        "id": "chapter-001-line-002",
        "order": 2,
        "text": "宇宙洪荒。",
        "generated_annotation": {
          "layers": {
            "translation_en": "The cosmos is vast and wild."
          }
        },
        "character_count": 5
      }
    ]
  }
}`

	components := `{
  "title": "Modern Common Character Components",
  "standard": "GF0014-2009",
  "grouped_component_count": 2,
  "raw_component_count": 3,
  "entries": [
    {
      "group_id": 1,
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
    }
  ]
}`

	characterIndex := `{
  "entries": [
    {
      "character": "学",
      "simplified": "学",
      "traditional": "學",
      "pinyin": ["xué"],
      "zhuyin": ["ㄒㄩㄝˊ"],
      "english": ["to study", "learning"],
      "explosion": {
        "analysis": {
          "expression": "子 + 冖 + 爻",
          "parts": ["子", "冖", "爻"]
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
          "synonyms": ["学习"],
          "antonyms": ["忘"]
        }
      }
    },
    {
      "character": "道",
      "simplified": "道",
      "traditional": "道",
      "pinyin": ["dào"],
      "zhuyin": ["ㄉㄠˋ"],
      "english": ["way", "path", "principle"],
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
    }
  ]
}`

	if err := os.WriteFile(filepath.Join(bookDir, "catalog.json"), []byte(catalog), 0o644); err != nil {
		t.Fatalf("failed to write catalog fixture: %v", err)
	}

	if err := os.WriteFile(filepath.Join(chaptersDir, "chapter-001.json"), []byte(chapter), 0o644); err != nil {
		t.Fatalf("failed to write chapter fixture: %v", err)
	}

	if err := os.WriteFile(
		filepath.Join(hanziDir, "modern-common-components-gf0014-2009-grouped.json"),
		[]byte(components),
		0o644,
	); err != nil {
		t.Fatalf("failed to write components fixture: %v", err)
	}

	if err := os.WriteFile(filepath.Join(charactersDir, "index.json"), []byte(characterIndex), 0o644); err != nil {
		t.Fatalf("failed to write character index fixture: %v", err)
	}

	return root
}

func createFixtureWebAppRoot(t *testing.T) string {
	t.Helper()

	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "assets"), 0o755); err != nil {
		t.Fatalf("failed to create web app fixture directory: %v", err)
	}

	if err := os.WriteFile(
		filepath.Join(root, "index.html"),
		[]byte("<!doctype html><html><body>Da Xue Web</body></html>"),
		0o644,
	); err != nil {
		t.Fatalf("failed to write web app index fixture: %v", err)
	}

	if err := os.WriteFile(
		filepath.Join(root, "assets", "app.js"),
		[]byte("console.log('web app');"),
		0o644,
	); err != nil {
		t.Fatalf("failed to write web app asset fixture: %v", err)
	}

	return root
}

func createZhongYongLibraryRoot(t *testing.T) string {
	t.Helper()

	root := t.TempDir()
	bookDir := filepath.Join(root, "books", "zhong-yong")
	chaptersDir := filepath.Join(bookDir, "chapters")
	hanziDir := filepath.Join(root, "references", "hanzi")
	charactersDir := filepath.Join(root, "references", "characters")

	if err := os.MkdirAll(chaptersDir, 0o755); err != nil {
		t.Fatalf("failed to create chapters fixture directory: %v", err)
	}
	if err := os.MkdirAll(hanziDir, 0o755); err != nil {
		t.Fatalf("failed to create hanzi fixture directory: %v", err)
	}
	if err := os.MkdirAll(charactersDir, 0o755); err != nil {
		t.Fatalf("failed to create characters fixture directory: %v", err)
	}

	catalog := `{
  "title": "中庸章句",
  "chapter_count": 3,
  "source_url": "https://example.com/zhong-yong",
  "provider": "fixture",
  "chapters": [
    {
      "id": "chapter-001",
      "order": 1,
      "title": "",
      "summary": "",
      "character_count": 15,
      "reading_unit_count": 1,
      "chapter_path": "books/zhong-yong/chapters/chapter-001.json"
    },
    {
      "id": "chapter-002",
      "order": 2,
      "title": "",
      "summary": "",
      "character_count": 12,
      "reading_unit_count": 1,
      "chapter_path": "books/zhong-yong/chapters/chapter-002.json"
    },
    {
      "id": "chapter-033",
      "order": 33,
      "title": "",
      "summary": "",
      "character_count": 14,
      "reading_unit_count": 1,
      "chapter_path": "books/zhong-yong/chapters/chapter-033.json"
    }
  ]
}`

	chapters := map[string]string{
		"chapter-001.json": `{
  "chapter": {
    "id": "chapter-001",
    "order": 1,
    "title": "",
    "summary": "",
    "text": "天命之謂性，率性之謂道，脩道之謂教。",
    "character_count": 15,
    "reading_unit_count": 1,
    "reading_units": [
      {
        "id": "chapter-001-line-001",
        "order": 1,
        "text": "天命之謂性，率性之謂道，脩道之謂教。",
        "generated_annotation": {
          "layers": {
            "translation_en": "What Heaven has conferred is called nature."
          }
        },
        "character_count": 15
      }
    ]
  }
}`,
		"chapter-002.json": `{
  "chapter": {
    "id": "chapter-002",
    "order": 2,
    "title": "",
    "summary": "",
    "text": "仲尼曰：「君子中庸，小人反中庸。」",
    "character_count": 12,
    "reading_unit_count": 1,
    "reading_units": [
      {
        "id": "chapter-002-line-001",
        "order": 1,
        "text": "仲尼曰：「君子中庸，小人反中庸。」",
        "generated_annotation": {
          "layers": {
            "translation_en": "The superior man embodies the Mean."
          }
        },
        "character_count": 12
      }
    ]
  }
}`,
		"chapter-033.json": `{
  "chapter": {
    "id": "chapter-033",
    "order": 33,
    "title": "",
    "summary": "",
    "text": "《詩》曰：「衣錦尚絅」，惡其文之著也。",
    "character_count": 14,
    "reading_unit_count": 1,
    "reading_units": [
      {
        "id": "chapter-033-line-001",
        "order": 1,
        "text": "《詩》曰：「衣錦尚絅」，惡其文之著也。",
        "generated_annotation": {
          "layers": {
            "translation_en": "Over embroidered robes, wear a plain outer garment."
          }
        },
        "character_count": 14
      }
    ]
  }
}`,
	}

	if err := os.WriteFile(filepath.Join(bookDir, "catalog.json"), []byte(catalog), 0o644); err != nil {
		t.Fatalf("failed to write catalog fixture: %v", err)
	}

	for name, contents := range chapters {
		if err := os.WriteFile(filepath.Join(chaptersDir, name), []byte(contents), 0o644); err != nil {
			t.Fatalf("failed to write %s fixture: %v", name, err)
		}
	}

	if err := os.WriteFile(
		filepath.Join(hanziDir, "modern-common-components-gf0014-2009-grouped.json"),
		[]byte(`{"title":"Modern Common Character Components","standard":"GF0014-2009","grouped_component_count":0,"raw_component_count":0,"entries":[]}`),
		0o644,
	); err != nil {
		t.Fatalf("failed to write components fixture: %v", err)
	}

	if err := os.WriteFile(
		filepath.Join(charactersDir, "index.json"),
		[]byte(`{"entries":[]}`),
		0o644,
	); err != nil {
		t.Fatalf("failed to write character index fixture: %v", err)
	}

	return root
}
