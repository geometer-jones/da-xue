#!/usr/bin/env python3
"""Import English line translations from deterministic web sources.

Sources used:
- Chinese Notes (CC BY 4.0): lunyu, mengzi, daodejing, sunzi-bingfa, sanguo-yanyi, chengyu-catalog
- Wikisource / James Legge (public domain): zhong-yong, da-xue
- Wikisource / Herbert A. Giles (public domain): san-zi-jing
- Wikisource / community translation (bilingual, chapters 1-19): sanguo-yanyi
- Wikisource / Brewitt-Taylor (public domain): sanguo-yanyi
- CC-CEDICT (CC BY-SA 4.0): chengyu-catalog
- Google Translate web endpoint (fallback): chengyu-catalog
- Chinasage: qian-zi-wen

The script fills missing translations, and may replace previously generated translations
when a better-aligned sourced translation is available.
"""

from __future__ import annotations

import argparse
from collections import Counter
import difflib
import gzip
import json
import re
import sys
import time
import unicodedata
from pathlib import Path
from typing import Iterable

import requests
from bs4 import BeautifulSoup, NavigableString, Tag


REPO_ROOT = Path(__file__).resolve().parents[1]
BOOKS_ROOT = REPO_ROOT / "content" / "books"

PUNCTUATION = set('，。！？；：、,.!?;:()（）-—[]…"\''"“”‘’")
VARIANT_MAP = {
    "脩": "修",
    "爲": "為",
    "說": "説",
    "塗": "涂",
    "遯": "遁",
    "溫": "温",
    "緜": "綿",
    "巖": "岩",
}
WIKTIONARY_MIN_INTERVAL_SECONDS = 1.2
WIKIMEDIA_MIN_INTERVAL_SECONDS = 0.5
GOOGLE_TRANSLATE_MIN_INTERVAL_SECONDS = 0.2
_CC_CEDICT_ENTRIES: dict[str, list[str]] | None = None


def build_session() -> requests.Session:
    session = requests.Session()
    session.headers["User-Agent"] = "Mozilla/5.0 (compatible; da-xue-importer/1.0)"
    return session


def clean_ws(text: str) -> str:
    return " ".join(text.split())


def canonical_zh(text: str) -> str:
    normalized = unicodedata.normalize("NFKC", text)
    for source, target in VARIANT_MAP.items():
        normalized = normalized.replace(source, target)
    return "".join(
        ch
        for ch in normalized
        if not ch.isdigit()
        and not ch.isspace()
        and ch not in PUNCTUATION
        and ch not in "「」『』《》〈〉【】"
    )


