#!/usr/bin/env python3
"""Fix Sanguo Yanyi English translation alignment.

The Brewitt-Taylor translation does not include the Chinese poems.
The previous alignment incorrectly assigned English text to poem/closing lines,
causing systematic misalignment. This script:

1. Fetches Brewitt-Taylor English paragraphs from Wikisource
2. Identifies poem/closing/formula reading units via block detection
3. Clears their translations
4. Re-distributes English text only to prose units via DP length matching
"""

import json
import re
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BOOKS_ROOT = REPO_ROOT / "content" / "books"
SANGUO_DIR = BOOKS_ROOT / "sanguo-yanyi" / "chapters"

sys.path.insert(0, str(REPO_ROOT / "tools"))
from import_line_translations import (
    assign_english_paragraphs_by_length,
    build_session,
    clean_translation_text,
    clean_ws,
    parse_sanguo_english_paragraphs,
    read_json,
    write_json,
    reading_units,
)

PUNCT = r"[，。、；：！？\"\"''「」『』（）\s…—\-·]"


def is_list_item(text: str) -> bool:
    """Check if text is a numbered list item like 第X鎮."""
    return bool(re.match(r"第[一二三四五六七八九十百千]+[鎮路]", text))


def identify_poem_units(units: list[dict]) -> set[int]:
    """Identify poem/formula units by finding blocks of consecutive short lines.

    Key insight: poems in Sanguo Yanyi appear as 2+ consecutive short lines
    (14-22 chars). Isolated short lines between long lines are short prose.
    """
    poem_indices: set[int] = set()
    i = 0
    while i < len(units):
        text = units[i]["text"]
        clean_len = len(re.sub(PUNCT, "", text))

        # Skip list items (numbered warlords, generals, etc.)
        if is_list_item(text):
            i += 1
            continue

        if clean_len <= 22:
            block_start = i
            while i < len(units):
                t = units[i]["text"]
                # Break block at list items
                if is_list_item(t):
                    break
                cl = len(re.sub(PUNCT, "", t))
                if cl <= 22:
                    i += 1
                else:
                    break
            block_end = i
            block_size = block_end - block_start

            if block_size >= 2:
                # Block of 2+ consecutive short lines = poem block
                for j in range(block_start, block_end):
                    poem_indices.add(j)
            else:
                # Isolated short line - only flag if it's a closing formula
                line = units[block_start]["text"]
                if re.search(r"畢竟.*且聽", line):
                    poem_indices.add(block_start)
                elif re.search(r"未知.*且聽", line):
                    poem_indices.add(block_start)
                elif re.search(r"不知.*且聽", line):
                    poem_indices.add(block_start)
                elif re.search(r"欲知.*且聽", line):
                    poem_indices.add(block_start)
        else:
            i += 1

    return poem_indices


def reassign_chapter_translations(session, chapter_path: Path) -> int:
    """Re-align English translations for a single chapter."""
    document = read_json(chapter_path)
    chapter = document["chapter"]
    order = chapter["order"]
    units = reading_units(document)

    if not units:
        return 0

    # Get Brewitt-Taylor English paragraphs
    english_paragraphs = parse_sanguo_english_paragraphs(session, order)
    if not english_paragraphs:
        print(f"  Ch{order}: no English text available")
        return 0

    # Identify poem/formula units
    poem_indices = identify_poem_units(units)

    prose_units = [u for i, u in enumerate(units) if i not in poem_indices]

    print(
        f"  Ch{order}: {len(units)} units, "
        f"{len(poem_indices)} poems, "
        f"{len(prose_units)} prose, "
        f"{len(english_paragraphs)} EN paragraphs"
    )

    # Align English only to prose units
    if prose_units and english_paragraphs:
        prose_assignments = assign_english_paragraphs_by_length(
            prose_units,
            english_paragraphs,
        )
    else:
        prose_assignments = {}

    # Apply translations
    changed = 0
    for i, unit in enumerate(units):
        gen_ann = unit.setdefault("generated_annotation", {})
        layers = gen_ann.setdefault("layers", {})

        if i in poem_indices:
            # Clear poem line translations
            existing = layers.get("translation_en", "")
            if existing:
                layers["translation_en"] = ""
                changed += 1
        else:
            uid = unit["id"]
            new_translation = prose_assignments.get(uid, "")
            if new_translation:
                new_translation = clean_ws(clean_translation_text(new_translation))
                existing = clean_ws(layers.get("translation_en", ""))
                if new_translation != existing:
                    layers["translation_en"] = new_translation
                    changed += 1

    if changed:
        write_json(chapter_path, document)

    return changed


def main():
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start", type=int, default=1, help="First chapter")
    parser.add_argument("--end", type=int, default=120, help="Last chapter")
    parser.add_argument(
        "--dry-run", action="store_true", help="Show what would change without writing"
    )
    args = parser.parse_args()

    session = build_session()
    total_changed = 0
    total_chapters = 0

    for order in range(args.start, args.end + 1):
        chapter_path = SANGUO_DIR / f"chapter-{order:03d}.json"
        if not chapter_path.exists():
            continue

        print(f"Ch{order}...", end="", flush=True)
        try:
            changed = reassign_chapter_translations(session, chapter_path)
            print(f" {changed} updated")
            total_changed += changed
            if changed:
                total_chapters += 1
        except Exception as e:
            print(f" error: {e}")

        # Rate limiting for Wikisource
        time.sleep(0.5)

    print(f"\nTotal: {total_changed} units updated across {total_chapters} chapters")


if __name__ == "__main__":
    main()
