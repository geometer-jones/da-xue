#!/usr/bin/env python3
"""Re-align Brewitt-Taylor translations to Chinese reading units using Claude.

For each chapter, takes the existing Brewitt-Taylor English text and the Chinese
reading units, then asks Claude to segment the English text to match each reading
unit. This preserves the Brewitt-Taylor quality while fixing alignment.
"""

import json
import os
import re
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BOOKS_ROOT = REPO_ROOT / "content" / "books"
SANGUO_DIR = BOOKS_ROOT / "sanguo-yanyi" / "chapters"

sys.path.insert(0, str(REPO_ROOT / "tools"))
from import_line_translations import (
    build_session,
    clean_ws,
    clean_translation_text,
    parse_sanguo_english_paragraphs,
    read_json,
    write_json,
    reading_units,
)


def get_client():
    """Get Anthropic client using available auth."""
    import anthropic

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    auth_token = os.environ.get("ANTHROPIC_AUTH_TOKEN")
    base_url = os.environ.get("ANTHROPIC_BASE_URL")

    if api_key:
        return anthropic.Anthropic(api_key=api_key)
    elif auth_token and base_url:
        return anthropic.Anthropic(
            auth_token=auth_token,
            base_url=base_url,
        )
    else:
        raise ValueError("No Anthropic credentials found")


def get_chapter_english_text(session, order):
    """Get the full Brewitt-Taylor English text for a chapter."""
    paragraphs = parse_sanguo_english_paragraphs(session, order)
    return " ".join(paragraphs)


def parse_json_response(text):
    """Extract JSON array from LLM response, handling various formats."""
    text = text.strip()
    # Remove markdown code fences
    if text.startswith("```"):
        text = text.split("\n", 1)[1] if "\n" in text else text[3:]
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()

    # Try direct parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Try to find JSON array in the text
    match = re.search(r"\[.*\]", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass

    return None


def align_chapter(client, model, session, order, chapter_path):
    """Use Claude to align English text with Chinese reading units."""
    document = read_json(chapter_path)
    units = reading_units(document)

    if not units:
        return 0

    # Get the Chinese reading unit texts
    chinese_units = []
    for unit in units:
        text = clean_ws(unit["text"])
        chinese_units.append(text)

    # Get Brewitt-Taylor English text
    english_text = get_chapter_english_text(session, order)
    if not english_text:
        print(f"no English text")
        return 0

    n = len(chinese_units)

    # Build prompt — include Chinese text with unit numbers
    units_text = "\n".join(
        f"[{i+1}] {text}" for i, text in enumerate(chinese_units)
    )

    prompt = f"""Segment this Brewitt-Taylor English translation of Chapter {order} of Romance of the Three Kingdoms into exactly {n} parts, one for each Chinese reading unit below.

IMPORTANT: Return exactly {n} segments. Output a JSON array of {n} strings. Nothing else.

If a Chinese reading unit is a poem line with no English equivalent (e.g. opening/closing poems), use an empty string "".

Chinese reading units ({n} total):
{units_text}

English text to segment:
{english_text}"""

    try:
        message = client.messages.create(
            model=model,
            max_tokens=16000,
            messages=[{"role": "user", "content": prompt}],
        )
        response_text = message.content[0].text.strip()

        translations = parse_json_response(response_text)

        if not isinstance(translations, list):
            print(f"non-list response")
            return 0

        if len(translations) != n:
            # Try to handle count mismatch: trim or pad
            if len(translations) > n:
                # Merge excess into last valid unit
                print(f"got {len(translations)}, expected {n} (trimming)")
                translations = translations[:n]
            else:
                # Pad with empty strings
                print(f"got {len(translations)}, expected {n} (padding)")
                translations.extend([""] * (n - len(translations)))

        # Apply translations
        changed = 0
        for unit, translation in zip(units, translations):
            translation = clean_ws(clean_translation_text(translation))
            if not translation:
                continue

            existing = clean_ws(
                (unit.get("generated_annotation") or {}).get("layers", {}).get("translation_en", "")
            )
            if translation == existing:
                continue

            gen_ann = unit.setdefault("generated_annotation", {})
            layers = gen_ann.setdefault("layers", {})
            layers["translation_en"] = translation
            changed += 1

        if changed:
            write_json(chapter_path, document)

        return changed

    except Exception as e:
        print(f"error: {e}")
        return 0


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=int, default=1, help="First chapter")
    parser.add_argument("--end", type=int, default=120, help="Last chapter")
    parser.add_argument("--model", default="claude-haiku-4-5-20251001", help="Model to use")
    args = parser.parse_args()

    client = get_client()
    session = build_session()

    total_changed = 0
    total_chapters = 0

    for order in range(args.start, args.end + 1):
        chapter_path = SANGUO_DIR / f"chapter-{order:03d}.json"
        if not chapter_path.exists():
            print(f"Ch{order}: not found")
            continue

        print(f"Ch{order}...", end=" ", flush=True)
        changed = align_chapter(client, args.model, session, order, chapter_path)
        print(f"{changed} updated")

        total_changed += changed
        if changed:
            total_chapters += 1

        # Rate limiting
        time.sleep(1)

    print(f"\nTotal: {total_changed} units updated across {total_chapters} chapters")


if __name__ == "__main__":
    main()
