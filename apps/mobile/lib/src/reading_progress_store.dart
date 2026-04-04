import 'dart:convert';

import 'package:daxue_mobile/src/local_storage.dart';

class BookReadingProgress {
  const BookReadingProgress({
    required this.chapterId,
    required this.readingUnitIndex,
  });

  factory BookReadingProgress.fromJson(Map<String, dynamic> json) {
    final chapterId = '${json['chapterId'] ?? ''}'.trim();
    final rawReadingUnitIndex = json['readingUnitIndex'];
    final readingUnitIndex = switch (rawReadingUnitIndex) {
      int value => value,
      num value => value.toInt(),
      _ => 0,
    };

    return BookReadingProgress(
      chapterId: chapterId,
      readingUnitIndex: readingUnitIndex < 0 ? 0 : readingUnitIndex,
    );
  }

  final String chapterId;
  final int readingUnitIndex;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'chapterId': chapterId,
      'readingUnitIndex': readingUnitIndex,
    };
  }
}

abstract class ReadingProgressStore {
  Future<BookReadingProgress?> loadBookProgress({required String bookId});

  Future<void> saveBookProgress({
    required String bookId,
    required BookReadingProgress progress,
  });
}

class SharedPreferencesReadingProgressStore implements ReadingProgressStore {
  SharedPreferencesReadingProgressStore._();

  static final SharedPreferencesReadingProgressStore instance =
      SharedPreferencesReadingProgressStore._();

  @override
  Future<BookReadingProgress?> loadBookProgress({
    required String bookId,
  }) async {
    final rawValue = await loadStoredString(_bookKey(bookId));
    if (rawValue == null || rawValue.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) {
        return null;
      }

      final progress = BookReadingProgress.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (progress.chapterId.isEmpty) {
        return null;
      }

      return progress;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveBookProgress({
    required String bookId,
    required BookReadingProgress progress,
  }) async {
    if (progress.chapterId.trim().isEmpty) {
      return;
    }

    await saveStoredString(_bookKey(bookId), jsonEncode(progress.toJson()));
  }

  String _bookKey(String bookId) => 'daxue.readingProgress.$bookId';
}

class MemoryReadingProgressStore implements ReadingProgressStore {
  final Map<String, BookReadingProgress> _progressByBookId =
      <String, BookReadingProgress>{};

  @override
  Future<BookReadingProgress?> loadBookProgress({
    required String bookId,
  }) async {
    return _progressByBookId[bookId];
  }

  @override
  Future<void> saveBookProgress({
    required String bookId,
    required BookReadingProgress progress,
  }) async {
    if (progress.chapterId.trim().isEmpty) {
      return;
    }

    _progressByBookId[bookId] = progress;
  }
}
