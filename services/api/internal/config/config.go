package config

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

var loadDotEnvOnce sync.Once

type Config struct {
	Port           string
	AppEnv         string
	AllowedOrigins []string
	ContentRoot    string
	WebAppRoot     string
	GLMAPIKey      string
	GLMBaseURL     string
	GLMModel       string
}

func Load() Config {
	loadDotEnv()

	return Config{
		Port:           envOrDefault("PORT", "8080"),
		AppEnv:         envOrDefault("APP_ENV", "development"),
		AllowedOrigins: splitCSV(envOrDefault("CORS_ALLOWED_ORIGINS", "*")),
		ContentRoot:    resolveContentRoot(),
		WebAppRoot:     resolveWebAppRoot(),
		GLMAPIKey:      strings.TrimSpace(os.Getenv("GLM_API_KEY")),
		GLMBaseURL:     envOrDefault("GLM_BASE_URL", "https://api.z.ai/api/anthropic"),
		GLMModel:       envOrDefault("GLM_MODEL", "glm-5-turbo"),
	}
}

func resolveContentRoot() string {
	if configuredRoot := strings.TrimSpace(os.Getenv("CONTENT_ROOT")); configuredRoot != "" {
		return expandHomePath(configuredRoot)
	}

	if workingDirectory, err := os.Getwd(); err == nil {
		candidates := []string{
			filepath.Join(workingDirectory, "content"),
			filepath.Join(workingDirectory, "..", "..", "content"),
		}

		for _, candidate := range candidates {
			if info, err := os.Stat(candidate); err == nil && info.IsDir() {
				return candidate
			}
		}
	}

	return expandHomePath("~/wokspace/da-xue/content")
}

func resolveWebAppRoot() string {
	if configuredRoot := strings.TrimSpace(os.Getenv("WEB_APP_ROOT")); configuredRoot != "" {
		root := expandHomePath(configuredRoot)
		if directoryContainsFile(root, "index.html") {
			return root
		}

		return ""
	}

	if workingDirectory, err := os.Getwd(); err == nil {
		candidates := []string{
			filepath.Join(workingDirectory, "build", "web"),
			filepath.Join(workingDirectory, "apps", "mobile", "build", "web"),
			filepath.Join(workingDirectory, "..", "..", "apps", "mobile", "build", "web"),
		}

		for _, candidate := range candidates {
			if directoryContainsFile(candidate, "index.html") {
				return candidate
			}
		}
	}

	return ""
}

func loadDotEnv() {
	loadDotEnvOnce.Do(func() {
		path, err := findDotEnvPath()
		if err != nil || path == "" {
			return
		}

		entries, err := parseDotEnv(path)
		if err != nil {
			return
		}

		for key, value := range entries {
			if existingValue, exists := os.LookupEnv(key); exists && strings.TrimSpace(existingValue) != "" {
				continue
			}

			_ = os.Setenv(key, value)
		}
	})
}

func findDotEnvPath() (string, error) {
	currentDir, err := os.Getwd()
	if err != nil {
		return "", err
	}

	for {
		candidate := filepath.Join(currentDir, ".env")
		if _, err := os.Stat(candidate); err == nil {
			return candidate, nil
		} else if !errors.Is(err, os.ErrNotExist) {
			return "", err
		}

		parentDir := filepath.Dir(currentDir)
		if parentDir == currentDir {
			return "", nil
		}

		currentDir = parentDir
	}
}

func parseDotEnv(path string) (map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	entries := make(map[string]string)
	scanner := bufio.NewScanner(file)
	for lineNumber := 1; scanner.Scan(); lineNumber++ {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		if strings.HasPrefix(line, "export ") {
			line = strings.TrimSpace(strings.TrimPrefix(line, "export "))
		}

		key, value, found := strings.Cut(line, "=")
		if !found {
			return nil, fmt.Errorf("invalid .env line %d", lineNumber)
		}

		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		if key == "" {
			return nil, fmt.Errorf("invalid .env key on line %d", lineNumber)
		}

		if len(value) >= 2 {
			if (strings.HasPrefix(value, "\"") && strings.HasSuffix(value, "\"")) ||
				(strings.HasPrefix(value, "'") && strings.HasSuffix(value, "'")) {
				value = value[1 : len(value)-1]
			}
		}

		entries[key] = value
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return entries, nil
}

func envOrDefault(key string, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	return value
}

func expandHomePath(value string) string {
	if value == "~" || strings.HasPrefix(value, "~/") {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return value
		}

		if value == "~" {
			return homeDir
		}

		return filepath.Join(homeDir, value[2:])
	}

	return value
}

func splitCSV(raw string) []string {
	parts := strings.Split(raw, ",")
	origins := make([]string, 0, len(parts))

	for _, part := range parts {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			origins = append(origins, trimmed)
		}
	}

	if len(origins) == 0 {
		return []string{"*"}
	}

	return origins
}

func directoryContainsFile(dir string, fileName string) bool {
	info, err := os.Stat(filepath.Join(dir, fileName))
	if err != nil {
		return false
	}

	return !info.IsDir()
}
