package zai

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"
)

func TestClientChatCompletion(t *testing.T) {
	var capturedRequest map[string]any

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/messages" {
			t.Fatalf("expected /v1/messages path, got %q", r.URL.Path)
		}

		if authHeader := r.Header.Get("x-api-key"); authHeader != "test-key" {
			t.Fatalf("expected x-api-key header, got %q", authHeader)
		}

		if versionHeader := r.Header.Get("anthropic-version"); versionHeader != anthropicVersionHeader {
			t.Fatalf("expected anthropic-version header %q, got %q", anthropicVersionHeader, versionHeader)
		}

		if err := json.NewDecoder(r.Body).Decode(&capturedRequest); err != nil {
			t.Fatalf("failed to decode request: %v", err)
		}

		w.Header().Set("request-id", "req_123")
		if err := json.NewEncoder(w).Encode(anthropicMessagesResponse{
			ID:    "msg_123",
			Model: "glm-5-turbo",
			Content: []anthropicContentBlock{
				{
					Type: "text",
					Text: "Helpful answer.",
				},
			},
		}); err != nil {
			t.Fatalf("failed to encode response: %v", err)
		}
	}))
	defer server.Close()

	client := NewClient("test-key", server.URL, server.Client())

	response, err := client.ChatCompletion(context.Background(), ChatCompletionRequest{
		Model: "glm-5-turbo",
		Messages: []Message{
			{Role: "system", Content: "You are a guide."},
			{Role: "user", Content: "Explain this line."},
		},
		Temperature: 0.2,
	})
	if err != nil {
		t.Fatalf("ChatCompletion returned error: %v", err)
	}

	if capturedRequest["model"] != "glm-5-turbo" {
		t.Fatalf("expected model glm-5-turbo, got %#v", capturedRequest["model"])
	}

	if capturedRequest["system"] != "You are a guide." {
		t.Fatalf("expected system prompt to be lifted to top-level field, got %#v", capturedRequest["system"])
	}

	messages, ok := capturedRequest["messages"].([]any)
	if !ok {
		t.Fatalf("expected messages array, got %#v", capturedRequest["messages"])
	}

	if len(messages) != 1 {
		t.Fatalf("expected 1 non-system message, got %d", len(messages))
	}

	if response.FirstMessageContent() != "Helpful answer." {
		t.Fatalf("unexpected first message content %q", response.FirstMessageContent())
	}

	if response.RequestID != "req_123" {
		t.Fatalf("expected request id req_123, got %q", response.RequestID)
	}
}

func TestClientChatCompletionRequiresAPIKey(t *testing.T) {
	client := NewClient("", "https://api.z.ai/api/anthropic", nil)

	_, err := client.ChatCompletion(context.Background(), ChatCompletionRequest{
		Model: "glm-5-turbo",
		Messages: []Message{
			{Role: "user", Content: "Hello"},
		},
	})
	if err != ErrNotConfigured {
		t.Fatalf("expected ErrNotConfigured, got %v", err)
	}
}

func TestClientChatCompletionSerializesConcurrentRequests(t *testing.T) {
	firstRequestStarted := make(chan struct{})
	secondRequestStarted := make(chan struct{})
	releaseFirstRequest := make(chan struct{})

	var (
		mu            sync.Mutex
		requestCount  int
		activeRequest int
		maxActive     int
	)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		requestCount++
		currentRequest := requestCount
		activeRequest++
		if activeRequest > maxActive {
			maxActive = activeRequest
		}
		mu.Unlock()

		defer func() {
			mu.Lock()
			activeRequest--
			mu.Unlock()
		}()

		if currentRequest == 1 {
			close(firstRequestStarted)
			<-releaseFirstRequest
		}
		if currentRequest == 2 {
			close(secondRequestStarted)
		}

		if err := json.NewEncoder(w).Encode(anthropicMessagesResponse{
			ID:    "msg_123",
			Model: "glm-5-turbo",
			Content: []anthropicContentBlock{
				{
					Type: "text",
					Text: "Helpful answer.",
				},
			},
		}); err != nil {
			t.Fatalf("failed to encode response: %v", err)
		}
	}))
	defer server.Close()

	client := NewClient("test-key", server.URL, server.Client())
	request := ChatCompletionRequest{
		Model: "glm-5-turbo",
		Messages: []Message{
			{Role: "user", Content: "Explain this line."},
		},
	}

	errCh := make(chan error, 2)
	go func() {
		_, err := client.ChatCompletion(context.Background(), request)
		errCh <- err
	}()

	select {
	case <-firstRequestStarted:
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for first request to reach the server")
	}

	go func() {
		_, err := client.ChatCompletion(context.Background(), request)
		errCh <- err
	}()

	select {
	case <-secondRequestStarted:
		t.Fatal("second request reached the server before the first request completed")
	case <-time.After(150 * time.Millisecond):
	}

	close(releaseFirstRequest)

	select {
	case <-secondRequestStarted:
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for second request to reach the server")
	}

	for range 2 {
		if err := <-errCh; err != nil {
			t.Fatalf("ChatCompletion returned error: %v", err)
		}
	}

	mu.Lock()
	defer mu.Unlock()

	if requestCount != 2 {
		t.Fatalf("expected 2 requests, got %d", requestCount)
	}

	if maxActive != 1 {
		t.Fatalf("expected max concurrent requests of 1, got %d", maxActive)
	}
}

