import importlib.util
import json
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1]
MODULE_PATH = TOOLS_DIR / "expand_chengyu_catalog.py"
SPEC = importlib.util.spec_from_file_location("expand_chengyu_catalog", MODULE_PATH)
EXPAND_CHENGYU_CATALOG = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(EXPAND_CHENGYU_CATALOG)


class ExpandChengyuCatalogTest(unittest.TestCase):
    def test_select_additional_words_prefers_diversity_before_relaxing(self) -> None:
        additional = EXPAND_CHENGYU_CATALOG.select_additional_words(
            existing_words=["持之以恒"],
            target_total=3,
            upstream_rows=[
                {"word": "甲乙丙丁", "explanation": "甲乙丙丁", "derivation": ""},
                {"word": "丁丙乙甲", "explanation": "甲乙丙丁", "derivation": ""},
                {"word": "天地玄黄", "explanation": "天地玄黄", "derivation": ""},
            ],
            current_char_counts=EXPAND_CHENGYU_CATALOG.collections.Counter(),
            curriculum_char_counts=EXPAND_CHENGYU_CATALOG.collections.Counter(),
        )

        self.assertEqual(additional, ["甲乙丙丁", "天地玄黄"])

    def test_bundled_catalog_has_3000_translated_four_character_entries(self) -> None:
        catalog = json.loads(
            (
                TOOLS_DIR.parent
                / "content"
                / "books"
                / "chengyu-catalog"
                / "catalog.json"
            ).read_text(encoding="utf-8")
        )
        chapters_dir = TOOLS_DIR.parent / "content" / "books" / "chengyu-catalog" / "chapters"

        self.assertEqual(catalog["chapter_count"], 100)
        self.assertEqual(len(catalog["chapters"]), 100)

        total_units = 0
        for chapter_entry in catalog["chapters"]:
            chapter_path = TOOLS_DIR.parent / "content" / chapter_entry["chapter_path"]
            payload = json.loads(chapter_path.read_text(encoding="utf-8"))["chapter"]

            self.assertEqual(payload["reading_unit_count"], 30)
            self.assertEqual(len(payload["reading_units"]), 30)
            self.assertEqual(payload["character_count"], 120)
            self.assertEqual(
                payload["title"],
                f"{(chapter_entry['order'] - 1) * 30 + 1}-{chapter_entry['order'] * 30}",
            )

            for unit in payload["reading_units"]:
                self.assertEqual(len(unit["text"]), 4)
                layers = ((unit.get("generated_annotation") or {}).get("layers") or {})
                translation = (
                    unit.get("translation_en")
                    or layers.get("translation_en")
                    or ""
                ).strip()
                self.assertTrue(translation, msg=f"missing translation for {unit['text']}")
                total_units += 1

        self.assertEqual(total_units, 3000)


if __name__ == "__main__":
    unittest.main()
