import 'package:daxue_mobile/src/app.dart';
import 'package:daxue_mobile/src/backend_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('changing Chinese font updates the preview text style', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: _StubBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    Text previewText() =>
        tester.widget<Text>(find.byKey(const ValueKey('chinese-font-preview')));
    final selectorFinder = find.byKey(const ValueKey('chinese-font-selector'));

    expect(previewText().style?.fontFamily, isNot('Kaiti SC'));
    expect(previewText().style?.fontFamily, isNot('Songti SC'));

    await tester.ensureVisible(selectorFinder);
    await tester.pumpAndSettle();

    await tester.tap(selectorFinder, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kai Ti').last);
    await tester.pumpAndSettle();

    expect(previewText().style?.fontFamily, 'Kaiti SC');
    expect(previewText().style?.fontFamilyFallback, contains('DaxueKaiTiSC'));

    await tester.tap(selectorFinder, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Song Ti').last);
    await tester.pumpAndSettle();

    expect(previewText().style?.fontFamily, 'Songti SC');
    expect(previewText().style?.fontFamilyFallback, contains('DaxueSongTiSC'));
  });
}

class _StubBackendClient implements BackendClient {
  @override
  String get baseUrl => 'http://stub-backend';

  @override
  Future<BookDetail> fetchBook(String bookId) async => BookDetail(
    id: bookId,
    title: '',
    chapterCount: 0,
    sourceUrl: '',
    sourceProvider: '',
    chapters: const [],
  );

  @override
  Future<List<BookSummary>> fetchBooks() async => const [];

  @override
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId) async =>
      const ChapterDetail(
        id: 'chapter-001',
        order: 1,
        title: '',
        summary: '',
        text: '',
        characterCount: 0,
        readingUnitCount: 0,
        readingUnits: [],
      );

  @override
  Future<CharacterComponentsDataset> fetchCharacterComponents() async =>
      const CharacterComponentsDataset(
        title: '',
        standard: '',
        groupedComponentCount: 0,
        rawComponentCount: 0,
        entries: [],
      );

  @override
  Future<CharacterIndex> fetchCharacterIndex() async => CharacterIndex.empty();

  @override
  Future<CharacterEntry> generateCharacterExplosion(String character) async =>
      CharacterEntry(
        character: character,
        simplified: character,
        traditional: character,
        pinyin: const [],
        zhuyin: const [],
        english: const [],
      );

  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String openLine = '',
    String characterComponent = '',
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async => const GuidedChatReply(
    message: GuidedConversationMessage(role: 'assistant', content: ''),
    provider: 'z.ai',
    model: 'glm-5-turbo',
  );
}
