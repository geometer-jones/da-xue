#!/usr/bin/env python3
"""Expand the bundled chengyu catalog to a fixed target size.

The existing catalog preserves a hand-curated pedagogy-first ordering for the
first 1,000 four-character chengyu. This tool keeps that prefix intact, then
selects additional four-character idioms from the upstream chinese-xinhua list
using a pedagogical heuristic grounded in this repository's curriculum.
"""

from __future__ import annotations

import argparse
import collections
import json
import math
from pathlib import Path
from typing import Any
from urllib.request import urlopen


REPO_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = REPO_ROOT / "content" / "books" / "chengyu-catalog" / "catalog.json"
CHAPTERS_DIR = CATALOG_PATH.parent / "chapters"
UPSTREAM_IDIOM_URL = (
    "https://raw.githubusercontent.com/pwxcoo/chinese-xinhua/master/data/idiom.json"
)
TARGET_TOTAL_DEFAULT = 3000
CHAPTER_SIZE = 30
CURRENT_PEDAGOGICAL_PREFIX = 1000
LOW_SIGNAL_CHARS = {
    "之",
    "不",
    "一",
    "人",
    "而",
    "也",
    "有",
    "為",
    "为",
    "以",
    "其",
    "言",
    "所",
    "於",
    "于",
    "者",
    "子",
    "大",
    "天",
    "上",
    "下",
    "可",
    "无",
    "無",
    "來",
    "来",
    "見",
    "见",
    "同",
    "自",
    "日",
    "月",
}
DEFINITIONAL_PREFIXES = (
    "比喻",
    "形容",
    "指",
    "原指",
    "泛指",
    "多指",
    "现多比喻",
)
OPAQUE_EXPLANATION_MARKERS = (
    "典故",
    "古代",
    "讥讽",
    "讽刺",
    "旧时",
    "旧称",
)
VARIANT_EXPLANATION_MARKERS = (
    "亦作",
    "亦称",
    "又作",
    "又称",
)
EXPLANATION_TRIM_CHARS = " \t\r\n，。；：、,.!?！？;:\"'“”‘’()（）[]{}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target-total",
        type=int,
        default=TARGET_TOTAL_DEFAULT,
        help="Desired total number of bundled chengyu entries.",
    )
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def load_catalog() -> dict[str, Any]:
    return read_json(CATALOG_PATH)


def load_chapter_payload(path: Path) -> dict[str, Any]:
    return read_json(path)


def chapter_path_for(order: int) -> Path:
    return CHAPTERS_DIR / f"chapter-{order:03d}.json"


def catalog_path_for(order: int) -> str:
    return f"books/chengyu-catalog/chapters/chapter-{order:03d}.json"


def load_existing_words() -> list[str]:
    words: list[str] = []
    for chapter_path in sorted(CHAPTERS_DIR.glob("chapter-*.json")):
        payload = load_chapter_payload(chapter_path)
        words.extend(unit["text"] for unit in payload["chapter"]["reading_units"])
    return words


def fetch_upstream_four_character_rows() -> list[dict[str, Any]]:
    with urlopen(UPSTREAM_IDIOM_URL, timeout=60) as response:
        rows = json.load(response)

    seen: set[str] = set()
    idioms: list[dict[str, Any]] = []
    for row in rows:
        word = str(row.get("word", "")).strip()
        if len(word) != 4 or word in seen:
            continue
        seen.add(word)
        idioms.append(
            {
                "word": word,
                "explanation": str(row.get("explanation", "")).strip(),
                "derivation": str(row.get("derivation", "")).strip(),
            }
        )
    return idioms


def load_curriculum_character_counts() -> collections.Counter[str]:
    counts: collections.Counter[str] = collections.Counter()
    for chapter_path in sorted((REPO_ROOT / "content" / "books").glob("*/chapters/*.json")):
        if "chengyu-catalog" in str(chapter_path):
            continue
        payload = load_chapter_payload(chapter_path)
        for unit in payload["chapter"]["reading_units"]:
            counts.update(ch for ch in unit["text"] if "\u4e00" <= ch <= "\u9fff")
    return counts


def load_current_chengyu_character_counts() -> collections.Counter[str]:
    counts: collections.Counter[str] = collections.Counter()
    for chapter_path in sorted(CHAPTERS_DIR.glob("chapter-*.json")):
        payload = load_chapter_payload(chapter_path)
        for unit in payload["chapter"]["reading_units"]:
            counts.update(unit["text"])
    return counts


def normalize_explanation(text: str) -> str:
    return "".join(ch for ch in text.strip() if ch not in EXPLANATION_TRIM_CHARS)


def character_signature(word: str) -> str:
    return "".join(sorted(word))