def looks_cjk(text: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


def is_cjk(ch: str) -> bool:
    return (
        "\u3400" <= ch <= "\u9fff"
        or "\U00020000" <= ch <= "\U0002ebef"
    )


def split_cjk_runs(text: str) -> list[str]:
    runs: list[str] = []
    current: list[str] = []
    for ch in text:
        if is_cjk(ch):
            current.append(ch)
            continue
        if current:
            runs.append("".join(current))
            current = []
    if current:
        runs.append("".join(current))
    return runs


def replace_cjk_runs(template: str, replacements: list[str]) -> str:
    result: list[str] = []
    replacement_index = 0
    inside_run = False

    for ch in template:
        if is_cjk(ch):
            if not inside_run:
                replacement = (
                    replacements[replacement_index]
                    if replacement_index < len(replacements)
                    else ""
                )
                result.append(replacement)
                replacement_index += 1
                inside_run = True
            continue

        inside_run = False
        result.append(ch)

    return "".join(result)


def same_length_mismatches(left: str, right: str) -> int | None:
    if len(left) != len(right):
        return None
    return sum(left_char != right_char for left_char, right_char in zip(left, right))


def similarity(left: str, right: str) -> float:
    return difflib.SequenceMatcher(None, left, right).ratio()


def texts_match(left: str, right: str) -> bool:
    if left == right:
        return True

    if len(left) == len(right) and len(left) <= 8 and Counter(left) == Counter(right):
        return True

    mismatches = same_length_mismatches(left, right)
    if mismatches is not None:
        if len(left) <= 4 and mismatches <= 1:
            return True
        if len(left) <= 12 and mismatches <= 2:
            return True
        if mismatches <= max(2, len(left) // 20):
            return True

    ratio = similarity(left, right)
    length_gap = abs(len(left) - len(right))
    max_len = max(len(left), len(right))

    if max_len <= 8:
        return ratio >= 0.72 and length_gap <= 2
    if max_len <= 20:
        return ratio >= 0.84 and length_gap <= 4
    return ratio >= 0.88 and length_gap <= max(8, max_len // 6)


def split_source_sentences(text: str) -> list[str]:
    text = clean_ws(text)
    if not text:
        return []

    segments = [
        clean_ws(segment)
        for segment in re.findall(r"[^。！？；]+[。！？；]?[」』”]?", text)
        if clean_ws(segment)
    ]
    return segments


def split_translation(text: str, parts: int) -> list[str]:
    text = clean_ws(text)
    if parts <= 1:
        return [text]

    separators = [
        re.compile(r'(?<=[.?!])\s+(?=["\'(A-Z])'),
        re.compile(r"(?<=;)\s+|(?<=:)\s+"),
        re.compile(r"(?<=,)\s+"),
    ]

    segments = [text]
    for separator in separators:
        candidate: list[str] = []
        for segment in segments:
            candidate.extend(part.strip() for part in separator.split(segment) if part.strip())
        segments = candidate
        if len(segments) >= parts:
            break

    if len(segments) == parts:
        return segments
    if len(segments) > parts:
        return segments[: parts - 1] + [" ".join(segments[parts - 1 :])]

    # Last resort: keep every line translated, even if the source only offers one long gloss.
    return [text] * parts


def list_chapter_paths(book_id: str) -> list[Path]:
    chapters_dir = BOOKS_ROOT / book_id / "chapters"
    return sorted(chapters_dir.glob("chapter-*.json"))


def read_json(path: Path) -> dict:
    return json.loads(path.read_text())


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def reading_units(document: dict) -> list[dict]:
    return document["chapter"]["reading_units"]


def has_translation(unit: dict) -> bool:
    direct = clean_ws(unit.get("translation_en", ""))
    generated = clean_ws(
        (
            (((unit.get("generated_annotation") or {}).get("layers") or {}).get("translation_en"))
            or ""
        )
    )
    return bool(direct or generated)


def set_generated_translation(
    unit: dict,
    translation: str,
    *,
    replace_generated: bool = False,
) -> bool:
    translation = clean_ws(translation)
    if not translation:
        return False
    direct = clean_ws(unit.get("translation_en", ""))
    if direct:
        return False
    generated_annotation = unit.setdefault("generated_annotation", {})
    layers = generated_annotation.setdefault("layers", {})
    existing = clean_ws(layers.get("translation_en", ""))
    if existing == translation:
        return False
    if existing and not replace_generated:
        return False
    layers["translation_en"] = translation
    return True


def set_source_text(unit: dict, source_text: str) -> bool:
    source_text = clean_ws(source_text)
    if not source_text:
        return False

    current_text = unit["text"]
    current_runs = split_cjk_runs(current_text)
    source_runs = split_cjk_runs(source_text)
    if current_runs and len(current_runs) == len(source_runs):
        proposed = replace_cjk_runs(current_text, source_runs)
    else:
        proposed = source_text

    if proposed == current_text:
        return False

    unit["text"] = proposed
    return True


def unit_source_texts(units: list[dict], source_text: str) -> dict[str, str]:
    if not units:
        return {}

    if len(units) == 1:
        return {units[0]["id"]: source_text}

    segments = split_source_sentences(source_text)
    if len(segments) == len(units):
        return {unit["id"]: segment for unit, segment in zip(units, segments)}

    return {}


def format_sanzi_source_text(phrases: list[str]) -> str:
    segments: list[str] = []
    for index in range(0, len(phrases), 2):
        if index + 1 < len(phrases):
            segments.append(f"{phrases[index]}，{phrases[index + 1]}。")
        else:
            segments.append(phrases[index])
    return "".join(segments)


def extract_corpus_br_lines(session: requests.Session, url: str) -> list[str]:
    response = session.get(url, timeout=30)
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    content = soup.select_one("div.mdc-top-app-bar--fixed-adjust")
    if content is None:
        raise ValueError(f"missing corpus content container for {url}")

    lines: list[str] = []
    buffer: list[str] = []
    inside_corpus = False

    def flush() -> None:
        text = clean_ws(" ".join(buffer))
        buffer.clear()
        if text:
            lines.append(text)

    for node in content.descendants:
        if isinstance(node, NavigableString):
            raw = str(node)
            if "CorpusText" in raw:
                inside_corpus = True
                buffer.clear()
                continue
            if not inside_corpus:
                continue
            if raw.startswith("<!--"):
                continue
            buffer.append(raw)
            continue

        if not isinstance(node, Tag):
            continue
        if node.name == "footer":
            break
        if node.name == "br" and inside_corpus:
            flush()

    if buffer:
        flush()

    return lines


def parse_chinese_notes_groups(session: requests.Session, url: str) -> list[tuple[str, str]]:
    response = session.get(url, timeout=30)
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    content = soup.select_one("div.mdc-top-app-bar--fixed-adjust")
    if content is None:
        raise ValueError(f"missing corpus content container for {url}")

    groups: list[tuple[str, str]] = []
    current_zh: list[str] = []
    current_en: list[str] = []
    inside_corpus = False

    def finalize() -> None:
        nonlocal current_zh, current_en
        zh = "".join(current_zh).strip()
        en = clean_ws(" ".join(current_en))
        if canonical_zh(zh) and en:
            groups.append((zh, en))
        current_zh = []
        current_en = []

    for child in content.children:
        if isinstance(child, NavigableString):
            raw = str(child)
            if "CorpusText" in raw:
                inside_corpus = True
                continue
            if not inside_corpus:
                continue
            text = clean_ws(raw)
            if not text:
                continue
            if re.search(r"[A-Za-z]{2,}", text):
                if current_zh:
                    current_en.append(text)
                continue
            if looks_cjk(text) or any(ch in text for ch in "《》「」『』，。！？；：、（）()—-[]0123456789"):
                if current_en:
                    finalize()
                current_zh.append(text)
            continue

        if not isinstance(child, Tag):
            continue
        if child.name == "footer":
            break
        if child.name == "br":
            continue
        if not inside_corpus:
            continue

        text = clean_ws(child.get_text(" ", strip=True))
        if not text:
            continue

        classes = child.get("class") or []
        if child.name == "span" and "vocabulary" in classes:
            if current_en:
                finalize()
            current_zh.append(text)
            continue

        if re.search(r"[A-Za-z]{2,}", text):
            if current_zh:
                current_en.append(text)
            continue

        if looks_cjk(text):
            if current_en:
                finalize()
            current_zh.append(text)

    if current_en:
        finalize()

    return groups


def parse_daodejing_groups(session: requests.Session, url: str) -> list[tuple[str, str]]:
    lines = extract_corpus_br_lines(session, url)
    groups: list[tuple[str, str]] = []
    current_zh: list[str] = []
    current_en: list[str] = []

    def finalize() -> None:
        nonlocal current_zh, current_en
        zh = "".join(current_zh).strip()
        en = clean_ws(" ".join(current_en))
        if canonical_zh(zh) and en:
            groups.append((zh, en))
        current_zh = []
        current_en = []

    for raw_line in lines:
        line = clean_ws(raw_line)
        collapsed = line.replace(" ", "")
        if not line:
            continue

        if collapsed.startswith(("作者：", "注：")) or collapsed in {
            "老子《道德經》上篇",
            "華亭張氏原本",
            "晉王弼注",
        }:
            continue

        if re.fullmatch(r"[一二三四五六七八九十百]+章", collapsed):
            if current_en:
                finalize()
            current_zh = []
            current_en = []
            continue

        if line.startswith("〈"):
            if current_en:
                finalize()
            continue

        if re.fullmatch(r"\([^)]*\)", line):
            continue

        if re.search(r"[A-Za-z]{2,}", line):
            if current_zh:
                current_en.append(line)
            continue

        if looks_cjk(line):
            if current_en:
                finalize()
            current_zh.append(line)

    if current_en:
        finalize()

    return groups


def parse_sunzi_groups(session: requests.Session, url: str) -> list[tuple[str, str]]:
    lines = extract_corpus_br_lines(session, url)
    groups: list[tuple[str, str]] = []
    current_zh: list[str] = []
    current_en: list[str] = []

    def finalize() -> None:
        nonlocal current_zh, current_en
        zh = "".join(current_zh).strip()
        en = clean_ws(" ".join(current_en))
        if canonical_zh(zh) and en:
            groups.append((zh, en))
        current_zh = []
        current_en = []

    for raw_line in lines:
        line = clean_ws(raw_line)
        collapsed = line.replace(" ", "")
        if not line:
            continue

        if collapsed.startswith("作者："):
            continue

        if re.fullmatch(r".*第[一二三四五六七八九十百]+", collapsed):
            if current_en:
                finalize()
            continue

        if line.startswith("Section "):
            continue

        if re.search(r"[A-Za-z]{2,}", line):
            if current_zh:
                current_en.append(line)
            continue

        if looks_cjk(line):
            if current_en:
                finalize()
            current_zh = [line]

    if current_en:
        finalize()

    return groups


def parse_sunzi_chapter_groups(session: requests.Session, url: str) -> list[list[tuple[str, str]]]:
    """Parse Sunzi groups, returning a list of per-chapter group lists."""
    lines = extract_corpus_br_lines(session, url)
    chapters: list[list[tuple[str, str]]] = []
    current_zh: list[str] = []
    current_en: list[str] = []

    def finalize() -> None:
        nonlocal current_zh, current_en
        zh = "".join(current_zh).strip()
        en = clean_ws(" ".join(current_en))
        if canonical_zh(zh) and en:
            if not chapters:
                chapters.append([])
            chapters[-1].append((zh, en))
        current_zh = []
        current_en = []

    for raw_line in lines:
        line = clean_ws(raw_line)
        collapsed = line.replace(" ", "")
        if not line:
            continue

        if collapsed.startswith("作者："):
            continue

        if re.fullmatch(r".*第[一二三四五六七八九十百]+", collapsed):
            if current_en:
                finalize()
            chapters.append([])
            continue
        if line.startswith("Section "):
            continue
        if re.search(r"[A-Za-z]{2,}", line):
            if current_zh:
                current_en.append(line)
            continue
        if looks_cjk(line):
            if current_en:
                finalize()
            current_zh = [line]

    if current_en:
        finalize()

    # Remove empty leading chapter if any (from text before first header)
    if chapters and not chapters[0]:
        chapters.pop(0)

    return chapters


def assign_units_by_containment(
    units: list[dict],
    groups: list[tuple[str, str]],
) -> tuple[dict[str, str], dict[str, str]]:
    """Assign translations to reading units using character-level containment.

    Works by concatenating all groups' canonical text into a single string, then
    for each reading unit, finding which groups' canonical characters are
    contained within the unit's canonical text range.  Merges those groups' English.
    """
    if not units or not groups:
        return {}, {}
    group_canonical = [canonical_zh(zh) for zh, _ in groups]
    unit_canonical = [canonical_zh(u["text"]) for u in units]
    if not group_canonical or not unit_canonical:
        return {}, {}

    group_ranges: list[tuple[int, int]] = []
    pos = 0
    for gc in group_canonical:
        group_ranges.append((pos, pos + len(gc)))
        pos += len(gc)
    unit_ranges: list[tuple[int, int]] = []
    pos = 0
    for uc in unit_canonical:
        unit_ranges.append((pos, pos + len(uc)))
        pos += len(uc)
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}

    for unit_idx in range(len(units)):
        u_start, u_end = unit_ranges[unit_idx]
        if u_end <= u_start:
            continue
        first_group = None
        last_group = None
        for g_idx in range(len(group_ranges)):
            g_start, g_end = group_ranges[g_idx]
            if g_end <= u_start or g_start >= u_end:
                continue
            if first_group is None:
                first_group = g_idx
            last_group = g_idx

        if first_group is None or last_group is None:
            continue
        covered_groups = groups[first_group : last_group + 1]
        assignments[units[unit_idx]["id"]] = clean_translation_text(
            " ".join(english for _, english in covered_groups)
        )
        source_texts[units[unit_idx]["id"]] = "".join(
            zh for zh, _ in covered_groups
        )
    return assignments, source_texts
def parse_wikisource_paragraph_pairs(session: requests.Session, url: str) -> list[tuple[str, str]]:
    response = session.get(url, timeout=30)
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    main = soup.find(id="mw-content-text")
    if main is None:
        raise ValueError(f"missing mw-content-text for {url}")

    pairs: list[tuple[str, str]] = []
    current_zh: str | None = None
    for paragraph in main.find_all("p"):
        text = clean_ws(paragraph.get_text(" ", strip=True))
        if not text:
            continue

        if paragraph.find("span", class_="wst-lang") is not None or looks_cjk(text):
            current_zh = text
            continue

        if current_zh and re.search(r"[A-Za-z]{2,}", text):
            normalized_zh = canonical_zh(current_zh)
            if current_zh in {"中庸", "大學"} or (
                len(normalized_zh) <= 8 and not re.search(r"[.?!;:]", text)
            ):
                current_zh = None
                continue
            pairs.append((current_zh, text))
            current_zh = None

    return pairs


def parse_wikisource_block_pairs(session: requests.Session, url: str) -> list[tuple[str, str]]:
    response = session.get(url, timeout=30)
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    main = soup.find(id="mw-content-text")
    if main is None:
        raise ValueError(f"missing mw-content-text for {url}")

    groups: list[tuple[str, str]] = []
    current_zh: list[str] = []
    for paragraph in main.find_all("p"):
        text = clean_ws(paragraph.get_text(" ", strip=True))
        if not text:
            continue

        if looks_cjk(text):
            current_zh.append(text)
            continue

        if current_zh and re.search(r"[A-Za-z]{2,}", text):
            if text.lower().startswith("there is a poem") and len(current_zh) > 1:
                groups.append((current_zh[0], text))
                current_zh = current_zh[1:]
                continue

            groups.append(("".join(current_zh), text))
            current_zh = []

    return groups


def parse_kongming_chapter(session: requests.Session, url: str) -> list[tuple[str, str]]:
    response = session.get(url, timeout=30)
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    container = soup.select_one(".reading__paragraphs")
    if container is None:
        raise ValueError(f"missing reading paragraphs for {url}")

    groups: list[tuple[str, str]] = []
    for block in container.select("div.block[data-ss]"):
        payload = block.get("data-ss", "")
        parts = payload.split("|")
        if len(parts) < 2:
            continue

        english = clean_translation_text(parts[0])
        chinese = clean_ws(parts[1])
        if canonical_zh(chinese) and english:
            groups.append((chinese, english))

    return groups


def parse_rotk_translation_groups(session: requests.Session, order: int) -> list[tuple[str, str]]:
    response = rate_limited_get(
        session,
        "https://en.wikisource.org/w/index.php",
        params={
            "title": f"Translation:Romance_of_the_Three_Kingdoms/Chapter_{order}",
            "action": "raw",
        },
        timeout=30,
        interval_seconds=WIKIMEDIA_MIN_INTERVAL_SECONDS,
        state_attr="_wikimedia_last_request_at",
    )
    if response.status_code == 404:
        return []
    if response.status_code == 429:
        return []
    response.raise_for_status()

    wikitext = response.text
    groups: list[tuple[str, str]] = []
    for match in re.finditer(r"==\s*\d+\s*==\n(.*?)(?=\n==\s*\d+\s*==|\Z)", wikitext, re.S):
        block = match.group(1)
        row_matches = re.findall(r"\|-\n(.*?)(?=\n\|-|\n\|\}|$)", block, re.S)
        if len(row_matches) < 2:
            continue

        chinese_row = " ".join(
            line.lstrip("|").strip()
            for line in row_matches[0].splitlines()
            if line.strip()
        )
        english_rows = [
            " ".join(
                line.lstrip("|").strip()
                for line in row.splitlines()
                if line.strip()
            )
            for row in row_matches[1:]
        ]

        chinese = strip_rotk_wiki_markup(chinese_row).replace(" ", "")
        english = clean_translation_text(
            " ".join(strip_rotk_wiki_markup(row) for row in english_rows)
        )
        if canonical_zh(chinese) and english:
            groups.append((chinese, english))

    return groups


def parse_sanguo_english_paragraphs(session: requests.Session, order: int) -> list[str]:
    volume = 1 if order <= 60 else 2
    response = rate_limited_get(
        session,
        f"https://en.wikisource.org/wiki/San_Kuo/Volume_{volume}/Chapter_{order}",
        timeout=30,
        interval_seconds=WIKIMEDIA_MIN_INTERVAL_SECONDS,
        state_attr="_wikimedia_last_request_at",
    )
    if response.status_code == 429:
        raise ValueError(f"rate limited fetching San Kuo chapter {order}")
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    main = soup.find(id="mw-content-text")
    if main is None:
        raise ValueError(f"missing mw-content-text for San Kuo chapter {order}")

    paragraphs: list[str] = []
    for paragraph in main.find_all("p"):
        text = clean_ws(paragraph.get_text(" ", strip=True))
        if not text:
            continue
        if re.fullmatch(r"CHAPTER\s+[IVXLCDM]+\.?", text):
            continue
        if text.startswith("Footnotes") or text.startswith("Notes") or text.startswith("References"):
            break
        if re.match(r"^\d+\.\s", text):
            break
        paragraphs.append(text)

    if len(paragraphs) >= 2:
        paragraphs = paragraphs[2:]

    cleaned: list[str] = []
    for paragraph in paragraphs:
        paragraph = re.sub(r"^([A-Z])\s+([a-z]{2,})", r"\1\2", paragraph)
        cleaned.append(clean_translation_text(paragraph))
    return [paragraph for paragraph in cleaned if paragraph]


def parse_wikisource_numbered_sections(session: requests.Session, url: str) -> dict[int, str]:
    response = session.get(url, timeout=30)
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    main = soup.find(id="mw-content-text")
    if main is None:
        raise ValueError(f"missing mw-content-text for {url}")

    sections: dict[int, str] = {}
    current_number: int | None = None
    current_lines: list[str] = []

    def finalize() -> None:
        nonlocal current_number, current_lines
        if current_number is not None and current_lines:
            sections[current_number] = clean_translation_text(" ".join(current_lines))
        current_number = None
        current_lines = []

    for node in main.find_all(["h3", "p"]):
        text = clean_ws(node.get_text(" ", strip=True))
        if not text:
            continue

        if node.name == "h3":
            if current_number is not None:
                finalize()
            if re.fullmatch(r"\d+", text):
                current_number = int(text)
            continue

        if current_number is not None:
            current_lines.append(text)

    if current_number is not None:
        finalize()

    return sections


def parse_wikisource_sanzi_phrases(session: requests.Session, url: str) -> list[tuple[str, str]]:
    response = session.get(url, timeout=30)
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    phrases: list[tuple[str, str]] = []
    for table in soup.find_all("table"):
        rows = table.find_all("tr")
        if len(rows) < 1:
            continue
        first_row = rows[0].find_all(["th", "td"])
        if len(first_row) < 5:
            continue

        cells = [clean_ws(cell.get_text(" ", strip=True)) for cell in first_row]
        if not re.fullmatch(r"\d+\.", cells[0]):
            continue

        chinese = "".join(cells[1:4])
        english = cells[-1]
        if canonical_zh(chinese) and english:
            phrases.append((chinese, english))

    return phrases


def parse_chinasage_qianzi_entries(session: requests.Session, url: str) -> list[tuple[str, str]]:
    response = session.get(url, timeout=30)
    response.raise_for_status()
    response.encoding = "utf-8"

    soup = BeautifulSoup(response.text, "html.parser")
    entries: list[tuple[str, str]] = []
    for heading in soup.find_all("h3"):
        title = clean_ws(heading.get_text(" ", strip=True))
        if not re.fullmatch(r"\d+\.\s+\[\d+\]", title):
            continue

        traditional_parts: list[str] = []
        english = ""
        sibling = heading
        while True:
            sibling = sibling.find_next_sibling()
            if sibling is None or sibling.name == "h3":
                break

            classes = sibling.get("class") or []
            if sibling.name == "span" and "ncht" in classes:
                traditional_parts.append(clean_ws(sibling.get_text(" ", strip=True)))
            elif sibling.name == "span" and "engt" in classes and not english:
                english = clean_ws(sibling.get_text(" ", strip=True))

        chinese = "".join(traditional_parts)
        if canonical_zh(chinese) and english:
            entries.append((chinese, english))

    return entries


def fetch_chengyu_translation(session: requests.Session, text: str) -> str:
    response = session.get(
        "https://chinesenotes.com/findsubstring",
        params={"query": text, "topic": "Idiom"},
        timeout=30,
    )
    response.raise_for_status()

    payload = response.json()
    for word in payload.get("Words") or []:
        for sense in word.get("Senses") or []:
            simplified = clean_ws(sense.get("Simplified", "") or "")
            traditional = clean_ws(sense.get("Traditional", "") or "")
            if text in {simplified, traditional}:
                return clean_ws(sense.get("English", "") or "")
    return ""


def load_cc_cedict_entries(session: requests.Session) -> dict[str, list[str]]:
    global _CC_CEDICT_ENTRIES
    if _CC_CEDICT_ENTRIES is not None:
        return _CC_CEDICT_ENTRIES

    response = session.get(
        "https://cc-cedict.org/editor/editor_export_cedict.php?c=gz",
        timeout=60,
    )
    response.raise_for_status()

    text = gzip.decompress(response.content).decode("utf-8", errors="replace")
    entries: dict[str, list[str]] = {}
    line_pattern = re.compile(r"^(\S+)\s+(\S+)\s+\[(.*?)\]\s+/(.*)/$")
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        match = line_pattern.match(line)
        if not match:
            continue
        traditional, simplified, _, raw_definitions = match.groups()
        definitions = [definition for definition in raw_definitions.split("/") if definition]
        for key in {traditional, simplified}:
            existing = entries.setdefault(key, [])
            existing.extend(definitions)

    _CC_CEDICT_ENTRIES = entries
    return entries


def resolve_cc_cedict_definition(
    entries: dict[str, list[str]],
    definitions: list[str],
    *,
    seen: set[str] | None = None,
) -> str:
    if seen is None:
        seen = set()

    for definition in unique_strings(definitions):
        if definition.startswith("CL:"):
            continue

        variant_match = re.match(
            r"^(?:variant of|old variant of|archaic variant of)\s+([^|[\s]+)(?:\|([^[]+))?",
            definition,
        )
        if variant_match:
            target = clean_ws(variant_match.group(2) or variant_match.group(1) or "")
            if target and target not in seen:
                seen.add(target)
                resolved = resolve_cc_cedict_definition(
                    entries,
                    entries.get(target, []),
                    seen=seen,
                )
                if resolved:
                    return resolved
            continue

        return definition

    return ""


def fetch_cc_cedict_translation(session: requests.Session, text: str) -> str:
    entries = load_cc_cedict_entries(session)
    definitions = entries.get(text, [])
    return resolve_cc_cedict_definition(entries, definitions)


def fetch_google_translation(session: requests.Session, text: str) -> str:
    response = rate_limited_get(
        session,
        "https://translate.googleapis.com/translate_a/single",
        params={
            "client": "gtx",
            "sl": "zh-CN",
            "tl": "en",
            "dt": "t",
            "q": text,
        },
        interval_seconds=GOOGLE_TRANSLATE_MIN_INTERVAL_SECONDS,
        state_attr="_google_translate_last_request_at",
        max_attempts=3,
    )
    if response.status_code == 429:
        return ""
    response.raise_for_status()

    payload = response.json()
    translated = "".join(part[0] for part in (payload[0] or []) if part and part[0])
    return clean_ws(translated)


def strip_wiki_markup(text: str) -> str:
    previous = None
    while previous != text:
        previous = text
        text = re.sub(r"\{\{[^{}]*\}\}", "", text)
    text = re.sub(r"\[\[([^|\]]+)\|([^\]]+)\]\]", r"\2", text)
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("'''", "").replace("''", "")
    text = re.sub(r"\s+", " ", text)
    return text.strip(" ;,")


def strip_rotk_wiki_markup(text: str) -> str:
    text = re.sub(r"<ref[^>]*>.*?</ref>", "", text, flags=re.S)
    text = text.replace("<poem>", "").replace("</poem>", "")

    def replace_template(match: re.Match[str]) -> str:
        body = match.group(1)
        parts = [part.strip() for part in body.split("|")]
        positional = [part for part in parts[1:] if "=" not in part]
        if positional:
            return positional[-1]
        if len(parts) > 1:
            return parts[-1]
        return ""

    previous = None
    while previous != text:
        previous = text
        text = re.sub(r"\{\{([^{}]*)\}\}", replace_template, text)

    text = re.sub(r"\[\[[^|\]]+\|([^\]]+)\]\]", r"\1", text)
    text = re.sub(r"\[\[([^\]]+)\]\]", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("'''", "").replace("''", "")
    text = text.replace("&nbsp;", " ")
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def unique_strings(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for value in values:
        normalized = clean_ws(value)
        if not normalized or normalized in seen:
            continue
        seen.add(normalized)
        unique.append(normalized)
    return unique


def rate_limited_get(
    session: requests.Session,
    url: str,
    *,
    params: dict[str, str] | None = None,
    timeout: int = 30,
    interval_seconds: float = 0.0,
    state_attr: str | None = None,
    max_attempts: int = 5,
) -> requests.Response:
    for attempt in range(max_attempts):
        if state_attr:
            last_request_at = getattr(session, state_attr, 0.0)
            wait_for = interval_seconds - (time.time() - last_request_at)
            if wait_for > 0:
                time.sleep(wait_for)

        response = session.get(url, params=params, timeout=timeout)
        if state_attr:
            setattr(session, state_attr, time.time())
        if response.status_code != 429:
            return response

        retry_after = response.headers.get("retry-after")
        delay = float(retry_after) if retry_after else min(30.0, 2.0 ** attempt)
        time.sleep(delay)

    return response


def fetch_wiktionary_translation(
    session: requests.Session,
    text: str,
    *,
    seen: set[str] | None = None,
) -> str:
    if seen is None:
        seen = set()
    if text in seen:
        return ""
    seen.add(text)

    response = rate_limited_get(
        session,
        "https://en.wiktionary.org/w/api.php",
        params={
            "action": "query",
            "titles": text,
            "prop": "revisions",
            "rvprop": "content",
            "format": "json",
            "formatversion": "2",
            "redirects": "1",
        },
        interval_seconds=WIKTIONARY_MIN_INTERVAL_SECONDS,
        state_attr="_wiktionary_last_request_at",
        max_attempts=5,
    )
    if response.status_code == 429:
        return ""
    response.raise_for_status()

    payload = response.json()
    pages = ((payload.get("query") or {}).get("pages")) or []
    if not pages or "revisions" not in pages[0]:
        return ""

    content = pages[0]["revisions"][0].get("content", "")
    see_match = re.search(r"\{\{zh-see\|([^}|]+)", content)
    if see_match:
        return fetch_wiktionary_translation(session, see_match.group(1), seen=seen)
    if "==Chinese==" not in content:
        return ""

    chinese_section = content.split("==Chinese==", 1)[1]
    chinese_section = re.split(r"\n==[^=]", chinese_section, maxsplit=1)[0]

    preferred_markers = ["===Idiom===", "===Chengyu===", "===Proverb===", "===Phrase==="]
    for marker in preferred_markers:
        if marker in chinese_section:
            chinese_section = chinese_section.split(marker, 1)[1]
            break

    for line in chinese_section.splitlines():
        stripped = line.strip()
        if not stripped.startswith("#") or stripped.startswith("#:") or stripped.startswith("#*"):
            continue
        definition = strip_wiki_markup(re.sub(r"^#+\s*", "", stripped))
        if definition:
            return definition

    return ""


def clean_translation_text(text: str) -> str:
    text = re.sub(r"\[p\.\s*\d+\]\s*", "", text)
    text = re.sub(r"\[\s*\d+\s*\]", "", text)
    text = re.sub(r"Source:.*", "", text)
    text = re.sub(r"Dictionary cache status:.*", "", text)
    return clean_ws(text)


def best_match_end(chunks: list[str], start: int, target: str, max_span: int) -> tuple[int | None, str, float]:
    best_end: int | None = None
    best_accumulated = ""
    best_ratio = 0.0
    accumulated = ""

    for index in range(start, min(len(chunks), start + max_span)):
        accumulated += chunks[index]
        if accumulated == target:
            return index + 1, accumulated, 1.0

        ratio = similarity(accumulated, target)
        if ratio > best_ratio:
            best_end = index + 1
            best_accumulated = accumulated
            best_ratio = ratio

        if len(accumulated) > len(target) + max(16, len(target) // 3) and best_ratio >= 0.84:
            break

    return best_end, best_accumulated, best_ratio


def assign_passage_groups(
    units: list[dict],
    groups: list[tuple[str, str]],
) -> tuple[dict[str, str], dict[str, str]]:
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}
    unit_index = 0
    unit_chunks = [canonical_zh(unit["text"]) for unit in units]

    for zh_group, english in groups:
        target = canonical_zh(zh_group)
        if not target or unit_index >= len(units):
            continue

        start = unit_index
        max_span = 30
        end, accumulated, ratio = best_match_end(unit_chunks, start, target, max_span)

        if end is None or not texts_match(accumulated, target):
            continue

        covered_units = units[start:end]
        for unit, piece in zip(covered_units, split_translation(english, len(covered_units))):
            assignments[unit["id"]] = clean_translation_text(piece)
        source_texts.update(unit_source_texts(covered_units, zh_group))
        unit_index = end

    return assignments, source_texts


def assign_flexible_groups(
    units: list[dict],
    groups: list[tuple[str, str]],
    *,
    max_unit_span: int = 8,
    max_group_span: int = 8,
    source_text_builder=None,
) -> tuple[dict[str, str], dict[str, str]]:
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}
    unit_chunks = [canonical_zh(unit["text"]) for unit in units]
    group_chunks = [canonical_zh(zh) for zh, _ in groups]
    unit_index = 0
    group_index = 0

    while unit_index < len(units) and group_index < len(groups):
        best_match: tuple[float, int, int, str, str] | None = None
        unit_accumulated = ""

        for unit_end in range(unit_index, min(len(units), unit_index + max_unit_span)):
            unit_accumulated += unit_chunks[unit_end]
            group_accumulated = ""
            for group_end in range(group_index, min(len(groups), group_index + max_group_span)):
                group_accumulated += group_chunks[group_end]
                if not texts_match(unit_accumulated, group_accumulated):
                    continue

                ratio = similarity(unit_accumulated, group_accumulated)
                unit_span = unit_end - unit_index + 1
                group_span = group_end - group_index + 1
                score = (ratio, -abs(unit_span - group_span), -(unit_span + group_span))
                if best_match is None or score > best_match[:3]:
                    best_match = (ratio, -abs(unit_span - group_span), -(unit_span + group_span), unit_end + 1, group_end + 1)

        if best_match is None:
            normalized_group = group_chunks[group_index]
            if len(normalized_group) <= 8 and not re.search(r"[。！？；]", groups[group_index][0]):
                group_index += 1
                continue
            if len(unit_chunks[unit_index]) <= len(group_chunks[group_index]):
                unit_index += 1
            else:
                group_index += 1
            continue

        unit_end = int(best_match[3])
        group_end = int(best_match[4])
        covered_units = units[unit_index:unit_end]
        covered_groups = groups[group_index:group_end]
        merged_english = clean_translation_text(" ".join(english for _, english in covered_groups))
        for unit, piece in zip(covered_units, split_translation(merged_english, len(covered_units))):
            assignments[unit["id"]] = piece

        merged_source = "".join(zh for zh, _ in covered_groups)
        source_texts.update(unit_source_texts(covered_units, merged_source))
        if len(covered_units) == 1:
            if source_text_builder is not None:
                source_texts[covered_units[0]["id"]] = source_text_builder(
                    covered_units[0],
                    covered_groups,
                )
            else:
                source_texts[covered_units[0]["id"]] = merged_source

        unit_index = unit_end
        group_index = group_end

    return assignments, source_texts


def assign_units_from_groups(
    units: list[dict],
    groups: list[tuple[str, str]],
    *,
    max_span: int = 12,
    source_text_builder=None,
) -> tuple[dict[str, str], dict[str, str]]:
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}
    group_index = 0
    group_chunks = [canonical_zh(zh) for zh, _ in groups]

    for unit in units:
        target = canonical_zh(unit["text"])
        if not target or group_index >= len(groups):
            continue

        end, accumulated, _ = best_match_end(group_chunks, group_index, target, max_span)
        if end is None or not texts_match(accumulated, target):
            continue

        covered_groups = groups[group_index:end]
        assignments[unit["id"]] = clean_translation_text(
            " ".join(english for _, english in covered_groups)
        )

        source_runs = [zh for zh, _ in covered_groups]
        if source_text_builder is not None:
            source_texts[unit["id"]] = source_text_builder(unit, covered_groups)
        elif split_cjk_runs(unit["text"]) and len(split_cjk_runs(unit["text"])) == len(source_runs):
            source_texts[unit["id"]] = replace_cjk_runs(unit["text"], source_runs)
        else:
            source_texts[unit["id"]] = "".join(source_runs)

        group_index = end

    return assignments, source_texts


def assign_english_paragraphs_by_length(
    units: list[dict],
    paragraphs: list[str],
    *,
    max_group_span: int = 6,
) -> dict[str, str]:
    if not units or not paragraphs:
        return {}

    if len(paragraphs) < len(units):
        merged = " ".join(paragraphs)
        return {
            unit["id"]: piece
            for unit, piece in zip(units, split_translation(merged, len(units)))
        }

    zh_lengths = [
        max(1, len(re.sub(r"[^\u3400-\u9fff\U00020000-\U0002ebef]", "", unit["text"])))
        for unit in units
    ]
    en_lengths = [
        max(1, len(re.findall(r"[A-Za-z']+", paragraph)))
        for paragraph in paragraphs
    ]
    scale = sum(en_lengths) / max(1, sum(zh_lengths))
    prefix_sums = [0]
    for length in en_lengths:
        prefix_sums.append(prefix_sums[-1] + length)

    def segment_words(start: int, end: int) -> int:
        return prefix_sums[end] - prefix_sums[start]

    unit_count = len(units)
    paragraph_count = len(paragraphs)
    infinity = float("inf")
    dp = [[infinity] * (paragraph_count + 1) for _ in range(unit_count + 1)]
    previous: list[list[int | None]] = [[None] * (paragraph_count + 1) for _ in range(unit_count + 1)]
    dp[0][0] = 0.0

    for unit_index in range(1, unit_count + 1):
        max_paragraph_index = paragraph_count - (unit_count - unit_index)
        for paragraph_index in range(unit_index, max_paragraph_index + 1):
            for group_span in range(1, max_group_span + 1):
                start_index = paragraph_index - group_span
                if start_index < unit_index - 1:
                    break

                words = segment_words(start_index, paragraph_index)
                target = max(8.0, zh_lengths[unit_index - 1] * scale)
                cost = ((words - target) ** 2) / target
                if group_span > 1 and zh_lengths[unit_index - 1] < 12:
                    cost += 20.0 * (group_span - 1)
                if group_span > 2 and zh_lengths[unit_index - 1] < 20:
                    cost += 10.0 * (group_span - 2)

                candidate = dp[unit_index - 1][start_index] + cost
                if candidate < dp[unit_index][paragraph_index]:
                    dp[unit_index][paragraph_index] = candidate
                    previous[unit_index][paragraph_index] = start_index

    assignments: dict[str, str] = {}
    paragraph_index = paragraph_count
    groups: list[tuple[int, int]] = []
    for unit_index in range(unit_count, 0, -1):
        start_index = previous[unit_index][paragraph_index]
        if start_index is None:
            merged = " ".join(paragraphs)
            return {
                unit["id"]: piece
                for unit, piece in zip(units, split_translation(merged, len(units)))
            }
        groups.append((start_index, paragraph_index))
        paragraph_index = start_index

    groups.reverse()
    for unit, (start_index, end_index) in zip(units, groups):
        assignments[unit["id"]] = clean_translation_text(
            " ".join(paragraphs[start_index:end_index])
        )

    return assignments


def apply_assignments(
    chapter_paths: Iterable[Path],
    assignments: dict[str, str],
    source_texts: dict[str, str],
    *,
    replace_generated: bool = False,
) -> tuple[int, int, int]:
    updated_chapters = 0
    updated_units = 0
    updated_texts = 0

    for chapter_path in chapter_paths:
        document = read_json(chapter_path)
        changed = False
        for unit in reading_units(document):
            source_text = source_texts.get(unit["id"], "")
            if set_source_text(unit, source_text):
                changed = True
                updated_texts += 1
            translation = assignments.get(unit["id"], "")
            if set_generated_translation(
                unit,
                translation,
                replace_generated=replace_generated,
            ):
                changed = True
                updated_units += 1

        if changed:
            write_json(chapter_path, document)
            updated_chapters += 1

    return updated_chapters, updated_units, updated_texts


def build_chinese_notes_chapter_assignments(
    session: requests.Session,
    book_id: str,
    url_template: str,
) -> tuple[dict[str, str], dict[str, str]]:
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}
    for chapter_path in list_chapter_paths(book_id):
        document = read_json(chapter_path)
        order = document["chapter"]["order"]
        groups = parse_chinese_notes_groups(session, url_template.format(order=order))
        chapter_assignments, chapter_source_texts = assign_passage_groups(reading_units(document), groups)
        assignments.update(chapter_assignments)
        source_texts.update(chapter_source_texts)
    return assignments, source_texts


def build_wikisource_chapter_assignments(
    session: requests.Session,
    book_id: str,
    url_template: str,
    parser,
    *,
    assigner=assign_passage_groups,
    **assigner_kwargs,
) -> tuple[dict[str, str], dict[str, str]]:
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}
    for chapter_path in list_chapter_paths(book_id):
        document = read_json(chapter_path)
        order = document["chapter"]["order"]
        groups = parser(session, url_template.format(order=order))
        chapter_assignments, chapter_source_texts = assigner(
            reading_units(document),
            groups,
            **assigner_kwargs,
        )
        assignments.update(chapter_assignments)
        source_texts.update(chapter_source_texts)
    return assignments, source_texts


