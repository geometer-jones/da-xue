import 'dart:convert';

import 'package:daxue_mobile/src/local_storage.dart';

bool _hasVisibleLineStudyText(String value) => value.trim().isNotEmpty;

class LineStudyEntry {
  const LineStudyEntry({
    this.translation = '',
    this.translationFeedback = '',
    this.response = '',
    this.responseFeedback = '',
  });

  final String translation;
  final String translationFeedback;
  final String response;
  final String responseFeedback;

  bool get hasTranslation => _hasVisibleLineStudyText(translation);
  bool get hasTranslationFeedback =>
      _hasVisibleLineStudyText(translationFeedback);
  bool get hasResponse => _hasVisibleLineStudyText(response);
  bool get hasResponseFeedback => _hasVisibleLineStudyText(responseFeedback);
  bool get hasAnyFeedback => hasTranslationFeedback || hasResponseFeedback;
  bool get isEmpty => !hasTranslation && !hasResponse;

  LineStudyEntry copyWith({
    String? translation,
    String? translationFeedback,
    String? response,
    String? responseFeedback,
  }) {
    return LineStudyEntry(
      translation: translation ?? this.translation,
      translationFeedback: translationFeedback ?? this.translationFeedback,
      response: response ?? this.response,
      responseFeedback: responseFeedback ?? this.responseFeedback,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'translation': translation,
      'response': response,
    };
  }

  factory LineStudyEntry.fromJson(Map<String, dynamic> json) {
    return LineStudyEntry(
      translation: json['translation'] as String? ?? '',
      translationFeedback: '',
      response: json['response'] as String? ?? '',
      responseFeedback: '',
    );
  }
}

abstract class LineStudyStore {
  Future<Map<String, LineStudyEntry>> loadChapterEntries({
    required String bookId,
    required String chapterId,
  });

  Future<void> saveLineEntry({
    required String bookId,
    required String chapterId,
    required String readingUnitId,
    required LineStudyEntry entry,
  });
}

class SharedPreferencesLineStudyStore implements LineStudyStore {
  SharedPreferencesLineStudyStore._();

  static final SharedPreferencesLineStudyStore instance =
      SharedPreferencesLineStudyStore._();

  @override
  Future<Map<String, LineStudyEntry>> loadChapterEntries({
    required String bookId,
    required String chapterId,
  }) async {
    return _decodeChapterEntries(
      await loadStoredString(_chapterKey(bookId: bookId, chapterId: chapterId)),
    );
  }

  @override
  Future<void> saveLineEntry({
    required String bookId,
    required String chapterId,
    required String readingUnitId,
    required LineStudyEntry entry,
  }) async {
    final chapterKey = _chapterKey(bookId: bookId, chapterId: chapterId);
    final chapterEntries = _decodeChapterEntries(
      await loadStoredString(chapterKey),
    );

    if (entry.isEmpty) {
      chapterEntries.remove(readingUnitId);
    } else {
      chapterEntries[readingUnitId] = entry;
    }

    if (chapterEntries.isEmpty) {
      await removeStoredString(chapterKey);
      return;
    }

    final payload = <String, dynamic>{
      for (final entry in chapterEntries.entries)
        entry.key: entry.value.toJson(),
    };
    await saveStoredString(chapterKey, jsonEncode(payload));
  }

  String _chapterKey({required String bookId, required String chapterId}) {
    return 'daxue.lineStudy.$bookId.$chapterId';
  }

  Map<String, LineStudyEntry> _decodeChapterEntries(String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) {
      return <String, LineStudyEntry>{};
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) {
        return <String, LineStudyEntry>{};
      }

      final chapterEntries = <String, LineStudyEntry>{};
      for (final entry in decoded.entries) {
        final readingUnitId = '${entry.key}'.trim();
        final value = entry.value;
        if (readingUnitId.isEmpty || value is! Map) {
          continue;
        }

        chapterEntries[readingUnitId] = LineStudyEntry.fromJson(
          Map<String, dynamic>.from(value),
        );
      }

      return chapterEntries;
    } on FormatException {
      return <String, LineStudyEntry>{};
    }
  }
}

class MemoryLineStudyStore implements LineStudyStore {
  final Map<String, Map<String, LineStudyEntry>> _entriesByChapterKey = {};

  @override
  Future<Map<String, LineStudyEntry>> loadChapterEntries({
    required String bookId,
    required String chapterId,
  }) async {
    final chapterEntries =
        _entriesByChapterKey[_chapterKey(
          bookId: bookId,
          chapterId: chapterId,
        )] ??
        const <String, LineStudyEntry>{};
    return Map<String, LineStudyEntry>.from(chapterEntries);
  }

  @override
  Future<void> saveLineEntry({
    required String bookId,
    required String chapterId,
    required String readingUnitId,
    required LineStudyEntry entry,
  }) async {
    final chapterKey = _chapterKey(bookId: bookId, chapterId: chapterId);
    final chapterEntries = Map<String, LineStudyEntry>.from(
      _entriesByChapterKey[chapterKey] ?? const <String, LineStudyEntry>{},
    );

    if (entry.isEmpty) {
      chapterEntries.remove(readingUnitId);
    } else {
      chapterEntries[readingUnitId] = entry;
    }

    if (chapterEntries.isEmpty) {
      _entriesByChapterKey.remove(chapterKey);
      return;
    }

    _entriesByChapterKey[chapterKey] = chapterEntries;
  }

  String _chapterKey({required String bookId, required String chapterId}) {
    return '$bookId/$chapterId';
  }
}
