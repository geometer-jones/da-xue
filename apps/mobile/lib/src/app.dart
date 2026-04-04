import 'dart:async';
import 'dart:math' as math;

import 'package:daxue_mobile/src/backend_client.dart';
import 'package:daxue_mobile/src/flashcard_store.dart';
import 'package:daxue_mobile/src/line_study_store.dart';
import 'package:daxue_mobile/src/reading_progress_store.dart';
import 'package:daxue_mobile/src/title_translations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String _chapterDetailTitle({required int order, required String title}) {
  final trimmedTitle = title.trim();
  if (trimmedTitle.isEmpty) {
    return '$order.';
  }

  return '$order. $trimmedTitle';
}

String _chapterMenuTitle({required int order, required String title}) {
  final trimmedTitle = title.trim();
  if (trimmedTitle.isEmpty) {
    return '$order.';
  }

  return '$order. $trimmedTitle';
}

String _topLevelMenuTitle({required int index, required String title}) {
  final trimmedTitle = title.trim();
  if (trimmedTitle.isEmpty) {
    return '$index.';
  }

  return '$index. $trimmedTitle';
}

String _countLabel(int count, String singular, String plural) {
  return '$count ${count == 1 ? singular : plural}';
}

int _totalReadingUnitCount(BookDetail book) {
  return book.chapters.fold<int>(
    0,
    (total, chapter) => total + chapter.readingUnitCount,
  );
}

String _componentsCountSummary(CharacterComponentsDataset dataset) {
  return _countLabel(
    dataset.groupedComponentCount,
    'grouped component',
    'grouped components',
  );
}

String _componentChapterCountSummary(
  Iterable<CharacterComponentEntry> entries,
) {
  var lineCount = 0;
  var characterCount = 0;
  for (final entry in entries) {
    lineCount += 1;
    characterCount += entry.memberCount;
  }

  return '${_countLabel(lineCount, 'line', 'lines')} • $characterCount chars';
}

String _bookCountSummary(BookDetail book) {
  final lineCount = _totalReadingUnitCount(book);
  final characterCount = book.chapters.fold<int>(
    0,
    (total, chapter) => total + chapter.characterCount,
  );

  if (book.id == 'chengyu-catalog') {
    return '$lineCount chengyu';
  }

  return '${_countLabel(book.chapterCount, 'chapter', 'chapters')} • '
      '${_countLabel(lineCount, 'line', 'lines')} • '
      '$characterCount chars';
}

String _chapterCountSummary(ChapterDetail chapter) {
  final lineCount = chapter.readingUnits.length;
  return '${_countLabel(lineCount, 'line', 'lines')} • '
      '${chapter.characterCount} chars';
}

String _chapterSummaryCountSummary(ChapterSummary chapter) {
  return '${_countLabel(chapter.readingUnitCount, 'line', 'lines')} • '
      '${chapter.characterCount} chars';
}

String _readingUnitPositionSummary({
  required int lineNumber,
  required int totalLineCount,
}) {
  return 'Line $lineNumber of $totalLineCount';
}

const String _characterComponentsProgressScopeId = 'character-components';

String _characterComponentsChapterStorageId(int chapterIndex) {
  return 'component-chapter-${(chapterIndex + 1).toString().padLeft(3, '0')}';
}

int? _characterComponentsChapterIndexFromStorageId(String chapterId) {
  final match = RegExp(r'^component-chapter-(\d+)$').firstMatch(chapterId);
  if (match == null) {
    return null;
  }

  final parsedIndex = int.tryParse(match.group(1) ?? '');
  if (parsedIndex == null || parsedIndex <= 0) {
    return null;
  }

  return parsedIndex - 1;
}

String _savedLineStudyCountSummary({
  required int translationCount,
  required int responseCount,
  bool includeLabel = true,
}) {
  final summary =
      '${_countLabel(translationCount, 'translation', 'translations')} • '
      '${_countLabel(responseCount, 'response', 'responses')}';
  if (!includeLabel) {
    return summary;
  }

  return 'Saved locally: $summary';
}

TextStyle? _counterTextStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodySmall;
}

class _LineStudyCounts {
  const _LineStudyCounts({this.translationCount = 0, this.responseCount = 0});

  final int translationCount;
  final int responseCount;

  _LineStudyCounts operator +(_LineStudyCounts other) {
    return _LineStudyCounts(
      translationCount: translationCount + other.translationCount,
      responseCount: responseCount + other.responseCount,
    );
  }
}

_LineStudyCounts _countLineStudyEntries(Iterable<LineStudyEntry> entries) {
  return _LineStudyCounts(
    translationCount: entries.where((entry) => entry.hasTranslation).length,
    responseCount: entries.where((entry) => entry.hasResponse).length,
  );
}

String _buildTranslationFeedbackPrompt({
  required String translation,
  String previousTranslation = '',
}) {
  final trimmedTranslation = translation.trim();
  final trimmedPreviousTranslation = previousTranslation.trim();
  final hasPreviousTranslation =
      trimmedPreviousTranslation.isNotEmpty &&
      trimmedPreviousTranslation != trimmedTranslation;
  final builder = StringBuffer();

  if (hasPreviousTranslation) {
    builder
      ..write('My previous English translation of this line:\n')
      ..write(trimmedPreviousTranslation)
      ..write('\n\n');
  }

  builder
    ..write(
      hasPreviousTranslation
          ? 'My updated English translation of this line:\n'
          : 'I drafted this English translation for the current Classical Chinese line:\n',
    )
    ..write(trimmedTranslation)
    ..write('\n\n')
    ..write(
      'Respond as a careful researcher, philosopher, and linguist, using whichever lens best fits this line. ',
    )
    ..write(
      hasPreviousTranslation
          ? 'Compare the updated version against both the current line and the previous draft. '
          : 'Evaluate it against the current line only. ',
    )
    ..write(
      hasPreviousTranslation
          ? 'Tell me what the revision improves, what it still misses or distorts, and whether it introduces any regression. '
          : 'Tell me what it captures, what it misses or distorts, and how you would revise it if a materially better version is obvious. ',
    )
    ..write(
      hasPreviousTranslation
          ? 'Give one revised translation only if it is materially better than the updated draft. '
          : '',
    )
    ..write(
      'Prioritize fidelity first, then natural English. Keep it brief, specific, and text-grounded.',
    );
  return builder.toString();
}

String _buildResponseFeedbackPrompt({
  required String chineseLine,
  required String response,
  String learnerTranslation = '',
}) {
  final builder = StringBuffer()
    ..write('Current Classical Chinese line:\n')
    ..write(chineseLine.trim())
    ..write('\n\n');
  final trimmedLearnerTranslation = learnerTranslation.trim();
  if (trimmedLearnerTranslation.isNotEmpty) {
    builder
      ..write('My translation of this line:\n')
      ..write(trimmedLearnerTranslation)
      ..write('\n\n');
  }
  builder
    ..write('I drafted this response to the current Classical Chinese line:\n')
    ..write(response.trim())
    ..write('\n\n')
    ..write(
      'Respond as a careful researcher, philosopher, and linguist, using whichever lens best fits this line. ',
    )
    ..write('Evaluate it against the current line only. ')
    ..write(
      'Tell me what is genuinely grounded in the text, where the response overreaches or misses something important, and what question, distinction, or revision would deepen it. ',
    )
    ..write(
      'Keep it brief, specific, and text-grounded. Avoid generic encouragement.',
    );
  return builder.toString();
}

String _readingUnitStatusLabel({
  required int order,
  required LineStudyEntry lineStudyEntry,
}) {
  final segments = <String>['$order'];
  if (lineStudyEntry.hasTranslation) {
    segments.add('T');
  }
  if (lineStudyEntry.hasResponse) {
    segments.add('R');
  }

  return segments.join(' ');
}

bool _hasVisibleText(String value) => value.trim().isNotEmpty;

extension<T extends StatefulWidget> on State<T> {
  bool get uiActive {
    if (!mounted) {
      return false;
    }

    final view = View.maybeOf(context);
    if (view == null) {
      return false;
    }

    return WidgetsBinding.instance.platformDispatcher.views.any(
      (candidate) => candidate.viewId == view.viewId,
    );
  }
}

int _normalizedFlashcardRandomSeed(int? seed) {
  final candidate = seed ?? DateTime.now().microsecondsSinceEpoch;
  final normalized = candidate & 0x7fffffff;
  return normalized == 0 ? 1 : normalized;
}

String _flashcardEnglishLabel(FlashcardEntry entry) {
  if (_hasVisibleText(entry.glossLabel)) {
    return entry.glossLabel;
  }

  return entry.translationEn.trim();
}

enum _FlashcardPromptKind { chinese, readingAndEnglish }

typedef _FlashcardVisibleSides = ({
  bool showChinese,
  bool showReadingAndEnglish,
});

bool _hasFlashcardChineseContent(FlashcardEntry entry) =>
    _hasVisibleText(entry.displayHeading);

bool _hasFlashcardReadingAndEnglishContent(FlashcardEntry entry) =>
    _hasVisibleText(entry.readingLabel) ||
    _hasVisibleText(_flashcardEnglishLabel(entry));

_FlashcardPromptKind _chooseFlashcardPromptKind(
  FlashcardEntry entry, {
  required math.Random random,
}) {
  final hasChinesePrompt = _hasVisibleText(entry.displayHeading);
  final hasReadingAndEnglishPrompt =
      _hasVisibleText(entry.readingLabel) &&
      _hasVisibleText(_flashcardEnglishLabel(entry));

  if (hasChinesePrompt && hasReadingAndEnglishPrompt) {
    return random.nextBool()
        ? _FlashcardPromptKind.readingAndEnglish
        : _FlashcardPromptKind.chinese;
  }
  if (hasChinesePrompt) {
    return _FlashcardPromptKind.chinese;
  }

  return _FlashcardPromptKind.readingAndEnglish;
}

_FlashcardVisibleSides _initialFlashcardVisibleSides(
  FlashcardEntry entry, {
  required math.Random random,
}) {
  final promptKind = _chooseFlashcardPromptKind(entry, random: random);
  final hasChineseContent = _hasFlashcardChineseContent(entry);
  final hasReadingAndEnglishContent = _hasFlashcardReadingAndEnglishContent(
    entry,
  );

  return switch (promptKind) {
    _FlashcardPromptKind.chinese => (
      showChinese: hasChineseContent,
      showReadingAndEnglish: !hasChineseContent && hasReadingAndEnglishContent,
    ),
    _FlashcardPromptKind.readingAndEnglish => (
      showChinese: !hasReadingAndEnglishContent && hasChineseContent,
      showReadingAndEnglish: hasReadingAndEnglishContent,
    ),
  };
}

_FlashcardVisibleSides _normalizedFlashcardVisibleSides(
  _FlashcardVisibleSides visibleSides,
  FlashcardEntry entry,
) {
  final hasChineseContent = _hasFlashcardChineseContent(entry);
  final hasReadingAndEnglishContent = _hasFlashcardReadingAndEnglishContent(
    entry,
  );
  var showChinese = hasChineseContent && visibleSides.showChinese;
  var showReadingAndEnglish =
      hasReadingAndEnglishContent && visibleSides.showReadingAndEnglish;

  if (!showChinese && !showReadingAndEnglish) {
    if (hasChineseContent) {
      showChinese = true;
    } else if (hasReadingAndEnglishContent) {
      showReadingAndEnglish = true;
    }
  }

  return (
    showChinese: showChinese,
    showReadingAndEnglish: showReadingAndEnglish,
  );
}

_FlashcardVisibleSides _toggleFlashcardVisibleSide(
  _FlashcardVisibleSides visibleSides,
  FlashcardEntry entry,
  _FlashcardPromptKind promptKind,
) {
  final normalizedVisibleSides = _normalizedFlashcardVisibleSides(
    visibleSides,
    entry,
  );
  final hasChineseContent = _hasFlashcardChineseContent(entry);
  final hasReadingAndEnglishContent = _hasFlashcardReadingAndEnglishContent(
    entry,
  );
  var showChinese = normalizedVisibleSides.showChinese;
  var showReadingAndEnglish = normalizedVisibleSides.showReadingAndEnglish;

  if (promptKind == _FlashcardPromptKind.chinese) {
    if (!hasChineseContent) {
      return normalizedVisibleSides;
    }
    showChinese = !showChinese;
  } else {
    if (!hasReadingAndEnglishContent) {
      return normalizedVisibleSides;
    }
    showReadingAndEnglish = !showReadingAndEnglish;
  }

  if (!showChinese && !showReadingAndEnglish) {
    if (promptKind == _FlashcardPromptKind.chinese &&
        hasReadingAndEnglishContent) {
      showReadingAndEnglish = true;
    } else if (promptKind == _FlashcardPromptKind.readingAndEnglish &&
        hasChineseContent) {
      showChinese = true;
    } else {
      return normalizedVisibleSides;
    }
  }

  return (
    showChinese: showChinese,
    showReadingAndEnglish: showReadingAndEnglish,
  );
}

const List<(int, int)> _cjkRanges = <(int, int)>[
  (0x2E80, 0x2FDF),
  (0x31C0, 0x31EF),
  (0x3400, 0x4DBF),
  (0x4E00, 0x9FFF),
  (0xF900, 0xFAFF),
  (0x20000, 0x2A6DF),
  (0x2A700, 0x2B73F),
  (0x2B740, 0x2B81F),
  (0x2B820, 0x2CEAF),
  (0x2CEB0, 0x2EBEF),
  (0x30000, 0x3134F),
];

bool _isCjkRune(int rune) =>
    _cjkRanges.any((range) => rune >= range.$1 && rune <= range.$2);

bool _containsChineseText(String value) => value.runes.any(_isCjkRune);

const double _readingUnitChineseLineSizeMultiplier = 1.2;
const double _exploderRootCharacterSizeMultiplier = 4.0;

List<String> _analysisBranchSymbols(CharacterExplosionAnalysis analysis) {
  final expressionParts = analysis.expression
      .split('+')
      .map((part) => part.trim())
      .where(_hasVisibleText)
      .toList();
  if (expressionParts.isNotEmpty) {
    return expressionParts;
  }

  return analysis.parts
      .map((part) => part.trim())
      .where(_hasVisibleText)
      .toList();
}

const int _analysisTreeMaxDepth = 8;

CharacterEntry? _resolveComponentReferenceEntry(
  CharacterComponentEntry? componentEntry,
  CharacterIndex characterIndex, {
  String exclude = '',
}) {
  if (componentEntry == null) {
    return null;
  }

  final excluded = exclude.trim();
  for (final candidate in [
    componentEntry.canonicalForm,
    ...componentEntry.forms,
    ...componentEntry.variantForms,
  ]) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || trimmed.runes.length != 1 || trimmed == excluded) {
      continue;
    }

    final referenceEntry = characterIndex.entryFor(trimmed);
    if (referenceEntry != null) {
      return referenceEntry;
    }
  }

  return null;
}

String _formatAnalysisComponentLabel(CharacterComponentEntry? componentEntry) {
  if (componentEntry == null) {
    return '';
  }

  final label = componentEntry.canonicalName.trim().isNotEmpty
      ? componentEntry.canonicalName.trim()
      : componentEntry.names.firstWhere(
          (value) => value.trim().isNotEmpty,
          orElse: () => '',
        );
  if (label.isEmpty) {
    return '';
  }

  return 'Component: $label';
}

String _formatAnalysisComponentExamples(
  CharacterComponentEntry? componentEntry,
) {
  if (componentEntry == null) {
    return '';
  }

  final examples = _singleCharacterExamples(
    componentEntry.sourceExampleCharacters,
  ).take(4).toList(growable: false);
  if (examples.isEmpty) {
    return '';
  }

  return 'Examples: ${examples.join(' ')}';
}

class _CharacterAnalysisTreeNode {
  const _CharacterAnalysisTreeNode({
    required this.symbol,
    this.entry,
    this.componentEntry,
    this.componentReferenceEntry,
    this.children = const [],
  });

  final String symbol;
  final CharacterEntry? entry;
  final CharacterComponentEntry? componentEntry;
  final CharacterEntry? componentReferenceEntry;
  final List<_CharacterAnalysisTreeNode> children;
}

_CharacterAnalysisTreeNode _buildCharacterAnalysisTree({
  required String symbol,
  required CharacterIndex characterIndex,
  required CharacterComponentsDataset characterComponents,
  CharacterExplosionAnalysis? analysis,
  Set<String> ancestors = const <String>{},
  int depth = 0,
}) {
  final trimmedSymbol = symbol.trim();
  final entry = characterIndex.entryFor(trimmedSymbol);
  final componentEntry = characterComponents.entryFor(trimmedSymbol);
  final componentReferenceEntry = _resolveComponentReferenceEntry(
    componentEntry,
    characterIndex,
    exclude: trimmedSymbol,
  );
  final nextAnalysis = analysis ?? entry?.explosion.analysis;
  final branchSymbols = nextAnalysis == null
      ? const <String>[]
      : _analysisBranchSymbols(nextAnalysis).where((part) {
          return part != trimmedSymbol;
        }).toList();

  if (depth >= _analysisTreeMaxDepth || branchSymbols.isEmpty) {
    return _CharacterAnalysisTreeNode(
      symbol: trimmedSymbol,
      entry: entry,
      componentEntry: componentEntry,
      componentReferenceEntry: componentReferenceEntry,
    );
  }

  final nextAncestors = {...ancestors, trimmedSymbol};
  return _CharacterAnalysisTreeNode(
    symbol: trimmedSymbol,
    entry: entry,
    componentEntry: componentEntry,
    componentReferenceEntry: componentReferenceEntry,
    children: [
      for (final branchSymbol in branchSymbols)
        if (nextAncestors.contains(branchSymbol))
          _CharacterAnalysisTreeNode(
            symbol: branchSymbol,
            entry: characterIndex.entryFor(branchSymbol),
            componentEntry: characterComponents.entryFor(branchSymbol),
            componentReferenceEntry: _resolveComponentReferenceEntry(
              characterComponents.entryFor(branchSymbol),
              characterIndex,
              exclude: branchSymbol,
            ),
          )
        else
          _buildCharacterAnalysisTree(
            symbol: branchSymbol,
            characterIndex: characterIndex,
            characterComponents: characterComponents,
            ancestors: nextAncestors,
            depth: depth + 1,
          ),
    ],
  );
}

class _ExplosionReferenceItemData {
  const _ExplosionReferenceItemData({
    required this.text,
    this.reading = '',
    this.english = '',
  });

  final String text;
  final String reading;
  final String english;
}

String _primaryEnglishGloss(CharacterEntry entry) {
  for (final value in entry.english) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  return '';
}

String _formatCompositeReading(List<CharacterEntry> entries) {
  final pinyin = entries
      .map(
        (entry) => entry.pinyin.firstWhere(_hasVisibleText, orElse: () => ''),
      )
      .where(_hasVisibleText)
      .toList();
  final zhuyin = entries
      .map(
        (entry) => entry.zhuyin.firstWhere(_hasVisibleText, orElse: () => ''),
      )
      .where(_hasVisibleText)
      .toList();

  if (pinyin.isEmpty && zhuyin.isEmpty) {
    return '';
  }
  if (pinyin.isNotEmpty && zhuyin.isNotEmpty) {
    return '${pinyin.join(' ')} (${zhuyin.join(' ')})';
  }

  return pinyin.isNotEmpty ? pinyin.join(' ') : zhuyin.join(' ');
}

String _formatCompositeEnglish(List<CharacterEntry> entries) {
  final glosses = entries
      .map(_primaryEnglishGloss)
      .where(_hasVisibleText)
      .toList();
  if (glosses.isEmpty) {
    return '';
  }

  return 'Literal gloss: ${glosses.join(' + ')}';
}

class _CharacterExplosionHistory {
  const _CharacterExplosionHistory({
    this.characters = const <String>[],
    this.currentIndex = -1,
  });

  final List<String> characters;
  final int currentIndex;

  bool get isEmpty =>
      characters.isEmpty ||
      currentIndex < 0 ||
      currentIndex >= characters.length;

  String get currentCharacter => isEmpty ? '' : characters[currentIndex];

  bool get canGoBack => !isEmpty && currentIndex > 0;

  bool get canGoForward => !isEmpty && currentIndex < characters.length - 1;

  _CharacterExplosionHistory push(String character) {
    final trimmedCharacter = character.trim();
    if (trimmedCharacter.isEmpty || !_containsChineseText(trimmedCharacter)) {
      return this;
    }

    if (!isEmpty && currentCharacter == trimmedCharacter) {
      return this;
    }

    final nextCharacters = <String>[
      if (!isEmpty) ...characters.take(currentIndex + 1),
      trimmedCharacter,
    ];

    return _CharacterExplosionHistory(
      characters: List<String>.unmodifiable(nextCharacters),
      currentIndex: nextCharacters.length - 1,
    );
  }

  _CharacterExplosionHistory goBack() {
    if (!canGoBack) {
      return this;
    }

    return _CharacterExplosionHistory(
      characters: characters,
      currentIndex: currentIndex - 1,
    );
  }

  _CharacterExplosionHistory goForward() {
    if (!canGoForward) {
      return this;
    }

    return _CharacterExplosionHistory(
      characters: characters,
      currentIndex: currentIndex + 1,
    );
  }
}

_ExplosionReferenceItemData _resolveExplosionReferenceItem(
  String value,
  CharacterIndex characterIndex,
) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return const _ExplosionReferenceItemData(text: '');
  }

  final exactEntry = characterIndex.entryFor(trimmed);
  if (exactEntry != null) {
    return _ExplosionReferenceItemData(
      text: trimmed,
      reading: _formatCharacterReading(exactEntry),
      english: _joinVisibleValues(exactEntry.english, separator: '; '),
    );
  }

  final componentEntries = <CharacterEntry>[];
  for (final rune in trimmed.runes) {
    final character = String.fromCharCode(rune);
    if (!_containsChineseText(character)) {
      continue;
    }

    final entry = characterIndex.entryFor(character);
    if (entry == null) {
      return _ExplosionReferenceItemData(text: trimmed);
    }
    componentEntries.add(entry);
  }

  if (componentEntries.isEmpty) {
    return _ExplosionReferenceItemData(text: trimmed);
  }

  return _ExplosionReferenceItemData(
    text: trimmed,
    reading: _formatCompositeReading(componentEntries),
    english: _formatCompositeEnglish(componentEntries),
  );
}

String _simplifiedChineseText(String value, CharacterIndex characterIndex) {
  final buffer = StringBuffer();

  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final simplified = characterIndex.entryFor(character)?.simplified.trim();
    buffer.write(
      simplified == null || simplified.isEmpty ? character : simplified,
    );
  }

  return buffer.toString();
}

List<String> _mergeFontFamilies(
  Iterable<String> preferredFamilies,
  List<String>? existingFamilies, {
  String? exclude,
}) {
  final mergedFamilies = <String>[];
  final seenFamilies = <String>{};

  void addFamily(String family) {
    final trimmedFamily = family.trim();
    if (trimmedFamily.isEmpty ||
        trimmedFamily == exclude ||
        !seenFamilies.add(trimmedFamily)) {
      return;
    }
    mergedFamilies.add(trimmedFamily);
  }

  for (final family in preferredFamilies) {
    addFamily(family);
  }
  for (final family in existingFamilies ?? const <String>[]) {
    addFamily(family);
  }

  return mergedFamilies;
}

Future<CharacterIndex> _loadOptionalCharacterIndex(BackendClient client) async {
  try {
    return await client.fetchCharacterIndex();
  } on Exception {
    // The reader can still work without exploded-character reference data.
    return CharacterIndex.empty();
  }
}

Future<CharacterComponentsDataset> _loadOptionalCharacterComponents(
  BackendClient? client,
) async {
  if (client == null) {
    return CharacterComponentsDataset.empty();
  }
  try {
    return await client.fetchCharacterComponents();
  } on Exception {
    // The exploder can still render without component label fallbacks.
    return CharacterComponentsDataset.empty();
  }
}

List<String> _singleCharacterExamples(Iterable<String> candidates) {
  final examples = <String>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty || trimmed.runes.length != 1 || !seen.add(trimmed)) {
      continue;
    }
    examples.add(trimmed);
  }
  return examples;
}

Iterable<String> _visibleCharacters(String text) sync* {
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    if (character.trim().isEmpty) {
      continue;
    }
    yield character;
  }
}

