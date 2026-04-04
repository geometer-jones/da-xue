import 'dart:convert';
import 'dart:math' as math;

import 'package:daxue_mobile/src/backend_client.dart';
import 'package:daxue_mobile/src/local_storage.dart';
import 'package:flutter/foundation.dart';

bool _hasVisibleFlashcardText(String value) => value.trim().isNotEmpty;

List<String> _visibleFlashcardValues(List<String> values) {
  return values
      .map((value) => value.trim())
      .where(_hasVisibleFlashcardText)
      .toList();
}

List<String> _mergeFlashcardValues(List<String> left, List<String> right) {
  final merged = <String>[];
  for (final value in [...left, ...right]) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || merged.contains(trimmed)) {
      continue;
    }
    merged.add(trimmed);
  }
  return List<String>.unmodifiable(merged);
}

String _flashcardEntryIdForCharacter({
  required String fallbackCharacter,
  String simplified = '',
  String traditional = '',
}) {
  final trimmedFallbackCharacter = fallbackCharacter.trim();
  final trimmedTraditional = traditional.trim().isEmpty
      ? trimmedFallbackCharacter
      : traditional.trim();
  final trimmedSimplified = simplified.trim().isEmpty
      ? trimmedTraditional
      : simplified.trim();

  return 'character:${trimmedSimplified.isEmpty ? trimmedTraditional : trimmedSimplified}';
}

class FlashcardEntry {
  const FlashcardEntry({
    required this.id,
    required this.traditional,
    required this.simplified,
    required this.zhuyin,
    required this.pinyin,
    required this.glossEn,
    required this.translationEn,
    required this.originKind,
    this.sourceWork = '',
    this.sourceLineIds = const [],
    this.sourceSegmentIds = const [],
    this.eligiblePromptLayers = const [
      'traditional',
      'simplified',
      'zhuyin',
      'pinyin',
      'gloss_en',
      'translation_en',
    ],
    this.status = 'active',
    this.weight = 1,
    required this.savedAtEpochMilliseconds,
  });

