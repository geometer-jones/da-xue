import 'package:daxue_mobile/src/local_storage.dart';
import 'package:daxue_mobile/src/reading_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugResetStoredStringFallback();
  });

  test(
    'shared preferences reading progress store saves and loads progress',
    () async {
      final store = SharedPreferencesReadingProgressStore.instance;

      await store.saveBookProgress(
        bookId: 'da-xue',
        progress: const BookReadingProgress(
          chapterId: 'chapter-003',
          readingUnitIndex: 7,
        ),
      );

      final progress = await store.loadBookProgress(bookId: 'da-xue');

      expect(progress?.chapterId, 'chapter-003');
      expect(progress?.readingUnitIndex, 7);
    },
  );

  test(
    'shared preferences reading progress store ignores invalid payloads',
    () async {
      await saveStoredString(
        'daxue.readingProgress.da-xue',
        '{"chapterId":""}',
      );

      final progress = await SharedPreferencesReadingProgressStore.instance
          .loadBookProgress(bookId: 'da-xue');

      expect(progress, isNull);
    },
  );

  test('shared preferences reading progress store clears on empty chapter id', () async {
    final store = SharedPreferencesReadingProgressStore.instance;

    await store.saveBookProgress(
      bookId: 'da-xue',
      progress: const BookReadingProgress(
        chapterId: 'chapter-003',
        readingUnitIndex: 7,
      ),
    );

    await store.saveBookProgress(
      bookId: 'da-xue',
      progress: const BookReadingProgress(
        chapterId: '',
        readingUnitIndex: 0,
      ),
    );

    final progress = await store.loadBookProgress(bookId: 'da-xue');

    expect(progress, isNull);
  });
}