enum ChineseFontOption { systemSans, pingFang, heiTi, songTi, fangSong, kaiTi }

const String _bundledPingFangFamily = 'DaxuePingFangSC';
const String _bundledHeiTiFamily = 'DaxueHeiTiSC';
const String _bundledSongTiFamily = 'DaxueSongTiSC';
const String _bundledFangSongFamily = 'DaxueFangSongSC';
const String _bundledKaiTiFamily = 'DaxueKaiTiSC';

extension ChineseFontOptionPresentation on ChineseFontOption {
  String get label => switch (this) {
    ChineseFontOption.systemSans => 'System Sans',
    ChineseFontOption.pingFang => 'Ping Fang',
    ChineseFontOption.heiTi => 'Hei Ti',
    ChineseFontOption.songTi => 'Song Ti',
    ChineseFontOption.fangSong => 'Fang Song',
    ChineseFontOption.kaiTi => 'Kai Ti',
  };

  String get description => switch (this) {
    ChineseFontOption.systemSans =>
      'Default modern system Chinese text for menus and reading lines.',
    ChineseFontOption.pingFang =>
      'Clean humanist sans style commonly used for modern Chinese interfaces.',
    ChineseFontOption.heiTi =>
      'Dense sans-serif Hei style with stronger contrast for headings.',
    ChineseFontOption.songTi =>
      'Serif Song style with a more book-like reading texture.',
    ChineseFontOption.fangSong =>
      'Printed Fang Song style suited to classical text and notes.',
    ChineseFontOption.kaiTi =>
      'Brush-inspired Kai style for a calligraphic feel.',
  };

  String? get primaryFamily => switch (this) {
    ChineseFontOption.systemSans => null,
    ChineseFontOption.pingFang => 'PingFang SC',
    ChineseFontOption.heiTi => 'STHeiti',
    ChineseFontOption.songTi => 'Songti SC',
    ChineseFontOption.fangSong => 'STFangsong',
    ChineseFontOption.kaiTi => 'Kaiti SC',
  };

  List<String> get fallbackFamilies => switch (this) {
    ChineseFontOption.systemSans => const <String>[
      'PingFang SC',
      'Hiragino Sans GB',
      'Heiti SC',
      'Noto Sans SC',
      'Noto Sans CJK SC',
      'Microsoft YaHei',
      _bundledPingFangFamily,
      _bundledHeiTiFamily,
    ],
    ChineseFontOption.pingFang => const <String>[
      'Hiragino Sans GB',
      'Heiti SC',
      'Noto Sans SC',
      'Noto Sans CJK SC',
      'Microsoft YaHei',
      _bundledPingFangFamily,
      _bundledHeiTiFamily,
    ],
    ChineseFontOption.heiTi => const <String>[
      'Heiti SC',
      'SimHei',
      'Microsoft YaHei',
      'Noto Sans SC',
      'Noto Sans CJK SC',
      _bundledHeiTiFamily,
      _bundledPingFangFamily,
    ],
    ChineseFontOption.songTi => const <String>[
      'STSong',
      'SimSun',
      'Noto Serif SC',
      'Noto Serif CJK SC',
      'Source Han Serif SC',
      _bundledSongTiFamily,
      _bundledFangSongFamily,
    ],
    ChineseFontOption.fangSong => const <String>[
      'FangSong',
      'FangSong_GB2312',
      'STSong',
      'Noto Serif SC',
      'Noto Serif CJK SC',
      _bundledFangSongFamily,
      _bundledSongTiFamily,
    ],
    ChineseFontOption.kaiTi => const <String>[
      'STKaiti',
      'KaiTi',
      'BiauKai',
      _bundledKaiTiFamily,
      _bundledSongTiFamily,
    ],
  };

  List<String> get preferredFamilies {
    final primaryFamily = this.primaryFamily;
    if (primaryFamily == null) {
      return fallbackFamilies;
    }

    return <String>[primaryFamily, ...fallbackFamilies];
  }

  TextStyle apply(TextStyle style) => switch (this) {
    ChineseFontOption.systemSans => style,
    ChineseFontOption.pingFang => style.copyWith(
      fontFamily: primaryFamily,
      fontFamilyFallback: _mergeFontFamilies(
        fallbackFamilies,
        style.fontFamilyFallback,
        exclude: primaryFamily,
      ),
    ),
    ChineseFontOption.heiTi => style.copyWith(
      fontFamily: primaryFamily,
      fontFamilyFallback: _mergeFontFamilies(
        fallbackFamilies,
        style.fontFamilyFallback,
        exclude: primaryFamily,
      ),
    ),
    ChineseFontOption.songTi => style.copyWith(
      fontFamily: primaryFamily,
      fontFamilyFallback: _mergeFontFamilies(
        fallbackFamilies,
        style.fontFamilyFallback,
        exclude: primaryFamily,
      ),
    ),
    ChineseFontOption.fangSong => style.copyWith(
      fontFamily: primaryFamily,
      fontFamilyFallback: _mergeFontFamilies(
        fallbackFamilies,
        style.fontFamilyFallback,
        exclude: primaryFamily,
      ),
    ),
    ChineseFontOption.kaiTi => style.copyWith(
      fontFamily: primaryFamily,
      fontFamilyFallback: _mergeFontFamilies(
        fallbackFamilies,
        style.fontFamilyFallback,
        exclude: primaryFamily,
      ),
    ),
  };

  TextStyle applyFallback(TextStyle style) {
    if (this == ChineseFontOption.systemSans) {
      return style;
    }

    return style.copyWith(
      fontFamilyFallback: _mergeFontFamilies(
        preferredFamilies,
        style.fontFamilyFallback,
        exclude: style.fontFamily,
      ),
    );
  }
}

class ChineseTextTheme extends ThemeExtension<ChineseTextTheme> {
  const ChineseTextTheme({required this.fontOption});

  final ChineseFontOption fontOption;

  @override
  ChineseTextTheme copyWith({ChineseFontOption? fontOption}) {
    return ChineseTextTheme(fontOption: fontOption ?? this.fontOption);
  }

  @override
  ChineseTextTheme lerp(
    covariant ThemeExtension<ChineseTextTheme>? other,
    double t,
  ) {
    if (other is! ChineseTextTheme) {
      return this;
    }

    return t < 0.5 ? this : other;
  }
}

TextStyle? _withChineseThemeFont(TextStyle? style, ChineseFontOption option) {
  if (style == null) {
    return null;
  }

  return option.apply(style);
}

TextTheme _applyChineseFontsToTextTheme(
  TextTheme textTheme,
  ChineseFontOption option,
) {
  if (option == ChineseFontOption.systemSans) {
    return textTheme;
  }

  return textTheme.copyWith(
    displayLarge: _withChineseThemeFont(textTheme.displayLarge, option),
    displayMedium: _withChineseThemeFont(textTheme.displayMedium, option),
    displaySmall: _withChineseThemeFont(textTheme.displaySmall, option),
    headlineLarge: _withChineseThemeFont(textTheme.headlineLarge, option),
    headlineMedium: _withChineseThemeFont(textTheme.headlineMedium, option),
    headlineSmall: _withChineseThemeFont(textTheme.headlineSmall, option),
    titleLarge: _withChineseThemeFont(textTheme.titleLarge, option),
    titleMedium: _withChineseThemeFont(textTheme.titleMedium, option),
    titleSmall: _withChineseThemeFont(textTheme.titleSmall, option),
    bodyLarge: _withChineseThemeFont(textTheme.bodyLarge, option),
    bodyMedium: _withChineseThemeFont(textTheme.bodyMedium, option),
    bodySmall: _withChineseThemeFont(textTheme.bodySmall, option),
    labelLarge: _withChineseThemeFont(textTheme.labelLarge, option),
    labelMedium: _withChineseThemeFont(textTheme.labelMedium, option),
    labelSmall: _withChineseThemeFont(textTheme.labelSmall, option),
  );
}

TextStyle? _withLargerChineseFont(
  BuildContext context,
  String text,
  TextStyle? baseStyle, {
  required double fallbackFontSize,
  double? sizeMultiplier,
  double? sizeIncrease,
}) {
  if (!_containsChineseText(text)) {
    return baseStyle;
  }

  final effectiveBaseStyle = baseStyle ?? const TextStyle();
  final baseFontSize = baseStyle?.fontSize ?? fallbackFontSize;
  final resizedStyle = effectiveBaseStyle.copyWith(
    fontSize: sizeMultiplier != null
        ? baseFontSize * sizeMultiplier
        : baseFontSize + (sizeIncrease ?? 0),
  );
  final fontOption =
      Theme.of(context).extension<ChineseTextTheme>()?.fontOption ??
      ChineseFontOption.systemSans;
  return fontOption.apply(resizedStyle);
}

TextStyle? _supportTableChineseTextStyle(BuildContext context, String text) {
  return _withLargerChineseFont(
    context,
    text,
    Theme.of(context).textTheme.headlineSmall,
    fallbackFontSize: 24,
    sizeMultiplier: _readingUnitChineseLineSizeMultiplier,
  );
}

TextStyle? _supportTableEnglishTextStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyLarge;
}

String _formatCharacterHeading(CharacterEntry entry, {String? fallback}) {
  final fallbackCharacter = fallback ?? entry.character;
  final simplified = entry.simplified.trim();
  final traditional = entry.traditional.trim();
  final primary = simplified.isEmpty ? fallbackCharacter : simplified;

  if (traditional.isEmpty || traditional == primary) {
    return primary;
  }

  return '$primary ($traditional)';
}

String _formatCharacterReading(CharacterEntry? entry) {
  if (entry == null) {
    return '';
  }

  final pinyin = entry.pinyin.join('; ');
  final zhuyin = entry.zhuyin.join('; ');
  if (_hasVisibleText(pinyin) && _hasVisibleText(zhuyin)) {
    return '$pinyin ($zhuyin)';
  }

  return _hasVisibleText(pinyin) ? pinyin : zhuyin;
}

String _joinVisibleValues(List<String> values, {String separator = ' • '}) {
  return values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .join(separator);
}

const Color _appSeedColor = Color(0xFF0B6E4F);
const List<ThemeMode> _themeModeOptions = <ThemeMode>[
  ThemeMode.light,
  ThemeMode.dark,
  ThemeMode.system,
];
const List<ChineseFontOption> _chineseFontOptions = <ChineseFontOption>[
  ChineseFontOption.systemSans,
  ChineseFontOption.pingFang,
  ChineseFontOption.heiTi,
  ChineseFontOption.songTi,
  ChineseFontOption.fangSong,
  ChineseFontOption.kaiTi,
];

ThemeData _buildAppTheme(
  Brightness brightness, {
  required ChineseFontOption chineseFontOption,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _appSeedColor,
    brightness: brightness,
  );
  final scaffoldBackgroundColor = brightness == Brightness.light
      ? const Color(0xFFF5F0E6)
      : const Color(0xFF101715);
  final baseTheme = ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    useMaterial3: true,
    extensions: <ThemeExtension<dynamic>>[
      ChineseTextTheme(fontOption: chineseFontOption),
    ],
  );

  return baseTheme.copyWith(
    textTheme: _applyChineseFontsToTextTheme(
      baseTheme.textTheme,
      chineseFontOption,
    ),
    primaryTextTheme: _applyChineseFontsToTextTheme(
      baseTheme.primaryTextTheme,
      chineseFontOption,
    ),
  );
}

String _themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Light',
  ThemeMode.dark => 'Dark',
  ThemeMode.system => 'System',
};

String _themeModeDescription(ThemeMode mode) => switch (mode) {
  ThemeMode.light => 'Always use the light reading surface.',
  ThemeMode.dark => 'Always use the dark reading surface.',
  ThemeMode.system => 'Match the device appearance automatically.',
};

IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
  ThemeMode.system => Icons.brightness_auto_outlined,
};

class DaxueApp extends StatefulWidget {
  DaxueApp({super.key, BackendClient? client})
    : _client = client ?? HttpBackendClient();

  final BackendClient _client;

  @override
  State<DaxueApp> createState() => _DaxueAppState();
}

class _DaxueAppState extends State<DaxueApp> {
  ThemeMode _themeMode = ThemeMode.system;
  ChineseFontOption _chineseFontOption = ChineseFontOption.systemSans;

  void _updateThemeMode(ThemeMode mode) {
    if (_themeMode == mode) {
      return;
    }

    setState(() {
      _themeMode = mode;
    });
  }