  factory FlashcardEntry.fromCharacterEntry(
    CharacterEntry entry, {
    String originKind = 'exploder-character',
    String sourceWork = '',
    List<String> sourceLineIds = const [],
    List<String> sourceSegmentIds = const [],
  }) {
    final traditional = entry.traditional.trim().isEmpty
        ? entry.character.trim()
        : entry.traditional.trim();
    final simplified = entry.simplified.trim().isEmpty
        ? traditional
        : entry.simplified.trim();
    final glossEn = _visibleFlashcardValues(entry.english);

    return FlashcardEntry(
      id: _flashcardEntryIdForCharacter(
        fallbackCharacter: entry.character,
        simplified: simplified,
        traditional: traditional,
      ),
      traditional: traditional,
      simplified: simplified,
      zhuyin: _visibleFlashcardValues(entry.zhuyin),
      pinyin: _visibleFlashcardValues(entry.pinyin),
      glossEn: glossEn,
      translationEn: glossEn.join('; '),
      originKind: originKind,
      sourceWork: sourceWork.trim(),
      sourceLineIds: _visibleFlashcardValues(sourceLineIds),
      sourceSegmentIds: _visibleFlashcardValues(sourceSegmentIds),
      savedAtEpochMilliseconds: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory FlashcardEntry.fromJson(Map<String, dynamic> json) {
    return FlashcardEntry(
      id: json['id'] as String? ?? '',
      traditional: json['traditional'] as String? ?? '',
      simplified: json['simplified'] as String? ?? '',
      zhuyin: _visibleFlashcardValues(_toStringList(json['zhuyin'])),
      pinyin: _visibleFlashcardValues(_toStringList(json['pinyin'])),
      glossEn: _visibleFlashcardValues(_toStringList(json['glossEn'])),
      translationEn: json['translationEn'] as String? ?? '',
      originKind: json['originKind'] as String? ?? '',
      sourceWork: json['sourceWork'] as String? ?? '',
      sourceLineIds: _visibleFlashcardValues(
        _toStringList(json['sourceLineIds']),
      ),
      sourceSegmentIds: _visibleFlashcardValues(
        _toStringList(json['sourceSegmentIds']),
      ),
      eligiblePromptLayers: _visibleFlashcardValues(
        _toStringList(json['eligiblePromptLayers']),
      ),
      status: json['status'] as String? ?? 'active',
      weight: _normalizedFlashcardWeight(json['weight'] as int?),
      savedAtEpochMilliseconds:
          json['savedAtEpochMilliseconds'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  final String id;
  final String traditional;
  final String simplified;
  final List<String> zhuyin;
  final List<String> pinyin;
  final List<String> glossEn;
  final String translationEn;
  final String originKind;
  final String sourceWork;
  final List<String> sourceLineIds;
  final List<String> sourceSegmentIds;
  final List<String> eligiblePromptLayers;
  final String status;
  final int weight;
  final int savedAtEpochMilliseconds;

  String get displayCharacter =>
      simplified.trim().isNotEmpty ? simplified.trim() : traditional.trim();

  String get displayHeading {
    final primary = displayCharacter;
    final traditionalValue = traditional.trim();
    if (traditionalValue.isEmpty || traditionalValue == primary) {
      return primary;
    }

    return '$primary ($traditionalValue)';
  }

  String get readingLabel {
    if (pinyin.isEmpty && zhuyin.isEmpty) {
      return '';
    }
    if (pinyin.isNotEmpty && zhuyin.isNotEmpty) {
      return '${pinyin.join(' ')} (${zhuyin.join(' ')})';
    }

    return pinyin.isNotEmpty ? pinyin.join(' ') : zhuyin.join(' ');
  }

  String get glossLabel => glossEn.join('; ');

  FlashcardEntry copyWith({int? weight}) {
    return FlashcardEntry(
      id: id,
      traditional: traditional,
      simplified: simplified,
      zhuyin: zhuyin,
      pinyin: pinyin,
      glossEn: glossEn,
      translationEn: translationEn,
      originKind: originKind,
      sourceWork: sourceWork,
      sourceLineIds: sourceLineIds,
      sourceSegmentIds: sourceSegmentIds,
      eligiblePromptLayers: eligiblePromptLayers,
      status: status,
      weight: _normalizedFlashcardWeight(weight ?? this.weight),
      savedAtEpochMilliseconds: savedAtEpochMilliseconds,
    );
  }

  FlashcardEntry mergeWith(FlashcardEntry other) {
    return FlashcardEntry(
      id: id,
      traditional: other.traditional.trim().isNotEmpty
          ? other.traditional.trim()
          : traditional,
      simplified: other.simplified.trim().isNotEmpty
          ? other.simplified.trim()
          : simplified,
      zhuyin: other.zhuyin.isNotEmpty ? other.zhuyin : zhuyin,
      pinyin: other.pinyin.isNotEmpty ? other.pinyin : pinyin,
      glossEn: other.glossEn.isNotEmpty ? other.glossEn : glossEn,
      translationEn: other.translationEn.trim().isNotEmpty
          ? other.translationEn.trim()
          : translationEn,
      originKind: other.originKind.trim().isNotEmpty
          ? other.originKind.trim()
          : originKind,
      sourceWork: other.sourceWork.trim().isNotEmpty
          ? other.sourceWork.trim()
          : sourceWork,
      sourceLineIds: _mergeFlashcardValues(sourceLineIds, other.sourceLineIds),
      sourceSegmentIds: _mergeFlashcardValues(
        sourceSegmentIds,
        other.sourceSegmentIds,
      ),
      eligiblePromptLayers: _mergeFlashcardValues(
        eligiblePromptLayers,
        other.eligiblePromptLayers,
      ),
      status: other.status.trim().isNotEmpty ? other.status.trim() : status,
      weight: weight,
      savedAtEpochMilliseconds: other.savedAtEpochMilliseconds,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'traditional': traditional,
      'simplified': simplified,
      'zhuyin': zhuyin,
      'pinyin': pinyin,
      'glossEn': glossEn,
      'translationEn': translationEn,
      'originKind': originKind,
      'sourceWork': sourceWork,
      'sourceLineIds': sourceLineIds,
      'sourceSegmentIds': sourceSegmentIds,
      'eligiblePromptLayers': eligiblePromptLayers,
      'status': status,
      'weight': weight,
      'savedAtEpochMilliseconds': savedAtEpochMilliseconds,
    };
  }
}

FlashcardEntry? sampleWeightedFlashcardEntry(
  List<FlashcardEntry> entries, {
  math.Random? random,
}) {
  if (entries.isEmpty) {
    return null;
  }

  final generator = random ?? math.Random();
  final totalWeight = entries.fold<int>(
    0,
    (total, entry) => total + _normalizedFlashcardWeight(entry.weight),
  );
  var target = generator.nextInt(totalWeight);
  for (final entry in entries) {
    target -= _normalizedFlashcardWeight(entry.weight);
    if (target < 0) {
      return entry;
    }
  }

  return entries.last;
}

List<FlashcardEntry> sampleWeightedFlashcardEntries(
  List<FlashcardEntry> entries, {
  math.Random? random,
}) {
  if (entries.isEmpty) {
    return const <FlashcardEntry>[];
  }

  final generator = random ?? math.Random();
  final remainingEntries = List<FlashcardEntry>.of(entries);
  final orderedEntries = <FlashcardEntry>[];
  while (remainingEntries.isNotEmpty) {
    final nextEntry = sampleWeightedFlashcardEntry(
      remainingEntries,
      random: generator,
    );
    if (nextEntry == null) {
      break;
    }

    orderedEntries.add(nextEntry);
    remainingEntries.remove(nextEntry);
  }

  return List<FlashcardEntry>.unmodifiable(orderedEntries);
}

enum FlashcardSaveResult { added, updated }

class SharedPreferencesFlashcardStore extends ChangeNotifier {
  SharedPreferencesFlashcardStore._();

  static final SharedPreferencesFlashcardStore instance =
      SharedPreferencesFlashcardStore._();
  static const String _storageKey = 'daxue.flashcards.bank';

  List<FlashcardEntry> _entries = const [];
  Future<void>? _loadFuture;

  List<FlashcardEntry> get entries =>
      List<FlashcardEntry>.unmodifiable(_entries);

  bool containsCharacter(String character) {
    final needle = character.trim();
    if (needle.isEmpty) {
      return false;
    }

    final id = _flashcardEntryIdForCharacter(fallbackCharacter: needle);
    return _entries.any(
      (entry) =>
          entry.id == id ||
          entry.displayCharacter == needle ||
          entry.simplified.trim() == needle ||
          entry.traditional.trim() == needle,
    );
  }

  Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<FlashcardSaveResult> saveEntry(FlashcardEntry entry) async {
    await ensureLoaded();

    final existingIndex = _entries.indexWhere(
      (existing) => existing.id == entry.id,
    );
    if (existingIndex == -1) {
      _entries = [entry, ..._entries];
      await _persist();
      notifyListeners();
      return FlashcardSaveResult.added;
    }

    final mergedEntry = _entries[existingIndex].mergeWith(entry);
    _entries = [
      mergedEntry,
      for (var index = 0; index < _entries.length; index++)
        if (index != existingIndex) _entries[index],
    ];
    await _persist();
    notifyListeners();
    return FlashcardSaveResult.updated;
  }

  Future<void> updateEntryWeight({
    required String entryId,
    required int weight,
  }) async {
    await ensureLoaded();

    final existingIndex = _entries.indexWhere((entry) => entry.id == entryId);
    if (existingIndex == -1) {
      return;
    }

    final nextWeight = _normalizedFlashcardWeight(weight);
    final existingEntry = _entries[existingIndex];
    if (existingEntry.weight == nextWeight) {
      return;
    }

    _entries = [
      for (var index = 0; index < _entries.length; index++)
        if (index == existingIndex)
          existingEntry.copyWith(weight: nextWeight)
        else
          _entries[index],
    ];
    await _persist();
    notifyListeners();
  }

  Future<void> removeEntry(String entryId) async {
    await ensureLoaded();

    final nextEntries = [
      for (final entry in _entries)
        if (entry.id != entryId) entry,
    ];
    if (nextEntries.length == _entries.length) {
      return;
    }

    _entries = nextEntries;
    await _persist();
    notifyListeners();
  }

  Future<void> _load() async {
    _entries = _decodeEntries(await loadStoredString(_storageKey));
    notifyListeners();
  }

  Future<void> _persist() async {
    final payload = jsonEncode([for (final entry in _entries) entry.toJson()]);
    await saveStoredString(_storageKey, payload);
  }

  List<FlashcardEntry> _decodeEntries(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const <FlashcardEntry>[];
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! List) {
        return const <FlashcardEntry>[];
      }

      return decoded
          .whereType<Map>()
          .map(
            (entry) =>
                FlashcardEntry.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList();
    } on FormatException {
      return const <FlashcardEntry>[];
    }
  }

  @visibleForTesting
  void debugReset() {
    _entries = const [];
    _loadFuture = null;
    notifyListeners();
  }
}

List<String> _toStringList(Object? value) {
  final items = value as List<dynamic>? ?? const [];
  return items.map((item) => item.toString()).toList();
}

int _normalizedFlashcardWeight(int? value) {
  final nextValue = value ?? 1;
  return nextValue < 1 ? 1 : nextValue;
}
