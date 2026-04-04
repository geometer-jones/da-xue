package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"

	"daxue/services/api/internal/books"
	"daxue/services/api/internal/characters"
	"daxue/services/api/internal/config"
	"daxue/services/api/internal/hanzi"
	"daxue/services/api/internal/translation"
	"daxue/services/api/internal/zai"
)

type healthResponse struct {
	Status      string `json:"status"`
	Service     string `json:"service"`
	Environment string `json:"environment"`
}

type infoResponse struct {
	Service     string `json:"service"`
	Environment string `json:"environment"`
	Message     string `json:"message"`
}

type errorResponse struct {
	Error string `json:"error"`
}

type guidedChatClient interface {
	ChatCompletion(
		ctx context.Context,
		request zai.ChatCompletionRequest,
	) (zai.ChatCompletionResponse, error)
}

type guidedChatContext struct {
	BookID             string `json:"bookId"`
	ChapterID          string `json:"chapterId"`
	ReadingUnitID      string `json:"readingUnitId,omitempty"`
	OpenLine           string `json:"openLine,omitempty"`
	CharacterComponent string `json:"characterComponent,omitempty"`
	LearnerTranslation string `json:"learnerTranslation,omitempty"`
	LearnerResponse    string `json:"learnerResponse,omitempty"`
}

type guidedChatRequest struct {
	Context       guidedChatContext        `json:"context"`
	Messages      []guidedChatMessage      `json:"messages"`
	PreviousLines []guidedChatPreviousLine `json:"previousLines"`
}

type guidedChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type guidedChatPreviousLine struct {
	ReadingUnitID      string `json:"readingUnitId"`
	Order              int    `json:"order"`
	Text               string `json:"text"`
	TranslationEn      string `json:"translationEn,omitempty"`
	LearnerTranslation string `json:"learnerTranslation,omitempty"`
	LearnerResponse    string `json:"learnerResponse,omitempty"`
}

type guidedChatResponse struct {
	Reply     guidedChatMessage `json:"reply"`
	Model     string            `json:"model,omitempty"`
	Provider  string            `json:"provider"`
	RequestID string            `json:"requestId,omitempty"`
}

func NewHandler(cfg config.Config) http.Handler {
	var bookTranslator books.Translator
	var bookChatClient guidedChatClient
	var characterExplosionGenerator characters.ExplosionGenerator
	if cfg.GLMAPIKey != "" {
		zaiClient := zai.NewClient(cfg.GLMAPIKey, cfg.GLMBaseURL, nil)
		bookTranslator = translation.NewZAITranslator(zaiClient, cfg.GLMModel)
		bookChatClient = zaiClient
		characterExplosionGenerator = characters.NewZAIExplosionGenerator(
			zaiClient,
			cfg.GLMModel,
		)
	}

	bookRepository := books.NewFSRepository(cfg.ContentRoot, bookTranslator)
	characterRepository := characters.NewFSRepository(cfg.ContentRoot)
	hanziRepository := hanzi.NewFSRepository(cfg.ContentRoot)

	return newHandler(
		cfg,
		bookRepository,
		characterRepository,
		hanziRepository,
		characterExplosionGenerator,
		bookChatClient,
	)
}

