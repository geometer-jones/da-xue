# Da Xue

Da Xue is a curriculum-first mobile reading app for classical Chinese study.

This repository ships a Flutter reader backed by a Go API that serves bundled text, reading units, and Hanzi reference data from local files.

Today, this repo is focused on a concrete study loop:

- open a book from the current curriculum spine
- move chapter by chapter through prepackaged reading units
- keep English support close to the active line
- ask guided questions tied to the exact reading unit you are on
- cross-check character and component reference data without leaving the app

## Approach

The app is built around a few explicit ideas:

- the content lives in `content/` as bundled JSON catalogs and chapter payloads
- the Go API turns that local data into app-friendly JSON endpoints
- the Flutter app provides the library, chapter reader, guided discussion, and Hanzi reference views
- study starts from canonical texts and a fixed curriculum spine rather than ad hoc phrase packs
- reading stays continuous, with questions and translation drafts tied to the active line

## Current Product Shape

- Guided reading library for the current curriculum spine
- Chapter reader with per-line progression
- Stored English line translations when available, with optional model-generated fallback for missing lines
- Guided discussion loop anchored to the active reading unit
- Character components reference browser from the bundled Hanzi dataset

The current library includes:

- `Da Xue`
- `Zhong Yong`
- `Lunyu`
- `Mengzi`
- `Sunzi Bingfa`
- `Daodejing`
- `San Zi Jing`
- `Qian Zi Wen`
- `Sanguo Yanyi`
- `Chengyu Catalog`

## Repository Layout

```text
.
|-- apps/
|   `-- mobile/
|       |-- lib/
|       |   |-- main.dart
|       |   `-- src/
|       |       |-- app.dart
|       |       |-- backend_client.dart
|       |       `-- title_translations.dart
|       `-- test/
|           `-- widget_test.dart
|-- content/
|   |-- books/
|   `-- references/
|-- services/
|   `-- api/
|       |-- cmd/
|       |   |-- server/
|       |   `-- backfill-translations/
|       `-- internal/
|           |-- books/
|           |-- characters/
|           |-- config/
|           |-- hanzi/
|           |-- httpapi/
|           |-- translation/
|           `-- zai/
`-- tools/
    `-- generate_character_index.py
```

## Architecture Summary

- System purpose: ship a curriculum-first mobile reading app backed by a local-content API.
- Primary languages: Dart for the app, Go for the API, JSON for bundled curriculum/reference data, plus a small Python helper under `tools/`.
- Entry points:
  - `apps/mobile/lib/main.dart`
  - `services/api/cmd/server/main.go`
- Key modules:
  - `apps/mobile/lib/src/app.dart`: library, chapter reader, guided discussion, and reference UI
  - `apps/mobile/lib/src/backend_client.dart`: API client and shared response models
  - `services/api/internal/books`: filesystem-backed book catalog and chapter loading, plus translation backfill support
  - `services/api/internal/characters`: bundled character index access
  - `services/api/internal/hanzi`: grouped component dataset access
  - `services/api/internal/httpapi`: JSON endpoints and route handling
  - `services/api/internal/config`: environment loading and content-root resolution
- Data flow:
  - the Flutter app calls the Go API over HTTP
  - the Go API reads bundled book and reference JSON from `content/`
  - chapter payloads are normalized into API responses for the app
  - optional GLM/z.ai calls fill missing English line translations and power guided reading chat replies
- Where app-oriented product changes usually belong:
  - learner-facing interaction changes belong in `apps/mobile`
  - content and serving changes belong in `services/api` and `content/`

## Dependency And Build Systems

- Flutter uses `pubspec.yaml`
- Go uses `services/api/go.mod`
- The mobile app builds and runs with the Flutter toolchain
- The API builds and runs with standard Go commands

## API Surface

The app currently talks to these backend routes:

- `GET /api/v1/books`
- `GET /api/v1/books/:bookId`
- `GET /api/v1/books/:bookId/chapters/:chapterId`
- `POST /api/v1/guided-chat`
- `GET /api/v1/characters`
- `GET /api/v1/characters/:character`
- `GET /api/v1/character-components`
- `GET /api/v1/health`

## Local Development

### Requirements

- Flutter SDK
- Go 1.25+
- Optional: a z.ai / GLM API key for guided chat and translation backfill

### Start the API

```bash
cd services/api
go run ./cmd/server
```

The API loads `.env` automatically from `services/api`, the repo root, or a parent directory before reading process env.

By default the API uses the vendored `content/` directory in this repository. If you want to point the app at a different local content checkout, set:

```bash
CONTENT_ROOT=/absolute/path/to/content-root go run ./cmd/server
```

### Start the Flutter app

```bash
cd apps/mobile
flutter run
```

Override the API base URL when needed:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

For the Android emulator, use `http://10.0.2.2:8080` instead of `127.0.0.1`.

### Serve the Flutter app through the backend

Build the Flutter web bundle:

```bash
cd apps/mobile
flutter build web
```

Then start the API:

```bash
cd services/api
go run ./cmd/server
```

If `apps/mobile/build/web` exists, the API auto-detects it and serves the web app from `/` while keeping the JSON API under `/api/v1/*`.

You can also point the server at a specific web build directory:

```bash
WEB_APP_ROOT=/absolute/path/to/apps/mobile/build/web go run ./cmd/server
```

## Environment Configuration

A sample env file lives at `.env.example`.

Optional GLM / z.ai settings:

```bash
GLM_API_KEY=your_api_key
GLM_BASE_URL=https://api.z.ai/api/anthropic
GLM_MODEL=glm-5-turbo
```

The API client talks to Z.AI through the Anthropic-compatible Messages API at `https://api.z.ai/api/anthropic/v1/messages`.

When `GLM_API_KEY` is configured:

- chapter responses can fill missing `translation_en` values on demand
- the guided reading chat endpoint becomes available

Stored translations in the bundled chapter files stay the source of truth. Generated translations only fill gaps where a reading unit does not already have English.

## Character Index

The bundled character index lives at `content/references/characters/index.json`.

The generator also reads `content/references/characters/manual-seed.json` for a small number of curated corpus characters that public deterministic datasets do not gloss completely.

- `GET /api/v1/characters` returns the full index payload
- `GET /api/v1/characters/:character` returns one character entry

Each character entry includes:

- simplified and traditional forms
- optional aliases for additional in-corpus variant forms
- the `traditional` field prefers the strongest curriculum-facing variant when multiple traditional forms map to one simplified form
- pinyin and zhuyin
- English senses
- a structured `explosion` object aligned with the app's explode-char turn shape:
  - `analysis`
  - `synthesis`
    - `containingCharacters`
    - `phraseUse`
    - `homophones`
  - `meaningMap`
    - `synonyms`
    - `antonyms`

To regenerate the index from the bundled books plus upstream reference datasets:

```bash
python3 tools/generate_character_index.py
```

## Translation Backfill

To persist missing English translations into chapter files:

```bash
cd services/api
GLM_MODEL=glm-5.1 go run ./cmd/backfill-translations
```

Limit the backfill to one book or chapter when needed:

```bash
cd services/api
GLM_MODEL=glm-5.1 go run ./cmd/backfill-translations -book lunyu -chapter chapter-001
```

## Tests

Test coverage lives in:

- `apps/mobile/test`
- `services/api/internal/.../*_test.go`

Useful verification commands:

```bash
cd services/api && go test ./...
cd apps/mobile && flutter analyze && flutter test
```
