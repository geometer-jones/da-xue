package zai

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
	"time"
)

var ErrNotConfigured = errors.New("zai: missing GLM_API_KEY")
var ErrOverloaded = errors.New("zai: overloaded")

const (
	anthropicVersionHeader   = "2023-06-01"
	defaultMaxTokens         = 2048
	defaultRequestSlots      = 1
	defaultMaxQueuedRequests = 32
	defaultMaxQueueWait      = 10 * time.Second
)

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ResponseFormat struct {
	Type string `json:"type"`
}

type ChatCompletionRequest struct {
	Model          string          `json:"model"`
	Messages       []Message       `json:"messages"`
	Temperature    float64         `json:"temperature,omitempty"`
	Stream         bool            `json:"stream"`
	ResponseFormat *ResponseFormat `json:"response_format,omitempty"`
}

type ChatCompletionResponse struct {
	RequestID string                     `json:"request_id"`
	Model     string                     `json:"model"`
	Choices   []ChatCompletionChoice     `json:"choices"`
	Error     *ChatCompletionErrorDetail `json:"error,omitempty"`
}

type Client struct {
	apiKey            string
	baseURL           string
	httpClient        *http.Client
	requestSlots      chan struct{}
	maxQueuedRequests int64
	maxQueueWait      time.Duration
	queuedRequests    atomic.Int64
}

func NewClient(apiKey string, baseURL string, httpClient *http.Client) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 45 * time.Second}
	}

	return &Client{
		apiKey:            strings.TrimSpace(apiKey),
		baseURL:           strings.TrimRight(strings.TrimSpace(baseURL), "/"),
		httpClient:        httpClient,
		requestSlots:      make(chan struct{}, defaultRequestSlots),
		maxQueuedRequests: defaultMaxQueuedRequests,
		maxQueueWait:      defaultMaxQueueWait,
	}
}

func (c *Client) ChatCompletion(
	ctx context.Context,
	request ChatCompletionRequest,
) (ChatCompletionResponse, error) {
	if c.apiKey == "" {
		return ChatCompletionResponse{}, ErrNotConfigured
	}

	if c.baseURL == "" {
		return ChatCompletionResponse{}, fmt.Errorf("zai: missing base URL")
	}

	if strings.TrimSpace(request.Model) == "" {
		return ChatCompletionResponse{}, fmt.Errorf("zai: missing model")
	}

	if len(request.Messages) == 0 {
		return ChatCompletionResponse{}, fmt.Errorf("zai: missing messages")
	}

	wireRequest, err := buildAnthropicRequest(request)
	if err != nil {
		return ChatCompletionResponse{}, err
	}

	payload, err := json.Marshal(wireRequest)
	if err != nil {
		return ChatCompletionResponse{}, fmt.Errorf("zai: marshal request: %w", err)
	}

	if err := c.acquireRequestSlot(ctx); err != nil {
		return ChatCompletionResponse{}, err
	}
	defer c.releaseRequestSlot()

	httpRequest, err := http.NewRequestWithContext(
		ctx,
		http.MethodPost,
		c.baseURL+"/v1/messages",
		bytes.NewReader(payload),
	)
	if err != nil {
		return ChatCompletionResponse{}, fmt.Errorf("zai: create request: %w", err)
	}

	httpRequest.Header.Set("x-api-key", c.apiKey)
	httpRequest.Header.Set("anthropic-version", anthropicVersionHeader)
	httpRequest.Header.Set("Content-Type", "application/json")

	httpResponse, err := c.httpClient.Do(httpRequest)
	if err != nil {
		return ChatCompletionResponse{}, fmt.Errorf("zai: call messages API: %w", err)
	}
	defer httpResponse.Body.Close()

	responseBody, err := io.ReadAll(httpResponse.Body)
	if err != nil {
		return ChatCompletionResponse{}, fmt.Errorf("zai: read response: %w", err)
	}

	var response anthropicMessagesResponse
	if err := json.Unmarshal(responseBody, &response); err != nil {
		if httpResponse.StatusCode < 200 || httpResponse.StatusCode >= 300 {
			return ChatCompletionResponse{}, fmt.Errorf(
				"zai: messages API returned status %d",
				httpResponse.StatusCode,
			)
		}

		return ChatCompletionResponse{}, fmt.Errorf("zai: decode response: %w", err)
	}

	if httpResponse.StatusCode < 200 || httpResponse.StatusCode >= 300 {
		if response.Error != nil && strings.TrimSpace(response.Error.Message) != "" {
			return ChatCompletionResponse{}, fmt.Errorf("zai: %s", response.Error.Message)
		}

		return ChatCompletionResponse{}, fmt.Errorf(
			"zai: messages API returned status %d",
			httpResponse.StatusCode,
		)
	}

	requestID := strings.TrimSpace(httpResponse.Header.Get("request-id"))
	if requestID == "" {
		requestID = strings.TrimSpace(response.ID)
	}

	return ChatCompletionResponse{
		RequestID: requestID,
		Model:     response.Model,
		Choices: []ChatCompletionChoice{
			{
				Message: ChatCompletionMessage{
					Role:    "assistant",
					Content: response.textContent(),
				},
			},
		},
	}, nil
}