func newHandler(
	cfg config.Config,
	bookRepository books.Repository,
	characterRepository characters.Repository,
	hanziRepository hanzi.Repository,
	characterExplosionGenerator characters.ExplosionGenerator,
	bookChatClient guidedChatClient,
) http.Handler {
	apiMux := http.NewServeMux()

	apiMux.HandleFunc("GET /{$}", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, infoResponse{
			Service:     "api",
			Environment: cfg.AppEnv,
			Message:     "Da Xue API is running",
		})
	})

	apiMux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{
			Status:      "ok",
			Service:     "api",
			Environment: cfg.AppEnv,
		})
	})

	apiMux.HandleFunc("GET /api/v1/health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{
			Status:      "ok",
			Service:     "api",
			Environment: cfg.AppEnv,
		})
	})

	apiMux.HandleFunc("GET /api/v1/books", func(w http.ResponseWriter, _ *http.Request) {
		bookList, err := bookRepository.ListBooks()
		if err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"books": bookList,
		})
	})

	apiMux.HandleFunc("GET /api/v1/books/", func(w http.ResponseWriter, r *http.Request) {
		handleBookRoute(w, r, bookRepository)
	})

	apiMux.HandleFunc("POST /api/v1/guided-chat", func(w http.ResponseWriter, r *http.Request) {
		handleGuidedChat(w, r, bookRepository, cfg.GLMModel, bookChatClient)
	})

	apiMux.HandleFunc("GET /api/v1/characters", func(w http.ResponseWriter, _ *http.Request) {
		index, err := characterRepository.ListCharacters()
		if err != nil {
			writeRepositoryError(w, err)
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"index": index,
		})
	})

	apiMux.HandleFunc("GET /api/v1/characters/", func(w http.ResponseWriter, r *http.Request) {
		character, suffix, ok := parseCharacterPath(r.URL.Path)
		if !ok || len(suffix) != 0 {
			writeError(w, http.StatusNotFound, "resource not found")
			return
		}

		entry, err := characterRepository.GetCharacter(character)
		if err != nil {
			writeRepositoryError(w, err)
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"character": entry,
		})
	})

	apiMux.HandleFunc("POST /api/v1/characters/", func(w http.ResponseWriter, r *http.Request) {
		handleCharacterExplosionGeneration(
			w,
			r,
			characterRepository,
			characterExplosionGenerator,
		)
	})

	apiMux.HandleFunc("GET /api/v1/character-components", func(w http.ResponseWriter, _ *http.Request) {
		dataset, err := hanziRepository.GetCharacterComponents()
		if err != nil {
			writeRepositoryError(w, err)
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"dataset": dataset,
		})
	})

	var rootHandler http.Handler = apiMux
	if cfg.WebAppRoot != "" {
		webAppHandler := newWebAppHandler(cfg.WebAppRoot)
		rootHandler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if isReservedAPIPath(r.URL.Path) || r.Method == http.MethodOptions {
				apiMux.ServeHTTP(w, r)
				return
			}

			if r.Method != http.MethodGet && r.Method != http.MethodHead {
				apiMux.ServeHTTP(w, r)
				return
			}

			webAppHandler.ServeHTTP(w, r)
		})
	}

	return withCORS(cfg.AllowedOrigins, rootHandler)
}

func withCORS(allowedOrigins []string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if origin := resolveAllowedOrigin(r.Header.Get("Origin"), allowedOrigins); origin != "" {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Vary", "Origin")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func handleBookRoute(
	w http.ResponseWriter,
	r *http.Request,
	repo books.Repository,
) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/books/")
	segments := strings.Split(strings.Trim(path, "/"), "/")

	switch {
	case len(segments) == 1 && segments[0] != "":
		book, err := repo.GetBook(segments[0])
		if err != nil {
			writeRepositoryError(w, err)
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"book": book,
		})
	case len(segments) == 3 && segments[0] != "" && segments[1] == "chapters" && segments[2] != "":
		chapter, err := repo.GetChapter(r.Context(), segments[0], segments[2])
		if err != nil {
			writeRepositoryError(w, err)
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"chapter": chapter,
		})
	default:
		writeError(w, http.StatusNotFound, "resource not found")
	}
}

func parseCharacterPath(path string) (string, []string, bool) {
	trimmedPath := strings.Trim(strings.TrimPrefix(path, "/api/v1/characters/"), "/")
	if trimmedPath == "" {
		return "", nil, false
	}

	segments := strings.Split(trimmedPath, "/")
	character, err := url.PathUnescape(segments[0])
	if err != nil {
		return "", nil, false
	}

	trimmedCharacter := strings.TrimSpace(character)
	if trimmedCharacter == "" {
		return "", nil, false
	}

	return trimmedCharacter, segments[1:], true
}

func handleCharacterExplosionGeneration(
	w http.ResponseWriter,
	r *http.Request,
	repo characters.Repository,
	generator characters.ExplosionGenerator,
) {
	character, suffix, ok := parseCharacterPath(r.URL.Path)
	if !ok || len(suffix) != 1 || suffix[0] != "explosion" {
		writeError(w, http.StatusNotFound, "resource not found")
		return
	}

	if generator == nil {
		writeError(
			w,
			http.StatusServiceUnavailable,
			"fresh character explosion generation is unavailable until GLM_API_KEY is configured",
		)
		return
	}

	var existing *characters.Entry
	entry, err := repo.GetCharacter(character)
	switch {
	case err == nil:
		existing = &entry
	case errors.Is(err, characters.ErrNotFound):
	default:
		writeRepositoryError(w, err)
		return
	}

	generatedEntry, err := generator.GenerateExplosion(r.Context(), character, existing)
	if err != nil {
		if errors.Is(err, zai.ErrNotConfigured) {
			writeError(w, http.StatusServiceUnavailable, "fresh character explosion generation is unavailable")
			return
		}
		if errors.Is(err, zai.ErrOverloaded) {
			writeError(w, http.StatusServiceUnavailable, "fresh character explosion generation is busy, try again shortly")
			return
		}

		writeError(w, http.StatusBadGateway, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"character": generatedEntry,
	})
}