def score_candidate(
    row: dict[str, Any],
    *,
    index: int,
    current_char_counts: collections.Counter[str],
    curriculum_char_counts: collections.Counter[str],
) -> tuple[float, int, int, int, int, int]:
    word = row["word"]
    explanation = str(row.get("explanation", "")).strip()
    derivation = str(row.get("derivation", "")).strip()

    useful_chars = [ch for ch in word if ch not in LOW_SIGNAL_CHARS]
    useful_curriculum = sum(math.log1p(curriculum_char_counts[ch]) for ch in useful_chars)
    useful_bridge = sum(math.log1p(current_char_counts[ch]) for ch in useful_chars)
    known_chars = sum(
        1 for ch in word if ch in current_char_counts or ch in curriculum_char_counts
    )
    new_chars = sum(
        1 for ch in word if ch not in current_char_counts and ch not in curriculum_char_counts
    )
    concise_bonus = -(len(explanation) * 0.03 + len(derivation) * 0.008)
    definitional_bonus = int(explanation.startswith(DEFINITIONAL_PREFIXES))
    source_heavy_penalty = int(
        any(marker in explanation for marker in OPAQUE_EXPLANATION_MARKERS)
    ) + int("《" in derivation or "·" in derivation)
    variant_penalty = int(explanation.startswith("犹")) + int(
        any(marker in explanation for marker in VARIANT_EXPLANATION_MARKERS)
    )
    if "同" in explanation and "”" in explanation:
        variant_penalty += 1
    repeated_chars = len(set(word) & set(current_char_counts))
    transparent_chars = len({ch for ch in word if ch in explanation})

    total = (
        useful_curriculum * 2.2
        + useful_bridge * 2.0
        + known_chars * 1.0
        + repeated_chars * 0.8
        + transparent_chars * 1.2
        + definitional_bonus * 1.5
        + concise_bonus
        - new_chars * 2.5
        - source_heavy_penalty * 1.6
        - variant_penalty * 1.8
    )

    return (
        total,
        known_chars,
        repeated_chars,
        definitional_bonus,
        -(len(explanation) + len(derivation)),
        -index,
    )


def select_additional_words(
    *,
    existing_words: list[str],
    target_total: int,
    upstream_rows: list[dict[str, Any]],
    current_char_counts: collections.Counter[str],
    curriculum_char_counts: collections.Counter[str],
) -> list[str]:
    needed = target_total - len(existing_words)
    if needed <= 0:
        return []

    existing_set = set(existing_words)
    scored_rows: list[tuple[tuple[float, int, int, int, int, int], dict[str, Any]]] = []
    for index, row in enumerate(upstream_rows):
        word = row["word"]
        if word in existing_set:
            continue
        scored_rows.append(
            (
                score_candidate(
                    row,
                    index=index,
                    current_char_counts=current_char_counts,
                    curriculum_char_counts=curriculum_char_counts,
                ),
                row,
            )
        )
    scored_rows.sort(key=lambda item: item[0], reverse=True)

    selected_words: list[str] = []
    selected_set: set[str] = set()
    seen_signatures: set[str] = set()
    seen_explanations: set[str] = set()

    def consider(*, enforce_signature: bool, enforce_explanation: bool) -> None:
        for _, row in scored_rows:
            if len(selected_words) >= needed:
                return

            word = row["word"]
            if word in selected_set:
                continue

            signature = character_signature(word)
            explanation_key = normalize_explanation(str(row.get("explanation", "")))
            if enforce_signature and signature in seen_signatures:
                continue
            if enforce_explanation and explanation_key and explanation_key in seen_explanations:
                continue

            selected_words.append(word)
            selected_set.add(word)
            seen_signatures.add(signature)
            if explanation_key:
                seen_explanations.add(explanation_key)

    consider(enforce_signature=True, enforce_explanation=True)
    consider(enforce_signature=True, enforce_explanation=False)
    consider(enforce_signature=False, enforce_explanation=False)

    if len(selected_words) < needed:
        raise SystemExit(
            f"pedagogical selector found only {len(selected_words)} additional idioms; "
            f"needed {needed}"
        )

    return selected_words[:needed]


def next_category(order: int) -> str:
    if order <= 34:
        return "较高难度 II"
    if order <= 56:
        return "较高难度 III"
    if order <= 78:
        return "较高难度 IV"
    return "较高难度 V"


def make_unit(
    *,
    chapter_id: str,
    unit_order: int,
    text: str,
    category: str,
) -> dict[str, Any]:
    return {
        "character_count": len(text),
        "id": f"{chapter_id}-line-{unit_order:03d}",
        "order": unit_order,
        "source_block_chunk": 1,
        "source_block_order": unit_order,
        "text": text,
        "category": category,
    }