  void _updateChineseFontOption(ChineseFontOption option) {
    if (_chineseFontOption == option) {
      return;
    }

    setState(() {
      _chineseFontOption = option;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Da Xue',
      theme: _buildAppTheme(
        Brightness.light,
        chineseFontOption: _chineseFontOption,
      ),
      darkTheme: _buildAppTheme(
        Brightness.dark,
        chineseFontOption: _chineseFontOption,
      ),
      themeMode: _themeMode,
      builder: (context, child) {
        final fontOption =
            Theme.of(context).extension<ChineseTextTheme>()?.fontOption ??
            ChineseFontOption.systemSans;
        return DefaultTextStyle.merge(
          style: fontOption.apply(const TextStyle()),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: HomeShellPage(
        client: widget._client,
        themeMode: _themeMode,
        onThemeModeChanged: _updateThemeMode,
        chineseFontOption: _chineseFontOption,
        onChineseFontOptionChanged: _updateChineseFontOption,
      ),
    );
  }
}

class HomeShellPage extends StatefulWidget {
  const HomeShellPage({
    super.key,
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.chineseFontOption,
    required this.onChineseFontOptionChanged,
  });

  final BackendClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ChineseFontOption chineseFontOption;
  final ValueChanged<ChineseFontOption> onChineseFontOptionChanged;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  int _selectedTabIndex = 0;

  void _selectTab(int index) {
    if (_selectedTabIndex == index) {
      return;
    }

    setState(() {
      _selectedTabIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          IntroPage(onOpenReadings: () => _selectTab(1)),
          ReadingMenuPage(client: widget.client),
          FlashcardsPage(
            client: widget.client,
            isActive: _selectedTabIndex == 2,
          ),
          SettingsPage(
            client: widget.client,
            themeMode: widget.themeMode,
            onThemeModeChanged: widget.onThemeModeChanged,
            chineseFontOption: widget.chineseFontOption,
            onChineseFontOptionChanged: widget.onChineseFontOptionChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Readings',
          ),
          NavigationDestination(
            icon: Icon(Icons.style_outlined),
            selectedIcon: Icon(Icons.style),
            label: 'Flashcards',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class IntroPage extends StatelessWidget {
  const IntroPage({super.key, required this.onOpenReadings});

  final VoidCallback onOpenReadings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final introGradientColors = theme.brightness == Brightness.dark
        ? [colorScheme.surfaceContainerHigh, theme.scaffoldBackgroundColor]
        : [const Color(0xFFE8F0E2), theme.scaffoldBackgroundColor];

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: introGradientColors,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Text(
                          'Da Xue',
                          style: textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Start where Chinese learning starts.',
                          style: textTheme.headlineSmall?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Skip the phrasebook openers like ni hao and xie xie. Da Xue gives you the texts, characters, and ideas that have rooted Chinese culture for generations.',
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _StatusCard(
                          title: 'How it works',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _IntroFeatureRow(
                                icon: Icons.menu_book_outlined,
                                title: 'Guided readings',
                                description:
                                    'Start with the Four Books in the Confucian tradition. Then enjoy the extended curriculum.',
                              ),
                              SizedBox(height: 16),
                              _IntroFeatureRow(
                                icon: Icons.forum_outlined,
                                title: 'Line-by-line discussion',
                                description:
                                    'Read closely, then draft your own translations and responses to these classic texts.',
                              ),
                              SizedBox(height: 16),
                              _IntroFeatureRow(
                                icon: Icons.account_tree_outlined,
                                title: 'Character explosion',
                                description:
                                    'Follow linked Hanzi into their components to see how the language is built from the inside.',
                              ),
                              SizedBox(height: 16),
                              _IntroFeatureRow(
                                icon: Icons.style_outlined,
                                title: 'Flashcards',
                                description:
                                    'Save characters worth keeping, then revisit them as flashcards inside the app.',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onOpenReadings,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Enter library'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FlashcardsPage extends StatefulWidget {
  const FlashcardsPage({
    super.key,
    this.randomSeed,
    this.flashcardStore,
    this.random,
    this.client,
    this.isActive = true,
  });

  final int? randomSeed;
  final SharedPreferencesFlashcardStore? flashcardStore;
  final math.Random? random;
  final BackendClient? client;
  final bool isActive;

  @override
  State<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  static const int _minimumFlashcardsForLooping = 3;
  static const int _flashcardLoopCyclesPerSide = 120;
  static const ValueKey<String> _flashcardsLoopCenterKey = ValueKey<String>(
    'flashcards-loop-center',
  );

  late final SharedPreferencesFlashcardStore _flashcardStore;
  late final Future<void> _loadFlashcardsFuture;
  late final Future<CharacterIndex> _characterIndexFuture;
  late final Future<CharacterComponentsDataset> _characterComponentsFuture;
  late final math.Random _random;
  late final ScrollController _flashcardsScrollController;
  List<String> _orderedFlashcardIds = const [];
  Map<String, _FlashcardVisibleSides> _visibleSidesByEntryId = const {};

  @override
  void initState() {
    super.initState();
    _flashcardsScrollController = ScrollController();
    _flashcardStore =
        widget.flashcardStore ?? SharedPreferencesFlashcardStore.instance;
    _characterIndexFuture = _loadOptionalCharacterIndex(
      widget.client ?? HttpBackendClient(),
    );
    _characterComponentsFuture = _loadOptionalCharacterComponents(
      widget.client ?? HttpBackendClient(),
    );
    _random =
        widget.random ??
        math.Random(_normalizedFlashcardRandomSeed(widget.randomSeed));
    _flashcardStore.addListener(_handleFlashcardsChanged);
    _loadFlashcardsFuture = _loadFlashcards();
  }

  @override
  void dispose() {
    _flashcardStore.removeListener(_handleFlashcardsChanged);
    _flashcardsScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FlashcardsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _reshuffleFlashcards();
    }
  }

  Future<void> _loadFlashcards() async {
    await _flashcardStore.ensureLoaded();
    if (!uiActive) {
      return;
    }

    _handleFlashcardsChanged();
  }

  void _handleFlashcardsChanged() {
    if (!uiActive) {
      return;
    }

    final entries = _flashcardStore.entries;
    if (entries.isEmpty) {
      setState(() {
        _orderedFlashcardIds = const [];
        _visibleSidesByEntryId = const {};
      });
      return;
    }

    final orderedFlashcardIds = _orderedFlashcardIds.isEmpty
        ? _weightedOrderedFlashcardIds(entries)
        : _nextOrderedFlashcardIds(entries);
    final visibleSidesByEntryId = <String, _FlashcardVisibleSides>{
      for (final entry in entries)
        entry.id: _normalizedFlashcardVisibleSides(
          _visibleSidesByEntryId[entry.id] ??
              _initialFlashcardVisibleSides(entry, random: _random),
          entry,
        ),
    };
    setState(() {
      _orderedFlashcardIds = orderedFlashcardIds;
      _visibleSidesByEntryId = visibleSidesByEntryId;
    });
  }

  void _reshuffleFlashcards() {
    if (!uiActive) {
      return;
    }

    final entries = _flashcardStore.entries;
    if (entries.isEmpty) {
      return;
    }

    setState(() {
      _orderedFlashcardIds = _weightedOrderedFlashcardIds(entries);
    });
    _resetFlashcardsScrollPosition();
  }

  List<String> _weightedOrderedFlashcardIds(List<FlashcardEntry> entries) {
    return [
      for (final entry in sampleWeightedFlashcardEntries(
        entries,
        random: _random,
      ))
        entry.id,
    ];
  }

  List<String> _nextOrderedFlashcardIds(List<FlashcardEntry> entries) {
    final entryIds = {for (final entry in entries) entry.id};
    final retainedIds = _orderedFlashcardIds
        .where(entryIds.contains)
        .toList(growable: true);
    final retainedIdSet = retainedIds.toSet();
    final newEntries = [
      for (final entry in entries)
        if (!retainedIdSet.contains(entry.id)) entry,
    ];
    final newIds = _weightedOrderedFlashcardIds(newEntries);

    return [...retainedIds, ...newIds];
  }

  List<FlashcardEntry> _orderedEntries(List<FlashcardEntry> entries) {
    final entriesById = {for (final entry in entries) entry.id: entry};
    return [
      for (final entryId in _orderedFlashcardIds)
        if (entriesById.containsKey(entryId)) entriesById[entryId]!,
    ];
  }

  _FlashcardVisibleSides _visibleSidesForEntry(FlashcardEntry entry) {
    return _normalizedFlashcardVisibleSides(
      _visibleSidesByEntryId[entry.id] ??
          _initialFlashcardVisibleSides(entry, random: _random),
      entry,
    );
  }

  void _toggleFlashcardSide(
    FlashcardEntry entry,
    _FlashcardPromptKind promptKind,
  ) {
    final currentVisibleSides = _visibleSidesForEntry(entry);
    final nextVisibleSides = _toggleFlashcardVisibleSide(
      currentVisibleSides,
      entry,
      promptKind,
    );
    if (nextVisibleSides == currentVisibleSides) {
      return;
    }

    setState(() {
      _visibleSidesByEntryId = {
        ..._visibleSidesByEntryId,
        entry.id: nextVisibleSides,
      };
    });
  }

  Future<void> _adjustEntryWeight(FlashcardEntry entry, int delta) async {
    final nextWeight = math.max(1, entry.weight + delta);
    if (nextWeight != entry.weight) {
      await _flashcardStore.updateEntryWeight(
        entryId: entry.id,
        weight: nextWeight,
      );
      if (!uiActive) {
        return;
      }
    }
  }

  Future<void> _handleDecreaseEntryWeight(FlashcardEntry entry) async {
    if (entry.weight > 1) {
      await _adjustEntryWeight(entry, -1);
      return;
    }

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove flashcard?'),
          content: const Text('This will remove the flashcard.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (shouldRemove != true) {
      return;
    }

    await _flashcardStore.removeEntry(entry.id);
  }

  void _resetFlashcardsScrollPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!uiActive || !_flashcardsScrollController.hasClients) {
        return;
      }

      _flashcardsScrollController.jumpTo(0);
    });
  }

  Widget _buildFlashcardSide({
    required BuildContext context,
    required bool isVisible,
    required VoidCallback? onToggle,
    required Widget content,
    required String sideKey,
    required String buttonKey,
    required String tooltip,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseBorderColor = colorScheme.outlineVariant;
    final activeBorderColor = colorScheme.primary.withValues(alpha: 0.4);

    return DecoratedBox(
      key: ValueKey(sideKey),
      decoration: BoxDecoration(
        color: isVisible
            ? colorScheme.surface
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isVisible ? activeBorderColor : baseBorderColor,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(child: isVisible ? content : const SizedBox()),
            ),
            const SizedBox(height: 8),
            Center(
              child: IconButton(
                key: ValueKey(buttonKey),
                onPressed: onToggle,
                tooltip: tooltip,
                icon: Icon(
                  isVisible ? Icons.visibility : Icons.visibility_outlined,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcardCard(BuildContext context, FlashcardEntry entry) {
    final englishLabel = _flashcardEnglishLabel(entry);
    final visibleSides = _visibleSidesForEntry(entry);
    final showingChineseContent = visibleSides.showChinese;
    final showingReadingAndEnglishContent = visibleSides.showReadingAndEnglish;
    final hasChineseContent = _hasFlashcardChineseContent(entry);
    final hasReadingAndEnglishContent = _hasFlashcardReadingAndEnglishContent(
      entry,
    );

    return _StatusCard(
      key: ValueKey('flashcard-card-${entry.id}'),
      title: '',
      titleSubtitle: _hasVisibleText(entry.sourceWork)
          ? 'Source: ${entry.sourceWork}'
          : null,
      contentPadding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _buildFlashcardSide(
                      context: context,
                      isVisible: showingChineseContent,
                      onToggle: hasChineseContent
                          ? () => _toggleFlashcardSide(
                              entry,
                              _FlashcardPromptKind.chinese,
                            )
                          : null,
                      sideKey: 'flashcard-left-side-${entry.id}',
                      buttonKey: 'flashcard-show-left-button-${entry.id}',
                      tooltip: showingChineseContent
                          ? 'Hide Chinese'
                          : 'Show Chinese',
                      content: Center(
                        child: _InteractiveChineseText(
                          text: entry.displayHeading,
                          keyPrefix: 'flashcard-left-character-${entry.id}',
                          onCharacterTap: _openCharacterExplosionSheet,
                          style: _supportTableChineseTextStyle(
                            context,
                            entry.displayHeading,
                          )?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFlashcardSide(
                      context: context,
                      isVisible: showingReadingAndEnglishContent,
                      onToggle: hasReadingAndEnglishContent
                          ? () => _toggleFlashcardSide(
                              entry,
                              _FlashcardPromptKind.readingAndEnglish,
                            )
                          : null,
                      sideKey: 'flashcard-right-side-${entry.id}',
                      buttonKey: 'flashcard-show-right-button-${entry.id}',
                      tooltip: showingReadingAndEnglishContent
                          ? 'Hide reading and meaning'
                          : 'Show reading and meaning',
                      content: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_hasVisibleText(entry.readingLabel))
                            Text(
                              entry.readingLabel,
                              key: ValueKey(
                                'flashcard-reading-label-${entry.id}',
                              ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          if (_hasVisibleText(englishLabel)) ...[
                            if (_hasVisibleText(entry.readingLabel))
                              const SizedBox(height: 12),
                            Text(
                              englishLabel,
                              key: ValueKey(
                                'flashcard-english-label-${entry.id}',
                              ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              IconButton(
                key: ValueKey('flashcard-weight-decrease-button-${entry.id}'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                tooltip: 'Decrease weight',
                onPressed: () => _handleDecreaseEntryWeight(entry),
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Priority level ${entry.weight}',
                  key: ValueKey('flashcard-weight-label-${entry.id}'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('flashcard-weight-increase-button-${entry.id}'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                visualDensity: VisualDensity.compact,
                tooltip: 'Increase weight',
                onPressed: () => _adjustEntryWeight(entry, 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openCharacterExplosionSheet(String character) {
    if (!_containsChineseText(character)) {
      return;
    }

    final exploderHistory = ValueNotifier<_CharacterExplosionHistory>(
      const _CharacterExplosionHistory(),
    );
    exploderHistory.value = exploderHistory.value.push(character);

    void addCharacterToExploder(String nextCharacter) {
      final trimmedCharacter = nextCharacter.trim();
      if (trimmedCharacter.isEmpty || !_containsChineseText(trimmedCharacter)) {
        return;
      }

      exploderHistory.value = exploderHistory.value.push(trimmedCharacter);
    }

    void goBackInExploder() {
      exploderHistory.value = exploderHistory.value.goBack();
    }

    void goForwardInExploder() {
      exploderHistory.value = exploderHistory.value.goForward();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CharacterExplosionSheet(
        client: widget.client ?? HttpBackendClient(),
        historyListenable: exploderHistory,
        characterIndexFuture: _characterIndexFuture,
        characterComponentsFuture: _characterComponentsFuture,
        onCharacterTap: addCharacterToExploder,
        onBack: goBackInExploder,
        onForward: goForwardInExploder,
      ),
    ).whenComplete(exploderHistory.dispose);
  }

  Widget _buildFiniteFlashcardsList(List<FlashcardEntry> orderedEntries) {
    return ListView.separated(
      key: const PageStorageKey<String>('flashcards-list'),
      controller: _flashcardsScrollController,
      itemCount: orderedEntries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildFlashcardCard(context, orderedEntries[index]);
      },
    );
  }

  Widget _buildLoopingFlashcardsList(List<FlashcardEntry> orderedEntries) {
    final repeatedItemCount =
        orderedEntries.length * _flashcardLoopCyclesPerSide;

    Widget leadingFlashcardBuilder(BuildContext context, int index) {
      final reversedIndex =
          orderedEntries.length - 1 - (index % orderedEntries.length);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildFlashcardCard(context, orderedEntries[reversedIndex]),
      );
    }

    Widget trailingFlashcardBuilder(BuildContext context, int index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildFlashcardCard(
          context,
          orderedEntries[index % orderedEntries.length],
        ),
      );
    }

    return CustomScrollView(
      key: const PageStorageKey<String>('flashcards-list'),
      controller: _flashcardsScrollController,
      center: _flashcardsLoopCenterKey,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            leadingFlashcardBuilder,
            childCount: repeatedItemCount,
          ),
        ),
        SliverList(
          key: _flashcardsLoopCenterKey,
          delegate: SliverChildBuilderDelegate(
            trailingFlashcardBuilder,
            childCount: repeatedItemCount,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flashcards')),
      body: FutureBuilder<void>(
        future: _loadFlashcardsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = _flashcardStore.entries;
          if (entries.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: _StatusCard(
                  title: 'No flashcards saved yet',
                  child: Text(
                    'Save a character from the exploded view to review it later.',
                  ),
                ),
              ),
            );
          }

          final orderedEntries = _orderedEntries(entries);
          if (orderedEntries.isEmpty) {
            return const SizedBox.shrink();
          }

          final shouldLoop =
              orderedEntries.length >= _minimumFlashcardsForLooping;

          return Padding(
            padding: const EdgeInsets.all(24),
            child: shouldLoop
                ? _buildLoopingFlashcardsList(orderedEntries)
                : _buildFiniteFlashcardsList(orderedEntries),
          );
        },
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.client,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.chineseFontOption,
    required this.onChineseFontOptionChanged,
  });

  final BackendClient client;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ChineseFontOption chineseFontOption;
  final ValueChanged<ChineseFontOption> onChineseFontOptionChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final previewBaseStyle =
        Theme.of(context).textTheme.titleLarge ?? const TextStyle();
    final previewBaseFontSize = previewBaseStyle.fontSize ?? 22;
    final previewStyle = chineseFontOption.apply(
      previewBaseStyle.copyWith(fontSize: previewBaseFontSize * 1.6),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ListView(
          children: [
            _StatusCard(
              title: 'Backend connection',
              child: Text('Current API base URL: ${client.baseUrl}'),
            ),
            const SizedBox(height: 16),
            _StatusCard(
              title: 'Appearance',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose how the app should render its reading surfaces.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _themeModeOptions.map((mode) {
                      return ChoiceChip(
                        key: ValueKey('theme-mode-${mode.name}'),
                        avatar: Icon(_themeModeIcon(mode), size: 18),
                        label: Text(_themeModeLabel(mode)),
                        selected: mode == themeMode,
                        onSelected: (_) => onThemeModeChanged(mode),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _themeModeDescription(themeMode),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _StatusCard(
              title: 'Chinese text',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose the Chinese font style used in reading lines, titles, and reference cards. Options use system fonts when available and fall back gracefully by device.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  KeyedSubtree(
                    key: ValueKey(
                      'chinese-font-selector-${chineseFontOption.name}',
                    ),
                    child: DropdownButtonFormField<ChineseFontOption>(
                      key: const ValueKey('chinese-font-selector'),
                      initialValue: chineseFontOption,
                      decoration: const InputDecoration(
                        labelText: 'Chinese font',
                        border: OutlineInputBorder(),
                      ),
                      items: _chineseFontOptions.map((option) {
                        return DropdownMenuItem<ChineseFontOption>(
                          value: option,
                          child: Text(option.label),
                        );
                      }).toList(),
                      onChanged: (option) {
                        if (option == null) {
                          return;
                        }
                        onChineseFontOptionChanged(option);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    chineseFontOption.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  KeyedSubtree(
                    key: ValueKey(
                      'chinese-font-preview-${chineseFontOption.name}',
                    ),
                    child: Text(
                      '大學之道，在明明德。',
                      key: const ValueKey('chinese-font-preview'),
                      style: previewStyle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReadingMenuPage extends StatefulWidget {
  const ReadingMenuPage({
    super.key,
    required this.client,
    this.lineStudyStore,
    this.readingProgressStore,
  });

  final BackendClient client;
  final LineStudyStore? lineStudyStore;
  final ReadingProgressStore? readingProgressStore;

  @override
  State<ReadingMenuPage> createState() => _ReadingMenuPageState();
}

class _ReadingMenuData {
  const _ReadingMenuData({
    required this.books,
    required this.characterIndex,
    required this.lineStudyCountsByBookId,
  });

  final List<BookDetail> books;
  final CharacterIndex characterIndex;
  final Map<String, _LineStudyCounts> lineStudyCountsByBookId;
}

class _ReadingMenuPageState extends State<ReadingMenuPage> {
  static const String _referenceIndexesMenuDisplayTitle = '參考：漢字部件';
  static const String _referenceIndexesMenuSupportTitle = '參考漢字部件';
  static const String _referenceIndexesMenuSubtitle =
      'Reference: character components';
  static const int _menuLoopCyclesPerSide = 200;
  static const ValueKey<String> _readingMenuLoopCenterKey = ValueKey<String>(
    'reading-menu-loop-center',
  );
  static const Map<String, int> _curriculumOrder = {
    'da-xue': 0,
    'zhong-yong': 1,
    'lunyu': 2,
    'mengzi': 3,
    'sunzi-bingfa': 4,
    'daodejing': 5,
    'san-zi-jing': 6,
    'qian-zi-wen': 7,
    'sanguo-yanyi': 8,
    'chengyu-catalog': 9,
  };

  late Future<_ReadingMenuData> _readingMenuFuture;
  late Future<CharacterComponentsDataset> _componentsFuture;
  late Future<CharacterIndex> _characterIndexFuture;
  late final ScrollController _readingMenuScrollController;

  LineStudyStore get _lineStudyStore =>
      widget.lineStudyStore ?? SharedPreferencesLineStudyStore.instance;

  @override
  void initState() {
    super.initState();
    _readingMenuScrollController = ScrollController();
    _componentsFuture = widget.client.fetchCharacterComponents();
    _characterIndexFuture = _loadOptionalCharacterIndex(widget.client);
    _readingMenuFuture = _loadReadingMenu();
  }

  @override
  void dispose() {
    _readingMenuScrollController.dispose();
    super.dispose();
  }

  Future<_ReadingMenuData> _loadReadingMenu() async {
    final books = await widget.client.fetchBooks();
    final orderedBooks = [...books]..sort(_compareBooks);
    final bookDetails = await Future.wait(
      orderedBooks.map((book) => widget.client.fetchBook(book.id)),
    );
    final characterIndex = await _characterIndexFuture;
    final lineStudyCountsByBookId = await _loadLineStudyCountsByBook(
      bookDetails,
    );
    return _ReadingMenuData(
      books: bookDetails,
      characterIndex: characterIndex,
      lineStudyCountsByBookId: lineStudyCountsByBookId,
    );
  }

  Future<Map<String, _LineStudyCounts>> _loadLineStudyCountsByBook(
    List<BookDetail> books,
  ) async {
    final countsByBook = await Future.wait(
      books.map((book) async {
        final chapterCounts = await Future.wait(
          book.chapters.map((chapter) async {
            final entries = await _lineStudyStore.loadChapterEntries(
              bookId: book.id,
              chapterId: chapter.id,
            );
            return _countLineStudyEntries(entries.values);
          }),
        );

        var bookCounts = const _LineStudyCounts();
        for (final chapterCounts in chapterCounts) {
          bookCounts = bookCounts + chapterCounts;
        }

        return MapEntry(book.id, bookCounts);
      }),
    );

    return Map<String, _LineStudyCounts>.fromEntries(countsByBook);
  }

  int _compareBooks(BookSummary left, BookSummary right) {
    final leftOrder = _curriculumOrder[left.id] ?? 999;
    final rightOrder = _curriculumOrder[right.id] ?? 999;

    if (leftOrder != rightOrder) {
      return leftOrder.compareTo(rightOrder);
    }

    return left.title.compareTo(right.title);
  }

  void _reload() {
    setState(() {
      _componentsFuture = widget.client.fetchCharacterComponents();
      _characterIndexFuture = _loadOptionalCharacterIndex(widget.client);
      _readingMenuFuture = _loadReadingMenu();
    });
  }

  void _reloadReadingMenu() {
    setState(() {
      _readingMenuFuture = _loadReadingMenu();
    });
  }

  Future<void> _openBook(
    BuildContext context,
    BookDetail book,
    CharacterIndex characterIndex,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookChaptersPage(
          client: widget.client,
          book: book,
          characterIndex: characterIndex,
          characterComponentsFuture: _componentsFuture,
          lineStudyStore: widget.lineStudyStore,
          readingProgressStore: widget.readingProgressStore,
        ),
      ),
    );

    if (!uiActive) {
      return;
    }

    _reloadReadingMenu();
  }

  void _openReferenceIndexes(
    BuildContext context,
    CharacterComponentsDataset dataset,
    CharacterIndex characterIndex,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CharacterComponentsPage(
          client: widget.client,
          dataset: dataset,
          characterIndex: characterIndex,
          readingProgressStore: widget.readingProgressStore,
        ),
      ),
    );
  }

  Widget _buildReadingMenuItem(
    BuildContext context,
    _ReadingMenuData menuData,
    int logicalIndex,
  ) {
    if (logicalIndex == 0) {
      return FutureBuilder<CharacterComponentsDataset>(
        future: _componentsFuture,
        builder: (context, componentsSnapshot) {
          if (componentsSnapshot.connectionState != ConnectionState.done) {
            return const _LibraryMenuTile(
              title: '0. 參考：漢字部件',
              subtitle: Text('Reference: character components'),
              trailing: Padding(
                padding: EdgeInsets.only(left: 12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }

          if (componentsSnapshot.hasError) {
            return _MessageCard(
              title: 'Character components unavailable',
              message: '${componentsSnapshot.error}',
              buttonLabel: 'Retry',
              onPressed: _reload,
            );
          }

          final dataset = componentsSnapshot.data;
          if (dataset == null) {
            return _MessageCard(
              title: 'Character components unavailable',
              message: 'The backend returned an empty components dataset.',
              buttonLabel: 'Retry',
              onPressed: _reload,
            );
          }

          return _LibraryMenuTile(
            title: _topLevelMenuTitle(
              index: 0,
              title: _referenceIndexesMenuDisplayTitle,
            ),
            subtitle: const Text(_referenceIndexesMenuSubtitle),
            details: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitleCharacterSupportTable(
                  client: widget.client,
                  title: _referenceIndexesMenuSupportTitle,
                  characterIndex: menuData.characterIndex,
                  characterComponentsFuture: Future.value(dataset),
                ),
                const SizedBox(height: 8),
                Text(_componentsCountSummary(dataset)),
              ],
            ),
            onTap: () => _openReferenceIndexes(
              context,
              dataset,
              menuData.characterIndex,
            ),
          );
        },
      );
    }

    final book = menuData.books[logicalIndex - 1];
    final lineStudyCounts =
        menuData.lineStudyCountsByBookId[book.id] ?? const _LineStudyCounts();
    return _ReadingMenuCard(
      client: widget.client,
      book: book,
      characterIndex: menuData.characterIndex,
      characterComponentsFuture: _componentsFuture,
      menuIndex: logicalIndex,
      lineStudySummary: _savedLineStudyCountSummary(
        translationCount: lineStudyCounts.translationCount,
        responseCount: lineStudyCounts.responseCount,
        includeLabel: false,
      ),
      onTap: () => _openBook(context, book, menuData.characterIndex),
    );
  }

  Widget _buildLoopingReadingMenu(
    BuildContext context,
    _ReadingMenuData menuData,
  ) {
    final logicalItemCount = menuData.books.length + 1;
    final repeatedItemCount = logicalItemCount * _menuLoopCyclesPerSide;

    Widget leadingMenuItemBuilder(BuildContext context, int index) {
      final reversedIndex = logicalItemCount - 1 - (index % logicalItemCount);
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildReadingMenuItem(context, menuData, reversedIndex),
      );
    }

    Widget trailingMenuItemBuilder(BuildContext context, int index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildReadingMenuItem(
          context,
          menuData,
          index % logicalItemCount,
        ),
      );
    }

    return CustomScrollView(
      key: const PageStorageKey<String>('reading-menu-list'),
      controller: _readingMenuScrollController,
      center: _readingMenuLoopCenterKey,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            leadingMenuItemBuilder,
            childCount: repeatedItemCount,
          ),
        ),
        SliverList(
          key: _readingMenuLoopCenterKey,
          delegate: SliverChildBuilderDelegate(
            trailingMenuItemBuilder,
            childCount: repeatedItemCount,
          ),
        ),
      ],
    );
  }

  Widget _buildReadingBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FutureBuilder<_ReadingMenuData>(
            future: _readingMenuFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return _MessageCard(
                  title: 'Could not load readings',
                  message: '${snapshot.error}',
                  buttonLabel: 'Retry',
                  onPressed: _reload,
                );
              }

              final menuData = snapshot.data;
              final books = menuData?.books ?? const [];
              if (books.isEmpty) {
                return _MessageCard(
                  title: 'No readings found',
                  message: 'The backend did not return any readable chapters.',
                  buttonLabel: 'Reload',
                  onPressed: _reload,
                );
              }

              final resolvedMenuData = menuData!;
              return _buildLoopingReadingMenu(context, resolvedMenuData);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Readings')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildReadingBody(context),
      ),
    );
  }
}

class CharacterReferencePage extends StatelessWidget {
  const CharacterReferencePage({
    super.key,
    required this.client,
    required this.dataset,
    required this.characterIndex,
    this.initialTabIndex = 1,
  });

  final BackendClient client;
  final CharacterComponentsDataset dataset;
  final CharacterIndex characterIndex;
  final int initialTabIndex;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex == 0 ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 72,
          title: _TranslatedTitle(
            primary: '參考：漢字與部件',
            translation: 'Reference: Character and component indexes',
            primaryStyle: textTheme.titleLarge,
            translationStyle: _supportTableEnglishTextStyle(context),
            primaryMaxLines: 1,
            translationMaxLines: 1,
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Characters'),
              Tab(text: 'Components'),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: TabBarView(
            children: [
              _CharacterIndexDatasetList(
                client: client,
                characterIndex: characterIndex,
                characterComponentsFuture: Future.value(dataset),
              ),
              _CharacterComponentsDatasetList(
                client: client,
                dataset: dataset,
                characterIndex: characterIndex,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CharacterIndexPage extends StatelessWidget {
  const CharacterIndexPage({
    super.key,
    required this.client,
    required this.characterIndex,
    this.characterComponentsFuture,
  });

  final BackendClient client;
  final CharacterIndex characterIndex;
  final Future<CharacterComponentsDataset>? characterComponentsFuture;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: _TranslatedTitle(
          primary: '參考：漢字',
          translation: 'Reference: Character index',
          primaryStyle: textTheme.titleLarge,
          translationStyle: _supportTableEnglishTextStyle(context),
          primaryMaxLines: 1,
          translationMaxLines: 1,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _CharacterIndexDatasetList(
          client: client,
          characterIndex: characterIndex,
          characterComponentsFuture: characterComponentsFuture,
        ),
      ),
    );
  }
}

class _CharacterIndexDatasetList extends StatefulWidget {
  const _CharacterIndexDatasetList({
    required this.client,
    required this.characterIndex,
    this.characterComponentsFuture,
  });

  final BackendClient client;
  final CharacterIndex characterIndex;
  final Future<CharacterComponentsDataset>? characterComponentsFuture;

  @override
  State<_CharacterIndexDatasetList> createState() =>
      _CharacterIndexDatasetListState();
}

class _CharacterIndexDatasetListState
    extends State<_CharacterIndexDatasetList> {
  static const Duration _characterScrollDuration = Duration(milliseconds: 250);

  late List<CharacterEntry> _orderedEntries;
  int _currentEntryIndex = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _resetVisibleEntries();
  }

  @override
  void didUpdateWidget(covariant _CharacterIndexDatasetList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.characterIndex, widget.characterIndex)) {
      _resetVisibleEntries();
    }
  }

  void _resetVisibleEntries() {
    _orderedEntries = widget.characterIndex.orderedEntries;
    if (_orderedEntries.isEmpty) {
      _currentEntryIndex = 0;
      return;
    }

    _currentEntryIndex = math.min(
      _currentEntryIndex,
      _orderedEntries.length - 1,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openCharacterExplosionSheet(String character) {
    if (!_containsChineseText(character)) {
      return;
    }

    final exploderHistory = ValueNotifier<_CharacterExplosionHistory>(
      const _CharacterExplosionHistory(),
    );
    exploderHistory.value = exploderHistory.value.push(character);

    void addCharacterToExploder(String nextCharacter) {
      final trimmedCharacter = nextCharacter.trim();
      if (trimmedCharacter.isEmpty || !_containsChineseText(trimmedCharacter)) {
        return;
      }

      exploderHistory.value = exploderHistory.value.push(trimmedCharacter);
    }

    void goBackInExploder() {
      exploderHistory.value = exploderHistory.value.goBack();
    }

    void goForwardInExploder() {
      exploderHistory.value = exploderHistory.value.goForward();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CharacterExplosionSheet(
        client: widget.client,
        historyListenable: exploderHistory,
        characterIndexFuture: Future.value(widget.characterIndex),
        characterComponentsFuture:
            widget.characterComponentsFuture ??
            _loadOptionalCharacterComponents(widget.client),
        onCharacterTap: addCharacterToExploder,
        onBack: goBackInExploder,
        onForward: goForwardInExploder,
      ),
    ).whenComplete(exploderHistory.dispose);
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.pixels == 0) {
      return;
    }

    final target = _scrollController.position.minScrollExtent;
    if (!uiActive) {
      return;
    }

    await _scrollController.animateTo(
      target,
      duration: _characterScrollDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  void _selectEntryAtIndex(int index) {
    if (_orderedEntries.isEmpty ||
        index < 0 ||
        index >= _orderedEntries.length ||
        index == _currentEntryIndex) {
      return;
    }

    setState(() {
      _currentEntryIndex = index;
    });

    unawaited(_scrollToTop());
  }

  void _jumpToEntryFromLineNumber(String rawValue) {
    final requestedLineNumber = int.tryParse(rawValue.trim());
    if (requestedLineNumber == null) {
      _showSnackBar('Enter a line number.');
      return;
    }

    if (requestedLineNumber < 1 ||
        requestedLineNumber > _orderedEntries.length) {
      _showSnackBar('Line $requestedLineNumber is not in the character index.');
      return;
    }

    _selectEntryAtIndex(requestedLineNumber - 1);
  }

  void _jumpToEntryFromQuery(String rawValue) {
    final query = rawValue.trim();
    if (query.isEmpty) {
      _showSnackBar('Enter a character, reading, or gloss.');
      return;
    }

    final entryIndex = widget.characterIndex.indexForQuery(query);
    if (entryIndex == null) {
      _showSnackBar('No character matched "$query".');
      return;
    }

    _selectEntryAtIndex(entryIndex);
  }

  Future<void> _selectNextEntry() async {
    _selectEntryAtIndex(_currentEntryIndex + 1);
  }

  void _selectPreviousEntry() {
    _selectEntryAtIndex(_currentEntryIndex - 1);
  }

  String _formatAliases(CharacterEntry entry) {
    final primary = _formatCharacterHeading(entry, fallback: entry.character);
    final aliases = <String>{
      entry.character.trim(),
      entry.simplified.trim(),
      entry.traditional.trim(),
      ...entry.aliases.map((value) => value.trim()),
    }.where((value) => value.isNotEmpty && value != primary).toList();

    if (aliases.isEmpty) {
      return '';
    }

    return aliases.join(', ');
  }

  Widget _buildReferenceLine(BuildContext context, CharacterEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heading = _formatCharacterHeading(entry, fallback: entry.character);
    final reading = _formatCharacterReading(entry);
    final english = _joinVisibleValues(entry.english, separator: '; ');
    final aliases = _formatAliases(entry);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InteractiveChineseText(
          text: heading,
          style: _supportTableChineseTextStyle(context, heading),
          onCharacterTap: _openCharacterExplosionSheet,
          keyPrefix: 'character-index-heading-${_currentEntryIndex + 1}',
        ),
        if (_hasVisibleText(reading)) ...[
          const SizedBox(height: 4),
          Text(
            reading,
            softWrap: true,
            style: _withLargerChineseFont(
              context,
              reading,
              textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              fallbackFontSize: 12,
              sizeIncrease: 1,
            ),
          ),
        ],
        if (_hasVisibleText(english)) ...[
          const SizedBox(height: 4),
          Text(
            english,
            softWrap: true,
            style: _supportTableEnglishTextStyle(context),
          ),
        ],
        if (_hasVisibleText(aliases)) ...[
          const SizedBox(height: 8),
          Text(
            'Aliases: $aliases',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (entry.exampleWords.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ExplosionReferenceList(
            label: 'Examples',
            items: entry.exampleWords,
            characterIndex: widget.characterIndex,
            onCharacterTap: _openCharacterExplosionSheet,
          ),
        ],
        if (entry.explosion.synthesis.containingCharacters.isNotEmpty)
          _ExplosionReferenceList(
            label: 'Contained In',
            items: entry.explosion.synthesis.containingCharacters,
            characterIndex: widget.characterIndex,
            onCharacterTap: _openCharacterExplosionSheet,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEntry = _orderedEntries.isEmpty
        ? null
        : _orderedEntries[_currentEntryIndex];
    final onPreviousPressed = _currentEntryIndex == 0
        ? null
        : _selectPreviousEntry;
    final onNextPressed =
        _orderedEntries.isEmpty ||
            _currentEntryIndex >= _orderedEntries.length - 1
        ? null
        : _selectNextEntry;

    return ListView(
      controller: _scrollController,
      children: [
        _StatusCard(
          title: '',
          child: _orderedEntries.isEmpty
              ? const Text('No characters found.')
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LineNumberJumpField(
                          currentLineNumber: _currentEntryIndex + 1,
                          totalLineCount: _orderedEntries.length,
                          onSubmitted: _jumpToEntryFromLineNumber,
                          onPreviousPressed: onPreviousPressed,
                          onNextPressed: onNextPressed,
                        ),
                        const SizedBox(height: 12),
                        _ReferenceLookupField(
                          label: 'Find',
                          hintText: 'Character, reading, or gloss',
                          onSubmitted: _jumpToEntryFromQuery,
                          keyPrefix: 'character-index',
                        ),
                        const SizedBox(height: 16),
                        _buildReferenceLine(context, currentEntry!),
                        const SizedBox(height: 16),
                        _LineNumberJumpField(
                          currentLineNumber: _currentEntryIndex + 1,
                          totalLineCount: _orderedEntries.length,
                          onSubmitted: _jumpToEntryFromLineNumber,
                          onPreviousPressed: onPreviousPressed,
                          onNextPressed: onNextPressed,
                          keyPrefix: 'bottom',
                          showSelectorBeforeNavigationButtons: true,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class CharacterComponentsPage extends StatelessWidget {
  const CharacterComponentsPage({
    super.key,
    required this.client,
    required this.dataset,
    required this.characterIndex,
    this.readingProgressStore,
  });

  final BackendClient client;
  final CharacterComponentsDataset dataset;
  final CharacterIndex characterIndex;
  final ReadingProgressStore? readingProgressStore;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: _TranslatedTitle(
          primary: '參考：漢字部件',
          translation: 'Reference: Character components',
          primaryStyle: textTheme.titleLarge,
          translationStyle: _supportTableEnglishTextStyle(context),
          primaryMaxLines: 1,
          translationMaxLines: 1,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _CharacterComponentsDatasetList(
          client: client,
          dataset: dataset,
          characterIndex: characterIndex,
          readingProgressStore: readingProgressStore,
        ),
      ),
    );
  }
}

class _CharacterComponentsDatasetList extends StatefulWidget {
  const _CharacterComponentsDatasetList({
    required this.client,
    required this.dataset,
    required this.characterIndex,
    this.readingProgressStore,
  });

  final BackendClient client;
  final CharacterComponentsDataset dataset;
  final CharacterIndex characterIndex;
  final ReadingProgressStore? readingProgressStore;

  @override
  State<_CharacterComponentsDatasetList> createState() =>
      _CharacterComponentsDatasetListState();
}

class _CharacterComponentsDatasetListState
    extends State<_CharacterComponentsDatasetList> {
  static const int _chapterSize = 30;
  static const Duration _componentScrollDelay = Duration(milliseconds: 180);
  static const Duration _componentScrollDuration = Duration(milliseconds: 450);
  static const double _estimatedCollapsedChapterExtent = 148;
  static const double _chapterCardSpacing = 12;
  static const int _minimumChaptersForLooping = 3;
  static const int _chapterLoopCyclesPerSide = 200;

  late List<CharacterComponentEntry> _orderedEntries;
  int? _expandedChapterLoopIndex;
  int _scrollRequestId = 0;
  final GlobalKey _chapterLoopCenterKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _chapterKeys = {};
  final Map<int, int> _currentLineIndexByChapter = {};

  bool get _shouldLoopChapters => _chapterCount >= _minimumChaptersForLooping;
  int get _chapterLoopRepeatedItemCount =>
      _chapterCount * _chapterLoopCyclesPerSide;
  int get _chapterLoopCenterIndex => _chapterLoopRepeatedItemCount;
  double get _estimatedCollapsedChapterStride =>
      _estimatedCollapsedChapterExtent + _chapterCardSpacing;
  ReadingProgressStore get _readingProgressStore =>
      widget.readingProgressStore ??
      SharedPreferencesReadingProgressStore.instance;

  @override
  void initState() {
    super.initState();
    _resetVisibleEntries();
    _restoreReadingProgress();
  }

  @override
  void didUpdateWidget(covariant _CharacterComponentsDatasetList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dataset, widget.dataset)) {
      _resetVisibleEntries();
    }
  }

  void _resetVisibleEntries() {
    _orderedEntries = widget.dataset.orderedEntries;
    if (_chapterCount == 0) {
      _expandedChapterLoopIndex = null;
      return;
    }

    final expandedChapterLoopIndex = _expandedChapterLoopIndex;
    if (expandedChapterLoopIndex == null) {
      return;
    }

    final logicalChapterIndex = _chapterLogicalIndexForLoopIndex(
      expandedChapterLoopIndex,
    );
    _expandedChapterLoopIndex = _loopIndexForLogicalChapter(
      math.min(logicalChapterIndex, _chapterCount - 1),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openCharacterExplosionSheet(String character) {
    if (!_containsChineseText(character)) {
      return;
    }

    final exploderHistory = ValueNotifier<_CharacterExplosionHistory>(
      const _CharacterExplosionHistory(),
    );
    exploderHistory.value = exploderHistory.value.push(character);

    void addCharacterToExploder(String nextCharacter) {
      final trimmedCharacter = nextCharacter.trim();
      if (trimmedCharacter.isEmpty || !_containsChineseText(trimmedCharacter)) {
        return;
      }

      exploderHistory.value = exploderHistory.value.push(trimmedCharacter);
    }

    void goBackInExploder() {
      exploderHistory.value = exploderHistory.value.goBack();
    }

    void goForwardInExploder() {
      exploderHistory.value = exploderHistory.value.goForward();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CharacterExplosionSheet(
        client: widget.client,
        historyListenable: exploderHistory,
        characterIndexFuture: Future.value(widget.characterIndex),
        characterComponentsFuture: Future.value(widget.dataset),
        onCharacterTap: addCharacterToExploder,
        onBack: goBackInExploder,
        onForward: goForwardInExploder,
      ),
    ).whenComplete(exploderHistory.dispose);
  }

  Future<void> _scrollChapterToTop(int chapterLoopIndex) async {
    if (!uiActive || _chapterCount == 0) {
      return;
    }

    final requestId = ++_scrollRequestId;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(_componentScrollDelay);

    if (!uiActive ||
        requestId != _scrollRequestId ||
        _expandedChapterLoopIndex != chapterLoopIndex) {
      return;
    }

    final chapterContext = _chapterKeyForLoopIndex(
      chapterLoopIndex,
    ).currentContext;
    if ((chapterContext == null || !chapterContext.mounted) &&
        _scrollController.hasClients) {
      final approximateOffset = _shouldLoopChapters
          ? (chapterLoopIndex - _chapterLoopCenterIndex) *
                _estimatedCollapsedChapterStride
          : chapterLoopIndex * _estimatedCollapsedChapterStride;
      final clampedOffset = approximateOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      await _scrollController.animateTo(
        clampedOffset.toDouble(),
        duration: _componentScrollDuration,
        curve: Curves.easeInOutCubic,
      );
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(_componentScrollDelay);
    }

    final resolvedChapterContext = _chapterKeyForLoopIndex(
      chapterLoopIndex,
    ).currentContext;
    if (resolvedChapterContext == null || !resolvedChapterContext.mounted) {
      return;
    }

    await Scrollable.ensureVisible(
      resolvedChapterContext,
      alignment: 0,
      duration: _componentScrollDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  int get _chapterCount => (_orderedEntries.length / _chapterSize).ceil();

  int _chapterLogicalIndexForLoopIndex(int loopIndex) {
    final chapterCount = _chapterCount;
    final normalizedIndex = loopIndex % chapterCount;
    return normalizedIndex < 0
        ? normalizedIndex + chapterCount
        : normalizedIndex;
  }

  int _loopIndexForLogicalChapter(int chapterIndex) {
    return _shouldLoopChapters
        ? _chapterLoopCenterIndex + chapterIndex
        : chapterIndex;
  }

  int _chapterStartIndex(int chapterIndex) => chapterIndex * _chapterSize;

  int _chapterLineCount(int chapterIndex) {
    final startIndex = _chapterStartIndex(chapterIndex);
    return math.min(_chapterSize, _orderedEntries.length - startIndex);
  }

  Iterable<CharacterComponentEntry> _entriesForChapter(int chapterIndex) sync* {
    final startIndex = _chapterStartIndex(chapterIndex);
    final endIndex = math.min(
      startIndex + _chapterSize,
      _orderedEntries.length,
    );
    for (var entryIndex = startIndex; entryIndex < endIndex; entryIndex++) {
      yield _orderedEntries[entryIndex];
    }
  }

  GlobalKey _chapterKeyForLoopIndex(int chapterIndex) {
    return _chapterKeys.putIfAbsent(chapterIndex, () => GlobalKey());
  }

  int _currentChapterLineIndex(int chapterIndex) {
    final lineCount = _chapterLineCount(chapterIndex);
    if (lineCount <= 0) {
      return 0;
    }

    final savedIndex = _currentLineIndexByChapter[chapterIndex] ?? 0;
    final clampedIndex = math.min(savedIndex, lineCount - 1);
    if (clampedIndex != savedIndex) {
      _currentLineIndexByChapter[chapterIndex] = clampedIndex;
    }
    return clampedIndex;
  }

  Future<void> _restoreReadingProgress() async {
    final progress = await _readingProgressStore.loadBookProgress(
      bookId: _characterComponentsProgressScopeId,
    );
    if (!uiActive || progress == null || _expandedChapterLoopIndex != null) {
      return;
    }

    final chapterIndex = _characterComponentsChapterIndexFromStorageId(
      progress.chapterId,
    );
    if (chapterIndex == null ||
        chapterIndex < 0 ||
        chapterIndex >= _chapterCount) {
      return;
    }

    final lineIndex = math.max(
      0,
      math.min(progress.readingUnitIndex, _chapterLineCount(chapterIndex) - 1),
    );
    final chapterLoopIndex = _loopIndexForLogicalChapter(chapterIndex);
    setState(() {
      _expandedChapterLoopIndex = chapterLoopIndex;
      _currentLineIndexByChapter[chapterIndex] = lineIndex;
    });

    await _scrollChapterToTop(chapterLoopIndex);
  }

  Future<void> _persistReadingProgress({
    required int chapterIndex,
    required int lineIndex,
  }) async {
    await _readingProgressStore.saveBookProgress(
      bookId: _characterComponentsProgressScopeId,
      progress: BookReadingProgress(
        chapterId: _characterComponentsChapterStorageId(chapterIndex),
        readingUnitIndex: lineIndex,
      ),
    );
  }

  void _toggleChapter(int chapterLoopIndex) {
    final nextExpandedChapterLoopIndex =
        _expandedChapterLoopIndex == chapterLoopIndex ? null : chapterLoopIndex;
    setState(() {
      _expandedChapterLoopIndex = nextExpandedChapterLoopIndex;
    });

    if (nextExpandedChapterLoopIndex != null) {
      final chapterIndex = _chapterLogicalIndexForLoopIndex(
        nextExpandedChapterLoopIndex,
      );
      unawaited(
        _persistReadingProgress(
          chapterIndex: chapterIndex,
          lineIndex: _currentChapterLineIndex(chapterIndex),
        ),
      );
      unawaited(_scrollChapterToTop(nextExpandedChapterLoopIndex));
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectChapterLineIndex(int chapterIndex, int lineIndex) async {
    final lineCount = _chapterLineCount(chapterIndex);
    final currentLineIndex = _currentChapterLineIndex(chapterIndex);
    if (lineCount <= 0 ||
        lineIndex < 0 ||
        lineIndex >= lineCount ||
        lineIndex == currentLineIndex) {
      return;
    }

    setState(() {
      _currentLineIndexByChapter[chapterIndex] = lineIndex;
    });
    unawaited(
      _persistReadingProgress(chapterIndex: chapterIndex, lineIndex: lineIndex),
    );

    final expandedChapterLoopIndex = _expandedChapterLoopIndex;
    final targetChapterLoopIndex =
        expandedChapterLoopIndex != null &&
            _chapterLogicalIndexForLoopIndex(expandedChapterLoopIndex) ==
                chapterIndex
        ? expandedChapterLoopIndex
        : _loopIndexForLogicalChapter(chapterIndex);

    await _scrollChapterToTop(targetChapterLoopIndex);
  }

  void _jumpToChapterLine(int chapterIndex, String rawValue) {
    final requestedLineNumber = int.tryParse(rawValue.trim());
    if (requestedLineNumber == null) {
      _showSnackBar('Enter a line number.');
      return;
    }

    final lineCount = _chapterLineCount(chapterIndex);
    if (requestedLineNumber < 1 || requestedLineNumber > lineCount) {
      _showSnackBar('Line $requestedLineNumber is not in this chapter.');
      return;
    }

    unawaited(_selectChapterLineIndex(chapterIndex, requestedLineNumber - 1));
  }

  Future<void> _selectNextChapterLine(int chapterIndex) async {
    await _selectChapterLineIndex(
      chapterIndex,
      _currentChapterLineIndex(chapterIndex) + 1,
    );
  }

  void _selectPreviousChapterLine(int chapterIndex) {
    unawaited(
      _selectChapterLineIndex(
        chapterIndex,
        _currentChapterLineIndex(chapterIndex) - 1,
      ),
    );
  }

  _CharacterComponentReferenceRow _buildRow({
    required int index,
    required CharacterComponentEntry entry,
  }) {
    final referenceEntry = _resolveReferenceEntry(entry);
    return _CharacterComponentReferenceRow(
      index: index,
      chineseForms: _formatChineseForms(entry),
      pinyin: _formatPinyin(referenceEntry),
      zhuyin: _formatZhuyin(referenceEntry),
      englishMeaning: _formatEnglishMeaning(referenceEntry),
      exampleCharacters: _buildExampleCharacters(referenceEntry, entry),
    );
  }

  CharacterEntry? _resolveReferenceEntry(CharacterComponentEntry entry) {
    final candidates = {
      entry.canonicalForm,
      ...entry.forms,
      ...entry.variantForms,
    };
    for (final candidate in candidates) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty || trimmed.runes.length != 1) {
        continue;
      }

      final referenceEntry = widget.characterIndex.entryFor(trimmed);
      if (referenceEntry != null) {
        return referenceEntry;
      }
    }

    return null;
  }

  bool _isDisplaySafeComponentForm(
    String value,
    CharacterComponentEntry entry,
  ) {
    return !value.contains('{') &&
        !value.contains('}') &&
        (value == entry.canonicalForm ||
            value.runes.every((rune) => rune <= 0xFFFF));
  }

  String _formatChineseForms(CharacterComponentEntry entry) {
    final forms = {
      entry.canonicalForm,
      ...entry.forms,
      ...entry.variantForms,
    }.map((value) => value.trim()).where((value) => value.isNotEmpty).toList();

    final displayForms = forms
        .where((value) => _isDisplaySafeComponentForm(value, entry))
        .toList(growable: false);
    if (displayForms.isNotEmpty) {
      return displayForms.join(', ');
    }

    final fallbackName = entry.canonicalName.trim().isNotEmpty
        ? entry.canonicalName.trim()
        : entry.names.firstWhere(
            (value) => value.trim().isNotEmpty,
            orElse: () => '',
          );
    return fallbackName;
  }

  String _formatPinyin(CharacterEntry? entry) {
    if (entry == null) {
      return '';
    }

    return entry.pinyin.join('; ');
  }

  String _formatZhuyin(CharacterEntry? entry) {
    if (entry == null) {
      return '';
    }

    return entry.zhuyin.join('; ');
  }

  String _formatEnglishMeaning(CharacterEntry? entry) {
    if (entry == null || entry.english.isEmpty) {
      return '';
    }

    return entry.english.join('; ');
  }

  List<String> _singleCharacterExamples(Iterable<String> candidates) {
    final examples = <String>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty || trimmed.runes.length != 1 || !seen.add(trimmed)) {
        continue;
      }
      examples.add(trimmed);
    }
    return examples;
  }

  int _pedagogicalExampleWordCount(CharacterEntry? entry) {
    if (entry == null) {
      return 0;
    }

    return entry.exampleWords.where(_hasVisibleText).length;
  }

  List<_CharacterComponentExampleRow> _buildExampleCharacters(
    CharacterEntry? entry,
    CharacterComponentEntry componentEntry,
  ) {
    final candidates = <_CharacterComponentExampleCandidate>[];
    final seen = <String>{};

    void addCandidates(Iterable<String> values, {required int sourceBucket}) {
      var originalOrder = 0;
      for (final character in _singleCharacterExamples(values)) {
        final referenceEntry = widget.characterIndex.entryFor(character);
        if (!seen.add(character)) {
          originalOrder += 1;
          continue;
        }
        candidates.add(
          _CharacterComponentExampleCandidate(
            character: character,
            referenceEntry: referenceEntry,
            sourceBucket: sourceBucket,
            originalOrder: originalOrder,
            pedagogicalExampleWordCount: _pedagogicalExampleWordCount(
              referenceEntry,
            ),
          ),
        );
        originalOrder += 1;
      }
    }

    addCandidates(componentEntry.sourceExampleCharacters, sourceBucket: 0);
    if (entry != null) {
      addCandidates(
        entry.explosion.synthesis.containingCharacters,
        sourceBucket: 1,
      );
    }

    candidates.sort((left, right) {
      final pedagogicalSupportComparison = right.pedagogicalExampleWordCount
          .compareTo(left.pedagogicalExampleWordCount);
      if (pedagogicalSupportComparison != 0) {
        return pedagogicalSupportComparison;
      }

      final sourceBucketComparison = left.sourceBucket.compareTo(
        right.sourceBucket,
      );
      if (sourceBucketComparison != 0) {
        return sourceBucketComparison;
      }

      final originalOrderComparison = left.originalOrder.compareTo(
        right.originalOrder,
      );
      if (originalOrderComparison != 0) {
        return originalOrderComparison;
      }

      return left.character.compareTo(right.character);
    });

    return [
      for (final candidate in candidates.take(5))
        _buildExampleCharacterRow(
          candidate.character,
          referenceEntry: candidate.referenceEntry,
        ),
    ];
  }

  _CharacterComponentExampleRow _buildExampleCharacterRow(
    String character, {
    CharacterEntry? referenceEntry,
  }) {
    return _CharacterComponentExampleRow(
      character: character,
      pinyin: _formatPinyin(referenceEntry),
      zhuyin: _formatZhuyin(referenceEntry),
      englishMeaning: _formatEnglishMeaning(referenceEntry),
    );
  }

  String _formatCombinedReadingValues({
    required String pinyin,
    required String zhuyin,
  }) {
    if (_hasVisibleText(pinyin) && _hasVisibleText(zhuyin)) {
      return '$pinyin ($zhuyin)';
    }

    return _hasVisibleText(pinyin) ? pinyin : zhuyin;
  }

  String _formatCombinedReading(_CharacterComponentReferenceRow row) {
    return _formatCombinedReadingValues(pinyin: row.pinyin, zhuyin: row.zhuyin);
  }

  Widget _buildExampleLine(
    BuildContext context,
    _CharacterComponentReferenceRow row,
    _CharacterComponentExampleRow example,
    int exampleIndex,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final supportTableEnglishStyle = _supportTableEnglishTextStyle(context);
    final reading = _formatCombinedReadingValues(
      pinyin: example.pinyin,
      zhuyin: example.zhuyin,
    );
    final chineseStyle = _supportTableChineseTextStyle(
      context,
      example.character,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InteractiveChineseText(
          text: example.character,
          style: chineseStyle,
          onCharacterTap: _openCharacterExplosionSheet,
          keyPrefix: 'component-example-${row.index}-$exampleIndex',
        ),
        if (_hasVisibleText(reading)) ...[
          const SizedBox(height: 2),
          Text(reading, softWrap: true, style: textTheme.bodySmall),
        ],
        if (_hasVisibleText(example.englishMeaning)) ...[
          const SizedBox(height: 2),
          Text(
            example.englishMeaning,
            softWrap: true,
            style: supportTableEnglishStyle,
          ),
        ],
      ],
    );
  }

  Widget _buildReferenceLine(
    BuildContext context,
    _CharacterComponentReferenceRow row,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final secondaryStyle = textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    final supportTableEnglishStyle = _supportTableEnglishTextStyle(context);
    final reading = _formatCombinedReading(row);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InteractiveChineseText(
          text: row.chineseForms,
          style: _supportTableChineseTextStyle(context, row.chineseForms),
          onCharacterTap: _openCharacterExplosionSheet,
          keyPrefix: 'component-heading-${row.index}',
        ),
        if (_hasVisibleText(reading)) ...[
          const SizedBox(height: 4),
          Text(
            reading,
            softWrap: true,
            style: _withLargerChineseFont(
              context,
              reading,
              secondaryStyle,
              fallbackFontSize: 12,
              sizeIncrease: 1,
            ),
          ),
        ],
        if (_hasVisibleText(row.englishMeaning)) ...[
          const SizedBox(height: 4),
          Text(
            row.englishMeaning,
            softWrap: true,
            style: supportTableEnglishStyle,
          ),
        ],
        if (row.exampleCharacters.isNotEmpty) ...[
          const SizedBox(height: 12),
          Divider(
            key: ValueKey('component-header-divider-${row.index}'),
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (
                var index = 0;
                index < row.exampleCharacters.length;
                index++
              ) ...[
                if (index > 0) const SizedBox(height: 8),
                _buildExampleLine(
                  context,
                  row,
                  row.exampleCharacters[index],
                  index,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildChapterReader(BuildContext context, int chapterIndex) {
    final startIndex = _chapterStartIndex(chapterIndex);
    final lineCount = _chapterLineCount(chapterIndex);
    final currentLineIndex = _currentChapterLineIndex(chapterIndex);
    final currentEntryIndex = startIndex + currentLineIndex;
    final currentRow = _buildRow(
      index: currentEntryIndex + 1,
      entry: _orderedEntries[currentEntryIndex],
    );
    final onPreviousPressed = currentLineIndex == 0
        ? null
        : () => _selectPreviousChapterLine(chapterIndex);
    final onNextPressed = currentLineIndex >= lineCount - 1
        ? null
        : () => _selectNextChapterLine(chapterIndex);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: _StatusCard(
        title: '',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LineNumberJumpField(
              currentLineNumber: currentLineIndex + 1,
              totalLineCount: lineCount,
              onSubmitted: (rawValue) =>
                  _jumpToChapterLine(chapterIndex, rawValue),
              onPreviousPressed: onPreviousPressed,
              onNextPressed: onNextPressed,
            ),
            const SizedBox(height: 16),
            _buildReferenceLine(context, currentRow),
            const SizedBox(height: 16),
            _LineNumberJumpField(
              currentLineNumber: currentLineIndex + 1,
              totalLineCount: lineCount,
              onSubmitted: (rawValue) =>
                  _jumpToChapterLine(chapterIndex, rawValue),
              onPreviousPressed: onPreviousPressed,
              onNextPressed: onNextPressed,
              keyPrefix: 'bottom',
              showSelectorBeforeNavigationButtons: true,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_orderedEntries.isEmpty) {
      return const _StatusCard(title: '', child: Text('No components found.'));
    }

    return _shouldLoopChapters
        ? _buildLoopingComponentChaptersList(context)
        : _buildFiniteComponentChaptersList(context);
  }

  Widget _buildChapterMenuCardForLoopIndex(
    BuildContext context,
    int chapterLoopIndex,
  ) {
    final chapterIndex = _chapterLogicalIndexForLoopIndex(chapterLoopIndex);
    final isExpanded = _expandedChapterLoopIndex == chapterLoopIndex;

    return KeyedSubtree(
      key: _chapterKeyForLoopIndex(chapterLoopIndex),
      child: _LibraryMenuTile(
        title: 'Chapter ${chapterIndex + 1}',
        subtitle: Text(
          _componentChapterCountSummary(_entriesForChapter(chapterIndex)),
        ),
        expandedChild: isExpanded
            ? _buildChapterReader(context, chapterIndex)
            : null,
        onTap: () => _toggleChapter(chapterLoopIndex),
      ),
    );
  }

  Widget _buildFiniteComponentChaptersList(BuildContext context) {
    return ListView.separated(
      controller: _scrollController,
      itemCount: _chapterCount,
      separatorBuilder: (_, _) => const SizedBox(height: _chapterCardSpacing),
      itemBuilder: (context, chapterIndex) {
        return _buildChapterMenuCardForLoopIndex(context, chapterIndex);
      },
    );
  }

  Widget _buildLoopingComponentChaptersList(BuildContext context) {
    final repeatedItemCount = _chapterLoopRepeatedItemCount;

    Widget buildLeadingChapterCard(BuildContext context, int index) {
      final chapterLoopIndex = _chapterLoopCenterIndex - 1 - index;
      return Padding(
        padding: const EdgeInsets.only(bottom: _chapterCardSpacing),
        child: _buildChapterMenuCardForLoopIndex(context, chapterLoopIndex),
      );
    }

    Widget buildTrailingChapterCard(BuildContext context, int index) {
      final chapterLoopIndex = _chapterLoopCenterIndex + index;
      return Padding(
        padding: const EdgeInsets.only(bottom: _chapterCardSpacing),
        child: _buildChapterMenuCardForLoopIndex(context, chapterLoopIndex),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      center: _chapterLoopCenterKey,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            buildLeadingChapterCard,
            childCount: repeatedItemCount,
          ),
        ),
        SliverList(
          key: _chapterLoopCenterKey,
          delegate: SliverChildBuilderDelegate(
            buildTrailingChapterCard,
            childCount: repeatedItemCount,
          ),
        ),
      ],
    );
  }
}

class _CharacterComponentReferenceRow {
  const _CharacterComponentReferenceRow({
    required this.index,
    required this.chineseForms,
    required this.pinyin,
    required this.zhuyin,
    required this.englishMeaning,
    required this.exampleCharacters,
  });

  final int index;
  final String chineseForms;
  final String pinyin;
  final String zhuyin;
  final String englishMeaning;
  final List<_CharacterComponentExampleRow> exampleCharacters;
}

class _CharacterComponentExampleCandidate {
  const _CharacterComponentExampleCandidate({
    required this.character,
    required this.referenceEntry,
    required this.sourceBucket,
    required this.originalOrder,
    required this.pedagogicalExampleWordCount,
  });

  final String character;
  final CharacterEntry? referenceEntry;
  final int sourceBucket;
  final int originalOrder;
  final int pedagogicalExampleWordCount;
}

class _CharacterComponentExampleRow {
  const _CharacterComponentExampleRow({
    required this.character,
    required this.pinyin,
    required this.zhuyin,
    required this.englishMeaning,
  });

  final String character;
  final String pinyin;
  final String zhuyin;
  final String englishMeaning;
}

class BookChaptersPage extends StatefulWidget {
  const BookChaptersPage({
    super.key,
    required this.client,
    required this.book,
    required this.characterIndex,
    this.characterComponentsFuture,
    this.lineStudyStore,
    this.readingProgressStore,
  });

  final BackendClient client;
  final BookDetail book;
  final CharacterIndex characterIndex;
  final Future<CharacterComponentsDataset>? characterComponentsFuture;
  final LineStudyStore? lineStudyStore;
  final ReadingProgressStore? readingProgressStore;

  @override
  State<BookChaptersPage> createState() => _BookChaptersPageState();
}

class _BookChaptersPageState extends State<BookChaptersPage> {
  static const Duration _chapterScrollDelay = Duration(milliseconds: 180);
  static const Duration _chapterScrollDuration = Duration(milliseconds: 450);
  static const double _estimatedCollapsedChapterExtent = 148;
  static const double _chapterCardSpacing = 12;
  static const int _minimumChaptersForLooping = 3;
  static const int _chapterLoopCyclesPerSide = 200;
  late final Future<CharacterComponentsDataset> _characterComponentsFuture;
  final GlobalKey _chapterLoopCenterKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  final Map<int, GlobalKey> _chapterKeys = {};
  final Map<int, GlobalKey<_ChapterReaderPageState>> _chapterReaderKeys = {};
  final Map<String, Map<String, LineStudyEntry>> _lineStudyEntriesByChapterId =
      {};
  int? _expandedChapterLoopIndex;
  int _scrollRequestId = 0;

  LineStudyStore get _lineStudyStore =>
      widget.lineStudyStore ?? SharedPreferencesLineStudyStore.instance;
  ReadingProgressStore get _readingProgressStore =>
      widget.readingProgressStore ??
      SharedPreferencesReadingProgressStore.instance;
  bool get _shouldLoopChapters =>
      widget.book.chapters.length >= _minimumChaptersForLooping;
  int get _chapterLoopRepeatedItemCount =>
      widget.book.chapters.length * _chapterLoopCyclesPerSide;
  int get _chapterLoopCenterIndex => _chapterLoopRepeatedItemCount;
  double get _estimatedCollapsedChapterStride =>
      _estimatedCollapsedChapterExtent + _chapterCardSpacing;

  int _chapterLogicalIndexForLoopIndex(int loopIndex) {
    final chapterCount = widget.book.chapters.length;
    final normalizedIndex = loopIndex % chapterCount;
    return normalizedIndex < 0
        ? normalizedIndex + chapterCount
        : normalizedIndex;
  }

  ChapterSummary _chapterForLoopIndex(int loopIndex) {
    return widget.book.chapters[_chapterLogicalIndexForLoopIndex(loopIndex)];
  }

  int _loopIndexForLogicalChapter(int chapterIndex) {
    return _shouldLoopChapters
        ? _chapterLoopCenterIndex + chapterIndex
        : chapterIndex;
  }

  GlobalKey _chapterKeyForLoopIndex(int loopIndex) {
    return _chapterKeys.putIfAbsent(loopIndex, () => GlobalKey());
  }

  GlobalKey<_ChapterReaderPageState> _chapterReaderKeyForLoopIndex(
    int loopIndex,
  ) {
    return _chapterReaderKeys.putIfAbsent(
      loopIndex,
      () => GlobalKey<_ChapterReaderPageState>(),
    );
  }

  String? get _expandedChapterId {
    final expandedChapterLoopIndex = _expandedChapterLoopIndex;
    if (expandedChapterLoopIndex == null) {
      return null;
    }

    return _chapterForLoopIndex(expandedChapterLoopIndex).id;
  }

  @override
  void initState() {
    super.initState();
    _characterComponentsFuture =
        widget.characterComponentsFuture ??
        _loadOptionalCharacterComponents(widget.client);
    _loadChapterLineStudyEntries();
    _restoreReadingProgress();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChapterLineStudyEntries() async {
    final chapterEntriesByChapterId = <String, Map<String, LineStudyEntry>>{};

    await Future.wait(
      widget.book.chapters.map((chapter) async {
        final chapterEntries = await _lineStudyStore.loadChapterEntries(
          bookId: widget.book.id,
          chapterId: chapter.id,
        );
        if (chapterEntries.isEmpty) {
          return;
        }

        chapterEntriesByChapterId[chapter.id] =
            Map<String, LineStudyEntry>.from(chapterEntries);
      }),
    );

    if (!uiActive) {
      return;
    }

    setState(() {
      _lineStudyEntriesByChapterId
        ..clear()
        ..addAll(chapterEntriesByChapterId);
    });
  }

  void _updateChapterLineStudyEntries(
    String chapterId,
    Map<String, LineStudyEntry> chapterEntries,
  ) {
    if (!uiActive) {
      return;
    }

    setState(() {
      if (chapterEntries.isEmpty) {
        _lineStudyEntriesByChapterId.remove(chapterId);
      } else {
        _lineStudyEntriesByChapterId[chapterId] =
            Map<String, LineStudyEntry>.from(chapterEntries);
      }
    });
  }

  int _savedTranslationCount(ChapterSummary chapter) {
    final chapterEntries = _lineStudyEntriesByChapterId[chapter.id];
    if (chapterEntries == null) {
      return 0;
    }

    return chapterEntries.values.where((entry) => entry.hasTranslation).length;
  }

  int _savedResponseCount(ChapterSummary chapter) {
    final chapterEntries = _lineStudyEntriesByChapterId[chapter.id];
    if (chapterEntries == null) {
      return 0;
    }

    return chapterEntries.values.where((entry) => entry.hasResponse).length;
  }

  String _chapterLineStudySummary(ChapterSummary chapter) {
    return _savedLineStudyCountSummary(
      translationCount: _savedTranslationCount(chapter),
      responseCount: _savedResponseCount(chapter),
      includeLabel: false,
    );
  }

  void _toggleChapter(int chapterLoopIndex) {
    final chapterId = _chapterForLoopIndex(chapterLoopIndex).id;
    final nextExpandedChapterLoopIndex =
        _expandedChapterLoopIndex == chapterLoopIndex ? null : chapterLoopIndex;

    setState(() {
      _expandedChapterLoopIndex = nextExpandedChapterLoopIndex;
    });

    if (nextExpandedChapterLoopIndex != null) {
      unawaited(_persistExpandedChapter(chapterId));
      _scrollChapterToTop(chapterLoopIndex);
    }
  }

  Future<void> _restoreReadingProgress() async {
    final progress = await _readingProgressStore.loadBookProgress(
      bookId: widget.book.id,
    );
    if (!uiActive || progress == null || _expandedChapterLoopIndex != null) {
      return;
    }

    final chapterIndex = widget.book.chapters.indexWhere(
      (chapter) => chapter.id == progress.chapterId,
    );
    if (chapterIndex < 0) {
      return;
    }

    final chapterLoopIndex = _loopIndexForLogicalChapter(chapterIndex);
    setState(() {
      _expandedChapterLoopIndex = chapterLoopIndex;
    });

    await _scrollChapterToTop(chapterLoopIndex);
  }

  Future<void> _persistExpandedChapter(String chapterId) async {
    final existingProgress = await _readingProgressStore.loadBookProgress(
      bookId: widget.book.id,
    );
    final nextProgress =
        existingProgress != null && existingProgress.chapterId == chapterId
        ? existingProgress
        : BookReadingProgress(chapterId: chapterId, readingUnitIndex: 0);
    await _readingProgressStore.saveBookProgress(
      bookId: widget.book.id,
      progress: nextProgress,
    );
  }

  Future<void> _scrollChapterToTop(int chapterLoopIndex) async {
    if (!uiActive) {
      return;
    }

    final requestId = ++_scrollRequestId;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(_chapterScrollDelay);

    if (!uiActive ||
        requestId != _scrollRequestId ||
        _expandedChapterLoopIndex != chapterLoopIndex) {
      return;
    }

    final chapterContext = _chapterKeyForLoopIndex(
      chapterLoopIndex,
    ).currentContext;
    if ((chapterContext == null || !chapterContext.mounted) &&
        _scrollController.hasClients) {
      final approximateOffset = _shouldLoopChapters
          ? (chapterLoopIndex - _chapterLoopCenterIndex) *
                _estimatedCollapsedChapterStride
          : chapterLoopIndex * _estimatedCollapsedChapterStride;
      final clampedOffset = approximateOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      await _scrollController.animateTo(
        clampedOffset.toDouble(),
        duration: _chapterScrollDuration,
        curve: Curves.easeInOutCubic,
      );
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(_chapterScrollDelay);
    }

    final resolvedChapterContext = _chapterKeyForLoopIndex(
      chapterLoopIndex,
    ).currentContext;
    if (resolvedChapterContext == null ||
        !resolvedChapterContext.mounted ||
        !uiActive) {
      return;
    }

    await Scrollable.ensureVisible(
      resolvedChapterContext,
      alignment: 0,
      duration: _chapterScrollDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _openNextChapterFrom(int chapterLoopIndex) async {
    final chapterIndex = _chapterLogicalIndexForLoopIndex(chapterLoopIndex);
    final nextChapterIndex = chapterIndex + 1;
    if (nextChapterIndex >= widget.book.chapters.length) {
      return;
    }

    final nextChapterLoopIndex = _shouldLoopChapters
        ? chapterLoopIndex + 1
        : nextChapterIndex;
    final nextChapterId = widget.book.chapters[nextChapterIndex].id;
    if (!uiActive) {
      return;
    }

    setState(() {
      _expandedChapterLoopIndex = nextChapterLoopIndex;
    });

    unawaited(_persistExpandedChapter(nextChapterId));
    await _scrollChapterToTop(nextChapterLoopIndex);
    _chapterReaderKeyForLoopIndex(
      nextChapterLoopIndex,
    ).currentState?.jumpToFirstReadingUnit();
  }

  Future<void> _openExpandedChapterChat() async {
    final chapterLoopIndex = _expandedChapterLoopIndex;
    if (chapterLoopIndex == null) {
      return;
    }

    await _chapterReaderKeyForLoopIndex(
      chapterLoopIndex,
    ).currentState?.openGuidedChatThreadForCurrentChapter();
  }

  Widget _buildChapterMenuCardForLoopIndex(
    BuildContext context,
    int chapterLoopIndex,
  ) {
    final chapter = _chapterForLoopIndex(chapterLoopIndex);
    final isExpanded = _expandedChapterLoopIndex == chapterLoopIndex;
    return _ChapterMenuCard(
      key: _chapterKeyForLoopIndex(chapterLoopIndex),
      client: widget.client,
      bookId: widget.book.id,
      chapter: chapter,
      characterIndex: widget.characterIndex,
      characterComponentsFuture: _characterComponentsFuture,
      lineStudySummary: _chapterLineStudySummary(chapter),
      isExpanded: isExpanded,
      expandedChild: isExpanded
          ? KeyedSubtree(
              key: PageStorageKey(
                'chapter-reader-${widget.book.id}-${chapter.id}-embedded',
              ),
              child: ChapterReaderPage(
                key: _chapterReaderKeyForLoopIndex(chapterLoopIndex),
                client: widget.client,
                bookTitle: widget.book.title,
                bookId: widget.book.id,
                chapterId: chapter.id,
                characterIndex: widget.characterIndex,
                lineStudyStore: _lineStudyStore,
                readingProgressStore: _readingProgressStore,
                embedded: true,
                onLineStudyEntriesChanged: (chapterEntries) =>
                    _updateChapterLineStudyEntries(chapter.id, chapterEntries),
                onAdvanceToNextReading: () =>
                    _scrollChapterToTop(chapterLoopIndex),
                onAdvancePastChapterEnd: () =>
                    _openNextChapterFrom(chapterLoopIndex),
              ),
            )
          : null,
      onTap: () => _toggleChapter(chapterLoopIndex),
    );
  }

  Widget _buildFiniteBookChaptersList(BuildContext context) {
    return ListView.separated(
      controller: _scrollController,
      itemCount: widget.book.chapters.length,
      separatorBuilder: (_, _) => const SizedBox(height: _chapterCardSpacing),
      itemBuilder: (context, index) {
        return _buildChapterMenuCardForLoopIndex(context, index);
      },
    );
  }

  Widget _buildLoopingBookChaptersList(BuildContext context) {
    final repeatedItemCount = _chapterLoopRepeatedItemCount;

    Widget buildLeadingChapterCard(BuildContext context, int index) {
      final chapterLoopIndex = _chapterLoopCenterIndex - 1 - index;
      return Padding(
        padding: const EdgeInsets.only(bottom: _chapterCardSpacing),
        child: _buildChapterMenuCardForLoopIndex(context, chapterLoopIndex),
      );
    }

    Widget buildTrailingChapterCard(BuildContext context, int index) {
      final chapterLoopIndex = _chapterLoopCenterIndex + index;
      return Padding(
        padding: const EdgeInsets.only(bottom: _chapterCardSpacing),
        child: _buildChapterMenuCardForLoopIndex(context, chapterLoopIndex),
      );
    }

    return CustomScrollView(
      controller: _scrollController,
      center: _chapterLoopCenterKey,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            buildLeadingChapterCard,
            childCount: repeatedItemCount,
          ),
        ),
        SliverList(
          key: _chapterLoopCenterKey,
          delegate: SliverChildBuilderDelegate(
            buildTrailingChapterCard,
            childCount: repeatedItemCount,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bookTitleTranslation = translatedBookTitle(
      bookId: widget.book.id,
      title: widget.book.title,
    );
    final bookDisplayTitle = displayBookTitle(
      bookId: widget.book.id,
      title: widget.book.title,
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: bookTitleTranslation == null ? kToolbarHeight : 72,
        title: _TranslatedTitle(
          primary: bookDisplayTitle,
          translation: bookTitleTranslation,
          primaryStyle: textTheme.titleLarge,
          translationStyle: _supportTableEnglishTextStyle(context),
          primaryMaxLines: 1,
          translationMaxLines: 1,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: widget.book.chapters.isEmpty
            ? const Center(
                child: _StatusCard(
                  title: 'No readings found',
                  child: Text(
                    'This book does not contain any readable chapters.',
                  ),
                ),
              )
            : _shouldLoopChapters
            ? _buildLoopingBookChaptersList(context)
            : _buildFiniteBookChaptersList(context),
      ),
      floatingActionButton: _expandedChapterId == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('guided-chat-fab'),
              onPressed: _openExpandedChapterChat,
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Chat'),
            ),
    );
  }
}

class ChapterReaderPage extends StatefulWidget {
  const ChapterReaderPage({
    super.key,
    required this.client,
    required this.bookTitle,
    required this.bookId,
    required this.chapterId,
    this.characterIndex,
    this.lineStudyStore,
    this.readingProgressStore,
    this.embedded = false,
    this.onLineStudyEntriesChanged,
    this.onAdvanceToNextReading,
    this.onAdvancePastChapterEnd,
  });

  final BackendClient client;
  final String bookTitle;
  final String bookId;
  final String chapterId;
  final CharacterIndex? characterIndex;
  final LineStudyStore? lineStudyStore;
  final ReadingProgressStore? readingProgressStore;
  final bool embedded;
  final ValueChanged<Map<String, LineStudyEntry>>? onLineStudyEntriesChanged;
  final Future<void> Function()? onAdvanceToNextReading;
  final Future<void> Function()? onAdvancePastChapterEnd;

  @override
  State<ChapterReaderPage> createState() => _ChapterReaderPageState();
}

enum _LineStudyField { translation, response }

class _ChapterReaderPageState extends State<ChapterReaderPage> {
  late Future<ChapterDetail> _chapterFuture;
  late Future<CharacterIndex> _characterIndexFuture;
  late Future<CharacterComponentsDataset> _characterComponentsFuture;
  final ValueNotifier<_CharacterExplosionHistory> _exploderHistory =
      ValueNotifier<_CharacterExplosionHistory>(
        const _CharacterExplosionHistory(),
      );
  final Map<String, List<GuidedConversationMessage>> _threadsByReadingUnit = {};
  final Map<String, String> _messageDrafts = {};
  final Map<String, LineStudyEntry> _lineStudyEntries = {};
  int _currentReadingUnitIndex = 0;
  bool _isExplosionSheetOpen = false;
  bool _restoredReadingUnitIndex = false;

  LineStudyStore get _lineStudyStore =>
      widget.lineStudyStore ?? SharedPreferencesLineStudyStore.instance;
  ReadingProgressStore get _readingProgressStore =>
      widget.readingProgressStore ??
      SharedPreferencesReadingProgressStore.instance;

  String get _readingUnitStorageId =>
      'chapter-reader:${widget.bookId}:${widget.chapterId}:${widget.embedded ? 'embedded' : 'full'}';

  @override
  void initState() {
    super.initState();
    _characterIndexFuture = widget.characterIndex == null
        ? _loadOptionalCharacterIndex(widget.client)
        : Future.value(widget.characterIndex!);
    _characterComponentsFuture = _loadOptionalCharacterComponents(
      widget.client,
    );
    _chapterFuture = widget.client.fetchChapter(
      widget.bookId,
      widget.chapterId,
    );
    _loadLineStudyEntries();
    _restorePersistedReadingProgress();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredReadingUnitIndex) {
      return;
    }

    _restoredReadingUnitIndex = true;
    final storedIndex = PageStorage.maybeOf(
      context,
    )?.readState(context, identifier: _readingUnitStorageId);
    if (storedIndex is int && storedIndex >= 0) {
      _currentReadingUnitIndex = storedIndex;
    }
  }

  @override
  void dispose() {
    _exploderHistory.dispose();
    super.dispose();
  }

  void _resetChapterState() {
    _threadsByReadingUnit.clear();
    _messageDrafts.clear();
    _lineStudyEntries.clear();
    _exploderHistory.value = const _CharacterExplosionHistory();
    _currentReadingUnitIndex = 0;
  }

  void _persistCurrentReadingUnitIndex({bool includeBookProgress = true}) {
    PageStorage.maybeOf(context)?.writeState(
      context,
      _currentReadingUnitIndex,
      identifier: _readingUnitStorageId,
    );
    if (!includeBookProgress) {
      return;
    }

    unawaited(
      _readingProgressStore.saveBookProgress(
        bookId: widget.bookId,
        progress: BookReadingProgress(
          chapterId: widget.chapterId,
          readingUnitIndex: _currentReadingUnitIndex,
        ),
      ),
    );
  }

  void _reload() {
    setState(() {
      _resetChapterState();
      _characterIndexFuture = widget.characterIndex == null
          ? _loadOptionalCharacterIndex(widget.client)
          : Future.value(widget.characterIndex!);
      _characterComponentsFuture = _loadOptionalCharacterComponents(
        widget.client,
      );
      _chapterFuture = widget.client.fetchChapter(
        widget.bookId,
        widget.chapterId,
      );
    });
    _persistCurrentReadingUnitIndex(includeBookProgress: false);
    _loadLineStudyEntries();
  }

  Future<void> _restorePersistedReadingProgress() async {
    final progress = await _readingProgressStore.loadBookProgress(
      bookId: widget.bookId,
    );
    if (!uiActive) {
      return;
    }

    if (progress != null && progress.chapterId == widget.chapterId) {
      if (_currentReadingUnitIndex != progress.readingUnitIndex) {
        setState(() {
          _currentReadingUnitIndex = progress.readingUnitIndex;
        });
      }
      _persistCurrentReadingUnitIndex(includeBookProgress: false);
      return;
    }

    _persistCurrentReadingUnitIndex();
  }

  Future<void> _loadLineStudyEntries() async {
    final loadedEntries = await _lineStudyStore.loadChapterEntries(
      bookId: widget.bookId,
      chapterId: widget.chapterId,
    );
    if (!uiActive) {
      return;
    }

    setState(() {
      _lineStudyEntries
        ..clear()
        ..addAll(loadedEntries);
    });
    _notifyLineStudyEntriesChanged();
  }

  LineStudyEntry _lineStudyEntryFor(String readingUnitId) {
    return _lineStudyEntries[readingUnitId] ?? const LineStudyEntry();
  }

  int _safeReadingUnitIndex(ChapterDetail chapter) {
    if (chapter.readingUnits.isEmpty) {
      return 0;
    }

    return math.max(
      0,
      math.min(_currentReadingUnitIndex, chapter.readingUnits.length - 1),
    );
  }

  void _selectReadingUnit(ChapterDetail chapter, int nextIndex) {
    if (nextIndex < 0 || nextIndex >= chapter.readingUnits.length) {
      return;
    }

    final currentIndex = _safeReadingUnitIndex(chapter);
    if (nextIndex == currentIndex) {
      return;
    }

    setState(() {
      _currentReadingUnitIndex = nextIndex;
    });
    _persistCurrentReadingUnitIndex();
  }

  void jumpToFirstReadingUnit() {
    if (_currentReadingUnitIndex == 0) {
      return;
    }

    setState(() {
      _currentReadingUnitIndex = 0;
    });
    _persistCurrentReadingUnitIndex();
  }

  int? _readingUnitIndexForLineNumber(ChapterDetail chapter, int lineNumber) {
    final matchingOrderIndex = chapter.readingUnits.indexWhere(
      (readingUnit) => readingUnit.order == lineNumber,
    );
    if (matchingOrderIndex >= 0) {
      return matchingOrderIndex;
    }
    if (lineNumber >= 1 && lineNumber <= chapter.readingUnits.length) {
      return lineNumber - 1;
    }
    return null;
  }

  void _jumpToReadingUnitFromLineNumber(
    ChapterDetail chapter,
    String rawValue,
  ) {
    final requestedLineNumber = int.tryParse(rawValue.trim());
    if (requestedLineNumber == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Enter a valid line number.')),
      );
      return;
    }

    final nextIndex = _readingUnitIndexForLineNumber(
      chapter,
      requestedLineNumber,
    );
    if (nextIndex == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Line $requestedLineNumber is not in this chapter.'),
        ),
      );
      return;
    }

    _selectReadingUnit(chapter, nextIndex);
  }

  Future<void> _advanceToNextReadingUnit(ChapterDetail chapter) async {
    final currentIndex = _safeReadingUnitIndex(chapter);
    if (currentIndex < chapter.readingUnits.length - 1) {
      _selectReadingUnit(chapter, currentIndex + 1);

      if (widget.embedded) {
        await widget.onAdvanceToNextReading?.call();
      }
      return;
    }

    await widget.onAdvancePastChapterEnd?.call();
  }

  bool _canAdvanceToNextReadingUnit(ChapterDetail chapter) {
    return _safeReadingUnitIndex(chapter) < chapter.readingUnits.length - 1;
  }

  bool _canAdvanceBeyondChapter(ChapterDetail chapter) {
    return !_canAdvanceToNextReadingUnit(chapter) &&
        widget.onAdvancePastChapterEnd != null;
  }

  void _storeDraft(
    Map<String, String> drafts,
    String readingUnitId,
    String value,
  ) {
    if (value.isEmpty) {
      drafts.remove(readingUnitId);
      return;
    }

    drafts[readingUnitId] = value;
  }

  List<GuidedChatPreviousLine> _guidedChatPreviousLines(ChapterDetail chapter) {
    final currentIndex = _safeReadingUnitIndex(chapter);
    return _guidedChatPreviousLinesForIndex(
      chapter: chapter,
      currentIndex: currentIndex,
    );
  }

  List<GuidedChatPreviousLine> _guidedChatPreviousLinesForIndex({
    required ChapterDetail chapter,
    required int currentIndex,
  }) {
    if (widget.bookId == 'chengyu-catalog') {
      return const <GuidedChatPreviousLine>[];
    }

    if (currentIndex <= 0) {
      return const <GuidedChatPreviousLine>[];
    }

    return chapter.readingUnits
        .take(currentIndex)
        .map((readingUnit) {
          final lineStudyEntry = _lineStudyEntryFor(readingUnit.id);
          return GuidedChatPreviousLine(
            readingUnitId: readingUnit.id,
            order: readingUnit.order,
            text: readingUnit.text,
            translationEn: readingUnit.translationEn,
            learnerTranslation: lineStudyEntry.translation,
            learnerResponse: lineStudyEntry.response,
          );
        })
        .toList(growable: false);
  }

  Future<void> _saveLineStudyEntry({
    required String readingUnitId,
    required LineStudyEntry entry,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final previousEntry = _lineStudyEntries[readingUnitId];

    setState(() {
      if (entry.isEmpty) {
        _lineStudyEntries.remove(readingUnitId);
      } else {
        _lineStudyEntries[readingUnitId] = entry;
      }
    });
    _notifyLineStudyEntriesChanged();

    try {
      await _lineStudyStore.saveLineEntry(
        bookId: widget.bookId,
        chapterId: widget.chapterId,
        readingUnitId: readingUnitId,
        entry: entry,
      );
    } catch (error) {
      if (!uiActive) {
        return;
      }

      setState(() {
        if (previousEntry == null) {
          _lineStudyEntries.remove(readingUnitId);
        } else {
          _lineStudyEntries[readingUnitId] = previousEntry;
        }
      });
      _notifyLineStudyEntriesChanged();

      messenger?.showSnackBar(
        SnackBar(content: Text('Could not save line notes: $error')),
      );
    }
  }

  void _notifyLineStudyEntriesChanged() {
    widget.onLineStudyEntriesChanged?.call(
      Map<String, LineStudyEntry>.unmodifiable(_lineStudyEntries),
    );
  }

  Future<String> _requestTranslationFeedback({
    required ReadingUnit readingUnit,
    required String translation,
    String previousTranslation = '',
  }) async {
    final reply = await widget.client.sendGuidedReadingMessage(
      bookId: widget.bookId,
      chapterId: widget.chapterId,
      readingUnitId: readingUnit.id,
      messages: [
        GuidedConversationMessage(
          role: 'user',
          content: _buildTranslationFeedbackPrompt(
            translation: translation,
            previousTranslation: previousTranslation,
          ),
        ),
      ],
    );

    return reply.message.content.trim();
  }

  Future<String> _requestResponseFeedback({
    required ReadingUnit readingUnit,
    required String response,
    String learnerTranslation = '',
  }) async {
    final reply = await widget.client.sendGuidedReadingMessage(
      bookId: widget.bookId,
      chapterId: widget.chapterId,
      readingUnitId: readingUnit.id,
      messages: [
        GuidedConversationMessage(
          role: 'user',
          content: _buildResponseFeedbackPrompt(
            chineseLine: readingUnit.text,
            response: response,
            learnerTranslation: learnerTranslation,
          ),
        ),
      ],
    );

    return reply.message.content.trim();
  }

  void _addCharacterToExploder(String character) {
    final trimmedCharacter = character.trim();
    if (trimmedCharacter.isEmpty || !_containsChineseText(trimmedCharacter)) {
      return;
    }

    _exploderHistory.value = _exploderHistory.value.push(trimmedCharacter);
  }

  void _goBackInExploder() {
    _exploderHistory.value = _exploderHistory.value.goBack();
  }

  void _goForwardInExploder() {
    _exploderHistory.value = _exploderHistory.value.goForward();
  }

  void _ensureCharacterExplosionSheetOpen() {
    if (_isExplosionSheetOpen) {
      return;
    }

    _isExplosionSheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CharacterExplosionSheet(
        client: widget.client,
        historyListenable: _exploderHistory,
        characterIndexFuture: _characterIndexFuture,
        characterComponentsFuture: _characterComponentsFuture,
        onCharacterTap: _openCharacterExplosionSheet,
        onBack: _goBackInExploder,
        onForward: _goForwardInExploder,
      ),
    ).whenComplete(() {
      _isExplosionSheetOpen = false;
    });
  }

  void _openCharacterExplosionSheet(String character) {
    if (!_containsChineseText(character)) {
      return;
    }

    _addCharacterToExploder(character);
    _ensureCharacterExplosionSheetOpen();
  }

  Future<void> _openLineStudyEditor({
    required ReadingUnit readingUnit,
    required _LineStudyField field,
  }) async {
    var lineStudyEntry = _lineStudyEntryFor(readingUnit.id);
    final initialValue = switch (field) {
      _LineStudyField.translation => lineStudyEntry.translation,
      _LineStudyField.response => lineStudyEntry.response,
    };
    final title = switch (field) {
      _LineStudyField.translation => 'Translate',
      _LineStudyField.response => 'Respond',
    };
    final labelText = switch (field) {
      _LineStudyField.translation => 'Your translation',
      _LineStudyField.response => 'Your response',
    };
    final helperText = switch (field) {
      _LineStudyField.translation =>
        'Save your translation and get backend feedback in this sheet.',
      _LineStudyField.response =>
        'Save your response and get backend feedback in this sheet.',
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return _LineStudyEditorSheet(
          title: title,
          readingUnit: readingUnit,
          showInteractiveReadingUnit: true,
          showReadingUnitTranslation: false,
          learnerTranslation: switch (field) {
            _LineStudyField.translation => '',
            _LineStudyField.response => lineStudyEntry.translation,
          },
          onReadingUnitCharacterTap: _openCharacterExplosionSheet,
          initialValue: initialValue,
          initialFeedback: switch (field) {
            _LineStudyField.translation => '',
            _LineStudyField.response => '',
          },
          labelText: labelText,
          helperText: helperText,
          saveButtonLabel: 'Save',
          savingButtonLabel: 'Getting feedback...',
          onSave: (value) async {
            final trimmedValue = value.trim();
            switch (field) {
              case _LineStudyField.translation:
                final previousTranslation = lineStudyEntry.translation;
                final savedTranslationEntry = lineStudyEntry.copyWith(
                  translation: trimmedValue,
                  translationFeedback: '',
                );
                await _saveLineStudyEntry(
                  readingUnitId: readingUnit.id,
                  entry: savedTranslationEntry,
                );
                lineStudyEntry = savedTranslationEntry;
                if (trimmedValue.isEmpty) {
                  return '';
                }

                final feedback = await _requestTranslationFeedback(
                  readingUnit: readingUnit,
                  translation: trimmedValue,
                  previousTranslation: previousTranslation,
                );
                return feedback;
              case _LineStudyField.response:
                final savedResponseEntry = lineStudyEntry.copyWith(
                  response: trimmedValue,
                  responseFeedback: '',
                );
                await _saveLineStudyEntry(
                  readingUnitId: readingUnit.id,
                  entry: savedResponseEntry,
                );
                lineStudyEntry = savedResponseEntry;
                if (trimmedValue.isEmpty) {
                  return '';
                }

                final feedback = await _requestResponseFeedback(
                  readingUnit: readingUnit,
                  response: trimmedValue,
                  learnerTranslation: savedResponseEntry.translation,
                );
                return feedback;
            }
          },
          onClear: () async {
            final nextEntry = switch (field) {
              _LineStudyField.translation => LineStudyEntry(
                translation: '',
                translationFeedback: '',
                response: lineStudyEntry.response,
                responseFeedback: '',
              ),
              _LineStudyField.response => lineStudyEntry.copyWith(
                response: '',
                responseFeedback: '',
              ),
            };
            await _saveLineStudyEntry(
              readingUnitId: readingUnit.id,
              entry: nextEntry,
            );
            lineStudyEntry = nextEntry;
          },
        );
      },
    );
  }

  Future<void> _openGuidedChatThread(ChapterDetail chapter) async {
    if (chapter.readingUnits.isEmpty) {
      return;
    }

    final currentReadingUnit =
        chapter.readingUnits[_safeReadingUnitIndex(chapter)];
    final currentLineStudyEntry = _lineStudyEntryFor(currentReadingUnit.id);
    final previousLines = _guidedChatPreviousLines(chapter);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: _GuidedChatThreadSheet(
              client: widget.client,
              bookId: widget.bookId,
              chapterId: widget.chapterId,
              readingUnit: currentReadingUnit,
              learnerTranslation: currentLineStudyEntry.translation,
              learnerResponse: currentLineStudyEntry.response,
              previousLines: previousLines,
              initialMessages:
                  _threadsByReadingUnit[currentReadingUnit.id] ??
                  const <GuidedConversationMessage>[],
              initialDraft: _messageDrafts[currentReadingUnit.id] ?? '',
              onThreadChanged: (messages) {
                if (!uiActive) {
                  return;
                }

                setState(() {
                  if (messages.isEmpty) {
                    _threadsByReadingUnit.remove(currentReadingUnit.id);
                  } else {
                    _threadsByReadingUnit[currentReadingUnit.id] =
                        List<GuidedConversationMessage>.unmodifiable(messages);
                  }
                });
              },
              onDraftChanged: (value) {
                _storeDraft(_messageDrafts, currentReadingUnit.id, value);
              },
              onCharacterTap: _openCharacterExplosionSheet,
            ),
          ),
        );
      },
    );
  }

  Future<void> openGuidedChatThreadForCurrentChapter() async {
    try {
      final chapter = await _chapterFuture;
      if (!uiActive || chapter.readingUnits.isEmpty) {
        return;
      }

      await _openGuidedChatThread(chapter);
    } on Exception {
      return;
    }
  }

  Widget _buildReadingUnitPresentation({
    required BuildContext context,
    required ReadingUnit readingUnit,
    required int chapterLineCount,
    required CharacterIndex characterIndex,
    required LineStudyEntry lineStudyEntry,
    required VoidCallback onTranslatePressed,
    required VoidCallback onRespondPressed,
    required ValueChanged<String> onLineNumberSubmitted,
    required VoidCallback? onPreviousPressed,
    required Future<void> Function()? onNextPressed,
    required String topKeyPrefix,
    required String bottomKeyPrefix,
    bool showTopLineJump = true,
    bool topLineJumpShowsNavigationButtons = true,
    String? bottomLineJumpKeyPrefix,
    bool bottomLineJumpShowsNavigationButtons = true,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final simplifiedText = _simplifiedChineseText(
      readingUnit.text,
      characterIndex,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTopLineJump) ...[
          _LineNumberJumpField(
            currentLineNumber: readingUnit.order,
            totalLineCount: chapterLineCount,
            onSubmitted: onLineNumberSubmitted,
            onPreviousPressed: onPreviousPressed,
            onNextPressed: onNextPressed,
            showNavigationButtons: topLineJumpShowsNavigationButtons,
          ),
          const SizedBox(height: 12),
        ],
        _InteractiveChineseText(
          text: simplifiedText,
          keyPrefix: topKeyPrefix,
          onCharacterTap: _openCharacterExplosionSheet,
          style: _withLargerChineseFont(
            context,
            simplifiedText,
            textTheme.headlineSmall,
            fallbackFontSize: 24,
            sizeMultiplier: _readingUnitChineseLineSizeMultiplier,
          ),
        ),
        if (readingUnit.category.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Chip(
            key: ValueKey('reading-unit-category-chip-${readingUnit.order}'),
            label: Text(readingUnit.category.trim()),
            visualDensity: VisualDensity.compact,
          ),
        ],
        if (readingUnit.translationEn.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(readingUnit.translationEn, style: textTheme.bodyLarge),
        ],
        const SizedBox(height: 12),
        _TitleCharacterSupportTable(
          client: widget.client,
          title: simplifiedText,
          characterIndex: characterIndex,
          characterComponentsFuture: _characterComponentsFuture,
        ),
        if (readingUnit.translationEn.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(readingUnit.translationEn, style: textTheme.bodyLarge),
        ],
        const SizedBox(height: 12),
        _InteractiveChineseText(
          text: simplifiedText,
          keyPrefix: bottomKeyPrefix,
          onCharacterTap: _openCharacterExplosionSheet,
          style: _withLargerChineseFont(
            context,
            simplifiedText,
            textTheme.headlineSmall,
            fallbackFontSize: 24,
            sizeMultiplier: _readingUnitChineseLineSizeMultiplier,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: lineStudyEntry.hasTranslation
                  ? FilledButton.tonalIcon(
                      key: ValueKey(
                        'line-study-translation-button-${readingUnit.order}',
                      ),
                      onPressed: onTranslatePressed,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Translate'),
                    )
                  : OutlinedButton.icon(
                      key: ValueKey(
                        'line-study-translation-button-${readingUnit.order}',
                      ),
                      onPressed: onTranslatePressed,
                      icon: const Icon(Icons.translate_outlined),
                      label: const Text('Translate'),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: lineStudyEntry.hasResponse
                  ? FilledButton.tonalIcon(
                      key: ValueKey(
                        'line-study-response-button-${readingUnit.order}',
                      ),
                      onPressed: onRespondPressed,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Respond'),
                    )
                  : OutlinedButton.icon(
                      key: ValueKey(
                        'line-study-response-button-${readingUnit.order}',
                      ),
                      onPressed: onRespondPressed,
                      icon: const Icon(Icons.reply_outlined),
                      label: const Text('Respond'),
                    ),
            ),
          ],
        ),
        if (bottomLineJumpKeyPrefix != null) ...[
          const SizedBox(height: 16),
          _LineNumberJumpField(
            currentLineNumber: readingUnit.order,
            totalLineCount: chapterLineCount,
            onSubmitted: onLineNumberSubmitted,
            onPreviousPressed: onPreviousPressed,
            onNextPressed: onNextPressed,
            keyPrefix: bottomLineJumpKeyPrefix,
            showNavigationButtons: bottomLineJumpShowsNavigationButtons,
          ),
        ],
      ],
    );
  }

  Widget _buildReadingNavigationButtons({
    required VoidCallback? onPreviousPressed,
    required Future<void> Function()? onNextPressed,
    required String keyPrefix,
  }) {
    return Row(
      children: [
        OutlinedButton(
          key: ValueKey('$keyPrefix-reading-nav-prev-button'),
          onPressed: onPreviousPressed,
          child: const Text('Previous'),
        ),
        const Spacer(),
        FilledButton.tonal(
          key: ValueKey('$keyPrefix-reading-nav-next-button'),
          onPressed: onNextPressed == null ? null : () => onNextPressed(),
          child: const Text('Next'),
        ),
      ],
    );
  }

  Widget _buildEmbeddedChapterContent(
    BuildContext context,
    ChapterDetail chapter,
  ) {
    final characterIndex = widget.characterIndex ?? CharacterIndex.empty();
    final safeReadingUnitIndex = _safeReadingUnitIndex(chapter);
    final readingUnit = chapter.readingUnits[safeReadingUnitIndex];
    final lineStudyEntry = _lineStudyEntryFor(readingUnit.id);
    void onLineNumberSubmitted(String value) {
      _jumpToReadingUnitFromLineNumber(chapter, value);
    }

    final onNextPressed =
        _canAdvanceToNextReadingUnit(chapter) ||
            _canAdvanceBeyondChapter(chapter)
        ? () => _advanceToNextReadingUnit(chapter)
        : null;
    final onPreviousPressed = safeReadingUnitIndex == 0
        ? null
        : () => _selectReadingUnit(chapter, safeReadingUnitIndex - 1);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReadingUnitPresentation(
              context: context,
              readingUnit: readingUnit,
              chapterLineCount: chapter.readingUnits.length,
              characterIndex: characterIndex,
              lineStudyEntry: lineStudyEntry,
              onTranslatePressed: () => _openLineStudyEditor(
                readingUnit: readingUnit,
                field: _LineStudyField.translation,
              ),
              onRespondPressed: () => _openLineStudyEditor(
                readingUnit: readingUnit,
                field: _LineStudyField.response,
              ),
              onLineNumberSubmitted: onLineNumberSubmitted,
              onPreviousPressed: onPreviousPressed,
              onNextPressed: onNextPressed,
              topKeyPrefix:
                  'embedded-reading-line-${readingUnit.order}-top-character',
              bottomKeyPrefix:
                  'embedded-reading-line-${readingUnit.order}-bottom-character',
              bottomLineJumpKeyPrefix: null,
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 16),
            _LineNumberJumpField(
              currentLineNumber: readingUnit.order,
              totalLineCount: chapter.readingUnits.length,
              onSubmitted: onLineNumberSubmitted,
              onPreviousPressed: onPreviousPressed,
              onNextPressed: onNextPressed,
              keyPrefix: 'bottom',
              showSelectorBeforeNavigationButtons: true,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bookDisplayTitle = displayBookTitle(
      bookId: widget.bookId,
      title: widget.bookTitle,
    );
    final bookTitleTranslation = translatedBookTitle(
      bookId: widget.bookId,
      title: widget.bookTitle,
    );

    final chapterBody = Padding(
      padding: widget.embedded ? EdgeInsets.zero : const EdgeInsets.all(24),
      child: FutureBuilder<ChapterDetail>(
        future: _chapterFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _MessageCard(
              title: 'Could not load chapter',
              message: '${snapshot.error}',
              buttonLabel: 'Retry',
              onPressed: _reload,
            );
          }

          final chapter = snapshot.data;
          if (chapter == null) {
            return _MessageCard(
              title: 'Chapter missing',
              message: 'The backend returned an empty chapter response.',
              buttonLabel: 'Retry',
              onPressed: _reload,
            );
          }

          if (chapter.readingUnits.isEmpty) {
            return _MessageCard(
              title: 'No reading units',
              message: 'This chapter does not contain any readable units yet.',
              buttonLabel: 'Retry',
              onPressed: _reload,
            );
          }

          if (widget.embedded) {
            return _buildEmbeddedChapterContent(context, chapter);
          }

          final safeReadingUnitIndex = _safeReadingUnitIndex(chapter);
          final currentReadingUnit = chapter.readingUnits[safeReadingUnitIndex];
          final displayTitle = displayChapterTitle(
            bookId: widget.bookId,
            title: chapter.title,
            summary: chapter.summary,
          );

          final chapterTitleTranslation = translatedChapterTitle(
            bookId: widget.bookId,
            title: chapter.title,
          );

          return ListView(
            shrinkWrap: widget.embedded,
            physics: widget.embedded
                ? const NeverScrollableScrollPhysics()
                : null,
            children: [
              _StatusCard(
                title: _chapterDetailTitle(
                  order: chapter.order,
                  title: displayTitle,
                ),
                titleSubtitle: chapterTitleTranslation,
                child: FutureBuilder<CharacterIndex>(
                  future: _characterIndexFuture,
                  builder: (context, characterSnapshot) {
                    final characterIndex =
                        characterSnapshot.data ??
                        widget.characterIndex ??
                        CharacterIndex.empty();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TitleCharacterSupportTable(
                          client: widget.client,
                          title: displayTitle,
                          characterIndex: characterIndex,
                          characterComponentsFuture: _characterComponentsFuture,
                        ),
                        if (_containsChineseText(displayTitle))
                          const SizedBox(height: 12),
                        Text(
                          _chapterCountSummary(chapter),
                          style: _counterTextStyle(context),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              _StatusCard(
                title: _readingUnitPositionSummary(
                  lineNumber: safeReadingUnitIndex + 1,
                  totalLineCount: chapter.readingUnits.length,
                ),
                titleSubtitle:
                    '${currentReadingUnit.characterCount} characters in the active line',
                child: FutureBuilder<CharacterIndex>(
                  future: _characterIndexFuture,
                  builder: (context, characterSnapshot) {
                    final characterIndex =
                        characterSnapshot.data ??
                        widget.characterIndex ??
                        CharacterIndex.empty();
                    final lineStudyEntry = _lineStudyEntryFor(
                      currentReadingUnit.id,
                    );
                    final onPreviousPressed = safeReadingUnitIndex == 0
                        ? null
                        : () => _selectReadingUnit(
                            chapter,
                            safeReadingUnitIndex - 1,
                          );
                    final onNextPressed =
                        _canAdvanceToNextReadingUnit(chapter) ||
                            _canAdvanceBeyondChapter(chapter)
                        ? () => _advanceToNextReadingUnit(chapter)
                        : null;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildReadingNavigationButtons(
                          onPreviousPressed: onPreviousPressed,
                          onNextPressed: onNextPressed,
                          keyPrefix: 'top',
                        ),
                        const SizedBox(height: 16),
                        _LineNumberJumpField(
                          currentLineNumber: currentReadingUnit.order,
                          totalLineCount: chapter.readingUnits.length,
                          onSubmitted: (value) =>
                              _jumpToReadingUnitFromLineNumber(chapter, value),
                          onPreviousPressed: onPreviousPressed,
                          onNextPressed: onNextPressed,
                          showNavigationButtons: false,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (
                              var index = 0;
                              index < chapter.readingUnits.length;
                              index++
                            )
                              ChoiceChip(
                                label: Text(
                                  _readingUnitStatusLabel(
                                    order: chapter.readingUnits[index].order,
                                    lineStudyEntry: _lineStudyEntryFor(
                                      chapter.readingUnits[index].id,
                                    ),
                                  ),
                                ),
                                selected: index == safeReadingUnitIndex,
                                onSelected: (_) =>
                                    _selectReadingUnit(chapter, index),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildReadingUnitPresentation(
                          context: context,
                          readingUnit: currentReadingUnit,
                          chapterLineCount: chapter.readingUnits.length,
                          characterIndex: characterIndex,
                          lineStudyEntry: lineStudyEntry,
                          onTranslatePressed: () => _openLineStudyEditor(
                            readingUnit: currentReadingUnit,
                            field: _LineStudyField.translation,
                          ),
                          onRespondPressed: () => _openLineStudyEditor(
                            readingUnit: currentReadingUnit,
                            field: _LineStudyField.response,
                          ),
                          onLineNumberSubmitted: (value) =>
                              _jumpToReadingUnitFromLineNumber(chapter, value),
                          onPreviousPressed: onPreviousPressed,
                          onNextPressed: onNextPressed,
                          topKeyPrefix: 'current-reading-character',
                          bottomKeyPrefix: 'current-reading-repeat-character',
                          showTopLineJump: false,
                          bottomLineJumpKeyPrefix: 'bottom',
                          bottomLineJumpShowsNavigationButtons: false,
                        ),
                        const SizedBox(height: 20),
                        _buildReadingNavigationButtons(
                          onPreviousPressed: onPreviousPressed,
                          onNextPressed: onNextPressed,
                          keyPrefix: 'bottom',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );

    if (widget.embedded) {
      return chapterBody;
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: bookTitleTranslation == null ? kToolbarHeight : 72,
        title: _TranslatedTitle(
          primary: bookDisplayTitle,
          translation: bookTitleTranslation,
          primaryStyle: textTheme.titleLarge,
          translationStyle: _supportTableEnglishTextStyle(context),
          primaryMaxLines: 1,
          translationMaxLines: 1,
        ),
      ),
      body: chapterBody,
      floatingActionButton: FutureBuilder<ChapterDetail>(
        future: _chapterFuture,
        builder: (context, snapshot) {
          final chapter = snapshot.data;
          if (chapter == null || chapter.readingUnits.isEmpty) {
            return const SizedBox.shrink();
          }

          return FloatingActionButton.extended(
            key: const ValueKey('guided-chat-fab'),
            onPressed: () => _openGuidedChatThread(chapter),
            icon: const Icon(Icons.forum_outlined),
            label: const Text('Chat'),
          );
        },
      ),
    );
  }
}

class _LineNumberJumpField extends StatefulWidget {
  const _LineNumberJumpField({
    required this.currentLineNumber,
    required this.totalLineCount,
    required this.onSubmitted,
    this.onPreviousPressed,
    this.onNextPressed,
    this.keyPrefix = '',
    this.showNavigationButtons = true,
    this.showSelectorBeforeNavigationButtons = false,
  });

  final int currentLineNumber;
  final int totalLineCount;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onPreviousPressed;
  final Future<void> Function()? onNextPressed;
  final String keyPrefix;
  final bool showNavigationButtons;
  final bool showSelectorBeforeNavigationButtons;

  @override
  State<_LineNumberJumpField> createState() => _LineNumberJumpFieldState();
}

class _LineNumberJumpFieldState extends State<_LineNumberJumpField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.currentLineNumber.toString(),
    );
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _LineNumberJumpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLineNumber == widget.currentLineNumber &&
        oldWidget.totalLineCount == widget.totalLineCount) {
      return;
    }
    if (_focusNode.hasFocus) {
      return;
    }
    final nextText = widget.currentLineNumber.toString();
    if (_controller.text == nextText) {
      return;
    }
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSubmitted(_controller.text);
    _focusNode.unfocus();
  }

  ValueKey<String> _keyFor(String name) {
    if (widget.keyPrefix.isEmpty) {
      return ValueKey(name);
    }

    return ValueKey('${widget.keyPrefix}-$name');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final hasMultipleLines = widget.totalLineCount > 1;
    if (!widget.showNavigationButtons && !hasMultipleLines) {
      return const SizedBox.shrink();
    }

    final navigationButtons = widget.showNavigationButtons
        ? Row(
            children: [
              FilledButton.tonal(
                key: _keyFor('line-number-jump-prev-button'),
                onPressed: widget.onPreviousPressed,
                child: const Text('Prev'),
              ),
              const Spacer(),
              FilledButton.tonal(
                key: _keyFor('line-number-jump-next-button'),
                onPressed: widget.onNextPressed == null
                    ? null
                    : () {
                        widget.onNextPressed!.call();
                        _focusNode.unfocus();
                      },
                child: const Text('Next'),
              ),
            ],
          )
        : null;
    final selector = hasMultipleLines
        ? Row(
            children: [
              Text('Line', style: textTheme.labelLarge),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: TextField(
                  key: _keyFor('line-number-jump-field'),
                  controller: _controller,
                  focusNode: _focusNode,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'of',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${widget.totalLineCount}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                key: _keyFor('line-number-jump-go-button'),
                onPressed: _submit,
                child: const Text('Go'),
              ),
            ],
          )
        : null;

    final children = <Widget>[];
    if (widget.showSelectorBeforeNavigationButtons) {
      if (selector != null) {
        children.add(selector);
      }
      if (selector != null && navigationButtons != null) {
        children.add(const SizedBox(height: 8));
      }
      if (navigationButtons != null) {
        children.add(navigationButtons);
      }
    } else {
      if (navigationButtons != null) {
        children.add(navigationButtons);
      }
      if (navigationButtons != null && selector != null) {
        children.add(const SizedBox(height: 8));
      }
      if (selector != null) {
        children.add(selector);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ReferenceLookupField extends StatefulWidget {
  const _ReferenceLookupField({
    required this.label,
    required this.hintText,
    required this.onSubmitted,
    this.keyPrefix = '',
  });

  final String label;
  final String hintText;
  final ValueChanged<String> onSubmitted;
  final String keyPrefix;

  @override
  State<_ReferenceLookupField> createState() => _ReferenceLookupFieldState();
}

class _ReferenceLookupFieldState extends State<_ReferenceLookupField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    widget.onSubmitted(_controller.text);
    _focusNode.unfocus();
  }

  ValueKey<String> _keyFor(String name) {
    if (widget.keyPrefix.isEmpty) {
      return ValueKey(name);
    }

    return ValueKey('${widget.keyPrefix}-$name');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: _keyFor('reference-lookup-field'),
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hintText,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(
          key: _keyFor('reference-lookup-go-button'),
          onPressed: _submit,
          child: const Text('Go'),
        ),
      ],
    );
  }
}

class _LineStudyEditorSheet extends StatefulWidget {
  const _LineStudyEditorSheet({
    required this.title,
    required this.readingUnit,
    this.showInteractiveReadingUnit = false,
    this.showReadingUnitTranslation = true,
    this.learnerTranslation = '',
    required this.onReadingUnitCharacterTap,
    required this.initialValue,
    this.initialFeedback = '',
    required this.labelText,
    required this.helperText,
    this.saveButtonLabel = 'Save',
    this.savingButtonLabel = 'Saving...',
    required this.onSave,
    required this.onClear,
  });

  final String title;
  final ReadingUnit readingUnit;
  final bool showInteractiveReadingUnit;
  final bool showReadingUnitTranslation;
  final String learnerTranslation;
  final ValueChanged<String> onReadingUnitCharacterTap;
  final String initialValue;
  final String initialFeedback;
  final String labelText;
  final String helperText;
  final String saveButtonLabel;
  final String savingButtonLabel;
  final Future<String> Function(String value) onSave;
  final Future<void> Function() onClear;

  @override
  State<_LineStudyEditorSheet> createState() => _LineStudyEditorSheetState();
}

class _LineStudyEditorSheetState extends State<_LineStudyEditorSheet> {
  late final TextEditingController _controller;
  late String _feedback;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _feedback = widget.initialFeedback;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _feedback = '';
    });

    try {
      final feedback = await widget.onSave(_controller.text);
      if (!uiActive) {
        return;
      }

      setState(() {
        _feedback = feedback;
        _isSaving = false;
      });
    } catch (error) {
      if (!uiActive) {
        return;
      }

      setState(() {
        _isSaving = false;
        _errorMessage = 'Could not save: $error';
      });
    }
  }

  Future<void> _clear() async {
    if (_isSaving) {
      return;
    }

    final navigator = Navigator.of(context);
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.onClear();
      if (!uiActive) {
        return;
      }

      navigator.pop();
    } catch (error) {
      if (!uiActive) {
        return;
      }

      setState(() {
        _isSaving = false;
        _errorMessage = 'Could not clear: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final trimmedLearnerTranslation = widget.learnerTranslation.trim();

    return Material(
      key: const ValueKey('line-study-editor-sheet'),
      color: colorScheme.surface,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (widget.showInteractiveReadingUnit) ...[
                  Text(
                    'Line ${widget.readingUnit.order}',
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InteractiveChineseText(
                    text: widget.readingUnit.text,
                    keyPrefix: 'line-study-editor-reading-unit',
                    onCharacterTap: widget.onReadingUnitCharacterTap,
                    style: _withLargerChineseFont(
                      context,
                      widget.readingUnit.text,
                      textTheme.headlineSmall,
                      fallbackFontSize: 24,
                      sizeMultiplier: 2,
                    ),
                  ),
                ] else
                  Text(
                    'Line ${widget.readingUnit.order}: ${widget.readingUnit.text}',
                    style: textTheme.bodyLarge,
                  ),
                if (widget.showReadingUnitTranslation &&
                    widget.readingUnit.translationEn.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.readingUnit.translationEn,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_hasVisibleText(trimmedLearnerTranslation)) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Your translation',
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    trimmedLearnerTranslation,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('line-study-editor-field'),
                  controller: _controller,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: widget.labelText,
                    helperText: widget.helperText,
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_hasVisibleText(_errorMessage ?? '')) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    key: const ValueKey('line-study-editor-error'),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],
                if (_hasVisibleText(_feedback)) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Feedback',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  KeyedSubtree(
                    key: const ValueKey('line-study-editor-feedback'),
                    child: _containsChineseText(_feedback)
                        ? _InteractiveChineseInlineText(
                            text: _feedback,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onCharacterTap: widget.onReadingUnitCharacterTap,
                            keyPrefix: 'line-study-editor-feedback-character',
                          )
                        : Text(
                            _feedback,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton(
                      key: const ValueKey('line-study-editor-clear-button'),
                      onPressed: _isSaving ? null : _clear,
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('line-study-editor-save-button'),
                        onPressed: _isSaving ? null : _save,
                        child: Text(
                          _isSaving
                              ? widget.savingButtonLabel
                              : widget.saveButtonLabel,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuidedChatThreadSheet extends StatefulWidget {
  const _GuidedChatThreadSheet({
    required this.client,
    required this.bookId,
    required this.chapterId,
    required this.learnerTranslation,
    required this.learnerResponse,
    required this.previousLines,
    required this.initialMessages,
    required this.initialDraft,
    required this.onThreadChanged,
    required this.onDraftChanged,
    required this.onCharacterTap,
    this.readingUnit,
  });

  final BackendClient client;
  final String bookId;
  final String chapterId;
  final ReadingUnit? readingUnit;
  final String learnerTranslation;
  final String learnerResponse;
  final List<GuidedChatPreviousLine> previousLines;
  final List<GuidedConversationMessage> initialMessages;
  final String initialDraft;
  final ValueChanged<List<GuidedConversationMessage>> onThreadChanged;
  final ValueChanged<String> onDraftChanged;
  final ValueChanged<String> onCharacterTap;

  @override
  State<_GuidedChatThreadSheet> createState() => _GuidedChatThreadSheetState();
}

class _GuidedChatThreadSheetState extends State<_GuidedChatThreadSheet> {
  late final TextEditingController _composerController;
  late final ScrollController _scrollController;
  late List<GuidedConversationMessage> _messages;
  late bool _didScrollToFirstVisibleMessage;
  bool _isSending = false;
  String? _error;

  List<GuidedConversationMessage> get _visibleMessages =>
      _messages.where((message) => message.isVisible).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _composerController = TextEditingController(text: widget.initialDraft)
      ..addListener(_handleDraftChanged);
    _scrollController = ScrollController();
    _messages = List<GuidedConversationMessage>.from(widget.initialMessages);
    _didScrollToFirstVisibleMessage = _visibleMessages.any(
      (message) => !message.isUser,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeSendInitialAnalysis();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _composerController
      ..removeListener(_handleDraftChanged)
      ..dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    widget.onDraftChanged(_composerController.text);
  }

  String _loadingStatusText() {
    return 'The guide is responding...';
  }

  void _scrollToTopOnFirstVisibleMessage(
    List<GuidedConversationMessage> messages,
  ) {
    if (_didScrollToFirstVisibleMessage ||
        !messages.any((message) => message.isVisible && !message.isUser)) {
      return;
    }

    _didScrollToFirstVisibleMessage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!uiActive || !_scrollController.hasClients) {
        return;
      }

      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  bool get _shouldAutoSendInitialAnalysis {
    return widget.readingUnit != null;
  }

  String _buildInitialGuidedAnalysisPrompt() {
    final readingUnit = widget.readingUnit;
    if (readingUnit == null) {
      return 'Start the guided chat for the current line.';
    }

    final buffer = StringBuffer('Start the guided chat for the current line.')
      ..write('\n\nCurrent line:\n${readingUnit.text}');
    final category = readingUnit.category.trim();
    final translation = readingUnit.translationEn.trim();

    if (category.isNotEmpty) {
      buffer.write('\n\nCategory:\n$category');
    }

    if (translation.isNotEmpty) {
      buffer.write('\n\nCurrent gloss:\n$translation');
    }

    final learnerTranslation = widget.learnerTranslation.trim();
    if (learnerTranslation.isNotEmpty) {
      buffer.write('\n\nMy translation of this line:\n$learnerTranslation');
    }

    final learnerResponse = widget.learnerResponse.trim();
    if (learnerResponse.isNotEmpty) {
      buffer.write('\n\nMy response to this line:\n$learnerResponse');
    }

    buffer.write(
      '\n\nKeep the first reply brief, text-grounded, and focused on the current line.',
    );
    return buffer.toString();
  }

  Future<void> _maybeSendInitialAnalysis() async {
    if (!_shouldAutoSendInitialAnalysis || !uiActive || _messages.isNotEmpty) {
      return;
    }

    await _sendPrompt(
      prompt: _buildInitialGuidedAnalysisPrompt(),
      isVisible: false,
      clearComposerOnSuccess: false,
    );
  }

  Future<void> _send() async {
    if (_isSending) {
      return;
    }

    final userPrompt = _composerController.text.trim();
    if (userPrompt.isEmpty) {
      setState(() {
        _error = 'Write a message before sending.';
      });
      return;
    }

    await _sendPrompt(
      prompt: userPrompt,
      isVisible: true,
      clearComposerOnSuccess: true,
    );
  }

  Future<void> _sendPrompt({
    required String prompt,
    required bool isVisible,
    required bool clearComposerOnSuccess,
  }) async {
    if (_isSending) {
      return;
    }

    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      return;
    }

    final previousMessages = List<GuidedConversationMessage>.from(_messages);
    final requestMessages = [
      ...previousMessages,
      GuidedConversationMessage(
        role: 'user',
        content: trimmedPrompt,
        isVisible: isVisible,
      ),
    ];

    setState(() {
      _messages = requestMessages;
      _isSending = true;
      _error = null;
    });
    _scrollToTopOnFirstVisibleMessage(requestMessages);

    try {
      final reply = await widget.client.sendGuidedReadingMessage(
        bookId: widget.bookId,
        chapterId: widget.chapterId,
        readingUnitId: widget.readingUnit?.id,
        messages: requestMessages,
        learnerTranslation: widget.learnerTranslation,
        learnerResponse: widget.learnerResponse,
        previousLines: widget.previousLines,
      );
      final updatedMessages = [...requestMessages, reply.message];
      widget.onThreadChanged(updatedMessages);
      if (clearComposerOnSuccess) {
        widget.onDraftChanged('');
      }

      if (!uiActive) {
        return;
      }

      if (clearComposerOnSuccess) {
        _composerController.clear();
      }
      setState(() {
        _messages = updatedMessages;
        _isSending = false;
      });
      _scrollToTopOnFirstVisibleMessage(updatedMessages);
    } catch (error) {
      if (!uiActive) {
        return;
      }

      setState(() {
        _messages = previousMessages;
        _error = '$error';
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final visibleMessages = _visibleMessages;

    return Material(
      key: const ValueKey('guided-chat-sheet'),
      color: colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Chat',
                key: const ValueKey('guided-chat-sheet-title'),
                style: textTheme.headlineSmall,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: _scrollController,
              key: const ValueKey('guided-chat-sheet-scrollable'),
              reverse: true,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              children: [
                if (_isSending) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const LinearProgressIndicator(
                        key: ValueKey('guided-chat-loading-bar'),
                      ),
                      const SizedBox(height: 12),
                      Text(_loadingStatusText(), style: textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                for (
                  var index = visibleMessages.length - 1;
                  index >= 0;
                  index--
                ) ...[
                  _GuidedConversationBubble(
                    message: visibleMessages[index],
                    onCharacterTap: widget.onCharacterTap,
                    keyPrefix: 'guided-chat-message-$index',
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('guided-chat-sheet-message-field'),
                        controller: _composerController,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          labelText: 'Message the guide',
                          hintText: widget.readingUnit == null
                              ? 'Ask about this chapter or send a follow-up.'
                              : 'Ask about this line or send a follow-up.',
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      key: const ValueKey('guided-chat-send-button'),
                      onPressed: _isSending ? null : _send,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(56, 56),
                        padding: const EdgeInsets.all(16),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveChineseText extends StatelessWidget {
  const _InteractiveChineseText({
    required this.text,
    required this.style,
    required this.onCharacterTap,
    this.keyPrefix,
  });

  final String text;
  final TextStyle? style;
  final ValueChanged<String> onCharacterTap;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final runes = text.runes.toList(growable: false);
    return Wrap(
      children: [
        for (var index = 0; index < runes.length; index++)
          _buildCharacter(context, String.fromCharCode(runes[index]), index),
      ],
    );
  }

  Widget _buildCharacter(BuildContext context, String character, int index) {
    final child = Text(character, style: style);
    if (!_containsChineseText(character)) {
      return child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: colorScheme.primary,
    );

    return Semantics(
      link: true,
      child: GestureDetector(
        key: keyPrefix == null
            ? null
            : ValueKey('$keyPrefix-$character-$index'),
        onTap: () => onCharacterTap(character),
        child: Text(character, style: linkStyle),
      ),
    );
  }
}

class _InteractiveChineseInlineText extends StatelessWidget {
  const _InteractiveChineseInlineText({
    required this.text,
    required this.style,
    required this.onCharacterTap,
    this.keyPrefix,
  });

  final String text;
  final TextStyle? style;
  final ValueChanged<String> onCharacterTap;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final messageStyle = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: messageStyle,
        children: _buildSpans(context, messageStyle),
      ),
      softWrap: true,
    );
  }

  List<InlineSpan> _buildSpans(BuildContext context, TextStyle messageStyle) {
    final colorScheme = Theme.of(context).colorScheme;
    final chineseStyle = _supportTableChineseTextStyle(
      context,
      text,
    )?.copyWith(color: colorScheme.primary);
    final spans = <InlineSpan>[];
    final buffer = StringBuffer();
    var chineseCharacterIndex = 0;

    void flushBuffer() {
      if (buffer.isEmpty) {
        return;
      }

      spans.add(TextSpan(text: buffer.toString(), style: messageStyle));
      buffer.clear();
    }

    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      if (!_containsChineseText(character)) {
        buffer.write(character);
        continue;
      }

      flushBuffer();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            link: true,
            child: GestureDetector(
              key: keyPrefix == null
                  ? null
                  : ValueKey('$keyPrefix-$character-$chineseCharacterIndex'),
              onTap: () => onCharacterTap(character),
              child: Text(character, style: chineseStyle),
            ),
          ),
        ),
      );
      chineseCharacterIndex += 1;
    }

    flushBuffer();
    return spans;
  }
}

class _CharacterExplosionSheet extends StatefulWidget {
  const _CharacterExplosionSheet({
    required this.client,
    required this.historyListenable,
    required this.characterIndexFuture,
    required this.characterComponentsFuture,
    required this.onCharacterTap,
    required this.onBack,
    required this.onForward,
  });

  final BackendClient client;
  final ValueListenable<_CharacterExplosionHistory> historyListenable;
  final Future<CharacterIndex> characterIndexFuture;
  final Future<CharacterComponentsDataset> characterComponentsFuture;
  final ValueChanged<String> onCharacterTap;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  State<_CharacterExplosionSheet> createState() =>
      _CharacterExplosionSheetState();
}

class _CharacterExplosionSheetState extends State<_CharacterExplosionSheet> {
  final SharedPreferencesFlashcardStore _flashcardStore =
      SharedPreferencesFlashcardStore.instance;
  final ScrollController _scrollController = ScrollController();
  final Map<String, CharacterEntry> _reloadedEntriesByCharacter = {};
  String? _activeCharacter;
  bool _isReloadingExplosion = false;
  bool _isSavingFlashcard = false;

  @override
  void initState() {
    super.initState();
    _flashcardStore.addListener(_handleFlashcardsChanged);
    _flashcardStore.ensureLoaded();
  }

  @override
  void dispose() {
    _flashcardStore.removeListener(_handleFlashcardsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleFlashcardsChanged() {
    if (!uiActive) {
      return;
    }

    setState(() {});
  }

  Future<CharacterEntry?> _resolveCharacterEntry(String character) async {
    CharacterIndex characterIndex;
    try {
      characterIndex = await widget.characterIndexFuture;
    } catch (_) {
      characterIndex = CharacterIndex.empty();
    }

    final effectiveIndex = characterIndex.withEntries(
      _reloadedEntriesByCharacter.values,
    );
    return effectiveIndex.entryFor(character);
  }

  Future<void> _reloadCharacterExplosion(String character) async {
    if (_isReloadingExplosion) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _isReloadingExplosion = true;
    });

    try {
      final entry = await widget.client.generateCharacterExplosion(character);
      if (!uiActive) {
        return;
      }

      setState(() {
        _reloadedEntriesByCharacter[character.trim()] = entry;
      });
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Loaded a fresh GLM-generated explosion for ${entry.character.trim().isEmpty ? character.trim() : entry.character}.',
          ),
        ),
      );
    } catch (error) {
      if (!uiActive) {
        return;
      }

      messenger?.showSnackBar(
        SnackBar(content: Text('Could not get a fresh GLM explosion: $error')),
      );
    } finally {
      if (uiActive) {
        setState(() {
          _isReloadingExplosion = false;
        });
      }
    }
  }

  Future<void> _saveCurrentCharacterAsFlashcard(String character) async {
    if (_isSavingFlashcard) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isSavingFlashcard = true;
    });

    try {
      final entry = await _resolveCharacterEntry(character);
      if (entry == null) {
        if (!uiActive) {
          return;
        }

        messenger.showSnackBar(
          SnackBar(
            content: Text('No flashcard data is available for $character.'),
          ),
        );
        return;
      }

      final flashcard = FlashcardEntry.fromCharacterEntry(entry);
      final result = await _flashcardStore.saveEntry(flashcard);
      if (!uiActive) {
        return;
      }

      final displayCharacter = flashcard.displayCharacter;
      final message = switch (result) {
        FlashcardSaveResult.added => 'Saved $displayCharacter to flashcards.',
        FlashcardSaveResult.updated =>
          'Updated the flashcard for $displayCharacter.',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!uiActive) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not save a flashcard: $error')),
      );
    } finally {
      if (uiActive) {
        setState(() {
          _isSavingFlashcard = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: ValueListenableBuilder<_CharacterExplosionHistory>(
          valueListenable: widget.historyListenable,
          builder: (context, history, _) {
            if (history.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: _StatusCard(
                  title: 'Exploded view',
                  child: const Text(
                    'Tap a linked Hanzi to add it to the exploder.',
                  ),
                ),
              );
            }

            if (_activeCharacter != history.currentCharacter) {
              _activeCharacter = history.currentCharacter;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!uiActive || !_scrollController.hasClients) {
                  return;
                }

                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                );
              });
            }

            final hasSavedFlashcard = _flashcardStore.containsCharacter(
              history.currentCharacter,
            );
            final flashcardIconColor = hasSavedFlashcard
                ? Theme.of(context).colorScheme.primary
                : null;

            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Exploded view',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('exploder-reload-button'),
                      tooltip: _isReloadingExplosion
                          ? 'Asking GLM for a fresh explosion'
                          : 'Ask GLM for a fresh explosion',
                      onPressed: _isReloadingExplosion
                          ? null
                          : () => _reloadCharacterExplosion(
                              history.currentCharacter,
                            ),
                      icon: _isReloadingExplosion
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('exploder-save-flashcard-button'),
                      tooltip: hasSavedFlashcard
                          ? 'Saved to flashcards'
                          : 'Save as flashcard',
                      onPressed: _isSavingFlashcard
                          ? null
                          : () => _saveCurrentCharacterAsFlashcard(
                              history.currentCharacter,
                            ),
                      icon: _isSavingFlashcard
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              hasSavedFlashcard
                                  ? Icons.style
                                  : Icons.style_outlined,
                              color: flashcardIconColor,
                            ),
                    ),
                    IconButton(
                      key: const ValueKey('exploder-back-button'),
                      tooltip: 'Back',
                      onPressed: history.canGoBack ? widget.onBack : null,
                      icon: const Icon(Icons.arrow_back_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('exploder-forward-button'),
                      tooltip: 'Forward',
                      onPressed: history.canGoForward ? widget.onForward : null,
                      icon: const Icon(Icons.arrow_forward_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isReloadingExplosion)
                  _StatusCard(
                    key: const ValueKey('exploder-reload-loading-indicator'),
                    title: 'Asking GLM',
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Waiting for a fresh GLM-generated explosion...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _CharacterExplosionCard(
                    character: history.currentCharacter,
                    characterIndexFuture: widget.characterIndexFuture,
                    characterComponentsFuture: widget.characterComponentsFuture,
                    characterEntryOverrides: _reloadedEntriesByCharacter.values
                        .toList(growable: false),
                    onCharacterTap: widget.onCharacterTap,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExplosionReferenceList extends StatelessWidget {
  const _ExplosionReferenceList({
    required this.label,
    required this.items,
    required this.characterIndex,
    required this.onCharacterTap,
  });

  final String label;
  final List<String> items;
  final CharacterIndex characterIndex;
  final ValueChanged<String> onCharacterTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (var index = 0; index < items.length; index++)
            _ExplosionReferenceRow(
              item: _resolveExplosionReferenceItem(
                items[index],
                characterIndex,
              ),
              onCharacterTap: onCharacterTap,
              isLast: index == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _ExplosionReferenceRow extends StatelessWidget {
  const _ExplosionReferenceRow({
    required this.item,
    required this.onCharacterTap,
    required this.isLast,
  });

  final _ExplosionReferenceItemData item;
  final ValueChanged<String> onCharacterTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final textStyle = _withLargerChineseFont(
      context,
      item.text,
      textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      fallbackFontSize: 24,
      sizeMultiplier: _readingUnitChineseLineSizeMultiplier,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '•',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_containsChineseText(item.text))
                  _InteractiveChineseText(
                    text: item.text,
                    style: textStyle,
                    onCharacterTap: onCharacterTap,
                  )
                else
                  Text(item.text, style: textStyle),
                if (_hasVisibleText(item.reading))
                  Text(
                    item.reading,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (_hasVisibleText(item.english))
                  Text(
                    item.english,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterAnalysisTree extends StatelessWidget {
  const _CharacterAnalysisTree({
    required this.root,
    required this.onCharacterTap,
  });

  final _CharacterAnalysisTreeNode root;
  final ValueChanged<String> onCharacterTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _buildRows(root, depth: 0, isRoot: true, path: 'root'),
    );
  }

  List<Widget> _buildRows(
    _CharacterAnalysisTreeNode node, {
    required int depth,
    required bool isRoot,
    required String path,
  }) {
    final rows = <Widget>[
      _CharacterAnalysisTreeRow(
        key: ValueKey('analysis-tree-row-$path'),
        symbol: node.symbol,
        entry: node.entry,
        componentEntry: node.componentEntry,
        componentReferenceEntry: node.componentReferenceEntry,
        depth: depth,
        isRoot: isRoot,
        onCharacterTap: onCharacterTap,
      ),
    ];

    for (var index = 0; index < node.children.length; index++) {
      rows.addAll(
        _buildRows(
          node.children[index],
          depth: depth + 1,
          isRoot: false,
          path: path == 'root' ? '$index' : '$path-$index',
        ),
      );
    }

    return rows;
  }
}

class _CharacterAnalysisTreeRow extends StatelessWidget {
  const _CharacterAnalysisTreeRow({
    super.key,
    required this.symbol,
    required this.entry,
    required this.componentEntry,
    required this.componentReferenceEntry,
    required this.depth,
    required this.isRoot,
    required this.onCharacterTap,
  });

  final String symbol;
  final CharacterEntry? entry;
  final CharacterComponentEntry? componentEntry;
  final CharacterEntry? componentReferenceEntry;
  final int depth;
  final bool isRoot;
  final ValueChanged<String> onCharacterTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reading = _formatCharacterReading(entry ?? componentReferenceEntry);
    final componentLabel = entry == null
        ? _formatAnalysisComponentLabel(componentEntry)
        : '';
    final englishSource = entry ?? componentReferenceEntry;
    final english = englishSource == null
        ? ''
        : _joinVisibleValues(englishSource.english, separator: '; ');
    final examples = entry == null
        ? _formatAnalysisComponentExamples(componentEntry)
        : '';
    final bulletStyle = textTheme.bodyMedium?.copyWith(
      color: colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
    final symbolStyle = isRoot
        ? _withLargerChineseFont(
            context,
            symbol,
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            fallbackFontSize: 18,
            sizeMultiplier: _exploderRootCharacterSizeMultiplier,
          )
        : _withLargerChineseFont(
            context,
            symbol,
            textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            fallbackFontSize: 24,
            sizeMultiplier: _readingUnitChineseLineSizeMultiplier,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: depth * 16.0),
          SizedBox(width: 20, child: Text('•', style: bulletStyle)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_containsChineseText(symbol))
                  _InteractiveChineseText(
                    text: symbol,
                    style: symbolStyle,
                    onCharacterTap: onCharacterTap,
                  )
                else
                  Text(symbol, style: symbolStyle),
                if (_hasVisibleText(reading))
                  Text(
                    reading,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (_hasVisibleText(componentLabel))
                  Text(
                    componentLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (_hasVisibleText(english))
                  Text(
                    english,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (_hasVisibleText(examples))
                  Text(
                    examples,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CharacterExplosionCard extends StatelessWidget {
  const _CharacterExplosionCard({
    required this.character,
    required this.characterIndexFuture,
    required this.characterComponentsFuture,
    this.characterEntryOverrides = const [],
    required this.onCharacterTap,
  });

  final String character;
  final Future<CharacterIndex> characterIndexFuture;
  final Future<CharacterComponentsDataset> characterComponentsFuture;
  final List<CharacterEntry> characterEntryOverrides;
  final ValueChanged<String> onCharacterTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CharacterIndex>(
      future: characterIndexFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StatusCard(
            title: 'Loading character',
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError && characterEntryOverrides.isEmpty) {
          return _StatusCard(
            title: character,
            child: Text('${snapshot.error}'),
          );
        }

        final characterIndex = (snapshot.data ?? CharacterIndex.empty())
            .withEntries(characterEntryOverrides);
        return FutureBuilder<CharacterComponentsDataset>(
          future: characterComponentsFuture,
          builder: (context, componentsSnapshot) {
            final characterComponents =
                componentsSnapshot.data ?? CharacterComponentsDataset.empty();
            final entry = characterIndex.entryFor(character);
            if (entry == null) {
              return _StatusCard(
                title: character,
                child: Text(
                  'No exploded view is available for $character yet.',
                ),
              );
            }

            final heading = _formatCharacterHeading(entry, fallback: character);
            final reading = _formatCharacterReading(entry);
            final explosion = entry.explosion;
            final analysisTree = _buildCharacterAnalysisTree(
              symbol: character,
              characterIndex: characterIndex,
              characterComponents: characterComponents,
              analysis: explosion.analysis,
            );
            final hasVisibleContent =
                explosion.analysis.hasContent ||
                explosion.synthesis.hasContent ||
                explosion.meaningMap.hasContent;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasVisibleContent)
                  _StatusCard(
                    title: heading,
                    titleSubtitle: reading.isEmpty ? null : reading,
                    child: const Text(
                      'No analysis, synthesis, or meaning-map data is available for this character yet.',
                    ),
                  ),
                if (explosion.analysis.hasContent) ...[
                  _CharacterAnalysisTree(
                    root: analysisTree,
                    onCharacterTap: onCharacterTap,
                  ),
                  if (explosion.synthesis.hasContent ||
                      explosion.meaningMap.hasContent)
                    const SizedBox(height: 12),
                ],
                if (explosion.synthesis.hasContent)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (explosion.synthesis.containingCharacters.isNotEmpty)
                        _ExplosionReferenceList(
                          label: 'Containing characters',
                          items: explosion.synthesis.containingCharacters,
                          characterIndex: characterIndex,
                          onCharacterTap: onCharacterTap,
                        ),
                      if (explosion.synthesis.phraseUse.isNotEmpty)
                        _ExplosionReferenceList(
                          label: 'Phrase use',
                          items: explosion.synthesis.phraseUse,
                          characterIndex: characterIndex,
                          onCharacterTap: onCharacterTap,
                        ),
                      if (explosion.synthesis.homophones.sameTone.isNotEmpty)
                        _ExplosionReferenceList(
                          label: 'Homophones (same tone)',
                          items: explosion.synthesis.homophones.sameTone,
                          characterIndex: characterIndex,
                          onCharacterTap: onCharacterTap,
                        ),
                      if (explosion
                          .synthesis
                          .homophones
                          .differentTone
                          .isNotEmpty)
                        _ExplosionReferenceList(
                          label: 'Homophones (different tone)',
                          items: explosion.synthesis.homophones.differentTone,
                          characterIndex: characterIndex,
                          onCharacterTap: onCharacterTap,
                        ),
                    ],
                  ),
                if (explosion.meaningMap.hasContent) ...[
                  if (explosion.analysis.hasContent ||
                      explosion.synthesis.hasContent)
                    const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (explosion.meaningMap.synonyms.isNotEmpty)
                        _ExplosionReferenceList(
                          label: 'Synonyms',
                          items: explosion.meaningMap.synonyms,
                          characterIndex: characterIndex,
                          onCharacterTap: onCharacterTap,
                        ),
                      if (explosion.meaningMap.antonyms.isNotEmpty)
                        _ExplosionReferenceList(
                          label: 'Antonyms',
                          items: explosion.meaningMap.antonyms,
                          characterIndex: characterIndex,
                          onCharacterTap: onCharacterTap,
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _GuidedConversationBubble extends StatelessWidget {
  const _GuidedConversationBubble({
    required this.message,
    required this.onCharacterTap,
    this.keyPrefix,
  });

  final GuidedConversationMessage message;
  final ValueChanged<String> onCharacterTap;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bubbleColor = message.isUser
        ? colorScheme.primaryContainer
        : colorScheme.surfaceContainerHighest;
    final alignment = message.isUser
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.isUser) ...[
                  Text(
                    'You',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _containsChineseText(message.content)
                    ? _InteractiveChineseInlineText(
                        text: message.content,
                        style: DefaultTextStyle.of(context).style,
                        onCharacterTap: onCharacterTap,
                        keyPrefix: keyPrefix == null
                            ? null
                            : '$keyPrefix-character',
                      )
                    : SelectableText(message.content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadingMenuCard extends StatelessWidget {
  const _ReadingMenuCard({
    required this.client,
    required this.book,
    required this.characterIndex,
    required this.characterComponentsFuture,
    required this.menuIndex,
    required this.lineStudySummary,
    required this.onTap,
  });

  final BackendClient client;
  final BookDetail book;
  final CharacterIndex characterIndex;
  final Future<CharacterComponentsDataset> characterComponentsFuture;
  final int menuIndex;
  final String lineStudySummary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bookDisplayTitle = displayBookTitle(
      bookId: book.id,
      title: book.title,
    );
    final bookTitleTranslation = translatedBookTitle(
      bookId: book.id,
      title: book.title,
    );
    final bookCountSummary = _bookCountSummary(book);
    final showStartHereBadge = book.id == 'da-xue';
    final counterTextStyle = _counterTextStyle(context);

    return _LibraryMenuTile(
      title: _topLevelMenuTitle(index: menuIndex, title: bookDisplayTitle),
      subtitle: Text(
        bookTitleTranslation ?? '${book.chapterCount} readings • ${book.id}',
        style: _supportTableEnglishTextStyle(context),
      ),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleCharacterSupportTable(
            client: client,
            title: bookDisplayTitle,
            characterIndex: characterIndex,
            characterComponentsFuture: characterComponentsFuture,
          ),
          const SizedBox(height: 8),
          Text(bookCountSummary, style: counterTextStyle),
          const SizedBox(height: 4),
          Text(lineStudySummary, style: counterTextStyle),
        ],
      ),
      badgeLabel: showStartHereBadge ? 'Start here!' : null,
      onTap: onTap,
    );
  }
}

class _ChapterMenuCard extends StatelessWidget {
  static const EdgeInsets _contentPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 4,
  );
  static const EdgeInsets _detailsPadding = EdgeInsets.fromLTRB(16, 0, 16, 16);

  const _ChapterMenuCard({
    super.key,
    required this.client,
    required this.bookId,
    required this.chapter,
    required this.characterIndex,
    required this.characterComponentsFuture,
    required this.lineStudySummary,
    required this.isExpanded,
    required this.onTap,
    this.expandedChild,
  });

  final BackendClient client;
  final String bookId;
  final ChapterSummary chapter;
  final CharacterIndex characterIndex;
  final Future<CharacterComponentsDataset> characterComponentsFuture;
  final String lineStudySummary;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget? expandedChild;

  @override
  Widget build(BuildContext context) {
    final displayTitle = displayChapterTitle(
      bookId: bookId,
      title: chapter.title,
      summary: chapter.summary,
    );
    final chapterTitle = _chapterMenuTitle(
      order: chapter.order,
      title: displayTitle,
    );
    final chapterTitleTranslation = translatedChapterTitle(
      bookId: bookId,
      title: chapter.title,
    );
    final hasChineseTitle = _containsChineseText(displayTitle);
    final chapterCountSummary = _chapterSummaryCountSummary(chapter);
    final counterTextStyle = _counterTextStyle(context);
    final titleSupportTableKey = ValueKey(
      'chapter-title-support-table-$bookId-${chapter.id}',
    );

    final detailsChildren = <Widget>[
      if (hasChineseTitle && !isExpanded) ...[
        Column(
          key: titleSupportTableKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TitleCharacterSupportTable(
              client: client,
              title: displayTitle,
              characterIndex: characterIndex,
              characterComponentsFuture: characterComponentsFuture,
            ),
            const SizedBox(height: 8),
          ],
        ),
        Text(chapterCountSummary, style: counterTextStyle),
        const SizedBox(height: 4),
      ] else ...[
        Text(chapterCountSummary, style: counterTextStyle),
        const SizedBox(height: 4),
      ],
      Text(lineStudySummary, style: counterTextStyle),
    ];

    return _LibraryMenuTile(
      title: chapterTitle,
      subtitle: chapterTitleTranslation != null
          ? Text(chapterTitleTranslation)
          : null,
      contentPadding: _contentPadding,
      detailsPadding: _detailsPadding,
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: detailsChildren,
      ),
      trailing: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
      expandedChild: expandedChild,
      onTap: onTap,
    );
  }
}

class _LibraryMenuTile extends StatelessWidget {
  const _LibraryMenuTile({
    required this.title,
    this.subtitle,
    this.details,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 8,
    ),
    this.detailsPadding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
    this.badgeLabel,
    this.onTap,
    this.trailing,
    this.expandedChild,
  });

  final String title;
  final Widget? subtitle;
  final Widget? details;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry detailsPadding;
  final String? badgeLabel;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? expandedChild;

  @override
  Widget build(BuildContext context) {
    final detailsWidget = details;
    final expandedContent = expandedChild;
    const sizeAnimationDuration = Duration(milliseconds: 180);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            color: Color(0x14000000),
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: contentPadding,
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _withLargerChineseFont(
                context,
                title,
                Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                fallbackFontSize: 16,
                sizeMultiplier: 2,
              ),
            ),
            subtitle: subtitle,
            trailing:
                trailing ??
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badgeLabel != null) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          child: Text(
                            badgeLabel!,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Icon(Icons.chevron_right),
                  ],
                ),
            onTap: onTap,
          ),
          if (details != null || expandedChild != null)
            AnimatedSize(
              duration: sizeAnimationDuration,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: Padding(
                padding: detailsPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...?(detailsWidget == null
                        ? null
                        : <Widget>[detailsWidget]),
                    if (detailsWidget != null && expandedContent != null)
                      const SizedBox(height: 16),
                    ...?(expandedContent == null
                        ? null
                        : <Widget>[expandedContent]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TitleCharacterSupportTable extends StatelessWidget {
  const _TitleCharacterSupportTable({
    required this.client,
    required this.title,
    required this.characterIndex,
    this.characterComponentsFuture,
  });

  final BackendClient client;
  final String title;
  final CharacterIndex characterIndex;
  final Future<CharacterComponentsDataset>? characterComponentsFuture;

  List<_TitleCharacterSupportRow> _buildRows() {
    final visibleCharacters = _visibleCharacters(title).toList();
    return [
      for (var index = 0; index < visibleCharacters.length; index++)
        _buildRow(index: index + 1, character: visibleCharacters[index]),
    ];
  }

  _TitleCharacterSupportRow _buildRow({
    required int index,
    required String character,
  }) {
    final entry = characterIndex.entryFor(character);
    return _TitleCharacterSupportRow(
      index: index,
      chinese: _formatChinese(entry, character),
      reading: _formatReading(entry),
      englishDefinition: _formatEnglishDefinition(entry, character),
    );
  }

  String _formatChinese(CharacterEntry? entry, String fallbackCharacter) {
    if (entry == null) {
      return fallbackCharacter;
    }

    final simplified = entry.simplified.trim();
    final traditional = entry.traditional.trim();
    final primary = simplified.isEmpty ? fallbackCharacter : simplified;

    if (traditional.isEmpty || traditional == primary) {
      return primary;
    }

    return '$primary ($traditional)';
  }

  String _formatReading(CharacterEntry? entry) {
    if (entry == null) {
      return '';
    }

    final pinyin = entry.pinyin.join('; ');
    final zhuyin = entry.zhuyin.join('; ');
    if (_hasVisibleText(pinyin) && _hasVisibleText(zhuyin)) {
      return '$pinyin ($zhuyin)';
    }

    return _hasVisibleText(pinyin) ? pinyin : zhuyin;
  }

  String _formatEnglishDefinition(CharacterEntry? entry, String character) {
    if (entry != null && entry.english.isNotEmpty) {
      return entry.english.join('; ');
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (!_containsChineseText(title)) {
      return const SizedBox.shrink();
    }

    final rows = _buildRows();
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final textTheme = Theme.of(context).textTheme;
    final supportTableMetadataStyle = textTheme.bodySmall;
    final supportTableEnglishStyle = _supportTableEnglishTextStyle(context);

    void openCharacterExplosionSheet(String character) {
      if (!_containsChineseText(character)) {
        return;
      }

      final exploderHistory = ValueNotifier<_CharacterExplosionHistory>(
        const _CharacterExplosionHistory(),
      );
      exploderHistory.value = exploderHistory.value.push(character);

      void addCharacterToExploder(String nextCharacter) {
        final trimmedCharacter = nextCharacter.trim();
        if (trimmedCharacter.isEmpty ||
            !_containsChineseText(trimmedCharacter)) {
          return;
        }

        exploderHistory.value = exploderHistory.value.push(trimmedCharacter);
      }

      void goBackInExploder() {
        exploderHistory.value = exploderHistory.value.goBack();
      }

      void goForwardInExploder() {
        exploderHistory.value = exploderHistory.value.goForward();
      }

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _CharacterExplosionSheet(
          client: client,
          historyListenable: exploderHistory,
          characterIndexFuture: Future.value(characterIndex),
          characterComponentsFuture:
              characterComponentsFuture ??
              Future.value(CharacterComponentsDataset.empty()),
          onCharacterTap: addCharacterToExploder,
          onBack: goBackInExploder,
          onForward: goForwardInExploder,
        ),
      ).whenComplete(exploderHistory.dispose);
    }

    Widget buildIndexCell(int index) {
      final value = index.toString();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          value,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: _withLargerChineseFont(
            context,
            value,
            supportTableEnglishStyle,
            fallbackFontSize: 16,
          ),
        ),
      );
    }

    Widget buildCell(String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          value,
          softWrap: true,
          style: _withLargerChineseFont(
            context,
            value,
            supportTableEnglishStyle,
            fallbackFontSize: 16,
          ),
        ),
      );
    }

    Widget buildCharacterCell(_TitleCharacterSupportRow row) {
      final chineseStyle = _supportTableChineseTextStyle(context, row.chinese);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InteractiveChineseText(
              text: row.chinese,
              style: chineseStyle,
              onCharacterTap: openCharacterExplosionSheet,
              keyPrefix: 'title-support-$title-${row.index}',
            ),
            if (_hasVisibleText(row.reading)) ...[
              const SizedBox(height: 2),
              Text(
                row.reading,
                softWrap: true,
                style: supportTableMetadataStyle,
              ),
            ],
          ],
        ),
      );
    }

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      columnWidths: const {
        0: FixedColumnWidth(40),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1.35),
      },
      children: [
        for (final row in rows)
          TableRow(
            children: [
              buildIndexCell(row.index),
              buildCharacterCell(row),
              buildCell(row.englishDefinition),
            ],
          ),
      ],
    );
  }
}

class _TitleCharacterSupportRow {
  const _TitleCharacterSupportRow({
    required this.index,
    required this.chinese,
    required this.reading,
    required this.englishDefinition,
  });

  final int index;
  final String chinese;
  final String reading;
  final String englishDefinition;
}

class _IntroFeatureRow extends StatelessWidget {
  const _IntroFeatureRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(description),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    super.key,
    required this.title,
    this.titleSubtitle,
    this.contentPadding = const EdgeInsets.all(20),
    required this.child,
  });

  final String title;
  final String? titleSubtitle;
  final EdgeInsetsGeometry contentPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final trimmedTitle = title.trim();
    final trimmedTitleSubtitle = titleSubtitle?.trim();
    final hasTitle = trimmedTitle.isNotEmpty;
    final hasTitleSubtitle =
        trimmedTitleSubtitle != null && trimmedTitleSubtitle.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            color: Color(0x14000000),
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasTitle)
              Text(
                trimmedTitle,
                style: _withLargerChineseFont(
                  context,
                  trimmedTitle,
                  Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  fallbackFontSize: 14,
                  sizeMultiplier: 2,
                ),
              ),
            if (hasTitleSubtitle) ...[
              if (hasTitle) const SizedBox(height: 4),
              Text(
                trimmedTitleSubtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (hasTitle || hasTitleSubtitle) const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _TranslatedTitle extends StatelessWidget {
  const _TranslatedTitle({
    required this.primary,
    this.translation,
    this.primaryStyle,
    this.translationStyle,
    this.primaryMaxLines = 2,
    this.translationMaxLines = 2,
  });

  final String primary;
  final String? translation;
  final TextStyle? primaryStyle;
  final TextStyle? translationStyle;
  final int primaryMaxLines;
  final int translationMaxLines;

  @override
  Widget build(BuildContext context) {
    final trimmedTranslation = translation?.trim();
    final showTranslation =
        trimmedTranslation != null &&
        trimmedTranslation.isNotEmpty &&
        trimmedTranslation != primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primary,
          maxLines: primaryMaxLines,
          overflow: TextOverflow.ellipsis,
          style: _withLargerChineseFont(
            context,
            primary,
            primaryStyle,
            fallbackFontSize: 16,
            sizeMultiplier: 2,
          ),
        ),
        if (showTranslation) ...[
          const SizedBox(height: 2),
          Text(
            trimmedTranslation,
            maxLines: translationMaxLines,
            overflow: TextOverflow.ellipsis,
            style: translationStyle ?? Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _StatusCard(
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}