func TestClientChatCompletionDropsWhenQueueIsFull(t *testing.T) {
	firstRequestStarted := make(chan struct{})
	releaseFirstRequest := make(chan struct{})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-firstRequestStarted:
		default:
			close(firstRequestStarted)
		}

		<-releaseFirstRequest

		if err := json.NewEncoder(w).Encode(anthropicMessagesResponse{
			ID:    "msg_123",
			Model: "glm-5-turbo",
			Content: []anthropicContentBlock{
				{
					Type: "text",
					Text: "Helpful answer.",
				},
			},
		}); err != nil {
			t.Fatalf("failed to encode response: %v", err)
		}
	}))
	defer server.Close()

	client := NewClient("test-key", server.URL, server.Client())
	client.maxQueuedRequests = 1

	request := ChatCompletionRequest{
		Model: "glm-5-turbo",
		Messages: []Message{
			{Role: "user", Content: "Explain this line."},
		},
	}

	firstErrCh := make(chan error, 1)
	secondErrCh := make(chan error, 1)

	go func() {
		_, err := client.ChatCompletion(context.Background(), request)
		firstErrCh <- err
	}()

	select {
	case <-firstRequestStarted:
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for first request to reach the server")
	}

	go func() {
		_, err := client.ChatCompletion(context.Background(), request)
		secondErrCh <- err
	}()

	deadline := time.After(time.Second)
	for client.queuedRequests.Load() != 1 {
		select {
		case <-deadline:
			t.Fatal("timed out waiting for second request to enter the queue")
		default:
			time.Sleep(5 * time.Millisecond)
		}
	}

	_, err := client.ChatCompletion(context.Background(), request)
	if !errors.Is(err, ErrOverloaded) {
		t.Fatalf("expected ErrOverloaded when queue is full, got %v", err)
	}

	close(releaseFirstRequest)

	if err := <-firstErrCh; err != nil {
		t.Fatalf("first request returned error: %v", err)
	}

	if err := <-secondErrCh; err != nil {
		t.Fatalf("second request returned error: %v", err)
	}
}

func TestClientChatCompletionTimesOutWhileWaitingForQueue(t *testing.T) {
	firstRequestStarted := make(chan struct{})
	releaseFirstRequest := make(chan struct{})

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-firstRequestStarted:
		default:
			close(firstRequestStarted)
		}

		<-releaseFirstRequest

		if err := json.NewEncoder(w).Encode(anthropicMessagesResponse{
			ID:    "msg_123",
			Model: "glm-5-turbo",
			Content: []anthropicContentBlock{
				{
					Type: "text",
					Text: "Helpful answer.",
				},
			},
		}); err != nil {
			t.Fatalf("failed to encode response: %v", err)
		}
	}))
	defer server.Close()

	client := NewClient("test-key", server.URL, server.Client())
	client.maxQueuedRequests = 1
	client.maxQueueWait = 50 * time.Millisecond

	request := ChatCompletionRequest{
		Model: "glm-5-turbo",
		Messages: []Message{
			{Role: "user", Content: "Explain this line."},
		},
	}

	firstErrCh := make(chan error, 1)
	go func() {
		_, err := client.ChatCompletion(context.Background(), request)
		firstErrCh <- err
	}()

	select {
	case <-firstRequestStarted:
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for first request to reach the server")
	}

	_, err := client.ChatCompletion(context.Background(), request)
	if !errors.Is(err, ErrOverloaded) {
		t.Fatalf("expected ErrOverloaded after queue wait timeout, got %v", err)
	}

	close(releaseFirstRequest)

	if err := <-firstErrCh; err != nil {
		t.Fatalf("first request returned error: %v", err)
	}
}
