#!/usr/bin/env python3

import argparse
import io
import json
import os
import re
import socket
import time
import urllib.error
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Iterator, Optional


DEFAULT_BASE_URL = "https://api.z.ai/api/anthropic"
DEFAULT_MODEL = "GLM-5.1"
ANTHROPIC_VERSION = "2023-06-01"
DEFAULT_MAX_TOKENS = 4096
MAKEMEAHANZI_DICTIONARY_URL = "https://raw.githubusercontent.com/skishore/makemeahanzi/master/dictionary.txt"
OPENCC_TS_URL = "https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/TSCharacters.txt"
OPENCC_ST_URL = "https://raw.githubusercontent.com/BYVoid/OpenCC/master/data/dictionary/STCharacters.txt"
UNICODE_UNIHAN_ZIP_URL = "https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip"
CJKVI_IDS_URL = "https://raw.githubusercontent.com/cjkvi/cjkvi-ids/master/ids.txt"
CHARACTER_COMPONENTS_RELATIVE_PATH = (
    "references/hanzi/modern-common-components-gf0014-2009-grouped.json"
)
DECOMPOSITION_ALIASES = {
    "⿳十罒一": "直",
}

CJK_RANGES = (
    (0x3400, 0x4DBF),   # CJK Unified Ideographs Extension A
    (0x4E00, 0x9FFF),   # CJK Unified Ideographs
    (0xF900, 0xFAFF),   # CJK Compatibility Ideographs
    (0x20000, 0x2A6DF), # CJK Unified Ideographs Extension B
    (0x2A700, 0x2B73F), # CJK Unified Ideographs Extension C
    (0x2B740, 0x2B81F), # CJK Unified Ideographs Extension D
    (0x2B820, 0x2CEAF), # CJK Unified Ideographs Extension E
    (0x2CEB0, 0x2EBEF), # CJK Unified Ideographs Extension F
    (0x30000, 0x3134F), # CJK Unified Ideographs Extension G
)

IDS_ARITY = {
    "⿰": 2,
    "⿱": 2,
    "⿲": 3,
    "⿳": 3,
    "⿴": 2,
    "⿵": 2,
    "⿶": 2,
    "⿷": 2,
    "⿸": 2,
    "⿹": 2,
    "⿺": 2,
    "⿻": 2,
}

INITIALS = {
    "zh": "ㄓ",
    "ch": "ㄔ",
    "sh": "ㄕ",
    "b": "ㄅ",
    "p": "ㄆ",
    "m": "ㄇ",
    "f": "ㄈ",
    "d": "ㄉ",
    "t": "ㄊ",
    "n": "ㄋ",
    "l": "ㄌ",
    "g": "ㄍ",
    "k": "ㄎ",
    "h": "ㄏ",
    "j": "ㄐ",
    "q": "ㄑ",
    "x": "ㄒ",
    "r": "ㄖ",
    "z": "ㄗ",
    "c": "ㄘ",
    "s": "ㄙ",
}

FINALS = {
    "": "",
    "a": "ㄚ",
    "o": "ㄛ",
    "e": "ㄜ",
    "ai": "ㄞ",
    "ei": "ㄟ",
    "ao": "ㄠ",
    "ou": "ㄡ",
    "an": "ㄢ",
    "en": "ㄣ",
    "ang": "ㄤ",
    "eng": "ㄥ",
    "er": "ㄦ",
    "i": "ㄧ",
    "ia": "ㄧㄚ",
    "ie": "ㄧㄝ",
    "iao": "ㄧㄠ",
    "iu": "ㄧㄡ",
    "iou": "ㄧㄡ",
    "ian": "ㄧㄢ",
    "in": "ㄧㄣ",
    "iang": "ㄧㄤ",
    "ing": "ㄧㄥ",
    "iong": "ㄩㄥ",
    "u": "ㄨ",
    "ua": "ㄨㄚ",
    "uo": "ㄨㄛ",
    "uai": "ㄨㄞ",
    "ui": "ㄨㄟ",
    "uei": "ㄨㄟ",
    "uan": "ㄨㄢ",
    "un": "ㄨㄣ",
    "uen": "ㄨㄣ",
    "uang": "ㄨㄤ",
    "ong": "ㄨㄥ",
    "ü": "ㄩ",
    "ue": "ㄩㄝ",
    "üe": "ㄩㄝ",
    "ve": "ㄩㄝ",
    "üan": "ㄩㄢ",
    "van": "ㄩㄢ",
    "ün": "ㄩㄣ",
    "vn": "ㄩㄣ",
}

WHOLE_SYLLABLES = {
    "zhi": "ㄓ",
    "chi": "ㄔ",
    "shi": "ㄕ",
    "ri": "ㄖ",
    "zi": "ㄗ",
    "ci": "ㄘ",
    "si": "ㄙ",
    "yi": "ㄧ",
    "ya": "ㄧㄚ",
    "yo": "ㄧㄛ",
    "ye": "ㄧㄝ",
    "yao": "ㄧㄠ",
    "you": "ㄧㄡ",
    "yan": "ㄧㄢ",
    "yin": "ㄧㄣ",
    "yang": "ㄧㄤ",
    "ying": "ㄧㄥ",
    "yong": "ㄩㄥ",
    "wu": "ㄨ",
    "wa": "ㄨㄚ",
    "wo": "ㄨㄛ",
    "wai": "ㄨㄞ",
    "wei": "ㄨㄟ",
    "wan": "ㄨㄢ",
    "wen": "ㄨㄣ",
    "wang": "ㄨㄤ",
    "weng": "ㄨㄥ",
    "yu": "ㄩ",
    "yue": "ㄩㄝ",
    "yuan": "ㄩㄢ",
    "yun": "ㄩㄣ",
    "m": "ㄇ",
    "n": "ㄋ",
    "ng": "ㄫ",
}

TONE_MARKS = {
    "ā": ("a", 1),
    "á": ("a", 2),
    "ǎ": ("a", 3),
    "à": ("a", 4),
    "ē": ("e", 1),
    "é": ("e", 2),
    "ě": ("e", 3),
    "è": ("e", 4),
    "ê": ("e", 1),
    "ī": ("i", 1),
    "í": ("i", 2),
    "ǐ": ("i", 3),
    "ì": ("i", 4),
    "ō": ("o", 1),
    "ó": ("o", 2),
    "ǒ": ("o", 3),
    "ò": ("o", 4),
    "ū": ("u", 1),
    "ú": ("u", 2),
    "ǔ": ("u", 3),
    "ù": ("u", 4),
    "ǖ": ("ü", 1),
    "ǘ": ("ü", 2),
    "ǚ": ("ü", 3),
    "ǜ": ("ü", 4),
    "ü": ("ü", 5),
    "ḿ": ("m", 2),
    "m̀": ("m", 4),
    "ń": ("n", 2),
    "ň": ("n", 3),
    "ǹ": ("n", 4),
}

TONE_SUFFIX = {
    1: "",
    2: "ˊ",
    3: "ˇ",
    4: "ˋ",
    5: "",
}