def build_full_page_assignments(
    session: requests.Session,
    book_id: str,
    parser,
    url: str,
    *,
    assigner=assign_passage_groups,
) -> tuple[dict[str, str], dict[str, str]]:
    groups = parser(session, url)
    units: list[dict] = []
    for chapter_path in list_chapter_paths(book_id):
        units.extend(reading_units(read_json(chapter_path)))
    return assigner(units, groups)


def build_daodejing_assignments(session: requests.Session) -> tuple[dict[str, str], dict[str, str]]:
    assignments, source_texts = build_full_page_assignments(
        session,
        "daodejing",
        parse_daodejing_groups,
        "https://chinesenotes.com/daodejing/daodejing001.html",
    )

    sections = parse_wikisource_numbered_sections(
        session,
        "https://en.wikisource.org/wiki/Tao_Teh_King",
    )
    for chapter_path in list_chapter_paths("daodejing"):
        document = read_json(chapter_path)
        order = document["chapter"]["order"]
        if order not in sections:
            continue
        chapter_units = reading_units(document)
        pieces = split_translation(sections[order], len(chapter_units))
        for unit, piece in zip(chapter_units, pieces):
            if not has_translation(unit):
                assignments[unit["id"]] = piece

    return assignments, source_texts


def build_qianzi_assignments(session: requests.Session) -> tuple[dict[str, str], dict[str, str]]:
    entries = parse_chinasage_qianzi_entries(
        session,
        "https://www.chinasage.info/1000character-classic.htm",
    )
    units: list[dict] = []
    for chapter_path in list_chapter_paths("qian-zi-wen"):
        units.extend(reading_units(read_json(chapter_path)))

    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}
    entry_chunks = [canonical_zh(entry_zh) for entry_zh, _ in entries]
    entry_index = 0
    for unit in units:
        unit_text = canonical_zh(unit["text"])
        end, accumulated, _ = best_match_end(entry_chunks, entry_index, unit_text, 2)
        if end is None or not texts_match(accumulated, unit_text):
            continue
        covered_entries = entries[entry_index:end]
        assignments[unit["id"]] = clean_translation_text(
            " ".join(entry_en for _, entry_en in covered_entries)
        )
        merged_source = "".join(entry_zh for entry_zh, _ in covered_entries)
        if Counter(canonical_zh(merged_source)) == Counter(unit_text) and canonical_zh(merged_source) != unit_text:
            entry_index = end
            continue
        if len(merged_source) == 8 and len(split_cjk_runs(unit["text"])) == 2:
            source_texts[unit["id"]] = replace_cjk_runs(
                unit["text"],
                [merged_source[:4], merged_source[4:]],
            )
        else:
            source_texts[unit["id"]] = merged_source
        entry_index = end
    return assignments, source_texts


