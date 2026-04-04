import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "generate_character_index.py"
SPEC = importlib.util.spec_from_file_location("generate_character_index", MODULE_PATH)
GENERATE_CHARACTER_INDEX = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(GENERATE_CHARACTER_INDEX)


class GenerateCharacterIndexTest(unittest.TestCase):
    def test_enrich_with_deterministic_component_characters_adds_only_complete_entries(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)
            components_path = (
                content_root
                / "references"
                / "hanzi"
                / "modern-common-components-gf0014-2009-grouped.json"
            )
            components_path.parent.mkdir(parents=True)
            components_path.write_text(
                json.dumps(
                    {
                        "entries": [
                            {
                                "group_id": 1,
                                "canonical_form": "卄",
                                "forms": ["卄"],
                                "variant_forms": [],
                            },
                            {
                                "group_id": 2,
                                "canonical_form": "冃",
                                "forms": ["冃"],
                                "variant_forms": [],
                            },
                            {
                                "group_id": 3,
                                "canonical_form": "{⿱一丰}",
                                "forms": [],
                                "variant_forms": [],
                            },
                        ]
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            entries: dict[str, dict] = {}
            report = (
                GENERATE_CHARACTER_INDEX.enrich_with_deterministic_component_characters(
                    entries=entries,
                    content_root=content_root,
                    seed_index_entries={},
                    manual_seed_entries={},
                    dictionary={
                        "卄": {
                            "pinyin": ["niàn"],
                            "definition": "twenty, twentieth",
                            "decomposition": "⿱艹十",
                        },
                        "冃": {
                            "pinyin": ["mào"],
                            "definition": "",
                            "decomposition": "⿵冂二",
                        },
                    },
                    unihan={},
                    ids_data={
                        "卄": "⿱艹十",
                        "冃": "⿵冂二",
                    },
                    ts_map={},
                    st_map={},
                    reasonable_component_forms={"卄", "冃"},
                    decomposition_lookup={},
                )
            )

            self.assertEqual(report["component_character_candidates"], 2)
            self.assertEqual(report["component_character_entries_added"], 1)
            self.assertEqual(report["component_character_entries_skipped"], 1)

            self.assertIn("卄", entries)
            self.assertNotIn("冃", entries)
            self.assertEqual(entries["卄"]["pinyin"], ["niàn"])
            self.assertEqual(entries["卄"]["zhuyin"], ["ㄋㄧㄢˋ"])
            self.assertEqual(entries["卄"]["english"], ["twenty, twentieth"])


if __name__ == "__main__":
    unittest.main()