PHRASE_TRIM_CHARS = " \t\r\n\"'`“”‘’「」『』（）()[]{}<>《》〈〉【】〔〕，。！？；：、,.;:!?"
PHRASE_WEAK_LEADING_CHARS = {
    "之",
    "其",
    "欲",
    "以",
    "言",
    "釋",
}
PHRASE_WEAK_TRAILING_CHARS = {
    "於",
    "乎",
    "也",
    "者",
    "矣",
    "焉",
    "曰",
    "云",
}
PHRASE_META_SUFFIXES = (
    "章句",
    "章",
    "注",
    "註",
    "題",
    "序",
)
GRAPHICAL_FRAGMENT_COMPONENTS = {
    "一",
    "丨",
    "丶",
    "丿",
    "乙",
    "亅",
    "二",
    "丷",
}
CURRICULUM_BOOK_PRIORITY = {
    "da-xue": 12,
    "zhong-yong": 11,
    "lunyu": 10,
    "mengzi": 9,
    "sunzi-bingfa": 8,
    "daodejing": 7,
    "san-zi-jing": 6,
    "qian-zi-wen": 5,
    "sanguo-yanyi": 4,
    "chengyu-catalog": 3,
}
PHRASE_BOOK_PRIORITY_WEIGHT = 5
PHRASE_SOURCE_WEIGHT = 6
TRADITIONAL_VARIANT_MIN_ADVANTAGE = 20
TRADITIONAL_VARIANT_MIN_RATIO = 2
GLOSS_STOP_PHRASES = {
    "surname",
    "used in transliterations",
    "final particle",
    "negative prefix",
    "structural particle used before a verb",
}
GLOSS_REFERENCE_PATTERN = re.compile(
    r"\((?:same as|variant of|corrupted form of|non-classical form of|ancient form of|abbreviated form of|standard form(?: of)?)\s+([^)]*)\)",
    re.IGNORECASE,
)
GLOSS_LEADING_ARTICLE_PATTERN = re.compile(r"^(?:a|an|the)\s+")
GLOSS_LEADING_INFINITIVE_PATTERN = re.compile(r"^to\s+")
MEANING_MAP_ANTONYM_CONCEPTS = {
    "size": ({"big", "large", "great", "vast"}, {"small", "tiny"}),
    "position": (
        {"above", "on top", "superior", "high", "elevated", "lofty", "tall"},
        {"below", "underneath", "inferior", "low"},
    ),
    "time_order": ({"previous"}, {"next"}),
    "morality": ({"good", "virtuous", "kind", "charitable"}, {"bad", "evil", "wicked"}),
    "length": ({"long", "lasting"}, {"short", "brief"}),
    "existence": ({"to have", "to own", "to possess", "to exist"}, {"no", "not", "lacking"}),
    "light": ({"bright", "clear"}, {"dark", "gloomy", "obscure"}),
    "fullness": ({"full"}, {"empty"}),
    "openness": ({"open"}, {"closed", "shut"}),
    "inside_outside": ({"inside"}, {"outside"}),
    "front_back": (
        {"front", "in front", "forward", "former", "preceding"},
        {"back", "behind", "rear", "after"},
    ),
    "left_right": ({"left"}, {"right"}),
    "movement": ({"to arrive", "to come", "to return"}, {"to depart", "to go away", "to leave"}),
    "temperature": ({"hot"}, {"cold"}),
    "age": (
        {"old", "ancient", "classic", "former", "past"},
        {"young", "new", "modern", "current", "today", "now", "recent", "fresh"},
    ),
    "life_death": ({"life", "lifetime", "birth", "growth", "to live"}, {"death", "dead"}),
    "quantity": ({"many", "much", "more than", "over", "multi-"}, {"few", "little", "less"}),
    "love_hate": (
        {"to love", "love", "affection", "fond", "cherish"},
        {"to hate", "hate", "hatred", "to detest", "to loathe"},
    ),
    "beautiful_ugly": (
        {"beautiful", "pretty", "handsome", "elegant", "graceful"},
        {"ugly"},
    ),
    "true_false": (
        {"true", "real", "genuine", "truth"},
        {"false", "fake", "counterfeit"},
    ),
    "male_female": (
        {"male", "man", "husband"},
        {"female", "woman", "wife"},
    ),
    "king_subject": (
        {"king", "emperor", "ruler", "sovereign", "monarch"},
        {"servant", "slave", "vassal", "minister"},
    ),
    "war_peace": (
        {"war", "battle", "fight", "combat", "military"},
        {"peace", "harmony"},
    ),
    "rich_poor": (
        {"rich", "wealthy", "prosperous", "abundant"},
        {"poor", "poverty", "destitute", "needy"},
    ),
    "hard_soft": (
        {"hard", "firm", "solid", "rigid", "tough"},
        {"soft", "gentle", "tender"},
    ),
    "clean_dirty": (
        {"clean", "pure"},
        {"dirty", "filthy", "unclean", "soiled"},
    ),
    "fast_slow": (
        {"fast", "quick", "rapid", "swift", "hasty"},
        {"slow", "sluggish", "leisurely"},
    ),
    "strong_weak": (
        {"strong", "powerful", "mighty", "robust", "vigorous"},
        {"weak", "feeble", "frail", "fragile"},
    ),
    "heavy_light": (
        {"heavy", "weight"},
        {"light"},
    ),
    "far_near": (
        {"far", "distant", "remote"},
        {"near", "close", "nearby"},
    ),
    "early_late": (
        {"early"},
        {"late", "to delay", "tardy"},
    ),
    "success_failure": (
        {"to succeed", "to win", "victory", "triumph", "to achieve", "to accomplish"},
        {"failure", "to fail", "defeat", "to lose", "loss"},
    ),
    "buy_sell": (
        {"to buy", "to purchase"},
        {"to sell", "to vend"},
    ),
    "ask_answer": (
        {"to ask", "to inquire", "to question"},
        {"to reply", "to respond"},
    ),
    "teach_learn": (
        {"to teach", "to instruct", "to educate"},
        {"to learn", "to study"},
    ),
    "give_receive": (
        {"to give", "to grant", "to bestow", "to donate", "to offer"},
        {"to receive", "to accept", "to obtain", "to acquire"},
    ),
    "rise_fall": (
        {"to rise", "to ascend", "to climb", "to soar", "to elevate"},
        {"to fall", "to descend", "to drop", "to decline", "to sink"},
    ),
    "attack_defend": (
        {"to attack", "to assault", "to strike", "to invade"},
        {"to defend", "to protect", "to guard", "shield"},
    ),
    "praise_criticize": (
        {"to praise", "to commend"},
        {"to criticize", "to blame", "to reprove"},
    ),
    "joy_sorrow": (
        {"joy", "happy", "glad", "pleased", "delight", "cheerful"},
        {"sorrow", "sad", "grief", "to mourn", "to lament", "melancholy"},
    ),
    "gather_scatter": (
        {"to gather", "to collect", "to assemble", "to amass"},
        {"to scatter", "to disperse", "to spread"},
    ),
    "connect_separate": (
        {"to connect", "to join", "to link", "to unite", "to attach", "to combine"},
        {"to separate", "to divide", "to split", "to part"},
    ),
    "honor_shame": (
        {"honorable", "dignified", "noble", "respect"},
        {"shameful", "disgrace", "shame"},
    ),
    "loyal_traitor": (
        {"loyal", "loyalty", "faithful"},
        {"traitor", "treason", "to betray"},
    ),
    "reward_punish": (
        {"to reward", "prize", "award"},
        {"to punish", "punishment", "penalty"},
    ),
    "wise_foolish": (
        {"wise", "wisdom", "intelligent", "sagely"},
        {"foolish", "stupid", "ignorant"},
    ),
    "brave_cowardly": (
        {"brave", "courage", "courageous", "valiant"},
        {"cowardly", "coward", "timid"},
    ),
    "humble_arrogant": (
        {"humble", "modest", "modesty"},
        {"arrogant", "proud", "pride", "conceited"},
    ),
    "order_chaos": (
        {"order", "ordered", "systematic", "neat"},
        {"chaos", "chaotic", "disorder", "mess"},
    ),
}
MEANING_MAP_CORE_ANTONYM_OVERRIDES = {
    "上": ["下"],
    "下": ["上"],
    "大": ["小"],
    "小": ["大"],
    "多": ["少"],
    "少": ["多"],
    "左": ["右"],
    "右": ["左"],
    "有": ["无"],
    "无": ["有"],
    "未": ["已"],
    "已": ["未"],
    "今": ["古"],
    "古": ["今"],
    "日": ["夜"],
    "夜": ["日"],
    "生": ["死"],
    "死": ["生"],
    "始": ["终"],
    "终": ["始"],
    "先": ["后"],
    "前": ["后"],
    "后": ["前"],
    "来": ["去"],
    "去": ["来"],
    "高": ["低"],
    "低": ["高"],
    "明": ["暗"],
    "暗": ["明"],
    "善": ["恶"],
    "恶": ["善"],
    "东": ["西"],
    "西": ["东"],
    "南": ["北"],
    "北": ["南"],
    "阴": ["阳"],
    "阳": ["阴"],
    "德": ["恶"],
    "止": ["行"],
    "行": ["止"],
    "亲": ["疏"],
    "疏": ["亲"],
    "新": ["旧"],
    "旧": ["新"],
    "爱": ["恨"],
    "恨": ["爱"],
    "美": ["丑"],
    "丑": ["美"],
    "真": ["假"],
    "假": ["真"],
    "男": ["女"],
    "女": ["男"],
    "雄": ["雌"],
    "雌": ["雄"],
    "王": ["臣"],
    "臣": ["王"],
    "战": ["和"],
    "和": ["战"],
    "富": ["贫"],
    "贫": ["富"],
    "硬": ["软"],
    "软": ["硬"],
    "刚": ["柔"],
    "柔": ["刚"],
    "清": ["浊"],
    "浊": ["清"],
    "快": ["慢"],
    "慢": ["快"],
    "强": ["弱"],
    "弱": ["强"],
    "重": ["轻"],
    "轻": ["重"],
    "远": ["近"],
    "近": ["远"],
    "早": ["晚"],
    "晚": ["早"],
    "胜": ["败"],
    "败": ["胜"],
    "买": ["卖"],
    "卖": ["买"],
    "问": ["答"],
    "答": ["问"],
    "教": ["学"],
    "学": ["教"],
    "给": ["受"],
    "受": ["给"],
    "起": ["落"],
    "落": ["起"],
    "升": ["降"],
    "降": ["升"],
    "攻": ["守"],
    "守": ["攻"],
    "赞": ["贬"],
    "贬": ["赞"],
    "褒": ["贬"],
    "喜": ["悲"],
    "悲": ["喜"],
    "欢": ["哀"],
    "哀": ["欢"],
    "聚": ["散"],
    "散": ["聚"],
    "合": ["分"],
    "分": ["合"],
    "连": ["断"],
    "忠": ["叛"],
    "叛": ["忠"],
    "赏": ["罚"],
    "罚": ["赏"],
    "智": ["愚"],
    "愚": ["智"],
    "勇": ["怯"],
    "怯": ["勇"],
    "谦": ["傲"],
    "傲": ["谦"],
    "治": ["乱"],
    "乱": ["治"],
    "尊": ["卑"],
    "卑": ["尊"],
    "荣": ["辱"],
    "辱": ["荣"],
    "功": ["过"],
    "过": ["功"],
    "进": ["退"],
    "退": ["进"],
    "加": ["减"],
    "减": ["加"],
    "取": ["舍"],
    "舍": ["取"],
    "恩": ["仇"],
    "仇": ["恩"],
    "信": ["疑"],
    "疑": ["信"],
    "宽": ["严"],
    "严": ["宽"],
    "勤": ["懒"],
    "懒": ["勤"],
    "益": ["损"],
    "损": ["益"],
    "安": ["危"],
    "危": ["安"],
    "福": ["祸"],
    "祸": ["福"],
    "兴": ["衰"],
    "衰": ["兴"],
    "盈": ["虚"],
    "虚": ["盈"],
    "实": ["空"],
    "空": ["实"],
}


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Generate a repo-local Chinese character index.")
    parser.add_argument(
        "--content-root",
        type=Path,
        default=repo_root / "content",
        help="Content root that contains books/ and references/.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "content" / "references" / "characters" / "index.json",
        help="Output JSON path.",
    )
    parser.add_argument(
        "--seed-index",
        type=Path,
        default=repo_root / "content" / "references" / "characters" / "index.json",
        help="Existing index used to seed entries that are missing deterministic source data.",
    )
    parser.add_argument(
        "--manual-seed",
        type=Path,
        default=repo_root / "content" / "references" / "characters" / "manual-seed.json",
        help="Curated seed entries for characters that deterministic sources cannot fully gloss.",
    )
    parser.add_argument(
        "--glm-batch-size",
        type=int,
        default=12,
        help="Fallback GLM characters per request when deterministic sources miss a character.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Optional cap on the number of canonical characters to generate.",
    )
    return parser.parse_args()


def normalize_list(values: object) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    if not isinstance(values, list):
        return normalized
    for value in values:
        if not isinstance(value, str):
            continue
        trimmed = value.strip()
        if not trimmed or trimmed in seen:
            continue
        seen.add(trimmed)
        normalized.append(trimmed)
    return normalized