func (c *Client) acquireRequestSlot(ctx context.Context) error {
	if c.requestSlots == nil {
		return nil
	}

	select {
	case c.requestSlots <- struct{}{}:
		return nil
	default:
	}

	queued := c.queuedRequests.Add(1)
	if c.maxQueuedRequests > 0 && queued > c.maxQueuedRequests {
		c.queuedRequests.Add(-1)
		return fmt.Errorf("%w: queue is full", ErrOverloaded)
	}
	defer c.queuedRequests.Add(-1)

	waitCtx := ctx
	cancel := func() {}
	if c.maxQueueWait > 0 {
		waitCtx, cancel = context.WithTimeout(ctx, c.maxQueueWait)
	}
	defer cancel()

	select {
	case c.requestSlots <- struct{}{}:
		return nil
	case <-waitCtx.Done():
		if ctx.Err() != nil {
			return fmt.Errorf("zai: wait for request slot: %w", ctx.Err())
		}
		return fmt.Errorf("%w: timed out waiting for request slot", ErrOverloaded)
	}
}

func (c *Client) releaseRequestSlot() {
	if c.requestSlots == nil {
		return
	}

	<-c.requestSlots
}

func (r ChatCompletionResponse) FirstMessageContent() string {
	if len(r.Choices) == 0 {
		return ""
	}

	return strings.TrimSpace(r.Choices[0].Message.Content)
}

type ChatCompletionChoice struct {
	Message ChatCompletionMessage `json:"message"`
}

type ChatCompletionMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ChatCompletionErrorDetail struct {
	Message string `json:"message"`
}

type anthropicMessagesRequest struct {
	Model       string             `json:"model"`
	System      string             `json:"system,omitempty"`
	Messages    []anthropicMessage `json:"messages"`
	MaxTokens   int                `json:"max_tokens"`
	Temperature float64            `json:"temperature,omitempty"`
}

type anthropicMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type anthropicMessagesResponse struct {
	ID      string                     `json:"id"`
	Model   string                     `json:"model"`
	Content []anthropicContentBlock    `json:"content"`
	Error   *ChatCompletionErrorDetail `json:"error,omitempty"`
}

type anthropicContentBlock struct {
	Type string `json:"type"`
	Text string `json:"text,omitempty"`
}

func (r anthropicMessagesResponse) textContent() string {
	if len(r.Content) == 0 {
		return ""
	}

	parts := make([]string, 0, len(r.Content))
	for _, block := range r.Content {
		if block.Type != "text" {
			continue
		}

		text := strings.TrimSpace(block.Text)
		if text != "" {
			parts = append(parts, text)
		}
	}

	return strings.TrimSpace(strings.Join(parts, "\n\n"))
}

func buildAnthropicRequest(request ChatCompletionRequest) (anthropicMessagesRequest, error) {
	systemParts := make([]string, 0, len(request.Messages)+1)
	messages := make([]anthropicMessage, 0, len(request.Messages))

	for _, message := range request.Messages {
		role := strings.TrimSpace(message.Role)
		content := strings.TrimSpace(message.Content)
		if content == "" {
			continue
		}

		switch role {
		case "system":
			systemParts = append(systemParts, content)
		case "user", "assistant":
			messages = append(messages, anthropicMessage{
				Role:    role,
				Content: content,
			})
		default:
			return anthropicMessagesRequest{}, fmt.Errorf("zai: unsupported message role %q", role)
		}
	}

	if len(messages) == 0 {
		return anthropicMessagesRequest{}, fmt.Errorf("zai: missing user or assistant messages")
	}

	if request.ResponseFormat != nil && request.ResponseFormat.Type == "json_object" {
		systemParts = append(systemParts, "Return exactly one valid JSON object and no surrounding prose or markdown.")
	}

	return anthropicMessagesRequest{
		Model:       strings.TrimSpace(request.Model),
		System:      strings.Join(systemParts, "\n\n"),
		Messages:    messages,
		MaxTokens:   defaultMaxTokens,
		Temperature: request.Temperature,
	}, nil
}