def build_sanzi_assignments(session: requests.Session) -> tuple[dict[str, str], dict[str, str]]:
    phrases = parse_wikisource_sanzi_phrases(
        session,
        "https://en.wikisource.org/wiki/San_Tzu_Ching/San_Tzu_Ching",
    )
    units: list[dict] = []
    for chapter_path in list_chapter_paths("san-zi-jing"):
        units.extend(reading_units(read_json(chapter_path)))
    return assign_flexible_groups(
        units,
        phrases,
        max_unit_span=4,
        max_group_span=20,
        source_text_builder=lambda unit, covered_groups: format_sanzi_source_text(
            [zh for zh, _ in covered_groups]
        ),
    )


def build_sunzi_assignments(session: requests.Session) -> tuple[dict[str, str], dict[str, str]]:
    chapter_groups = parse_sunzi_chapter_groups(
        session,
        "https://chinesenotes.com/sunzibingfa/sunzibingfa001.html",
    )
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}

    for chapter_index, chapter_path in enumerate(list_chapter_paths("sunzi-bingfa")):
        document = read_json(chapter_path)
        chapter_units = reading_units(document)
        if chapter_index >= len(chapter_groups):
            break
        groups = chapter_groups[chapter_index]
        if not groups:
            continue
        chapter_assignments, chapter_source_texts = assign_units_by_containment(
            chapter_units,
            groups,
        )
        assignments.update(chapter_assignments)
        source_texts.update(chapter_source_texts)

        # Debug: show per-chapter stats
        total_units = len(chapter_units)
        matched_units = len(chapter_assignments)
        print(f"  Ch{chapter_index+1:02d}: {matched_units}/{total_units} units matched")

    # Fix known source typo: Giles Ch13 has "water" where "war" is intended
    for unit_id, translation in assignments.items():
        if "element in water" in translation:
            assignments[unit_id] = translation.replace("element in water", "element in war")
    return assignments, source_texts


