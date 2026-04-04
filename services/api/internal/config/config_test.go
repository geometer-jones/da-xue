package config

import (
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestLoadReadsDotEnvFromParentDirectories(t *testing.T) {
	originalWorkingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get working directory: %v", err)
	}
	defer func() {
		if chdirErr := os.Chdir(originalWorkingDir); chdirErr != nil {
			t.Fatalf("failed to restore working directory: %v", chdirErr)
		}
	}()

	tempRoot := t.TempDir()
	nestedDir := filepath.Join(tempRoot, "services", "api")
	if err := os.MkdirAll(nestedDir, 0o755); err != nil {
		t.Fatalf("failed to create nested directory: %v", err)
	}

	dotEnv := "GLM_API_KEY=test-key\nGLM_BASE_URL=https://example.z.ai/api/anthropic\nGLM_MODEL=glm-test\n"
	if err := os.WriteFile(filepath.Join(tempRoot, ".env"), []byte(dotEnv), 0o644); err != nil {
		t.Fatalf("failed to write .env file: %v", err)
	}

	if err := os.Chdir(nestedDir); err != nil {
		t.Fatalf("failed to change working directory: %v", err)
	}

	t.Setenv("GLM_API_KEY", "")
	t.Setenv("GLM_BASE_URL", "")
	t.Setenv("GLM_MODEL", "")

	loadDotEnvOnce = sync.Once{}
	cfg := Load()

	if cfg.GLMAPIKey != "test-key" {
		t.Fatalf("expected GLM API key from .env, got %q", cfg.GLMAPIKey)
	}

	if cfg.GLMBaseURL != "https://example.z.ai/api/anthropic" {
		t.Fatalf("expected GLM base URL from .env, got %q", cfg.GLMBaseURL)
	}

	if cfg.GLMModel != "glm-test" {
		t.Fatalf("expected GLM model from .env, got %q", cfg.GLMModel)
	}
}

func TestLoadReadsWebAppRootFromDotEnvWhenBundleExists(t *testing.T) {
	originalWorkingDir, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get working directory: %v", err)
	}
	defer func() {
		if chdirErr := os.Chdir(originalWorkingDir); chdirErr != nil {
			t.Fatalf("failed to restore working directory: %v", chdirErr)
		}
	}()

	tempRoot := t.TempDir()
	nestedDir := filepath.Join(tempRoot, "services", "api")
	webRoot := filepath.Join(tempRoot, "apps", "mobile", "build", "web")
	if err := os.MkdirAll(nestedDir, 0o755); err != nil {
		t.Fatalf("failed to create nested directory: %v", err)
	}
	if err := os.MkdirAll(webRoot, 0o755); err != nil {
		t.Fatalf("failed to create web build directory: %v", err)
	}
	if err := os.WriteFile(filepath.Join(webRoot, "index.html"), []byte("web"), 0o644); err != nil {
		t.Fatalf("failed to write index.html: %v", err)
	}

	dotEnv := "WEB_APP_ROOT=" + webRoot + "\n"
	if err := os.WriteFile(filepath.Join(tempRoot, ".env"), []byte(dotEnv), 0o644); err != nil {
		t.Fatalf("failed to write .env file: %v", err)
	}

	if err := os.Chdir(nestedDir); err != nil {
		t.Fatalf("failed to change working directory: %v", err)
	}

	t.Setenv("WEB_APP_ROOT", "")

	loadDotEnvOnce = sync.Once{}
	cfg := Load()

	if cfg.WebAppRoot != webRoot {
		t.Fatalf("expected web app root %q, got %q", webRoot, cfg.WebAppRoot)
	}
}
