#!/usr/bin/env python3

"""Enrich antonyms for character index entries using GLM batch API calls."""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_BASE_URL = "https://api.z.ai/api/anthropic"
DEFAULT_MODEL = "GLM-5.1"
ANTHROPIC_VERSION = "2023-06-01"
DEFAULT_MAX_TOKENS = 8192
BATCH_SIZE = 40


def load_index(path: Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return payload.get("entries", [])


def write_index(path: Path, entries: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"entries": entries}
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def is_cjk_character(char: str) -> bool:
    if len(char) != 1:
        return False
    codepoint = ord(char)
    return any(
        start <= codepoint <= end
        for start, end in (
            (0x3400, 0x4DBF),
            (0x4E00, 0x9FFF),
            (0xF900, 0xFAFF),
            (0x20000, 0x2A6DF),
            (0x2A700, 0x2B73F),
            (0x2B740, 0x2B81F),
            (0x2B820, 0x2CEAF),
            (0x2CEB0, 0x2EBEF),
            (0x30000, 0x3134F),
        )
    )


def build_character_set(entries: list[dict]) -> set[str]:
    chars: set[str] = set()
    for entry in entries:
        for key in ("character", "simplified", "traditional"):
            val = entry.get(key, "")
            if val:
                chars.add(val)
        for alias in entry.get("aliases", []):
            if alias:
                chars.add(alias)
    return chars


def build_batch_prompt(batch: list[dict], valid_chars: set[str]) -> str:
    rows = []
    for entry in batch:
        rows.append({
            "character": entry["character"],
            "simplified": entry.get("simplified", ""),
            "traditional": entry.get("traditional", ""),
            "english": entry.get("english", []),
        })
    return (
        "You are building antonym relationships for a Chinese character learning index. "
        "For each character below, return a JSON object with key \"results\" containing one object per row in the same order. "
        "Each object has \"character\" (string) and \"antonyms\" (array of 1-5 Chinese character strings). "
        "Rules:\n"
        "- Only include characters that are genuine antonyms or semantic opposites of the given character.\n"
        "- Prefer common characters over rare ones.\n"
        "- Each antonym must be exactly one Chinese character.\n"
        "- If a character has no clear antonym, return an empty array.\n"
        "- Do not include markdown or commentary.\n"
        f"- Only use characters from this valid set (partial): {json.dumps(sorted(c for c in valid_chars if len(c) == 1 and is_cjk_character(c) and ord(c) <= 0x9FFF)[:2000], ensure_ascii=False)}\n"
        f"Rows: {json.dumps(rows, ensure_ascii=False)}"
    )


def extract_json_object(raw: str) -> str:
    trimmed = raw.strip()
    if not trimmed:
        return trimmed
    if trimmed.startswith("```"):
        trimmed = re.sub(r"^```(?:json|JSON)?\s*", "", trimmed)
        trimmed = re.sub(r"\s*```$", "", trimmed)
        trimmed = trimmed.strip()
    start = trimmed.find("{")
    end = trimmed.rfind("}")
    if start >= 0 and end >= start:
        return trimmed[start : end + 1]
    return trimmed


def request_batch(api_key: str, base_url: str, model: str, batch: list[dict], valid_chars: set[str]) -> list[dict]:
    payload = {
        "model": model,
        "system": (
            "You are a Chinese language expert building antonym relationships for a character learning tool. "
            "Return strict JSON only. Each antonym must be a single Chinese character that is a genuine opposite."
        ),
        "messages": [
            {
                "role": "user",
                "content": build_batch_prompt(batch, valid_chars),
            },
        ],
        "max_tokens": DEFAULT_MAX_TOKENS,
        "temperature": 0.1,
    }

    request = urllib.request.Request(
        url=base_url.rstrip("/") + "/v1/messages",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={
            "x-api-key": api_key,
            "anthropic-version": ANTHROPIC_VERSION,
            "Content-Type": "application/json",
        },
        method="POST",
    )

    response_body = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                response_body = response.read().decode("utf-8")
            break
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            print(f"  HTTP {exc.code} on attempt {attempt + 1}: {body[:200]}", file=sys.stderr)
            if attempt == 2:
                raise RuntimeError(f"API request failed with HTTP {exc.code}: {body}") from exc
            time.sleep(2 ** attempt)
        except (urllib.error.URLError, TimeoutError) as exc:
            print(f"  Network error on attempt {attempt + 1}: {exc}", file=sys.stderr)
            if attempt == 2:
                raise RuntimeError(f"API request failed: {exc}") from exc
            time.sleep(2 ** attempt)

    if response_body is None:
        raise RuntimeError("API request failed without a response body")

    # Sanitize control characters that break JSON parsing
    response_body = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", response_body)

    envelope = json.loads(response_body)
    content_blocks = envelope.get("content", [])
    content = "\n\n".join(
        block.get("text", "").strip()
        for block in content_blocks
        if isinstance(block, dict) and block.get("type") == "text" and block.get("text", "").strip()
    ).strip()
    if not content:
        raise RuntimeError("API response did not contain message content")

    json_text = extract_json_object(content)
    json_text = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", json_text)
    decoded = json.loads(json_text)
    results = decoded.get("results")
    if not isinstance(results, list):
        raise RuntimeError("API response did not contain a results array")
    if len(results) != len(batch):
        raise RuntimeError(f"API returned {len(results)} results for {len(batch)} inputs")

    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0, help="Max entries to process")
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    index_path = repo_root / "content" / "references" / "characters" / "index.json"

    api_key = os.environ.get("GLM_API_KEY", "").strip()
    if not api_key:
        api_key = os.environ.get("ANTHROPIC_AUTH_TOKEN", "").strip()
    if not api_key:
        print("Error: GLM_API_KEY or ANTHROPIC_AUTH_TOKEN must be set", file=sys.stderr)
        return 1

    base_url = os.environ.get("GLM_BASE_URL", os.environ.get("ANTHROPIC_BASE_URL", DEFAULT_BASE_URL)).strip()
    model = os.environ.get("GLM_MODEL", DEFAULT_MODEL).strip()

    entries = load_index(index_path)
    valid_chars = build_character_set(entries)
    print(f"Loaded {len(entries)} entries, {len(valid_chars)} valid character forms", flush=True)

    # Find entries with empty antonyms
    missing = []
    for entry in entries:
        antonyms = entry.get("explosion", {}).get("meaningMap", {}).get("antonyms", [])
        if not antonyms:
            missing.append(entry)

    print(f"Entries with empty antonyms: {len(missing)}", flush=True)

    # Sort: prioritize common characters with book usage and semantic content
    def entry_priority(entry: dict) -> tuple:
        has_phrase = bool(entry.get("explosion", {}).get("synthesis", {}).get("phraseUse"))
        is_basic = 0x4E00 <= ord(entry.get("character", "\x00")) <= 0x9FFF
        english_len = len(entry.get("english", []))
        has_synonyms = bool(entry.get("explosion", {}).get("meaningMap", {}).get("synonyms"))
        return (
            0 if has_phrase else 1,
            0 if is_basic else 1,
            0 if has_synonyms else 1,
            -english_len,
            entry.get("character", ""),
        )

    missing.sort(key=entry_priority)

    if args.limit:
        missing = missing[:args.limit]

    if not missing:
        print("Nothing to do.", flush=True)
        return 0

    # Build lookup for merging
    entry_by_char: dict[str, dict] = {}
    for entry in entries:
        entry_by_char[entry["character"]] = entry

    total_filled = 0
    batch_size = args.batch_size
    total_batches = (len(missing) + batch_size - 1) // batch_size
    checkpoint_interval = 20  # write index every N batches

    for batch_idx in range(total_batches):
        start = batch_idx * batch_size
        batch = missing[start : start + batch_size]
        batch_label = f"[{start + 1}-{min(start + len(batch), len(missing))}/{len(missing)}]"

        try:
            results = request_batch(api_key, base_url, model, batch, valid_chars)
        except Exception as exc:
            print(f"  {batch_label} FAILED: {exc}", file=sys.stderr, flush=True)
            continue

        batch_filled = 0
        for result in results:
            char = result.get("character", "")
            raw_antonyms = result.get("antonyms", [])
            if not isinstance(raw_antonyms, list):
                continue

            # Filter: only keep valid CJK characters that exist in the index
            filtered = []
            for a in raw_antonyms:
                a = str(a).strip()
                if not a or not is_cjk_character(a) or a == char:
                    continue
                if a in valid_chars:
                    filtered.append(a)

            if filtered:
                entry = entry_by_char.get(char)
                if entry is not None:
                    existing = entry.get("explosion", {}).get("meaningMap", {}).get("antonyms", [])
                    merged = list(dict.fromkeys(filtered + existing))[:5]
                    if "explosion" not in entry:
                        entry["explosion"] = {}
                    if "meaningMap" not in entry["explosion"]:
                        entry["explosion"]["meaningMap"] = {}
                    entry["explosion"]["meaningMap"]["antonyms"] = merged
                    batch_filled += 1

        total_filled += batch_filled
        print(f"  {batch_label} filled {batch_filled}/{len(batch)}", flush=True)

        # Checkpoint every N batches
        if (batch_idx + 1) % checkpoint_interval == 0:
            write_index(index_path, entries)
            still_missing = sum(1 for e in entries if not e.get("explosion", {}).get("meaningMap", {}).get("antonyms"))
            print(f"  === Checkpoint: {total_filled} filled, {still_missing} remaining ===", flush=True)

    print(f"\nTotal filled: {total_filled}/{len(missing)}", flush=True)

    write_index(index_path, entries)

    # Final count
    still_missing = sum(
        1 for e in entries if not e.get("explosion", {}).get("meaningMap", {}).get("antonyms")
    )
    print(f"Remaining with empty antonyms: {still_missing}/{len(entries)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