def build_sanguo_assignments(session: requests.Session) -> tuple[dict[str, str], dict[str, str]]:
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}
    for chapter_path in list_chapter_paths("sanguo-yanyi"):
        document = read_json(chapter_path)
        order = document["chapter"]["order"]
        chapter_units = reading_units(document)

        chapter_assignments = assign_english_paragraphs_by_length(
            chapter_units,
            parse_sanguo_english_paragraphs(session, order),
        )
        if order <= 19:
            exact_assignments, chapter_source_texts = assign_flexible_groups(
                chapter_units,
                parse_rotk_translation_groups(session, order),
                max_unit_span=4,
                max_group_span=6,
            )
            chapter_assignments.update(exact_assignments)
            source_texts.update(chapter_source_texts)

        assignments.update(chapter_assignments)

    return assignments, source_texts


def build_chengyu_assignments(session: requests.Session) -> tuple[dict[str, str], dict[str, str]]:
    assignments: dict[str, str] = {}
    source_texts: dict[str, str] = {}
    for chapter_path in list_chapter_paths("chengyu-catalog"):
        document = read_json(chapter_path)
        for unit in reading_units(document):
            if has_translation(unit):
                continue
            translation = fetch_chengyu_translation(session, unit["text"])
            if not translation:
                translation = fetch_cc_cedict_translation(session, unit["text"])
            if not translation:
                translation = fetch_wiktionary_translation(session, unit["text"])
            if not translation:
                translation = fetch_google_translation(session, unit["text"])
            if translation:
                assignments[unit["id"]] = clean_translation_text(translation)
    return assignments, source_texts