func handleGuidedChat(
	w http.ResponseWriter,
	r *http.Request,
	repo books.Repository,
	model string,
	client guidedChatClient,
) {
	if client == nil {
		writeError(
			w,
			http.StatusServiceUnavailable,
			"guided reading chat is unavailable until GLM_API_KEY is configured",
		)
		return
	}

	var request guidedChatRequest
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid guided chat request body")
		return
	}

	context, err := normalizeGuidedChatContext(request.Context)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	history, err := normalizeGuidedChatHistory(request.Messages)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	previousLines := normalizeGuidedChatPreviousLines(request.PreviousLines)

	book, err := repo.GetBook(context.BookID)
	if err != nil {
		writeRepositoryError(w, err)
		return
	}

	chapter, err := repo.GetChapter(r.Context(), context.BookID, context.ChapterID)
	if err != nil {
		writeRepositoryError(w, err)
		return
	}

	var readingUnit *books.ReadingUnit
	if context.ReadingUnitID != "" {
		resolvedReadingUnit, ok := findReadingUnit(chapter.ReadingUnits, context.ReadingUnitID)
		if !ok {
			writeError(w, http.StatusNotFound, "reading unit not found")
			return
		}

		readingUnit = &resolvedReadingUnit
	}

	completionResponse, err := client.ChatCompletion(r.Context(), zai.ChatCompletionRequest{
		Model:       model,
		Temperature: 0.3,
		Messages: buildGuidedChatMessages(
			book,
			chapter,
			context,
			readingUnit,
			previousLines,
			history,
		),
	})
	if err != nil {
		if errors.Is(err, zai.ErrNotConfigured) {
			writeError(w, http.StatusServiceUnavailable, "guided reading chat is unavailable")
			return
		}
		if errors.Is(err, zai.ErrOverloaded) {
			writeError(w, http.StatusServiceUnavailable, "guided reading chat is busy, try again shortly")
			return
		}

		writeError(w, http.StatusBadGateway, err.Error())
		return
	}

	reply := completionResponse.FirstMessageContent()
	if reply == "" {
		writeError(w, http.StatusBadGateway, "guided reading chat returned an empty reply")
		return
	}

	writeJSON(w, http.StatusOK, guidedChatResponse{
		Reply: guidedChatMessage{
			Role:    "assistant",
			Content: reply,
		},
		Model:     completionResponse.Model,
		Provider:  "z.ai",
		RequestID: completionResponse.RequestID,
	})
}

func normalizeGuidedChatContext(
	rawContext guidedChatContext,
) (guidedChatContext, error) {
	context := guidedChatContext{
		BookID:             strings.TrimSpace(rawContext.BookID),
		ChapterID:          strings.TrimSpace(rawContext.ChapterID),
		ReadingUnitID:      strings.TrimSpace(rawContext.ReadingUnitID),
		OpenLine:           strings.TrimSpace(rawContext.OpenLine),
		CharacterComponent: strings.TrimSpace(rawContext.CharacterComponent),
		LearnerTranslation: strings.TrimSpace(rawContext.LearnerTranslation),
		LearnerResponse:    strings.TrimSpace(rawContext.LearnerResponse),
	}

	if context.BookID == "" {
		return guidedChatContext{}, fmt.Errorf("context.bookId is required")
	}

	if context.ChapterID == "" {
		return guidedChatContext{}, fmt.Errorf("context.chapterId is required")
	}

	return context, nil
}

func normalizeGuidedChatHistory(
	rawMessages []guidedChatMessage,
) ([]guidedChatMessage, error) {
	if len(rawMessages) == 0 {
		return nil, fmt.Errorf("messages must include at least one user message")
	}

	messages := make([]guidedChatMessage, 0, len(rawMessages))
	userMessageCount := 0
	for index, message := range rawMessages {
		role := strings.TrimSpace(message.Role)
		content := strings.TrimSpace(message.Content)
		if content == "" {
			return nil, fmt.Errorf("message %d content is required", index+1)
		}

		switch role {
		case "user":
			userMessageCount++
		case "assistant":
		default:
			return nil, fmt.Errorf("message %d role must be user or assistant", index+1)
		}

		messages = append(messages, guidedChatMessage{
			Role:    role,
			Content: content,
		})
	}

	if userMessageCount == 0 {
		return nil, fmt.Errorf("messages must include at least one user message")
	}

	if messages[len(messages)-1].Role != "user" {
		return nil, fmt.Errorf("the last guided chat message must come from the user")
	}

	return messages, nil
}

