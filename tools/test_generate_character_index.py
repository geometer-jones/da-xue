import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("generate_character_index.py")
SPEC = importlib.util.spec_from_file_location("generate_character_index", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"failed to load module from {MODULE_PATH}")

generate_character_index = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generate_character_index)


class GenerateCharacterIndexTests(unittest.TestCase):
    def test_collect_unique_characters_reads_all_book_json_strings_and_extended_cjk(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)
            catalog_path = content_root / "books" / "demo" / "catalog.json"
            catalog_path.parent.mkdir(parents=True)
            catalog_path.write_text(
                json.dumps(
                    {
                        "book": {
                            "title": "學而",
                            "summary": "𩅦德",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            commentary_path = (
                content_root
                / "books"
                / "demo"
                / "commentary"
                / "commentary-001.json"
            )
            commentary_path.parent.mkdir(parents=True)
            commentary_path.write_text(
                json.dumps(
                    {
                        "commentary": {
                            "text": "止於至善",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                generate_character_index.collect_unique_characters(content_root),
                sorted(["學", "而", "𩅦", "德", "止", "於", "至", "善"]),
            )

    def test_build_phrase_usage_reads_non_chapter_book_json_content(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)
            catalog_path = content_root / "books" / "demo" / "catalog.json"
            catalog_path.parent.mkdir(parents=True)
            catalog_path.write_text(
                json.dumps(
                    {
                        "book": {
                            "title": "學而時習之",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            commentary_path = (
                content_root
                / "books"
                / "demo"
                / "commentary"
                / "commentary-001.json"
            )
            commentary_path.parent.mkdir(parents=True)
            commentary_path.write_text(
                json.dumps(
                    {
                        "commentary": {
                            "text": "止於至善",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            usage = generate_character_index.build_phrase_usage(content_root, {}, {})

            self.assertIn("學而時習之", usage["學"])
            self.assertIn("止於至善", usage["於"])

    def test_build_phrase_usage_prefers_pedagogical_sort_for_examples(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)
            chapter_path = content_root / "books" / "da-xue" / "chapters" / "chapter-001.json"
            chapter_path.parent.mkdir(parents=True)
            chapter_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "text": "大道。天下有道。",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            usage = generate_character_index.build_phrase_usage(content_root, {}, {})

            self.assertEqual(usage["道"][:2], ["大道", "天下有道"])

    def test_normalize_phrase_candidate_strips_wrapping_punctuation(self) -> None:
        self.assertEqual(
            generate_character_index.normalize_phrase_candidate("「學而時習之」"),
            "學而時習之",
        )

    def test_build_explosion_keeps_trailing_components_from_non_strict_ids_sequences(self) -> None:
        explosion = generate_character_index.build_explosion("⿱⺍冖子")

        self.assertEqual(
            explosion["analysis"],
            {
                "expression": "⺍ + 冖 + 子",
                "parts": ["⺍", "冖", "子"],
            },
        )

    def test_build_explosion_collapses_nested_subtrees_to_reasonable_units(self) -> None:
        explosion = generate_character_index.build_explosion(
            "⿰彳⿱十⿻罒一心",
            decomposition_lookup={
                "⿱十⿻罒一": "直",
            },
        )

        self.assertEqual(
            explosion["analysis"],
            {
                "expression": "彳 + 直 + 心",
                "parts": ["彳", "直", "心"],
            },
        )

    def test_build_explosion_strips_trailing_ids_annotations(self) -> None:
        explosion = generate_character_index.build_explosion("⿱⿱羊䒑口[GJK]")

        self.assertEqual(
            explosion["analysis"],
            {
                "expression": "羊 + 䒑 + 口",
                "parts": ["羊", "䒑", "口"],
            },
        )

    def test_build_explosion_expands_obscure_leaf_components_via_ids_data(self) -> None:
        explosion = generate_character_index.build_explosion(
            "⿰彳𢛳",
            decomposition_lookup={
                "⿳十罒一": "直",
            },
            nested_ids_data={
                "𢛳": "⿱⿳十罒一心",
            },
            reasonable_component_forms={"直", "彳", "心"},
        )

        self.assertEqual(
            explosion["analysis"],
            {
                "expression": "彳 + 直 + 心",
                "parts": ["彳", "直", "心"],
            },
        )

    def test_build_reasonable_decomposition_lookup_skips_obscure_aliases(self) -> None:
        lookup = generate_character_index.build_reasonable_decomposition_lookup(
            dictionary={
                "吾": {
                    "decomposition": "⿱五口",
                },
                "𰃮": {
                    "decomposition": "⿱⺍冖",
                },
            },
            ids_data={},
            reasonable_component_forms=set(),
        )

        self.assertEqual(
            lookup,
            {
                "⿱五口": "吾",
                "⿳十罒一": "直",
            },
        )

    def test_choose_preferred_explosion_prefers_cleaner_ids_decomposition(self) -> None:
        explosion = generate_character_index.choose_preferred_explosion(
            [
                "⿱羊⿱⿱丷一口",
                "⿱⿱羊䒑口[GJK]",
            ],
            decomposition_lookup=None,
            reasonable_component_forms={"䒑"},
        )

        self.assertEqual(
            explosion["analysis"],
            {
                "expression": "羊 + 䒑 + 口",
                "parts": ["羊", "䒑", "口"],
            },
        )

    def test_choose_preferred_explosion_rejects_obscure_ids_aliases(self) -> None:
        explosion = generate_character_index.choose_preferred_explosion(
            [
                "⿰彳⿱⿱十罒⿱一心",
                "⿰彳𢛳",
            ],
            decomposition_lookup=None,
            reasonable_component_forms={"彳", "罒", "心"},
        )

        self.assertEqual(
            explosion["analysis"],
            {
                "expression": "彳 + 十 + 罒 + 一 + 心",
                "parts": ["彳", "十", "罒", "一", "心"],
            },
        )

    def test_choose_preferred_explosion_avoids_supplementary_plane_components(self) -> None:
        explosion = generate_character_index.choose_preferred_explosion(
            [
                "⿱⿱⺍冖子",
                "⿳𭕄冖子",
                "⿱𦥯子",
            ],
            decomposition_lookup=None,
            reasonable_component_forms={"𭕄"},
        )

        self.assertEqual(
            explosion["analysis"],
            {
                "expression": "⺍ + 冖 + 子",
                "parts": ["⺍", "冖", "子"],
            },
        )

    def test_extract_gloss_phrases_normalizes_articles_and_infinitives(self) -> None:
        phrases = generate_character_index.extract_gloss_phrases(
            ["a tower, pagoda", "to laugh", "the ferry"]
        )

        self.assertIn("a tower", phrases)
        self.assertIn("tower", phrases)
        self.assertIn("to laugh", phrases)
        self.assertIn("laugh", phrases)
        self.assertIn("the ferry", phrases)
        self.assertIn("ferry", phrases)

    def test_seed_entry_can_fill_missing_deterministic_fields(self) -> None:
        payload = {
            "entries": [
                {
                    "character": "学",
                    "simplified": "学",
                    "traditional": "學",
                    "pinyin": ["xué"],
                    "zhuyin": ["ㄒㄩㄝˊ"],
                    "english": ["to study", "learning"],
                    "explosion": {
                        "analysis": {
                            "expression": "子 + 冖 + 爻",
                            "parts": ["子", "冖", "爻"],
                        },
                        "synthesis": {
                            "containingCharacters": [],
                            "phraseUse": [],
                            "homophones": {
                                "sameTone": [],
                                "differentTone": [],
                            },
                        },
                        "meaningMap": {
                            "synonyms": ["学习"],
                            "antonyms": ["忘"],
                        },
                    },
                }
            ]
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            seed_path = Path(temp_dir) / "index.json"
            seed_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

            seed_entries = generate_character_index.load_seed_entries(seed_path)
            seed_entry = generate_character_index.find_seed_entry(seed_entries, "学", "學")
            merged = generate_character_index.merge_entries(
                {
                    "character": "学",
                    "simplified": "学",
                    "traditional": "學",
                    "pinyin": [],
                    "zhuyin": [],
                    "english": [],
                    "explosion": generate_character_index.build_explosion(""),
                },
                seed_entry,
            )

        self.assertTrue(generate_character_index.is_complete_entry(merged))
        self.assertEqual(merged["explosion"]["meaningMap"]["synonyms"], ["学习"])
        self.assertEqual(merged["explosion"]["meaningMap"]["antonyms"], ["忘"])

    def test_manual_seed_can_override_existing_gloss_fields(self) -> None:
        merged = generate_character_index.apply_seed_overrides(
            {
                "character": "水",
                "simplified": "水",
                "traditional": "水",
                "pinyin": ["shuǐ"],
                "zhuyin": ["ㄕㄨㄟˇ"],
                "english": ["water, liquid, lotion, juice"],
                "explosion": generate_character_index.build_explosion("水"),
            },
            {
                "character": "水",
                "simplified": "水",
                "traditional": "水",
                "english": ["water, liquid"],
            },
        )

        self.assertEqual(merged["pinyin"], ["shuǐ"])
        self.assertEqual(merged["zhuyin"], ["ㄕㄨㄟˇ"])
        self.assertEqual(merged["english"], ["water, liquid"])

    def test_apply_entry_aliases_keeps_only_non_primary_variant_forms(self) -> None:
        entry = generate_character_index.apply_entry_aliases(
            {
                "character": "为",
                "simplified": "为",
                "traditional": "爲",
                "aliases": ["僞"],
                "pinyin": ["wèi"],
                "zhuyin": ["ㄨㄟˋ"],
                "english": ["to do, to act"],
                "explosion": generate_character_index.build_explosion("为"),
            },
            ["為", "爲", "为", " 為 "],
        )

        self.assertEqual(entry["aliases"], ["僞", "為"])

    def test_prefer_corpus_traditional_variant_promotes_strongly_preferred_alias(self) -> None:
        entry = generate_character_index.prefer_corpus_traditional_variant(
            {
                "character": "为",
                "simplified": "为",
                "traditional": "爲",
                "aliases": ["為"],
                "pinyin": ["wèi"],
                "zhuyin": ["ㄨㄟˋ"],
                "english": ["to do, to act"],
                "explosion": generate_character_index.build_explosion("为"),
            },
            character_frequencies={"爲": 5, "為": 120},
            traditional_variants_by_simplified={"为": ["為", "爲"]},
        )

        self.assertEqual(entry["traditional"], "為")
        self.assertEqual(entry["aliases"], ["爲"])

    def test_prefer_corpus_traditional_variant_keeps_borderline_current_form(self) -> None:
        entry = generate_character_index.prefer_corpus_traditional_variant(
            {
                "character": "俊",
                "simplified": "俊",
                "traditional": "俊",
                "aliases": ["儁"],
                "pinyin": ["jùn"],
                "zhuyin": ["ㄐㄩㄣˋ"],
                "english": ["talented, handsome"],
                "explosion": generate_character_index.build_explosion("俊"),
            },
            character_frequencies={"俊": 52, "儁": 67},
            traditional_variants_by_simplified={"俊": ["儁"]},
        )

        self.assertEqual(entry["traditional"], "俊")
        self.assertEqual(entry["aliases"], ["儁"])

    def test_seed_entries_index_alias_forms_for_lookup(self) -> None:
        payload = {
            "entries": [
                {
                    "character": "为",
                    "simplified": "为",
                    "traditional": "爲",
                    "aliases": ["為"],
                    "pinyin": ["wèi"],
                    "zhuyin": ["ㄨㄟˋ"],
                    "english": ["to do, to act"],
                    "explosion": generate_character_index.build_explosion("为"),
                }
            ]
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            seed_path = Path(temp_dir) / "index.json"
            seed_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

            seed_entries = generate_character_index.load_seed_entries(seed_path)

        seed_entry = generate_character_index.find_seed_entry(seed_entries, "为", "為")

        self.assertIsNotNone(seed_entry)
        assert seed_entry is not None
        self.assertEqual(seed_entry["character"], "为")
        self.assertEqual(seed_entry["aliases"], ["為"])

    def test_seed_canonical_pairs_include_manual_seed_only_characters_once(self) -> None:
        payload = {
            "entries": [
                {
                    "character": "匕",
                    "simplified": "匕",
                    "traditional": "匕",
                    "pinyin": ["bǐ"],
                    "zhuyin": ["ㄅㄧˇ"],
                    "english": ["spoon, ladle", "knife, dirk"],
                },
                {
                    "character": "𩧻",
                    "simplified": "𩧻",
                    "traditional": "𩣵",
                    "pinyin": ["wǎn"],
                    "zhuyin": ["ㄨㄢˇ"],
                    "english": ["to stain", "to smudge", "to soil"],
                },
            ]
        }

        with tempfile.TemporaryDirectory() as temp_dir:
            seed_path = Path(temp_dir) / "manual-seed.json"
            seed_path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

            seed_entries = generate_character_index.load_seed_entries(seed_path)

        self.assertEqual(
            generate_character_index.seed_canonical_pairs(seed_entries),
            [("匕", "匕"), ("𩧻", "𩣵")],
        )

    def test_enrich_meaning_maps_adds_synonyms_and_antonyms(self) -> None:
        entries = {
            "道": generate_character_index.normalize_entry(
                {
                    "character": "道",
                    "simplified": "道",
                    "traditional": "道",
                    "pinyin": ["dào"],
                    "zhuyin": ["ㄉㄠˋ"],
                    "english": ["method, way", "path, road"],
                    "explosion": generate_character_index.build_explosion("⿺首辶"),
                }
            ),
            "路": generate_character_index.normalize_entry(
                {
                    "character": "路",
                    "simplified": "路",
                    "traditional": "路",
                    "pinyin": ["lù"],
                    "zhuyin": ["ㄌㄨˋ"],
                    "english": ["road, path, street"],
                    "explosion": generate_character_index.build_explosion("⿰足各"),
                }
            ),
            "善": generate_character_index.normalize_entry(
                {
                    "character": "善",
                    "simplified": "善",
                    "traditional": "善",
                    "pinyin": ["shàn"],
                    "zhuyin": ["ㄕㄢˋ"],
                    "english": ["good, virtuous, kind"],
                    "explosion": generate_character_index.build_explosion("⿱羊言"),
                }
            ),
            "恶": generate_character_index.normalize_entry(
                {
                    "character": "恶",
                    "simplified": "恶",
                    "traditional": "惡",
                    "pinyin": ["è"],
                    "zhuyin": ["ㄜˋ"],
                    "english": ["bad, evil, wicked"],
                    "explosion": generate_character_index.build_explosion("⿱亚心"),
                }
            ),
            "有": generate_character_index.normalize_entry(
                {
                    "character": "有",
                    "simplified": "有",
                    "traditional": "有",
                    "pinyin": ["yǒu"],
                    "zhuyin": ["ㄧㄡˇ"],
                    "english": ["to have, to own, to possess", "to exist"],
                    "explosion": generate_character_index.build_explosion("⿸𠂇月"),
                }
            ),
            "无": generate_character_index.normalize_entry(
                {
                    "character": "无",
                    "simplified": "无",
                    "traditional": "無",
                    "pinyin": ["wú"],
                    "zhuyin": ["ㄨˊ"],
                    "english": ["no, not", "lacking, -less"],
                    "explosion": generate_character_index.build_explosion("无"),
                }
            ),
        }

        generate_character_index.enrich_meaning_maps(entries)

        self.assertIn("路", entries["道"]["explosion"]["meaningMap"]["synonyms"])
        self.assertIn("恶", entries["善"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("有", entries["无"]["explosion"]["meaningMap"]["antonyms"])

    def test_enrich_meaning_maps_adds_common_antonym_pairs(self) -> None:
        entries = {
            "高": generate_character_index.normalize_entry(
                {
                    "character": "高",
                    "simplified": "高",
                    "traditional": "高",
                    "pinyin": ["gāo"],
                    "zhuyin": ["ㄍㄠ"],
                    "english": ["tall, lofty", "high, elevated"],
                    "explosion": generate_character_index.build_explosion("⿳亠口冋"),
                }
            ),
            "低": generate_character_index.normalize_entry(
                {
                    "character": "低",
                    "simplified": "低",
                    "traditional": "低",
                    "pinyin": ["dī"],
                    "zhuyin": ["ㄉㄧ"],
                    "english": ["low", "to lower, to hang", "to bend, to bow"],
                    "explosion": generate_character_index.build_explosion("⿰亻氐"),
                }
            ),
            "来": generate_character_index.normalize_entry(
                {
                    "character": "来",
                    "simplified": "来",
                    "traditional": "來",
                    "pinyin": ["lái"],
                    "zhuyin": ["ㄌㄞˊ"],
                    "english": ["to arrive, to come, to return", "in the future, later on"],
                    "explosion": generate_character_index.build_explosion("⿻木从"),
                }
            ),
            "去": generate_character_index.normalize_entry(
                {
                    "character": "去",
                    "simplified": "去",
                    "traditional": "去",
                    "pinyin": ["qù"],
                    "zhuyin": ["ㄑㄩˋ"],
                    "english": ["to go away, to leave, to depart"],
                    "explosion": generate_character_index.build_explosion("⿱土厶"),
                }
            ),
            "前": generate_character_index.normalize_entry(
                {
                    "character": "前",
                    "simplified": "前",
                    "traditional": "前",
                    "pinyin": ["qián"],
                    "zhuyin": ["ㄑㄧㄢˊ"],
                    "english": ["in front, forward", "former, preceding"],
                    "explosion": generate_character_index.build_explosion("⿱䒑刖"),
                }
            ),
            "后": generate_character_index.normalize_entry(
                {
                    "character": "后",
                    "simplified": "后",
                    "traditional": "後",
                    "pinyin": ["hòu"],
                    "zhuyin": ["ㄏㄡˋ"],
                    "english": ["after", "behind, rear", "descendants"],
                    "explosion": generate_character_index.build_explosion("⿸𠂆口"),
                }
            ),
            "多": generate_character_index.normalize_entry(
                {
                    "character": "多",
                    "simplified": "多",
                    "traditional": "多",
                    "pinyin": ["duō"],
                    "zhuyin": ["ㄉㄨㄛ"],
                    "english": ["much, many, multi-", "more than, over"],
                    "explosion": generate_character_index.build_explosion("⿱夕夕"),
                }
            ),
            "少": generate_character_index.normalize_entry(
                {
                    "character": "少",
                    "simplified": "少",
                    "traditional": "少",
                    "pinyin": ["shǎo"],
                    "zhuyin": ["ㄕㄠˇ"],
                    "english": ["few, little", "less", "inadequate"],
                    "explosion": generate_character_index.build_explosion("少"),
                }
            ),
        }

        generate_character_index.enrich_meaning_maps(entries)

        self.assertIn("低", entries["高"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("高", entries["低"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("去", entries["来"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("来", entries["去"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("后", entries["前"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("前", entries["后"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("少", entries["多"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("多", entries["少"]["explosion"]["meaningMap"]["antonyms"])

    def test_extract_gloss_reference_characters_reads_same_as_and_variant_forms(self) -> None:
        references = generate_character_index.extract_gloss_reference_characters(
            [
                "(same as 襄) to help",
                "(variant of 幮 𢅥) a screen used to make a temporary kitchen",
            ]
        )

        self.assertEqual(references, ["襄", "幮", "𢅥"])

    def test_enrich_meaning_maps_promotes_gloss_references_into_synonyms(self) -> None:
        entries = {
            "双": generate_character_index.normalize_entry(
                {
                    "character": "双",
                    "simplified": "双",
                    "traditional": "雙",
                    "pinyin": ["shuāng"],
                    "zhuyin": ["ㄕㄨㄤ"],
                    "english": ["a pair", "double"],
                    "explosion": generate_character_index.build_explosion("⿰又又"),
                }
            ),
            "㕠": generate_character_index.normalize_entry(
                {
                    "character": "㕠",
                    "simplified": "㕠",
                    "traditional": "㕠",
                    "pinyin": ["shuāng"],
                    "zhuyin": ["ㄕㄨㄤ"],
                    "english": ["(same as 雙) a pair", "a couple, both, two, double, even"],
                    "explosion": generate_character_index.build_explosion("㕠"),
                }
            ),
        }

        generate_character_index.enrich_meaning_maps(entries)

        self.assertIn("双", entries["㕠"]["explosion"]["meaningMap"]["synonyms"])

    def test_enrich_meaning_maps_inherits_phrase_use_and_antonyms_from_gloss_reference(self) -> None:
        entries = {
            "新": generate_character_index.normalize_entry(
                {
                    "character": "新",
                    "simplified": "新",
                    "traditional": "新",
                    "pinyin": ["xīn"],
                    "zhuyin": ["ㄒㄧㄣ"],
                    "english": ["new, recent, fresh, modern"],
                    "explosion": {
                        "analysis": {"expression": "亲 + 斤", "parts": ["亲", "斤"]},
                        "synthesis": {
                            "containingCharacters": [],
                            "phraseUse": ["日新又新", "清新俊逸"],
                            "homophones": {
                                "sameTone": [],
                                "differentTone": [],
                            },
                        },
                        "meaningMap": {
                            "synonyms": [],
                            "antonyms": ["古", "旧"],
                        },
                    },
                }
            ),
            "㜛": generate_character_index.normalize_entry(
                {
                    "character": "㜛",
                    "simplified": "㜛",
                    "traditional": "㜛",
                    "pinyin": ["nèn"],
                    "zhuyin": ["ㄋㄣˋ"],
                    "english": ["(same as 嫩) soft and tender", "delicate, weak"],
                    "explosion": generate_character_index.build_explosion("㜛"),
                }
            ),
            "嫩": generate_character_index.normalize_entry(
                {
                    "character": "嫩",
                    "simplified": "嫩",
                    "traditional": "嫩",
                    "pinyin": ["nèn"],
                    "zhuyin": ["ㄋㄣˋ"],
                    "english": ["new, tender, delicate"],
                    "explosion": {
                        "analysis": {"expression": "女 + 敕", "parts": ["女", "敕"]},
                        "synthesis": {
                            "containingCharacters": [],
                            "phraseUse": ["嫩草綠凝煙"],
                            "homophones": {
                                "sameTone": [],
                                "differentTone": [],
                            },
                        },
                        "meaningMap": {
                            "synonyms": [],
                            "antonyms": ["旧"],
                        },
                    },
                }
            ),
        }

        generate_character_index.enrich_meaning_maps(entries)

        self.assertIn("嫩草綠凝煙", entries["㜛"]["explosion"]["synthesis"]["phraseUse"])
        self.assertIn("旧", entries["㜛"]["explosion"]["meaningMap"]["antonyms"])

    def test_enrich_meaning_maps_inherits_phrase_use_from_synonyms_when_empty(self) -> None:
        entries = {
            "甲": generate_character_index.normalize_entry(
                {
                    "character": "甲",
                    "simplified": "甲",
                    "traditional": "甲",
                    "pinyin": ["jiǎ"],
                    "zhuyin": ["ㄐㄧㄚˇ"],
                    "english": ["first, best"],
                    "explosion": {
                        "analysis": {"expression": "甲", "parts": ["甲"]},
                        "synthesis": {
                            "containingCharacters": [],
                            "phraseUse": [],
                            "homophones": {
                                "sameTone": [],
                                "differentTone": [],
                            },
                        },
                        "meaningMap": {
                            "synonyms": ["优"],
                            "antonyms": [],
                        },
                    },
                }
            ),
            "优": generate_character_index.normalize_entry(
                {
                    "character": "优",
                    "simplified": "优",
                    "traditional": "優",
                    "pinyin": ["yōu"],
                    "zhuyin": ["ㄧㄡ"],
                    "english": ["excellent, superior"],
                    "explosion": {
                        "analysis": {"expression": "亻 + 尤", "parts": ["亻", "尤"]},
                        "synthesis": {
                            "containingCharacters": [],
                            "phraseUse": ["品学兼优", "优柔寡断"],
                            "homophones": {
                                "sameTone": [],
                                "differentTone": [],
                            },
                        },
                        "meaningMap": {
                            "synonyms": [],
                            "antonyms": [],
                        },
                    },
                }
            ),
        }

        generate_character_index.enrich_meaning_maps(entries)

        self.assertIn("品学兼优", entries["甲"]["explosion"]["synthesis"]["phraseUse"])

    def test_enrich_meaning_maps_prefers_basic_related_characters(self) -> None:
        ranked = generate_character_index.rank_related_characters(
            ["㪓", "恶", "弊", "歹"],
            {
                "㪓": generate_character_index.normalize_entry(
                    {
                        "character": "㪓",
                        "simplified": "㪓",
                        "traditional": "㪓",
                        "pinyin": ["chuí"],
                        "zhuyin": ["ㄔㄨㄟˊ"],
                        "english": ["bad"],
                        "explosion": generate_character_index.build_explosion("㪓"),
                    }
                ),
                "恶": generate_character_index.normalize_entry(
                    {
                        "character": "恶",
                        "simplified": "恶",
                        "traditional": "惡",
                        "pinyin": ["è"],
                        "zhuyin": ["ㄜˋ"],
                        "english": ["bad, evil, wicked"],
                        "explosion": {
                            "analysis": {"expression": "亚 + 心", "parts": ["亚", "心"]},
                            "synthesis": {
                                "containingCharacters": [],
                                "phraseUse": ["惩恶扬善"],
                                "homophones": {
                                    "sameTone": [],
                                    "differentTone": [],
                                },
                            },
                            "meaningMap": {
                                "synonyms": [],
                                "antonyms": [],
                            },
                        },
                    }
                ),
                "弊": generate_character_index.normalize_entry(
                    {
                        "character": "弊",
                        "simplified": "弊",
                        "traditional": "弊",
                        "pinyin": ["bì"],
                        "zhuyin": ["ㄅㄧˋ"],
                        "english": ["harm, evil"],
                        "explosion": generate_character_index.build_explosion("弊"),
                    }
                ),
                "歹": generate_character_index.normalize_entry(
                    {
                        "character": "歹",
                        "simplified": "歹",
                        "traditional": "歹",
                        "pinyin": ["dǎi"],
                        "zhuyin": ["ㄉㄞˇ"],
                        "english": ["bad, evil"],
                        "explosion": generate_character_index.build_explosion("歹"),
                    }
                ),
            },
        )

        self.assertEqual(ranked[:3], ["恶", "弊", "歹"])

    def test_enrich_meaning_maps_adds_curriculum_antonym_overrides(self) -> None:
        entries = {
            "德": generate_character_index.normalize_entry(
                {
                    "character": "德",
                    "simplified": "德",
                    "traditional": "德",
                    "pinyin": ["dé"],
                    "zhuyin": ["ㄉㄜˊ"],
                    "english": ["ethics, morality", "compassion, kindness"],
                    "explosion": generate_character_index.build_explosion("⿰彳直心"),
                }
            ),
            "恶": generate_character_index.normalize_entry(
                {
                    "character": "恶",
                    "simplified": "恶",
                    "traditional": "惡",
                    "pinyin": ["è"],
                    "zhuyin": ["ㄜˋ"],
                    "english": ["bad, evil, wicked"],
                    "explosion": generate_character_index.build_explosion("⿱亚心"),
                }
            ),
            "止": generate_character_index.normalize_entry(
                {
                    "character": "止",
                    "simplified": "止",
                    "traditional": "止",
                    "pinyin": ["zhǐ"],
                    "zhuyin": ["ㄓˇ"],
                    "english": ["to stop, to halt", "to desist"],
                    "explosion": generate_character_index.build_explosion("止"),
                }
            ),
            "行": generate_character_index.normalize_entry(
                {
                    "character": "行",
                    "simplified": "行",
                    "traditional": "行",
                    "pinyin": ["xíng"],
                    "zhuyin": ["ㄒㄧㄥˊ"],
                    "english": ["to go, to walk, to move"],
                    "explosion": generate_character_index.build_explosion("行"),
                }
            ),
            "亲": generate_character_index.normalize_entry(
                {
                    "character": "亲",
                    "simplified": "亲",
                    "traditional": "親",
                    "pinyin": ["qīn"],
                    "zhuyin": ["ㄑㄧㄣ"],
                    "english": ["intimate", "relatives, parents"],
                    "explosion": generate_character_index.build_explosion("亲"),
                }
            ),
            "疏": generate_character_index.normalize_entry(
                {
                    "character": "疏",
                    "simplified": "疏",
                    "traditional": "疏",
                    "pinyin": ["shū"],
                    "zhuyin": ["ㄕㄨ"],
                    "english": ["distant", "estranged"],
                    "explosion": generate_character_index.build_explosion("疏"),
                }
            ),
            "东": generate_character_index.normalize_entry(
                {
                    "character": "东",
                    "simplified": "东",
                    "traditional": "東",
                    "pinyin": ["dōng"],
                    "zhuyin": ["ㄉㄨㄥ"],
                    "english": ["east, eastern, eastward"],
                    "explosion": generate_character_index.build_explosion("东"),
                }
            ),
            "西": generate_character_index.normalize_entry(
                {
                    "character": "西",
                    "simplified": "西",
                    "traditional": "西",
                    "pinyin": ["xī"],
                    "zhuyin": ["ㄒㄧ"],
                    "english": ["west, western, westward"],
                    "explosion": generate_character_index.build_explosion("西"),
                }
            ),
            "南": generate_character_index.normalize_entry(
                {
                    "character": "南",
                    "simplified": "南",
                    "traditional": "南",
                    "pinyin": ["nán"],
                    "zhuyin": ["ㄋㄢˊ"],
                    "english": ["south, southern, southward"],
                    "explosion": generate_character_index.build_explosion("南"),
                }
            ),
            "北": generate_character_index.normalize_entry(
                {
                    "character": "北",
                    "simplified": "北",
                    "traditional": "北",
                    "pinyin": ["běi"],
                    "zhuyin": ["ㄅㄟˇ"],
                    "english": ["north, northern, northward"],
                    "explosion": generate_character_index.build_explosion("北"),
                }
            ),
            "未": generate_character_index.normalize_entry(
                {
                    "character": "未",
                    "simplified": "未",
                    "traditional": "未",
                    "pinyin": ["wèi"],
                    "zhuyin": ["ㄨㄟˋ"],
                    "english": ["not yet"],
                    "explosion": generate_character_index.build_explosion("未"),
                }
            ),
            "已": generate_character_index.normalize_entry(
                {
                    "character": "已",
                    "simplified": "已",
                    "traditional": "已",
                    "pinyin": ["yǐ"],
                    "zhuyin": ["ㄧˇ"],
                    "english": ["already", "finished"],
                    "explosion": generate_character_index.build_explosion("已"),
                }
            ),
            "日": generate_character_index.normalize_entry(
                {
                    "character": "日",
                    "simplified": "日",
                    "traditional": "日",
                    "pinyin": ["rì"],
                    "zhuyin": ["ㄖˋ"],
                    "english": ["sun", "day", "daytime"],
                    "explosion": generate_character_index.build_explosion("日"),
                }
            ),
            "夜": generate_character_index.normalize_entry(
                {
                    "character": "夜",
                    "simplified": "夜",
                    "traditional": "夜",
                    "pinyin": ["yè"],
                    "zhuyin": ["ㄧㄝˋ"],
                    "english": ["night, dark"],
                    "explosion": generate_character_index.build_explosion("夜"),
                }
            ),
            "始": generate_character_index.normalize_entry(
                {
                    "character": "始",
                    "simplified": "始",
                    "traditional": "始",
                    "pinyin": ["shǐ"],
                    "zhuyin": ["ㄕˇ"],
                    "english": ["to begin, to start", "beginning"],
                    "explosion": generate_character_index.build_explosion("始"),
                }
            ),
            "终": generate_character_index.normalize_entry(
                {
                    "character": "终",
                    "simplified": "终",
                    "traditional": "終",
                    "pinyin": ["zhōng"],
                    "zhuyin": ["ㄓㄨㄥ"],
                    "english": ["end", "finally, in the end"],
                    "explosion": generate_character_index.build_explosion("终"),
                }
            ),
            "明": generate_character_index.normalize_entry(
                {
                    "character": "明",
                    "simplified": "明",
                    "traditional": "明",
                    "pinyin": ["míng"],
                    "zhuyin": ["ㄇㄧㄥˊ"],
                    "english": ["bright, clear"],
                    "explosion": generate_character_index.build_explosion("明"),
                }
            ),
            "暗": generate_character_index.normalize_entry(
                {
                    "character": "暗",
                    "simplified": "暗",
                    "traditional": "暗",
                    "pinyin": ["àn"],
                    "zhuyin": ["ㄢˋ"],
                    "english": ["dark, gloomy, obscure"],
                    "explosion": generate_character_index.build_explosion("暗"),
                }
            ),
        }

        generate_character_index.enrich_meaning_maps(entries)

        self.assertIn("恶", entries["德"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("行", entries["止"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("疏", entries["亲"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("西", entries["东"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("东", entries["西"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("北", entries["南"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("南", entries["北"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("已", entries["未"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("未", entries["已"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("夜", entries["日"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("日", entries["夜"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("终", entries["始"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("始", entries["终"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("暗", entries["明"]["explosion"]["meaningMap"]["antonyms"])
        self.assertIn("明", entries["暗"]["explosion"]["meaningMap"]["antonyms"])

    def test_enrich_meaning_maps_prioritizes_curated_antonym_overrides(self) -> None:
        entries = {
            "阴": generate_character_index.normalize_entry(
                {
                    "character": "阴",
                    "simplified": "阴",
                    "traditional": "陰",
                    "pinyin": ["yīn"],
                    "zhuyin": ["ㄧㄣ"],
                    "english": ["dark, gloomy, obscure", "shade"],
                    "explosion": generate_character_index.build_explosion("阴"),
                }
            ),
            "阳": generate_character_index.normalize_entry(
                {
                    "character": "阳",
                    "simplified": "阳",
                    "traditional": "陽",
                    "pinyin": ["yáng"],
                    "zhuyin": ["ㄧㄤˊ"],
                    "english": ["bright, clear", "sunlight"],
                    "explosion": generate_character_index.build_explosion("阳"),
                }
            ),
            "明": generate_character_index.normalize_entry(
                {
                    "character": "明",
                    "simplified": "明",
                    "traditional": "明",
                    "pinyin": ["míng"],
                    "zhuyin": ["ㄇㄧㄥˊ"],
                    "english": ["bright, clear", "brilliance"],
                    "explosion": generate_character_index.build_explosion("明"),
                }
            ),
            "暗": generate_character_index.normalize_entry(
                {
                    "character": "暗",
                    "simplified": "暗",
                    "traditional": "暗",
                    "pinyin": ["àn"],
                    "zhuyin": ["ㄢˋ"],
                    "english": ["dark, gloomy, obscure"],
                    "explosion": generate_character_index.build_explosion("暗"),
                }
            ),
        }

        generate_character_index.enrich_meaning_maps(entries)

        self.assertEqual(entries["阴"]["explosion"]["meaningMap"]["antonyms"][0], "阳")
        self.assertEqual(entries["阳"]["explosion"]["meaningMap"]["antonyms"][0], "阴")

    def test_mirror_antonym_relationships_caps_reverse_lists(self) -> None:
        entries = {
            "上": generate_character_index.normalize_entry(
                {
                    "character": "上",
                    "simplified": "上",
                    "traditional": "上",
                    "pinyin": ["shàng"],
                    "zhuyin": ["ㄕㄤˋ"],
                    "english": ["above", "on top", "superior", "high"],
                    "explosion": {
                        "analysis": {"expression": "上", "parts": ["上"]},
                        "synthesis": {
                            "containingCharacters": [],
                            "phraseUse": ["上升"],
                            "homophones": {
                                "sameTone": [],
                                "differentTone": [],
                            },
                        },
                        "meaningMap": {
                            "synonyms": [],
                            "antonyms": ["下"],
                        },
                    },
                }
            ),
            "下": generate_character_index.normalize_entry(
                {
                    "character": "下",
                    "simplified": "下",
                    "traditional": "下",
                    "pinyin": ["xià"],
                    "zhuyin": ["ㄒㄧㄚˋ"],
                    "english": ["below", "underneath", "inferior", "low"],
                    "explosion": {
                        "analysis": {"expression": "下", "parts": ["下"]},
                        "synthesis": {
                            "containingCharacters": [],
                            "phraseUse": ["下降"],
                            "homophones": {
                                "sameTone": [],
                                "differentTone": [],
                            },
                        },
                        "meaningMap": {
                            "synonyms": [],
                            "antonyms": ["上"],
                        },
                    },
                }
            ),
        }

        for index in range(8):
            character = f"低{index}"
            entries[character] = generate_character_index.normalize_entry(
                {
                    "character": character,
                    "simplified": character,
                    "traditional": character,
                    "pinyin": ["dī"],
                    "zhuyin": ["ㄉㄧ"],
                    "english": ["low, inferior"],
                    "explosion": {
                        "analysis": {"expression": character, "parts": [character]},
                        "synthesis": {
                            "containingCharacters": [],
                            "phraseUse": ["低处"],
                            "homophones": {
                                "sameTone": [],
                                "differentTone": [],
                            },
                        },
                        "meaningMap": {
                            "synonyms": [],
                            "antonyms": ["上"],
                        },
                    },
                }
            )

        generate_character_index.mirror_antonym_relationships(entries)

        self.assertLessEqual(len(entries["上"]["explosion"]["meaningMap"]["antonyms"]), 5)
        self.assertIn("下", entries["上"]["explosion"]["meaningMap"]["antonyms"])

    def test_build_phrase_usage_prefers_shorter_examples_when_frequency_ties(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)
            chapter_path = content_root / "books" / "demo" / "chapters" / "chapter-001.json"
            chapter_path.parent.mkdir(parents=True)
            chapter_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "大學",
                            "text": "博大精深 大學 大人",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            usage = generate_character_index.build_phrase_usage(content_root, {}, {})

            self.assertEqual(usage["大"][:3], ["大學", "大人", "博大精深"])

    def test_build_phrase_usage_prefers_chapter_text_over_commentary(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)

            chapter_path = content_root / "books" / "demo" / "chapters" / "chapter-001.json"
            chapter_path.parent.mkdir(parents=True)
            chapter_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "大學",
                            "text": "大學",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            commentary_path = (
                content_root
                / "books"
                / "demo"
                / "commentary"
                / "commentary-001.json"
            )
            commentary_path.parent.mkdir(parents=True)
            commentary_path.write_text(
                json.dumps(
                    {
                        "commentary": {
                            "text": "大夫。大夫。大夫。大夫。",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            usage = generate_character_index.build_phrase_usage(content_root, {}, {})

            self.assertEqual(usage["大"][0], "大學")

    def test_build_phrase_usage_prefers_curriculum_books_over_later_spine_books(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)

            da_xue_path = content_root / "books" / "da-xue" / "chapters" / "chapter-001.json"
            da_xue_path.parent.mkdir(parents=True)
            da_xue_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "大學之道",
                            "text": "大學之道",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            sanguo_path = (
                content_root / "books" / "sanguo-yanyi" / "chapters" / "chapter-001.json"
            )
            sanguo_path.parent.mkdir(parents=True)
            sanguo_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "天下大事",
                            "text": "天下大事",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            usage = generate_character_index.build_phrase_usage(content_root, {}, {})

            self.assertEqual(usage["大"][0], "大學之道")

    def test_rank_phrase_candidates_prefers_cleaner_phrase_boundaries(self) -> None:
        ranked = generate_character_index.rank_phrase_candidates(
            {
                "之欲明明德": 60,
                "欲明明德於": 60,
                "在明明德": 48,
            },
            {
                "之欲明明德": False,
                "欲明明德於": False,
                "在明明德": True,
            },
            {
                "之欲明明德": generate_character_index.phrase_candidate_rank_score(12, 5),
                "欲明明德於": generate_character_index.phrase_candidate_rank_score(12, 5),
                "在明明德": generate_character_index.phrase_candidate_rank_score(12, 4),
            },
            {
                "之欲明明德": 5,
                "欲明明德於": 5,
                "在明明德": 4,
            },
            {
                "之欲明明德": 0,
                "欲明明德於": 1,
                "在明明德": 2,
            },
        )

        self.assertEqual(ranked[0], "在明明德")

    def test_rank_phrase_candidates_penalizes_editorial_suffixes(self) -> None:
        ranked = generate_character_index.rank_phrase_candidates(
            {
                "大學章句": 60,
                "大學之道": 60,
            },
            {
                "大學章句": True,
                "大學之道": True,
            },
            {
                "大學章句": generate_character_index.phrase_candidate_rank_score(12, 5),
                "大學之道": generate_character_index.phrase_candidate_rank_score(12, 5),
            },
            {
                "大學章句": 5,
                "大學之道": 5,
            },
            {
                "大學章句": 0,
                "大學之道": 1,
            },
        )

        self.assertEqual(ranked[0], "大學之道")

    def test_build_phrase_usage_prefers_cleaner_curriculum_phrase_over_clipped_snippets(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)
            chapter_path = content_root / "books" / "da-xue" / "chapters" / "chapter-001.json"
            chapter_path.parent.mkdir(parents=True)
            chapter_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "古之欲明明德於天下者在明明德",
                            "text": "古之欲明明德於天下者在明明德",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            usage = generate_character_index.build_phrase_usage(content_root, {}, {})

            self.assertEqual(usage["明"][0], "在明明德")

    def test_build_phrase_usage_prefers_highest_priority_book_over_broader_lower_priority_support(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)

            da_xue_path = content_root / "books" / "da-xue" / "chapters" / "chapter-001.json"
            da_xue_path.parent.mkdir(parents=True)
            da_xue_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "大學之道",
                            "text": "大學之道",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            zhong_yong_path = (
                content_root / "books" / "zhong-yong" / "chapters" / "chapter-001.json"
            )
            zhong_yong_path.parent.mkdir(parents=True)
            zhong_yong_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "人之道也",
                            "text": "人之道也",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            lunyu_path = content_root / "books" / "lunyu" / "chapters" / "chapter-001.json"
            lunyu_path.parent.mkdir(parents=True)
            lunyu_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "天下有道",
                            "text": "天下有道",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            usage = generate_character_index.build_phrase_usage(content_root, {}, {})

            self.assertEqual(usage["道"][0], "大學之道")

    def test_build_phrase_usage_prefers_stronger_source_text_over_earlier_commentary(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            content_root = Path(temp_dir)

            commentary_path = (
                content_root
                / "books"
                / "da-xue"
                / "commentary"
                / "commentary-001.json"
            )
            commentary_path.parent.mkdir(parents=True)
            commentary_path.write_text(
                json.dumps(
                    {
                        "commentary": {
                            "text": "大甲",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            chapter_path = (
                content_root / "books" / "lunyu" / "chapters" / "chapter-001.json"
            )
            chapter_path.parent.mkdir(parents=True)
            chapter_path.write_text(
                json.dumps(
                    {
                        "chapter": {
                            "title": "大夫",
                            "text": "大夫",
                        },
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            usage = generate_character_index.build_phrase_usage(content_root, {}, {})

            self.assertEqual(usage["大"][0], "大夫")


if __name__ == "__main__":
    unittest.main()