def import_book(session: requests.Session, book_id: str) -> tuple[int, int, int]:
    replace_generated = False
    if book_id == "lunyu":
        assignments, source_texts = build_chinese_notes_chapter_assignments(
            session,
            book_id,
            "https://chinesenotes.com/lunyu/lunyu{order:03d}.html",
        )
    elif book_id == "mengzi":
        assignments, source_texts = build_wikisource_chapter_assignments(
            session,
            book_id,
            "https://en.wikisource.org/wiki/The_Chinese_Classics/Volume_2/The_Works_of_Mencius/chapter{order:02d}",
            parse_wikisource_paragraph_pairs,
            assigner=assign_flexible_groups,
            max_unit_span=8,
            max_group_span=16,
        )
    elif book_id == "sanguo-yanyi":
        assignments, source_texts = build_sanguo_assignments(session)
        replace_generated = True
    elif book_id == "daodejing":
        assignments, source_texts = build_daodejing_assignments(session)
    elif book_id == "sunzi-bingfa":
        assignments, source_texts = build_sunzi_assignments(session)
        replace_generated = True
    elif book_id == "zhong-yong":
        assignments, source_texts = build_full_page_assignments(
            session,
            book_id,
            parse_wikisource_paragraph_pairs,
            "https://en.wikisource.org/wiki/The_Chinese_Classics/Volume_1/The_Doctrine_of_the_Mean",
        )
    elif book_id == "da-xue":
        assignments, source_texts = build_full_page_assignments(
            session,
            book_id,
            parse_wikisource_paragraph_pairs,
            "https://en.wikisource.org/wiki/The_Chinese_Classics/Volume_1/The_Great_Learning",
        )
    elif book_id == "san-zi-jing":
        assignments, source_texts = build_sanzi_assignments(session)
    elif book_id == "qian-zi-wen":
        assignments, source_texts = build_qianzi_assignments(session)
    elif book_id == "chengyu-catalog":
        assignments, source_texts = build_chengyu_assignments(session)
    else:
        raise ValueError(f"unsupported book {book_id}")

    return apply_assignments(
        list_chapter_paths(book_id),
        assignments,
        source_texts,
        replace_generated=replace_generated,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--book",
        action="append",
        dest="books",
        help="Limit the import to one or more book ids.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    selected_books = args.books or [
        "chengyu-catalog",
        "da-xue",
        "daodejing",
        "lunyu",
        "mengzi",
        "qian-zi-wen",
        "san-zi-jing",
        "sanguo-yanyi",
        "sunzi-bingfa",
        "zhong-yong",
    ]

    session = build_session()
    chapters_updated = 0
    units_updated = 0
    texts_updated = 0
    for book_id in selected_books:
        updated_chapters, updated_units, updated_texts = import_book(session, book_id)
        chapters_updated += updated_chapters
        units_updated += updated_units
        texts_updated += updated_texts
        print(
            f"{book_id}: updated {updated_units} translations and {updated_texts} source texts across {updated_chapters} chapters"
        )

    print(
        f"total: updated {units_updated} translations and {texts_updated} source texts across {chapters_updated} chapters"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