func findReadingUnit(
	readingUnits []books.ReadingUnit,
	readingUnitID string,
) (books.ReadingUnit, bool) {
	for _, readingUnit := range readingUnits {
		if readingUnit.ID == readingUnitID {
			return readingUnit, true
		}
	}

	return books.ReadingUnit{}, false
}

func normalizeGuidedChatPreviousLines(
	rawLines []guidedChatPreviousLine,
) []guidedChatPreviousLine {
	if len(rawLines) == 0 {
		return nil
	}

	lines := make([]guidedChatPreviousLine, 0, len(rawLines))
	for _, line := range rawLines {
		readingUnitID := strings.TrimSpace(line.ReadingUnitID)
		text := strings.TrimSpace(line.Text)
		if readingUnitID == "" && text == "" {
			continue
		}

		lines = append(lines, guidedChatPreviousLine{
			ReadingUnitID:      readingUnitID,
			Order:              line.Order,
			Text:               text,
			TranslationEn:      strings.TrimSpace(line.TranslationEn),
			LearnerTranslation: strings.TrimSpace(line.LearnerTranslation),
			LearnerResponse:    strings.TrimSpace(line.LearnerResponse),
		})
	}

	return lines
}

func buildGuidedChatMessages(
	book books.BookDetail,
	chapter books.ChapterDetail,
	context guidedChatContext,
	readingUnit *books.ReadingUnit,
	previousLines []guidedChatPreviousLine,
	history []guidedChatMessage,
) []zai.Message {
	messages := []zai.Message{
		{
			Role: "system",
			Content: "You are the guided-reading loop for this mobile app. " +
				"Help the learner stay with the current reading focus, remain flexible in style and pedagogy, and stay grounded in the provided text. " +
				"Use English by default, but quote Chinese text and pinyin when helpful. " +
				"Try to draw inspiration from the text and relate it to what the learner is conveying. " +
				"When the learner submits a translation or interpretation, evaluate it against the current line and prioritize fidelity to the text. " +
				"If earlier chapter lines or the learner's own earlier translations and responses are provided, use them to keep continuity without losing the current focus. " +
				"If the learner asks for something beyond the provided chapter context, say so plainly instead of inventing details.",
		},
		{
			Role: "user",
			Content: buildGuidedChatContext(
				book,
				chapter,
				context,
				readingUnit,
				previousLines,
			),
		},
	}

	for _, message := range history {
		messages = append(messages, zai.Message{
			Role:    message.Role,
			Content: message.Content,
		})
	}

	return messages
}