def normalize_decomposition_text(value: str) -> str:
    normalized = value.strip()
    if not normalized:
        return ""
    normalized = re.sub(r"\[[^]]+\]$", "", normalized).strip()
    return normalized


def is_cjk_character(char: str) -> bool:
    if len(char) != 1:
        return False
    codepoint = ord(char)
    return any(start <= codepoint <= end for start, end in CJK_RANGES)


def is_basic_cjk_character(char: str) -> bool:
    if len(char) != 1:
        return False
    codepoint = ord(char)
    return (0x4E00 <= codepoint <= 0x9FFF) or (0xF900 <= codepoint <= 0xFAFF)


def merge_string_lists(*value_sets: object) -> list[str]:
    merged: list[str] = []
    seen: set[str] = set()
    for values in value_sets:
        for value in normalize_list(values):
            if value in seen:
                continue
            seen.add(value)
            merged.append(value)
    return merged


def fetch_text(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "codex-character-index/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode("utf-8")


def fetch_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "codex-character-index/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def iter_book_json_string_values(value: object) -> Iterator[str]:
    if isinstance(value, dict):
        for child in value.values():
            yield from iter_book_json_string_values(child)
        return

    if isinstance(value, list):
        for child in value:
            yield from iter_book_json_string_values(child)
        return

    if isinstance(value, str) and value.strip():
        yield value


def iter_book_strings(content_root: Path) -> Iterator[str]:
    for path in sorted(content_root.glob("books/**/*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        yield from iter_book_json_string_values(payload)


def collect_unique_characters(content_root: Path) -> list[str]:
    characters: set[str] = set()
    for text in iter_book_strings(content_root):
        for char in text:
            if is_cjk_character(char):
                characters.add(char)
    return sorted(characters)


def collect_character_frequencies(content_root: Path) -> dict[str, int]:
    counts: dict[str, int] = defaultdict(int)
    for text in iter_book_strings(content_root):
        for char in text:
            if is_cjk_character(char):
                counts[char] += 1
    return dict(counts)


def load_makemeahanzi_dictionary() -> dict[str, dict]:
    dictionary: dict[str, dict] = {}
    for line in fetch_text(MAKEMEAHANZI_DICTIONARY_URL).splitlines():
        if not line.strip():
            continue
        entry = json.loads(line)
        character = str(entry.get("character", "")).strip()
        if character:
            dictionary[character] = entry
    return dictionary


def load_opencc_map(url: str) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for line in fetch_text(url).splitlines():
        if not line or line.startswith("#"):
            continue
        key, _, values = line.partition("\t")
        first_value = values.split(" ", 1)[0].strip()
        if key and first_value:
            mapping[key] = first_value
    return mapping


def load_opencc_traditional_variants(url: str) -> dict[str, list[str]]:
    variants_by_simplified: dict[str, list[str]] = defaultdict(list)
    for line in fetch_text(url).splitlines():
        if not line or line.startswith("#"):
            continue
        traditional, _, values = line.partition("\t")
        normalized_traditional = traditional.strip()
        if not is_cjk_character(normalized_traditional):
            continue
        for simplified in values.split():
            normalized_simplified = simplified.strip()
            if not is_cjk_character(normalized_simplified):
                continue
            variants = variants_by_simplified[normalized_simplified]
            if normalized_traditional not in variants:
                variants.append(normalized_traditional)
    return dict(variants_by_simplified)


def load_unihan_data() -> dict[str, dict]:
    archive = zipfile.ZipFile(io.BytesIO(fetch_bytes(UNICODE_UNIHAN_ZIP_URL)))
    readings = archive.read("Unihan_Readings.txt").decode("utf-8")

    data: dict[str, dict] = {}
    for line in readings.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t", 2)
        if len(parts) != 3:
            continue
        codepoint, field, value = parts
        if field not in {"kMandarin", "kHanyuPinyin", "kDefinition"}:
            continue

        character = chr(int(codepoint[2:], 16))
        entry = data.setdefault(character, {})
        if field == "kMandarin":
            entry["mandarin"] = [token.strip() for token in value.split() if token.strip()]
        elif field == "kHanyuPinyin":
            hanyu_readings = []
            for chunk in value.split():
                _, _, pinyin = chunk.partition(":")
                for token in pinyin.split(","):
                    normalized = token.strip()
                    if normalized and normalized not in hanyu_readings:
                        hanyu_readings.append(normalized)
            if hanyu_readings:
                entry["hanyu_pinyin"] = hanyu_readings
        elif field == "kDefinition":
            entry["definition"] = value.strip()
    return data


def load_ids_data() -> dict[str, str]:
    ids: dict[str, str] = {}
    for line in fetch_text(CJKVI_IDS_URL).splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        character = parts[1].strip()
        decomposition = normalize_decomposition_text(parts[2])
        if character and decomposition:
            ids[character] = decomposition
    return ids


def load_reasonable_component_forms(content_root: Path) -> set[str]:
    file_path = content_root / Path(CHARACTER_COMPONENTS_RELATIVE_PATH)
    if not file_path.exists():
        return set()

    payload = json.loads(file_path.read_text(encoding="utf-8"))
    forms: set[str] = set()
    for entry in payload.get("entries", []):
        if not isinstance(entry, dict):
            continue
        for key in ("canonical_form",):
            value = str(entry.get(key, "")).strip()
            if value:
                forms.add(value)
        for key in ("forms", "variant_forms"):
            for value in entry.get(key, []):
                normalized = str(value).strip()
                if normalized:
                    forms.add(normalized)
    return forms


def iter_component_character_pairs(
    content_root: Path,
    ts_map: dict[str, str],
    st_map: dict[str, str],
) -> Iterator[tuple[str, str]]:
    file_path = content_root / Path(CHARACTER_COMPONENTS_RELATIVE_PATH)
    if not file_path.exists():
        return

    payload = json.loads(file_path.read_text(encoding="utf-8"))
    seen: set[str] = set()
    for raw_entry in payload.get("entries", []):
        if not isinstance(raw_entry, dict):
            continue

        raw_forms: list[object] = [raw_entry.get("canonical_form", "")]
        for key in ("forms", "variant_forms"):
            values = raw_entry.get(key, [])
            if isinstance(values, list):
                raw_forms.extend(values)

        for raw_form in raw_forms:
            form = str(raw_form).strip()
            if not is_cjk_character(form):
                continue

            simplified, traditional = canonical_character(form, ts_map, st_map)
            if not simplified or simplified in seen:
                continue

            seen.add(simplified)
            yield simplified, traditional


def is_reasonable_component_unit(character: str, reasonable_component_forms: set[str]) -> bool:
    trimmed = character.strip()
    if not is_cjk_character(trimmed):
        return False
    if is_basic_cjk_character(trimmed):
        return True
    return trimmed in reasonable_component_forms and ord(trimmed) <= 0xFFFF


def choose_reasonable_decomposition_target(
    candidates: set[str],
    reasonable_component_forms: set[str],
) -> Optional[str]:
    ranked = sorted(
        (
            candidate.strip()
            for candidate in candidates
            if is_reasonable_component_unit(candidate, reasonable_component_forms)
        ),
        key=lambda candidate: (
            0 if candidate in reasonable_component_forms else 1,
            0 if is_basic_cjk_character(candidate) else 1,
            candidate,
        ),
    )
    return ranked[0] if ranked else None


def build_reasonable_decomposition_lookup(
    dictionary: dict[str, dict],
    ids_data: dict[str, str],
    reasonable_component_forms: set[str],
) -> dict[str, str]:
    candidates_by_decomposition: dict[str, set[str]] = defaultdict(set)

    for character, source_entry in dictionary.items():
        decomposition = normalize_decomposition_text(str(source_entry.get("decomposition", "")))
        if decomposition:
            candidates_by_decomposition[decomposition].add(character.strip())

    for character, decomposition in ids_data.items():
        normalized_decomposition = normalize_decomposition_text(str(decomposition))
        if normalized_decomposition:
            candidates_by_decomposition[normalized_decomposition].add(character.strip())

    lookup: dict[str, str] = {}
    for decomposition, candidates in candidates_by_decomposition.items():
        chosen = choose_reasonable_decomposition_target(candidates, reasonable_component_forms)
        if chosen is not None:
            lookup[decomposition] = chosen
    for decomposition, replacement in DECOMPOSITION_ALIASES.items():
        normalized_decomposition = normalize_decomposition_text(decomposition)
        if is_reasonable_component_unit(replacement, reasonable_component_forms):
            lookup[normalized_decomposition] = replacement
    return lookup


def canonical_character(char: str, ts_map: dict[str, str], st_map: dict[str, str]) -> tuple[str, str]:
    if char in st_map:
        return char, st_map[char]
    if char in ts_map:
        return ts_map[char], char
    return char, char


def normalize_senses(definition: str) -> list[str]:
    if not definition:
        return []
    chunks = re.split(r"[;/]", definition)
    senses: list[str] = []
    seen: set[str] = set()
    for chunk in chunks:
        normalized = re.sub(r"\s+", " ", chunk).strip(" ,.")
        if not normalized:
            continue
        lowered = normalized.lower()
        if lowered in seen:
            continue
        seen.add(lowered)
        senses.append(normalized)
        if len(senses) >= 5:
            break
    return senses


def normalize_pinyin_syllable(syllable: str) -> tuple[str, int]:
    tone = 5
    normalized = []
    for char in syllable.strip().lower().replace("u:", "ü").replace("v", "ü"):
        mapped = TONE_MARKS.get(char)
        if mapped is None:
            normalized.append(char)
            continue
        base, mapped_tone = mapped
        normalized.append(base)
        if mapped_tone != 5:
            tone = mapped_tone
    return "".join(normalized), tone


def pinyin_to_zhuyin_syllable(syllable: str) -> str:
    base, tone = normalize_pinyin_syllable(syllable)
    base = base.strip().lower()
    if not base:
        return ""

    body = WHOLE_SYLLABLES.get(base)
    if body is None:
        initial = ""
        rest = base
        for candidate in sorted(INITIALS.keys(), key=len, reverse=True):
            if base.startswith(candidate):
                initial = candidate
                rest = base[len(candidate) :]
                break

        if initial in {"j", "q", "x"} and rest.startswith("u"):
            rest = "ü" + rest[1:]

        body = INITIALS.get(initial, "") + FINALS.get(rest, "")
        if not body:
            return ""

    if tone == 5:
        return "˙" + body
    return body + TONE_SUFFIX[tone]


def pinyin_list_to_zhuyin(values: list[str]) -> list[str]:
    zhuyin: list[str] = []
    seen: set[str] = set()
    for value in values:
        converted = pinyin_to_zhuyin_syllable(value)
        if not converted or converted in seen:
            continue
        seen.add(converted)
        zhuyin.append(converted)
    return zhuyin


def parse_ids(text: str, index: int = 0) -> tuple[object, int]:
    if index >= len(text):
        return "", index

    char = text[index]
    arity = IDS_ARITY.get(char)
    if arity is None:
        return char, index + 1

    parts = []
    cursor = index + 1
    for _ in range(arity):
        child, cursor = parse_ids(text, cursor)
        parts.append(child)
    return {"operator": char, "parts": parts}, cursor


def parse_ids_sequence(text: str) -> list[object]:
    nodes: list[object] = []
    index = 0
    while index < len(text):
        if text[index].isspace():
            index += 1
            continue
        node, next_index = parse_ids(text, index)
        if next_index <= index:
            break
        if isinstance(node, str):
            stripped = node.strip()
            if not stripped or stripped == "？":
                index = next_index
                continue
        nodes.append(node)
        index = next_index
    return nodes


def serialize_ids(node: object) -> str:
    if isinstance(node, str):
        return node.strip()
    operator = str(node.get("operator", "")).strip()
    return operator + "".join(serialize_ids(child) for child in node.get("parts", []))


def flatten_ids(
    node: object,
    decomposition_lookup: Optional[dict[str, str]] = None,
    *,
    allow_collapse: bool = True,
    nested_ids_data: Optional[dict[str, str]] = None,
    reasonable_component_forms: Optional[set[str]] = None,
    ancestor_components: Optional[set[str]] = None,
) -> list[str]:
    if ancestor_components is None:
        ancestor_components = set()

    if isinstance(node, str):
        stripped = node.strip()
        if not stripped or stripped == "？":
            return []
        can_expand_nested_component = (
            nested_ids_data is not None
            and reasonable_component_forms is not None
            and stripped not in ancestor_components
            and not is_reasonable_component_unit(stripped, reasonable_component_forms)
        )
        if can_expand_nested_component:
            nested_decomposition = normalize_decomposition_text(nested_ids_data.get(stripped, ""))
            if nested_decomposition and nested_decomposition != stripped:
                expanded_parts: list[str] = []
                next_ancestors = set(ancestor_components)
                next_ancestors.add(stripped)
                for child in parse_ids_sequence(nested_decomposition):
                    expanded_parts.extend(
                        flatten_ids(
                            child,
                            decomposition_lookup,
                            allow_collapse=False,
                            nested_ids_data=nested_ids_data,
                            reasonable_component_forms=reasonable_component_forms,
                            ancestor_components=next_ancestors,
                        )
                    )
                if expanded_parts:
                    return expanded_parts
        return [stripped]

    if allow_collapse and decomposition_lookup is not None:
        replacement = decomposition_lookup.get(serialize_ids(node), "").strip()
        if replacement:
            return [replacement]

    parts: list[str] = []
    for child in node.get("parts", []):
        parts.extend(
            flatten_ids(
                child,
                decomposition_lookup,
                allow_collapse=True,
                nested_ids_data=nested_ids_data,
                reasonable_component_forms=reasonable_component_forms,
                ancestor_components=ancestor_components,
            )
        )
    return parts


def build_explosion(
    decomposition: str,
    decomposition_lookup: Optional[dict[str, str]] = None,
    nested_ids_data: Optional[dict[str, str]] = None,
    reasonable_component_forms: Optional[set[str]] = None,
) -> dict:
    decomposition = normalize_decomposition_text(decomposition)
    parts: list[str] = []
    if decomposition and decomposition != "？":
        for node in parse_ids_sequence(decomposition):
            parts.extend(
                flatten_ids(
                    node,
                    decomposition_lookup,
                    allow_collapse=False,
                    nested_ids_data=nested_ids_data,
                    reasonable_component_forms=reasonable_component_forms,
                )
            )
    return {
        "analysis": {
            "expression": " + ".join(parts),
            "parts": parts,
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
            "synonyms": [],
            "antonyms": [],
        },
    }


def analysis_quality(
    parts: list[str],
    reasonable_component_forms: set[str],
) -> tuple[int, int, int, int]:
    supplementary_plane_components = sum(
        1
        for part in parts
        if len(part) == 1 and is_cjk_character(part) and ord(part) > 0xFFFF
    )
    unreasonable_components = sum(
        1 for part in parts if not is_reasonable_component_unit(part, reasonable_component_forms)
    )
    graphical_fragments = sum(1 for part in parts if part in GRAPHICAL_FRAGMENT_COMPONENTS)
    return supplementary_plane_components, unreasonable_components, graphical_fragments, len(parts)


def choose_preferred_explosion(
    decompositions: list[str],
    decomposition_lookup: Optional[dict[str, str]],
    reasonable_component_forms: set[str],
    ids_data: Optional[dict[str, str]] = None,
) -> dict:
    best_explosion = build_explosion("")
    best_score: Optional[tuple[int, int, int, int]] = None

    for decomposition in decompositions:
        normalized = normalize_decomposition_text(decomposition)
        if not normalized or normalized == "？":
            continue
        explosion = build_explosion(
            normalized,
            decomposition_lookup,
            nested_ids_data=ids_data,
            reasonable_component_forms=reasonable_component_forms,
        )
        score = analysis_quality(explosion["analysis"]["parts"], reasonable_component_forms)
        if best_score is None or score < best_score:
            best_explosion = explosion
            best_score = score

    return best_explosion


def normalize_entry(raw_entry: dict) -> dict:
    explosion = raw_entry.get("explosion", {})
    if not isinstance(explosion, dict):
        explosion = {}

    simplified = str(raw_entry.get("simplified", "")).strip()
    traditional = str(raw_entry.get("traditional", "")).strip()
    character = str(raw_entry.get("character", "")).strip() or simplified or traditional
    primary_simplified = simplified or character
    primary_traditional = traditional or primary_simplified or character
    aliases = [
        value
        for value in normalize_list(raw_entry.get("aliases"))
        if value not in {character, primary_simplified, primary_traditional}
    ]

    return {
        "character": character,
        "simplified": primary_simplified,
        "traditional": primary_traditional,
        "aliases": aliases,
        "pinyin": normalize_list(raw_entry.get("pinyin")),
        "zhuyin": normalize_list(raw_entry.get("zhuyin")),
        "english": normalize_list(raw_entry.get("english")),
        "explosion": {
            "analysis": {
                "expression": str(explosion.get("analysis", {}).get("expression", "")).strip(),
                "parts": normalize_list(explosion.get("analysis", {}).get("parts")),
            },
            "synthesis": {
                "containingCharacters": normalize_list(explosion.get("synthesis", {}).get("containingCharacters")),
                "phraseUse": normalize_list(explosion.get("synthesis", {}).get("phraseUse")),
                "homophones": {
                    "sameTone": normalize_list(explosion.get("synthesis", {}).get("homophones", {}).get("sameTone")),
                    "differentTone": normalize_list(explosion.get("synthesis", {}).get("homophones", {}).get("differentTone")),
                },
            },
            "meaningMap": {
                "synonyms": normalize_list(explosion.get("meaningMap", {}).get("synonyms")),
                "antonyms": normalize_list(explosion.get("meaningMap", {}).get("antonyms")),
            },
        },
    }


def is_complete_entry(entry: Optional[dict]) -> bool:
    if entry is None:
        return False
    return bool(entry["pinyin"] and entry["zhuyin"] and entry["english"])


def merge_entries(primary: Optional[dict], secondary: Optional[dict]) -> Optional[dict]:
    if primary is None:
        return secondary
    if secondary is None:
        return primary

    merged = normalize_entry(primary)
    for key in ("pinyin", "zhuyin", "english"):
        if not merged[key] and secondary.get(key):
            merged[key] = secondary[key]
    if not merged["explosion"]["analysis"]["expression"] and secondary.get("explosion", {}).get("analysis", {}).get("expression"):
        merged["explosion"]["analysis"]["expression"] = secondary["explosion"]["analysis"]["expression"]
    if not merged["explosion"]["analysis"]["parts"] and secondary.get("explosion", {}).get("analysis", {}).get("parts"):
        merged["explosion"]["analysis"]["parts"] = secondary["explosion"]["analysis"]["parts"]
    if not merged["traditional"] and secondary.get("traditional"):
        merged["traditional"] = secondary["traditional"]
    if not merged["simplified"] and secondary.get("simplified"):
        merged["simplified"] = secondary["simplified"]
    merged["aliases"] = merge_string_lists(
        merged.get("aliases"),
        secondary.get("aliases"),
    )
    merged["explosion"]["meaningMap"]["synonyms"] = merge_string_lists(
        merged["explosion"]["meaningMap"].get("synonyms"),
        secondary.get("explosion", {}).get("meaningMap", {}).get("synonyms"),
    )
    merged["explosion"]["meaningMap"]["antonyms"] = merge_string_lists(
        merged["explosion"]["meaningMap"].get("antonyms"),
        secondary.get("explosion", {}).get("meaningMap", {}).get("antonyms"),
    )
    return normalize_entry(merged)


def load_seed_entries(path: Path) -> dict[str, dict]:
    if not path.exists():
        return {}

    payload = json.loads(path.read_text(encoding="utf-8"))
    entries: dict[str, dict] = {}
    for raw_entry in payload.get("entries", []):
        if not isinstance(raw_entry, dict):
            continue
        entry = normalize_entry(raw_entry)
        if not entry["character"]:
            continue
        for key in (
            entry["character"],
            entry["simplified"],
            entry["traditional"],
            *entry.get("aliases", []),
        ):
            if key:
                entries[key] = entry
    return entries


def merge_seed_entry_maps(*entry_maps: dict[str, dict]) -> dict[str, dict]:
    merged: dict[str, dict] = {}
    for entry_map in entry_maps:
        merged.update(entry_map)
    return merged


def find_seed_entry(seed_entries: dict[str, dict], simplified: str, traditional: str) -> Optional[dict]:
    for key in (simplified, traditional):
        if key and key in seed_entries:
            return seed_entries[key]
    return None


def apply_seed_overrides(primary: Optional[dict], secondary: Optional[dict]) -> Optional[dict]:
    if primary is None:
        return secondary
    if secondary is None:
        return primary

    merged = normalize_entry(primary)
    override = normalize_entry(secondary)
    for key in ("pinyin", "zhuyin", "english"):
        if override[key]:
            merged[key] = override[key]
    if override["traditional"]:
        merged["traditional"] = override["traditional"]
    if override["simplified"]:
        merged["simplified"] = override["simplified"]
    merged["aliases"] = merge_string_lists(
        merged.get("aliases"),
        override.get("aliases"),
    )
    return normalize_entry(merged)


def seed_canonical_pairs(seed_entries: dict[str, dict]) -> list[tuple[str, str]]:
    canonical_pairs: dict[str, tuple[str, str]] = {}
    for raw_entry in seed_entries.values():
        if not isinstance(raw_entry, dict):
            continue
        entry = normalize_entry(raw_entry)
        simplified = entry["simplified"] or entry["character"]
        traditional = entry["traditional"] or entry["character"]
        if not simplified or simplified in canonical_pairs:
            continue
        canonical_pairs[simplified] = (simplified, traditional)
    return [canonical_pairs[key] for key in sorted(canonical_pairs)]


def iter_unique_seed_entries(seed_entries: dict[str, dict]) -> Iterator[dict]:
    seen: set[int] = set()
    for raw_entry in seed_entries.values():
        if not isinstance(raw_entry, dict):
            continue
        identifier = id(raw_entry)
        if identifier in seen:
            continue
        seen.add(identifier)
        yield normalize_entry(raw_entry)


def record_canonical_alias(
    alias_forms_by_simplified: dict[str, set[str]],
    form: str,
    ts_map: dict[str, str],
    st_map: dict[str, str],
) -> None:
    normalized = str(form).strip()
    if not is_cjk_character(normalized):
        return

    simplified, _ = canonical_character(normalized, ts_map, st_map)
    if simplified:
        alias_forms_by_simplified[simplified].add(normalized)


def build_alias_forms(
    content_root: Path,
    seed_entries: dict[str, dict],
    ts_map: dict[str, str],
    st_map: dict[str, str],
) -> dict[str, list[str]]:
    alias_forms_by_simplified: dict[str, set[str]] = defaultdict(set)

    for char in collect_unique_characters(content_root):
        record_canonical_alias(alias_forms_by_simplified, char, ts_map, st_map)

    for form in load_reasonable_component_forms(content_root):
        record_canonical_alias(alias_forms_by_simplified, form, ts_map, st_map)

    for entry in iter_unique_seed_entries(seed_entries):
        for form in (
            entry["character"],
            entry["simplified"],
            entry["traditional"],
            *entry.get("aliases", []),
        ):
            record_canonical_alias(alias_forms_by_simplified, form, ts_map, st_map)

    return {
        simplified: sorted(forms)
        for simplified, forms in alias_forms_by_simplified.items()
    }


def apply_entry_aliases(entry: Optional[dict], aliases: object) -> Optional[dict]:
    if entry is None:
        return None

    merged = normalize_entry(entry)
    merged["aliases"] = merge_string_lists(merged.get("aliases"), aliases)
    return normalize_entry(merged)


def should_promote_traditional_variant(current_count: int, candidate_count: int) -> bool:
    if candidate_count <= current_count:
        return False
    if candidate_count - current_count < TRADITIONAL_VARIANT_MIN_ADVANTAGE:
        return False
    if current_count == 0:
        return candidate_count >= TRADITIONAL_VARIANT_MIN_ADVANTAGE
    return candidate_count >= current_count * TRADITIONAL_VARIANT_MIN_RATIO


def prefer_corpus_traditional_variant(
    entry: Optional[dict],
    character_frequencies: dict[str, int],
    traditional_variants_by_simplified: dict[str, list[str]],
) -> Optional[dict]:
    if entry is None:
        return None

    merged = normalize_entry(entry)
    simplified = merged["simplified"]
    current_traditional = merged["traditional"]
    variant_pool = merge_string_lists(
        traditional_variants_by_simplified.get(simplified, []),
        merged.get("aliases"),
        [current_traditional],
    )
    distinct_candidates = [
        candidate
        for candidate in variant_pool
        if candidate != simplified and candidate != merged["character"]
    ]
    if not distinct_candidates:
        return merged

    best_candidate = max(
        distinct_candidates,
        key=lambda candidate: (character_frequencies.get(candidate, 0), candidate),
    )
    best_count = character_frequencies.get(best_candidate, 0)
    current_count = character_frequencies.get(current_traditional, 0)
    if best_candidate == current_traditional or not should_promote_traditional_variant(
        current_count,
        best_count,
    ):
        return merged

    merged["traditional"] = best_candidate
    merged["aliases"] = merge_string_lists(
        merged.get("aliases"),
        [current_traditional],
    )
    return normalize_entry(merged)


def apply_aliases_to_entries(
    entries: dict[str, dict],
    alias_forms_by_simplified: dict[str, list[str]],
    character_frequencies: dict[str, int],
    traditional_variants_by_simplified: dict[str, list[str]],
) -> None:
    for simplified, entry in list(entries.items()):
        next_entry = apply_entry_aliases(
            entry,
            alias_forms_by_simplified.get(simplified, []),
        )
        entries[simplified] = prefer_corpus_traditional_variant(
            next_entry,
            character_frequencies,
            traditional_variants_by_simplified,
        )


def deterministic_entry(
    simplified: str,
    traditional: str,
    dictionary: dict[str, dict],
    ids_data: dict[str, str],
    reasonable_component_forms: set[str],
    decomposition_lookup: Optional[dict[str, str]] = None,
) -> Optional[dict]:
    source_entry = dictionary.get(simplified) or dictionary.get(traditional)
    if source_entry is None:
        return None

    pinyin = [value.strip() for value in source_entry.get("pinyin", []) if isinstance(value, str) and value.strip()]
    english = normalize_senses(str(source_entry.get("definition", "")).strip())
    explosion = choose_preferred_explosion(
        [
            str(source_entry.get("decomposition", "")).strip(),
            ids_data.get(simplified, ""),
            ids_data.get(traditional, ""),
        ],
        decomposition_lookup,
        reasonable_component_forms,
        ids_data,
    )

    entry = {
        "character": simplified,
        "simplified": simplified,
        "traditional": traditional,
        "pinyin": pinyin,
        "zhuyin": pinyin_list_to_zhuyin(pinyin),
        "english": english,
        "explosion": explosion,
    }
    normalized = normalize_entry(entry)
    if not normalized["character"]:
        return None
    return normalized


def supplemental_entry(
    simplified: str,
    traditional: str,
    unihan: dict[str, dict],
    ids_data: dict[str, str],
    reasonable_component_forms: set[str],
    decomposition_lookup: Optional[dict[str, str]] = None,
) -> Optional[dict]:
    source = unihan.get(simplified) or unihan.get(traditional)
    if source is None:
        return None

    pinyin = source.get("mandarin") or source.get("hanyu_pinyin") or []
    english = normalize_senses(str(source.get("definition", "")).strip())
    decomposition = ids_data.get(simplified) or ids_data.get(traditional) or ""

    entry = {
        "character": simplified,
        "simplified": simplified,
        "traditional": traditional,
        "pinyin": pinyin,
        "zhuyin": pinyin_list_to_zhuyin(pinyin),
        "english": english,
        "explosion": build_explosion(
            decomposition,
            decomposition_lookup,
            nested_ids_data=ids_data,
            reasonable_component_forms=reasonable_component_forms,
        ),
    }
    normalized = normalize_entry(entry)
    if not normalized["character"] or not normalized["pinyin"] or not normalized["zhuyin"]:
        return None
    return normalized


def build_glm_prompt(batch: list[dict]) -> str:
    return (
        "Return a JSON object with key \"entries\" containing one object per input row in the same order. "
        "Use this exact schema for each object: "
        "{\"character\":string,\"simplified\":string,\"traditional\":string,"
        "\"pinyin\":[string],\"zhuyin\":[string],\"english\":[string],"
        "\"explosion\":{\"analysis\":{\"expression\":string,\"parts\":[string]},"
        "\"synthesis\":{\"containingCharacters\":[string],\"phraseUse\":[string],"
        "\"homophones\":{\"sameTone\":[string],\"differentTone\":[string]}},"
        "\"meaningMap\":{\"synonyms\":[string],\"antonyms\":[string]}}}. "
        "Rules: keep arrays deduplicated, keep english concise and character-level, use visible components in explosion, "
        "preserve the provided simplified, traditional, pinyin, zhuyin, and explosion values unless they are clearly invalid, "
        "and fill missing english values. Do not include markdown or commentary. "
        f"Rows: {json.dumps(batch, ensure_ascii=False)}"
    )


def request_glm_batch(api_key: str, base_url: str, model: str, batch: list[dict]) -> list[dict]:
    payload = {
        "model": model,
        "system": (
            "You build a Chinese character index for learners. "
            "Return strict JSON only and follow the requested schema exactly."
        ),
        "messages": [
            {
                "role": "user",
                "content": build_glm_prompt(batch),
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
            if attempt == 2:
                raise RuntimeError(f"GLM request failed with HTTP {exc.code}: {body}") from exc
            time.sleep(2**attempt)
        except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
            if attempt == 2:
                raise RuntimeError(f"GLM request failed: {exc}") from exc
            time.sleep(2**attempt)

    if response_body is None:
        raise RuntimeError("GLM request failed without a response body")

    envelope = json.loads(response_body)
    content_blocks = envelope.get("content", [])
    content = "\n\n".join(
        block.get("text", "").strip()
        for block in content_blocks
        if isinstance(block, dict) and block.get("type") == "text" and block.get("text", "").strip()
    ).strip()
    if not content:
        raise RuntimeError("GLM response did not contain message content")

    decoded = json.loads(extract_json_object(content))
    entries = decoded.get("entries")
    if not isinstance(entries, list):
        raise RuntimeError("GLM response did not contain an entries array")
    if len(entries) != len(batch):
        raise RuntimeError(f"GLM response returned {len(entries)} entries for {len(batch)} inputs")

    return [normalize_entry(entry) for entry in entries]


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


def build_containing_character_map(ids_data: dict[str, str]) -> dict[str, list[str]]:
    containing: dict[str, list[str]] = {}
    for character, decomposition in ids_data.items():
        if not decomposition or decomposition == "？":
            continue
        node, _ = parse_ids(decomposition)
        seen_parts: set[str] = set()
        for part in flatten_ids(node):
            if part in seen_parts:
                continue
            seen_parts.add(part)
            containing.setdefault(part, []).append(character)
    return containing


def normalize_phrase_candidate(value: str) -> str:
    normalized = value.strip(PHRASE_TRIM_CHARS)
    normalized = re.sub(r"\s+", "", normalized)
    return normalized.strip(PHRASE_TRIM_CHARS)


def phrase_candidate_quality(value: str) -> int:
    quality = 0
    length = len(value)
    if 2 <= length <= 6:
        quality += 2
    elif length in {7, 8}:
        quality += 1

    if value:
        quality += -4 if value[0] in PHRASE_WEAK_LEADING_CHARS else 1
        quality += -4 if value[-1] in PHRASE_WEAK_TRAILING_CHARS else 1
        if any(value.endswith(suffix) for suffix in PHRASE_META_SUFFIXES):
            quality -= 3

    return quality


def append_phrase_usage_record(
    records: list[tuple[str, int, str]],
    book_id: str,
    weight: int,
    value: object,
) -> None:
    if weight <= 0 or not isinstance(value, str):
        return
    text = value.strip()
    if not text:
        return
    records.append((book_id, weight, text))


def phrase_usage_total_weight(book_id: str, weight: int) -> int:
    return weight * CURRICULUM_BOOK_PRIORITY.get(book_id, 2)


def phrase_candidate_rank_score(book_priority: int, source_weight: int) -> int:
    return (book_priority * PHRASE_BOOK_PRIORITY_WEIGHT) + (
        source_weight * PHRASE_SOURCE_WEIGHT
    )


def extract_section_phrase_usage_records(
    book_id: str,
    section: object,
    *,
    title_weight: int,
    summary_weight: int,
    text_weight: int,
    reading_unit_weight: int,
    supplemental_weight: int,
) -> list[tuple[str, int, str]]:
    if not isinstance(section, dict):
        return []

    records: list[tuple[str, int, str]] = []
    append_phrase_usage_record(records, book_id, title_weight, section.get("title"))
    append_phrase_usage_record(records, book_id, summary_weight, section.get("summary"))
    append_phrase_usage_record(records, book_id, text_weight, section.get("text"))

    for reading_unit in section.get("reading_units", []):
        if isinstance(reading_unit, dict):
            append_phrase_usage_record(records, book_id, reading_unit_weight, reading_unit.get("text"))

    append_phrase_usage_record(records, book_id, supplemental_weight, section.get("supplemental_text"))
    for supplemental_unit in section.get("supplemental_units", []):
        if isinstance(supplemental_unit, dict):
            append_phrase_usage_record(records, book_id, supplemental_weight, supplemental_unit.get("text"))

    return records


def iter_phrase_usage_records(content_root: Path) -> Iterator[tuple[str, int, str]]:
    for path in sorted(content_root.glob("books/**/*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        relative_path = path.relative_to(content_root)
        parts = relative_path.parts
        book_id = parts[1] if len(parts) > 1 else path.stem

        if "commentary" in parts:
            yield from extract_section_phrase_usage_records(
                book_id,
                payload.get("commentary"),
                title_weight=1,
                summary_weight=1,
                text_weight=1,
                reading_unit_weight=1,
                supplemental_weight=1,
            )
            continue

        if "chapters" in parts:
            yield from extract_section_phrase_usage_records(
                book_id,
                payload.get("chapter"),
                title_weight=5,
                summary_weight=4,
                text_weight=4,
                reading_unit_weight=4,
                supplemental_weight=2,
            )
            continue

        if path.name == "catalog.json":
            catalog_records: list[tuple[str, int, str]] = []
            append_phrase_usage_record(catalog_records, book_id, 3, payload.get("title"))
            for chapter in payload.get("chapters", []):
                if isinstance(chapter, dict):
                    append_phrase_usage_record(catalog_records, book_id, 5, chapter.get("title"))
                    append_phrase_usage_record(catalog_records, book_id, 4, chapter.get("summary"))
            for chapter in payload.get("commentary_chapters", []):
                if isinstance(chapter, dict):
                    append_phrase_usage_record(catalog_records, book_id, 1, chapter.get("title"))
                    append_phrase_usage_record(catalog_records, book_id, 1, chapter.get("summary"))
            if not catalog_records:
                for raw_text in iter_book_json_string_values(payload):
                    append_phrase_usage_record(catalog_records, book_id, 2, raw_text)
            yield from catalog_records
            continue

        for raw_text in iter_book_json_string_values(payload):
            yield (book_id, 2, raw_text)


def rank_phrase_candidates(
    candidate_counts: dict[str, int],
    candidate_has_direct_segments: dict[str, bool],
    candidate_best_rank_scores: dict[str, int],
    candidate_best_source_weights: dict[str, int],
    first_seen_order: dict[str, int],
) -> list[str]:
    # Favor whole-segment phrases over clipped fallback windows, then prefer
    # candidates whose strongest occurrence balances curriculum priority with
    # source strength.
    return sorted(
        candidate_counts,
        key=lambda candidate: (
            0 if candidate_has_direct_segments.get(candidate) else 1,
            -candidate_best_rank_scores[candidate],
            -phrase_candidate_quality(candidate),
            -candidate_best_source_weights[candidate],
            -candidate_counts[candidate],
            len(candidate),
            first_seen_order[candidate],
            candidate,
        ),
    )


def extract_phrase_candidates(text: str, target: str) -> list[tuple[str, bool]]:
    candidates: list[tuple[str, bool]] = []
    for segment in re.split(r"[，。！？；：、\s]+", text):
        segment = normalize_phrase_candidate(segment)
        if not segment or target not in segment:
            continue
        if 1 < len(segment) <= 8:
            candidates.append((segment, True))
            continue

        for index, char in enumerate(segment):
            if char != target:
                continue
            start = max(0, index - 2)
            end = min(len(segment), index + 3)
            snippet = normalize_phrase_candidate(segment[start:end])
            if len(snippet) > 1:
                candidates.append((snippet, False))
    return candidates


def build_phrase_usage(content_root: Path, ts_map: dict[str, str], st_map: dict[str, str]) -> dict[str, list[str]]:
    candidate_book_weights: dict[str, dict[str, dict[str, int]]] = defaultdict(
        lambda: defaultdict(dict)
    )
    candidate_has_direct_segments: dict[str, dict[str, bool]] = defaultdict(dict)
    candidate_best_rank_scores: dict[str, dict[str, int]] = defaultdict(dict)
    candidate_best_source_weights: dict[str, dict[str, int]] = defaultdict(dict)
    first_seen_order: dict[str, dict[str, int]] = defaultdict(dict)
    for book_id, weight, raw_text in iter_phrase_usage_records(content_root):
        text = raw_text.strip()
        if not text:
            continue
        seen_characters_in_text: set[str] = set()
        seen_candidates_in_text: dict[str, set[str]] = defaultdict(set)
        for char in text:
            if not is_cjk_character(char):
                continue
            if char in seen_characters_in_text:
                continue
            seen_characters_in_text.add(char)
            simplified, _ = canonical_character(char, ts_map, st_map)
            for candidate, from_direct_segment in extract_phrase_candidates(text, char):
                if candidate in seen_candidates_in_text[simplified]:
                    continue
                seen_candidates_in_text[simplified].add(candidate)
                priority = CURRICULUM_BOOK_PRIORITY.get(book_id, 2)
                total_weight = phrase_usage_total_weight(book_id, weight)
                existing_weight = candidate_book_weights[simplified][candidate].get(book_id, 0)
                if total_weight > existing_weight:
                    candidate_book_weights[simplified][candidate][book_id] = total_weight
                if from_direct_segment:
                    candidate_has_direct_segments[simplified][candidate] = True
                rank_score = phrase_candidate_rank_score(priority, weight)
                current_best_rank_score = candidate_best_rank_scores[simplified].get(candidate, 0)
                if rank_score > current_best_rank_score:
                    candidate_best_rank_scores[simplified][candidate] = rank_score
                    candidate_best_source_weights[simplified][candidate] = weight
                elif rank_score == current_best_rank_score:
                    current_best_source_weight = candidate_best_source_weights[simplified].get(candidate, 0)
                    if weight > current_best_source_weight:
                        candidate_best_source_weights[simplified][candidate] = weight
                current_best_source_weight = candidate_best_source_weights[simplified].get(candidate, 0)
                if weight > current_best_source_weight:
                    candidate_best_source_weights[simplified][candidate] = weight
                first_seen_order[simplified].setdefault(
                    candidate,
                    len(first_seen_order[simplified]),
                )

    usage: dict[str, list[str]] = {}
    for simplified, candidate_weights in candidate_book_weights.items():
        counts = {
            candidate: sum(book_weights.values())
            for candidate, book_weights in candidate_weights.items()
        }
        usage[simplified] = rank_phrase_candidates(
            counts,
            candidate_has_direct_segments[simplified],
            candidate_best_rank_scores[simplified],
            candidate_best_source_weights[simplified],
            first_seen_order[simplified],
        )
    return usage


def build_entry_containing_map(entries: dict[str, dict]) -> dict[str, list[str]]:
    containing: dict[str, list[str]] = {}
    for key, entry in entries.items():
        for part in entry.get("explosion", {}).get("analysis", {}).get("parts", []):
            if not part or not is_cjk_character(part) or part == entry["character"]:
                continue
            if part not in containing:
                containing[part] = []
            if key not in containing[part]:
                containing[part].append(key)
    return containing


def enrich_explosions(entries: dict[str, dict], ids_data: dict[str, str], content_root: Path, ts_map: dict[str, str], st_map: dict[str, str]) -> dict[str, dict]:
    containing_map = build_containing_character_map(ids_data)
    entry_containing_map = build_entry_containing_map(entries)
    phrase_usage = build_phrase_usage(content_root, ts_map, st_map)
    primary_by_exact_pinyin: dict[str, list[str]] = {}
    primary_by_toneless_pinyin: dict[str, list[str]] = {}

    for entry in entries.values():
        primary_pinyin = entry["pinyin"][0] if entry["pinyin"] else ""
        if not primary_pinyin:
            continue
        primary_by_exact_pinyin.setdefault(primary_pinyin, []).append(entry["character"])
        toneless = normalize_pinyin_syllable(primary_pinyin)[0]
        if toneless:
            primary_by_toneless_pinyin.setdefault(toneless, []).append(entry["character"])

    for key, entry in entries.items():
        analysis = entry["explosion"]["analysis"]
        entry["explosion"]["analysis"] = {
            "expression": analysis["expression"],
            "parts": analysis["parts"],
        }

        containing_characters = (
            containing_map.get(entry["simplified"], [])
            + containing_map.get(entry["traditional"], [])
            + entry_containing_map.get(entry["simplified"], [])
            + entry_containing_map.get(entry["traditional"], [])
        )
        ordered_containing: list[str] = []
        for candidate in containing_characters:
            if candidate == entry["character"] or candidate in ordered_containing:
                continue
            ordered_containing.append(candidate)
            if len(ordered_containing) >= 5:
                break

        primary_pinyin = entry["pinyin"][0] if entry["pinyin"] else ""
        same_tone: list[str] = []
        different_tone: list[str] = []
        if primary_pinyin:
            for candidate in primary_by_exact_pinyin.get(primary_pinyin, []):
                if candidate != entry["character"] and candidate not in same_tone:
                    same_tone.append(candidate)
            toneless = normalize_pinyin_syllable(primary_pinyin)[0]
            for candidate in primary_by_toneless_pinyin.get(toneless, []):
                if candidate == entry["character"] or candidate in same_tone or candidate in different_tone:
                    continue
                different_tone.append(candidate)

        entry["explosion"]["synthesis"] = {
            "containingCharacters": ordered_containing,
            "phraseUse": phrase_usage.get(key, [])[:5],
            "homophones": {
                "sameTone": same_tone[:5],
                "differentTone": different_tone[:5],
            },
        }
        entry["explosion"]["meaningMap"] = {
            "synonyms": entry["explosion"]["meaningMap"].get("synonyms", []),
            "antonyms": entry["explosion"]["meaningMap"].get("antonyms", []),
        }

    return entries


def extract_gloss_phrases(values: list[str]) -> set[str]:
    phrases: set[str] = set()
    for value in values:
        for part in re.split(r"[,;/()]", value):
            normalized = " ".join(part.strip().lower().split())
            if not normalized or normalized in GLOSS_STOP_PHRASES:
                continue
            candidates = [
                normalized,
                GLOSS_LEADING_ARTICLE_PATTERN.sub("", normalized),
                GLOSS_LEADING_INFINITIVE_PATTERN.sub("", normalized),
                GLOSS_LEADING_INFINITIVE_PATTERN.sub(
                    "",
                    GLOSS_LEADING_ARTICLE_PATTERN.sub("", normalized),
                ),
            ]
            for candidate in candidates:
                if not candidate or candidate in GLOSS_STOP_PHRASES:
                    continue
                phrases.add(candidate)
    return phrases


def extract_gloss_reference_characters(values: list[str], *, exclude: str = "") -> list[str]:
    references: list[str] = []
    seen: set[str] = set()
    for value in values:
        for match in GLOSS_REFERENCE_PATTERN.finditer(value):
            for char in match.group(1):
                if not is_cjk_character(char):
                    continue
                if char == exclude or char in seen:
                    continue
                seen.add(char)
                references.append(char)
    return references


def build_entry_form_lookup(entries: dict[str, dict]) -> dict[str, str]:
    lookup: dict[str, str] = {}
    for key, entry in entries.items():
        for value in (
            key,
            entry.get("character", ""),
            entry.get("simplified", ""),
            entry.get("traditional", ""),
            *entry.get("aliases", []),
        ):
            form = str(value).strip()
            if form and form not in lookup:
                lookup[form] = key
    return lookup


def resolve_gloss_reference_entries(
    character: str,
    english_values: list[str],
    form_lookup: dict[str, str],
) -> list[str]:
    references: list[str] = []
    for reference in extract_gloss_reference_characters(english_values, exclude=character):
        canonical_reference = form_lookup.get(reference)
        if canonical_reference is None or canonical_reference == character:
            continue
        if canonical_reference in references:
            continue
        references.append(canonical_reference)
    return references


def build_phrase_index(entries: dict[str, dict]) -> tuple[dict[str, set[str]], dict[str, list[str]]]:
    phrase_sets: dict[str, set[str]] = {}
    phrase_index: dict[str, list[str]] = defaultdict(list)

    for character in sorted(entries.keys()):
        phrases = extract_gloss_phrases(entries[character]["english"])
        phrase_sets[character] = phrases
        for phrase in sorted(phrases):
            phrase_index[phrase].append(character)

    return phrase_sets, phrase_index


def build_synonym_list(
    character: str,
    phrase_sets: dict[str, set[str]],
    phrase_index: dict[str, list[str]],
) -> list[str]:
    scores: dict[str, int] = defaultdict(int)
    for phrase in phrase_sets.get(character, set()):
        for candidate in phrase_index.get(phrase, []):
            if candidate == character:
                continue
            scores[candidate] += 1

    ranked = sorted(scores.items(), key=lambda item: (-item[1], item[0]))
    return [candidate for candidate, score in ranked if score >= 1][:5]


def build_antonym_list(
    character: str,
    phrase_sets: dict[str, set[str]],
    phrase_index: dict[str, list[str]],
) -> list[str]:
    target_phrases = phrase_sets.get(character, set())
    scores: dict[str, int] = defaultdict(int)

    for left_phrases, right_phrases in MEANING_MAP_ANTONYM_CONCEPTS.values():
        left_hits = target_phrases & left_phrases
        right_hits = target_phrases & right_phrases

        if left_hits:
            candidate_hits: dict[str, int] = defaultdict(int)
            for phrase in right_phrases:
                for candidate in phrase_index.get(phrase, []):
                    if candidate == character:
                        continue
                    candidate_hits[candidate] += 1
            for candidate, hit_count in candidate_hits.items():
                same_side_hits = len(phrase_sets.get(candidate, set()) & left_phrases)
                score = len(left_hits) + hit_count - same_side_hits
                if score > 0:
                    scores[candidate] += score

        if right_hits:
            candidate_hits = defaultdict(int)
            for phrase in left_phrases:
                for candidate in phrase_index.get(phrase, []):
                    if candidate == character:
                        continue
                    candidate_hits[candidate] += 1
            for candidate, hit_count in candidate_hits.items():
                same_side_hits = len(phrase_sets.get(candidate, set()) & right_phrases)
                score = len(right_hits) + hit_count - same_side_hits
                if score > 0:
                    scores[candidate] += score

    ranked = sorted(scores.items(), key=lambda item: (-item[1], item[0]))
    return [candidate for candidate, score in ranked if score >= 2][:5]


def rank_related_characters(
    candidates: list[str],
    entries: dict[str, dict],
) -> list[str]:
    original_order = {candidate: index for index, candidate in enumerate(candidates)}

    def sort_key(candidate: str) -> tuple[int, int, int, str]:
        entry = entries.get(candidate)
        has_phrase_use = bool(entry and entry["explosion"]["synthesis"].get("phraseUse"))
        return (
            0 if is_basic_cjk_character(candidate) else 1,
            0 if has_phrase_use else 1,
            original_order[candidate],
            candidate,
        )

    return sorted(candidates, key=sort_key)


def mirror_antonym_relationships(entries: dict[str, dict]) -> dict[str, dict]:
    for character, entry in entries.items():
        antonyms = entry["explosion"].get("meaningMap", {}).get("antonyms", [])
        for antonym in antonyms:
            counterpart = entries.get(antonym)
            if counterpart is None:
                continue
            existing_map = counterpart["explosion"].setdefault("meaningMap", {})
            existing_map["antonyms"] = merge_string_lists(existing_map.get("antonyms"), [character])

    for entry in entries.values():
        existing_map = entry["explosion"].setdefault("meaningMap", {})
        existing_map["antonyms"] = rank_related_characters(
            merge_string_lists(existing_map.get("antonyms")),
            entries,
        )[:5]

    return entries


def inherit_gloss_reference_details(
    entries: dict[str, dict],
    form_lookup: dict[str, str],
) -> dict[str, dict]:
    for character, entry in entries.items():
        references = resolve_gloss_reference_entries(character, entry["english"], form_lookup)

        if not entry["explosion"]["synthesis"].get("phraseUse"):
            inherited_phrase_use: list[str] = []
            for reference in references:
                for phrase in entries[reference]["explosion"]["synthesis"].get("phraseUse", []):
                    if phrase not in inherited_phrase_use:
                        inherited_phrase_use.append(phrase)
            if not inherited_phrase_use:
                for synonym in entry["explosion"]["meaningMap"].get("synonyms", []):
                    synonym_entry = entries.get(synonym)
                    if synonym_entry is None:
                        continue
                    for phrase in synonym_entry["explosion"]["synthesis"].get("phraseUse", []):
                        if phrase not in inherited_phrase_use:
                            inherited_phrase_use.append(phrase)
            entry["explosion"]["synthesis"]["phraseUse"] = inherited_phrase_use[:5]

        if references and not entry["explosion"]["meaningMap"].get("antonyms"):
            inherited_antonyms: list[str] = []
            for reference in references:
                for antonym in entries[reference]["explosion"]["meaningMap"].get("antonyms", []):
                    if antonym == character or antonym in inherited_antonyms:
                        continue
                    inherited_antonyms.append(antonym)
            entry["explosion"]["meaningMap"]["antonyms"] = inherited_antonyms[:5]

    return entries


def enrich_meaning_maps(entries: dict[str, dict]) -> dict[str, dict]:
    phrase_sets, phrase_index = build_phrase_index(entries)
    form_lookup = build_entry_form_lookup(entries)

    for character, entry in entries.items():
        generated_synonyms = build_synonym_list(character, phrase_sets, phrase_index)
        generated_antonyms = build_antonym_list(character, phrase_sets, phrase_index)
        referenced_synonyms = resolve_gloss_reference_entries(character, entry["english"], form_lookup)
        curated_antonyms = [
            candidate
            for candidate in MEANING_MAP_CORE_ANTONYM_OVERRIDES.get(character, [])
            if candidate in entries and candidate != character
        ]
        existing_map = entry["explosion"].get("meaningMap", {})
        entry["explosion"]["meaningMap"] = {
            "synonyms": rank_related_characters(
                merge_string_lists(
                    existing_map.get("synonyms"),
                    referenced_synonyms,
                    generated_synonyms,
                ),
                entries,
            )[:5],
            "antonyms": rank_related_characters(
                merge_string_lists(
                    curated_antonyms,
                    existing_map.get("antonyms"),
                    generated_antonyms,
                ),
                entries,
            )[:5],
        }

    inherit_gloss_reference_details(entries, form_lookup)
    return mirror_antonym_relationships(entries)


def enrich_with_deterministic_containing_characters(
    entries: dict[str, dict],
    seed_index_entries: dict[str, dict],
    manual_seed_entries: dict[str, dict],
    dictionary: dict[str, dict],
    unihan: dict[str, dict],
    ids_data: dict[str, str],
    ts_map: dict[str, str],
    st_map: dict[str, str],
    reasonable_component_forms: set[str],
    decomposition_lookup: Optional[dict[str, str]] = None,
) -> dict[str, int]:
    candidates: set[str] = set()
    for entry in entries.values():
        for value in entry.get("explosion", {}).get("synthesis", {}).get(
            "containingCharacters", []
        ):
            candidate = str(value).strip()
            if candidate:
                candidates.add(candidate)

    added = 0
    skipped = 0
    for candidate in sorted(candidates):
        simplified, traditional = canonical_character(candidate, ts_map, st_map)
        if simplified in entries:
            continue

        entry = deterministic_entry(
            simplified,
            traditional,
            dictionary,
            ids_data,
            reasonable_component_forms,
            decomposition_lookup,
        )
        entry = merge_entries(
            entry,
            supplemental_entry(
                simplified,
                traditional,
                unihan,
                ids_data,
                reasonable_component_forms,
                decomposition_lookup,
            ),
        )
        entry = merge_entries(
            entry,
            find_seed_entry(seed_index_entries, simplified, traditional),
        )
        entry = apply_seed_overrides(
            entry,
            find_seed_entry(manual_seed_entries, simplified, traditional),
        )
        if not is_complete_entry(entry):
            skipped += 1
            continue

        entries[simplified] = entry
        added += 1

    return {
        "containing_character_candidates": len(candidates),
        "containing_character_entries_added": added,
        "containing_character_entries_skipped": skipped,
    }


def enrich_with_deterministic_component_characters(
    entries: dict[str, dict],
    content_root: Path,
    seed_index_entries: dict[str, dict],
    manual_seed_entries: dict[str, dict],
    dictionary: dict[str, dict],
    unihan: dict[str, dict],
    ids_data: dict[str, str],
    ts_map: dict[str, str],
    st_map: dict[str, str],
    reasonable_component_forms: set[str],
    decomposition_lookup: Optional[dict[str, str]] = None,
) -> dict[str, int]:
    candidates = list(iter_component_character_pairs(content_root, ts_map, st_map))

    added = 0
    skipped = 0
    for simplified, traditional in candidates:
        if simplified in entries:
            continue

        entry = deterministic_entry(
            simplified,
            traditional,
            dictionary,
            ids_data,
            reasonable_component_forms,
            decomposition_lookup,
        )
        entry = merge_entries(
            entry,
            supplemental_entry(
                simplified,
                traditional,
                unihan,
                ids_data,
                reasonable_component_forms,
                decomposition_lookup,
            ),
        )
        entry = merge_entries(
            entry,
            find_seed_entry(seed_index_entries, simplified, traditional),
        )
        entry = apply_seed_overrides(
            entry,
            find_seed_entry(manual_seed_entries, simplified, traditional),
        )
        if not is_complete_entry(entry):
            skipped += 1
            continue

        entries[simplified] = entry
        added += 1

    return {
        "component_character_candidates": len(candidates),
        "component_character_entries_added": added,
        "component_character_entries_skipped": skipped,
    }


def write_index(path: Path, entries: dict[str, dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"entries": [entries[key] for key in sorted(entries.keys())]}
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    dictionary = load_makemeahanzi_dictionary()
    ts_map = load_opencc_map(OPENCC_TS_URL)
    st_map = load_opencc_map(OPENCC_ST_URL)
    traditional_variants_by_simplified = load_opencc_traditional_variants(OPENCC_TS_URL)
    unihan = load_unihan_data()
    ids_data = load_ids_data()
    character_frequencies = collect_character_frequencies(args.content_root)
    reasonable_component_forms = load_reasonable_component_forms(args.content_root)
    decomposition_lookup = build_reasonable_decomposition_lookup(
        dictionary,
        ids_data,
        reasonable_component_forms,
    )
    seed_index_entries = load_seed_entries(args.seed_index)
    manual_seed_entries = load_seed_entries(args.manual_seed)
    alias_forms_by_simplified = build_alias_forms(
        args.content_root,
        merge_seed_entry_maps(seed_index_entries, manual_seed_entries),
        ts_map,
        st_map,
    )

    seen_canonical: set[str] = set()
    canonical_pairs: list[tuple[str, str]] = []
    for char in collect_unique_characters(args.content_root):
        simplified, traditional = canonical_character(char, ts_map, st_map)
        if simplified in seen_canonical:
            continue
        seen_canonical.add(simplified)
        canonical_pairs.append((simplified, traditional))
    for simplified, traditional in seed_canonical_pairs(manual_seed_entries):
        if simplified in seen_canonical:
            continue
        seen_canonical.add(simplified)
        canonical_pairs.append((simplified, traditional))

    if args.limit:
        canonical_pairs = canonical_pairs[: args.limit]

    entries: dict[str, dict] = {}
    missing_for_glm: list[dict] = []

    for simplified, traditional in canonical_pairs:
        entry = deterministic_entry(
            simplified,
            traditional,
            dictionary,
            ids_data,
            reasonable_component_forms,
            decomposition_lookup,
        )
        entry = merge_entries(
            entry,
            supplemental_entry(
                simplified,
                traditional,
                unihan,
                ids_data,
                reasonable_component_forms,
                decomposition_lookup,
            ),
        )
        entry = merge_entries(
            entry,
            find_seed_entry(seed_index_entries, simplified, traditional),
        )
        entry = apply_seed_overrides(
            entry,
            find_seed_entry(manual_seed_entries, simplified, traditional),
        )
        if not is_complete_entry(entry):
            missing_for_glm.append(
                entry
                or {
                    "character": simplified,
                    "simplified": simplified,
                    "traditional": traditional,
                    "pinyin": [],
                    "zhuyin": [],
                    "english": [],
                    "explosion": build_explosion(""),
                }
            )
            continue
        entries[simplified] = entry

    api_key = os.environ.get("GLM_API_KEY", "").strip()
    base_url = os.environ.get("GLM_BASE_URL", DEFAULT_BASE_URL).strip() or DEFAULT_BASE_URL
    model = os.environ.get("GLM_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL

    print(
        json.dumps(
            {
                "content_root": str(args.content_root),
                "output": str(args.output),
                "canonical_characters": len(canonical_pairs),
                "deterministic_entries": len(entries),
                "glm_missing_entries": len(missing_for_glm),
                "glm_enabled": bool(api_key),
                "base_url": base_url if api_key else "",
                "model": model if api_key else "",
            },
            ensure_ascii=False,
        )
    )

    if missing_for_glm and not api_key:
        raise SystemExit("GLM_API_KEY is required for characters missing deterministic source data")

    for start in range(0, len(missing_for_glm), args.glm_batch_size):
        batch = missing_for_glm[start : start + args.glm_batch_size]
        generated = request_glm_batch(api_key, base_url, model, batch)
        for entry in generated:
            entries[entry["character"]] = entry
        print(
            json.dumps(
                {
                    "glm_completed": min(start + len(batch), len(missing_for_glm)),
                    "glm_remaining": max(len(missing_for_glm) - (start + len(batch)), 0),
                    "stored_entries": len(entries),
                },
                ensure_ascii=False,
            )
        )

    component_report = enrich_with_deterministic_component_characters(
        entries,
        args.content_root,
        seed_index_entries,
        manual_seed_entries,
        dictionary,
        unihan,
        ids_data,
        ts_map,
        st_map,
        reasonable_component_forms,
        decomposition_lookup,
    )
    enrich_explosions(entries, ids_data, args.content_root, ts_map, st_map)
    containing_report = enrich_with_deterministic_containing_characters(
        entries,
        seed_index_entries,
        manual_seed_entries,
        dictionary,
        unihan,
        ids_data,
        ts_map,
        st_map,
        reasonable_component_forms,
        decomposition_lookup,
    )
    if containing_report["containing_character_entries_added"] > 0:
        enrich_explosions(entries, ids_data, args.content_root, ts_map, st_map)
    enrich_meaning_maps(entries)
    apply_aliases_to_entries(
        entries,
        alias_forms_by_simplified,
        character_frequencies,
        traditional_variants_by_simplified,
    )
    write_index(args.output, entries)
    print(
        json.dumps(
            {
                "stored_entries": len(entries),
                **component_report,
                **containing_report,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