def make_chapter_payload(
    *,
    order: int,
    words: list[str],
    category: str,
) -> dict[str, Any]:
    chapter_id = f"chapter-{order:03d}"
    title_start = (order - 1) * CHAPTER_SIZE + 1
    title_end = title_start + len(words) - 1
    reading_units = [
        make_unit(
            chapter_id=chapter_id,
            unit_order=index,
            text=word,
            category=category,
        )
        for index, word in enumerate(words, start=1)
    ]
    chapter = {
        "id": chapter_id,
        "order": order,
        "summary": words[0],
        "text": "\n".join(words),
        "title": f"{title_start}-{title_end}",
        "character_count": sum(len(word) for word in words),
        "reading_unit_count": len(words),
        "reading_units": reading_units,
        "supplemental_text": "",
        "supplemental_unit_count": 0,
        "supplemental_units": [],
    }
    return {
        "chapter": chapter,
        "chapter_path": catalog_path_for(order),
        "provider": "bundled-local",
        "schema_version": 2,
        "source_title": "成語目錄",
        "source_url": "bundled://chengyu-catalog",
    }


def update_existing_last_chapter(words: list[str]) -> None:
    chapter_path = chapter_path_for(34)
    payload = load_chapter_payload(chapter_path)
    chapter = payload["chapter"]
    existing_units = list(chapter["reading_units"])
    if len(existing_units) > len(words):
        raise ValueError("existing chapter-034 has more units than expected")

    category = next_category(34)
    for index, word in enumerate(words[len(existing_units) :], start=len(existing_units) + 1):
        existing_units.append(
            make_unit(
                chapter_id=chapter["id"],
                unit_order=index,
                text=word,
                category=category,
            )
        )

    chapter["summary"] = words[0]
    chapter["text"] = "\n".join(words)
    chapter["title"] = "991-1020"
    chapter["character_count"] = sum(len(word) for word in words)
    chapter["reading_unit_count"] = len(words)
    chapter["reading_units"] = existing_units
    write_json(chapter_path, payload)


def refresh_catalog(total_words: list[str]) -> None:
    catalog = load_catalog()
    chapters: list[dict[str, Any]] = []

    for order in range(1, len(total_words) // CHAPTER_SIZE + 1):
        start = (order - 1) * CHAPTER_SIZE
        words = total_words[start : start + CHAPTER_SIZE]
        chapter_file = load_chapter_payload(chapter_path_for(order))
        chapter = chapter_file["chapter"]
        chapters.append(
            {
                "chapter_path": catalog_path_for(order),
                "character_count": chapter["character_count"],
                "id": chapter["id"],
                "order": order,
                "reading_unit_count": len(words),
                "summary": words[0],
                "supplemental_unit_count": 0,
                "title": chapter["title"],
            }
        )

    catalog["chapter_count"] = len(chapters)
    catalog["chapters"] = chapters
    catalog["pedagogy_note"] = (
        "The first 1,000 chengyu preserve the existing pedagogy-ordered sequence. "
        "The catalog then extends to 3,000 total four-character chengyu using a "
        "curriculum-aware pedagogical ranking and fixed-size lists of 30."
    )
    catalog["selection_note"] = (
        "Front chapters prioritize transparent, high-utility, and culturally central "
        "idioms from the curated pedagogy-first list. Chapters 35-100 preserve that "
        "prefix, then rank remaining upstream candidates by learner-facing value: "
        "character familiarity in the current curriculum, overlap with already-bundled "
        "chengyu, explanation brevity, and penalties for source-heavy or opaque entries, "
        "with light diversity filters to avoid redundant variants."
    )
    write_json(CATALOG_PATH, catalog)


def main() -> int:
    args = parse_args()
    if args.target_total <= 0:
        raise SystemExit("--target-total must be positive")

    if args.target_total % CHAPTER_SIZE != 0:
        raise SystemExit("--target-total must be divisible by 30")

    existing_words = load_existing_words()
    if len(existing_words) > args.target_total:
        raise SystemExit("existing catalog is already larger than the requested total")

    if len(existing_words) != CURRENT_PEDAGOGICAL_PREFIX:
        raise SystemExit(
            f"expected {CURRENT_PEDAGOGICAL_PREFIX} existing chengyu before expansion, "
            f"found {len(existing_words)}"
        )

    upstream_rows = fetch_upstream_four_character_rows()
    curriculum_char_counts = load_curriculum_character_counts()
    current_char_counts = load_current_chengyu_character_counts()
    additional_words = select_additional_words(
        existing_words=existing_words,
        target_total=args.target_total,
        upstream_rows=upstream_rows,
        current_char_counts=current_char_counts,
        curriculum_char_counts=curriculum_char_counts,
    )
    total_words = existing_words + additional_words

    update_existing_last_chapter(total_words[990:1020])
    for order in range(35, args.target_total // CHAPTER_SIZE + 1):
        start = (order - 1) * CHAPTER_SIZE
        words = total_words[start : start + CHAPTER_SIZE]
        payload = make_chapter_payload(
            order=order,
            words=words,
            category=next_category(order),
        )
        write_json(chapter_path_for(order), payload)

    refresh_catalog(total_words)
    print(
        f"expanded chengyu catalog from {len(existing_words)} to {len(total_words)} entries "
        f"across {len(total_words) // CHAPTER_SIZE} chapters"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