func buildGuidedChatContext(
	book books.BookDetail,
	chapter books.ChapterDetail,
	context guidedChatContext,
	readingUnit *books.ReadingUnit,
	previousLines []guidedChatPreviousLine,
) string {
	var builder strings.Builder
	builder.WriteString("Guided reading context\n")
	builder.WriteString("Book: ")
	builder.WriteString(book.Title)
	builder.WriteString(" (")
	builder.WriteString(book.ID)
	builder.WriteString(")\n")
	builder.WriteString("Source: ")
	builder.WriteString(book.SourceURL)
	builder.WriteString("\nChapter: ")
	chapterTitle := strings.TrimSpace(chapter.Title)
	if chapterTitle == "" {
		builder.WriteString(fmt.Sprintf("Reading %d\n", chapter.Order))
	} else {
		builder.WriteString(fmt.Sprintf("%d. %s\n", chapter.Order, chapterTitle))
	}
	if chapterSummary := strings.TrimSpace(chapter.Summary); chapterSummary != "" {
		builder.WriteString("Chapter summary: ")
		builder.WriteString(chapterSummary)
		builder.WriteString("\n")
	}
	builder.WriteString("Reading units in chapter: ")
	builder.WriteString(fmt.Sprintf("%d\n", len(chapter.ReadingUnits)))
	if readingUnit != nil {
		builder.WriteString("Current focus: line-level reading\n")
		builder.WriteString("Current reading unit: ")
		builder.WriteString(fmt.Sprintf("%d of %d\n", readingUnit.Order, len(chapter.ReadingUnits)))
		builder.WriteString("Current line id: ")
		builder.WriteString(readingUnit.ID)
		builder.WriteString("\nChinese text: ")
		builder.WriteString(readingUnit.Text)
		if context.OpenLine != "" {
			builder.WriteString("\nOpen line: ")
			builder.WriteString(context.OpenLine)
		}
		if strings.TrimSpace(readingUnit.TranslationEn) != "" {
			builder.WriteString("\nSaved English translation: ")
			builder.WriteString(readingUnit.TranslationEn)
		}
		if context.LearnerTranslation != "" {
			builder.WriteString("\nLearner translation: ")
			builder.WriteString(context.LearnerTranslation)
		}
		if context.LearnerResponse != "" {
			builder.WriteString("\nLearner response: ")
			builder.WriteString(context.LearnerResponse)
		}
	} else {
		builder.WriteString("Current focus: chapter-level discussion\n")
		if chapter.Text != "" {
			builder.WriteString("Chapter text: ")
			builder.WriteString(chapter.Text)
			builder.WriteString("\n")
		}
	}
	if context.CharacterComponent != "" {
		builder.WriteString("\nCharacter component focus: ")
		builder.WriteString(context.CharacterComponent)
		builder.WriteString(
			"\nYou are helping a learner understand how the character component functions in the language.\n",
		)
	}
	if len(previousLines) > 0 {
		if readingUnit != nil {
			builder.WriteString("\n\nPrevious chapter lines before the current one:\n")
		} else {
			builder.WriteString("\n\nRelevant lines included with the request:\n")
		}
		for _, line := range previousLines {
			builder.WriteString("- ")
			if line.Order > 0 {
				builder.WriteString(fmt.Sprintf("Line %d", line.Order))
			} else {
				builder.WriteString("Earlier line")
			}
			if line.ReadingUnitID != "" {
				builder.WriteString(" (")
				builder.WriteString(line.ReadingUnitID)
				builder.WriteString(")")
			}
			if line.Text != "" {
				builder.WriteString(": ")
				builder.WriteString(line.Text)
			}
			if line.TranslationEn != "" {
				builder.WriteString("\n  Saved English translation: ")
				builder.WriteString(line.TranslationEn)
			}
			if line.LearnerTranslation != "" {
				builder.WriteString("\n  Learner translation: ")
				builder.WriteString(line.LearnerTranslation)
			}
			if line.LearnerResponse != "" {
				builder.WriteString("\n  Learner response: ")
				builder.WriteString(line.LearnerResponse)
			}
			builder.WriteString("\n")
		}
	}
	builder.WriteString("\n\nKeep the learner moving through the text. When helpful, end with one short sentence that points them back to the current focus or the next reading step.")
	return builder.String()
}

func resolveAllowedOrigin(origin string, allowedOrigins []string) string {
	for _, allowedOrigin := range allowedOrigins {
		if allowedOrigin == "*" {
			return "*"
		}

		if origin != "" && origin == allowedOrigin {
			return origin
		}
	}

	return ""
}

func isReservedAPIPath(requestPath string) bool {
	return requestPath == "/healthz" ||
		requestPath == "/api" ||
		strings.HasPrefix(requestPath, "/api/")
}

type webAppHandler struct {
	root string
}

func newWebAppHandler(root string) http.Handler {
	return webAppHandler{root: root}
}

func (h webAppHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	cleanPath := path.Clean("/" + r.URL.Path)
	if cleanPath == "/" {
		h.serveIndex(w, r)
		return
	}

	resolvedPath := filepath.Join(h.root, filepath.FromSlash(strings.TrimPrefix(cleanPath, "/")))
	info, err := os.Stat(resolvedPath)
	if err == nil {
		if info.IsDir() {
			indexPath := filepath.Join(resolvedPath, "index.html")
			if indexInfo, indexErr := os.Stat(indexPath); indexErr == nil && !indexInfo.IsDir() {
				http.ServeFile(w, r, indexPath)
				return
			}

			http.NotFound(w, r)
			return
		}

		http.ServeFile(w, r, resolvedPath)
		return
	}

	if path.Ext(cleanPath) != "" {
		http.NotFound(w, r)
		return
	}

	h.serveIndex(w, r)
}

func (h webAppHandler) serveIndex(w http.ResponseWriter, r *http.Request) {
	http.ServeFile(w, r, filepath.Join(h.root, "index.html"))
}

func writeRepositoryError(w http.ResponseWriter, err error) {
	if errors.Is(err, books.ErrNotFound) || errors.Is(err, characters.ErrNotFound) || errors.Is(err, hanzi.ErrNotFound) {
		writeError(w, http.StatusNotFound, "resource not found")
		return
	}

	writeError(w, http.StatusInternalServerError, err.Error())
}

func writeJSON(w http.ResponseWriter, statusCode int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, statusCode int, message string) {
	writeJSON(w, statusCode, errorResponse{
		Error: message,
	})
}
