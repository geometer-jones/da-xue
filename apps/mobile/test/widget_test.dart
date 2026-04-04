import 'dart:async';
import 'dart:math' as math;

import 'package:daxue_mobile/src/app.dart';
import 'package:daxue_mobile/src/backend_client.dart';
import 'package:daxue_mobile/src/flashcard_store.dart';
import 'package:daxue_mobile/src/line_study_store.dart';
import 'package:daxue_mobile/src/reading_progress_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _readingMenuScrollable() => find.descendant(
  of: find.byType(ReadingMenuPage),
  matching: find.byType(Scrollable),
);

Finder _bookChaptersScrollable() => find
    .descendant(
      of: find.byType(BookChaptersPage),
      matching: find.byType(Scrollable),
    )
    .first;

Finder _characterComponentsScrollable() => find
    .descendant(
      of: find.byType(CharacterComponentsPage),
      matching: find.byType(Scrollable),
    )
    .first;

Finder _flashcardsScrollable() => find.descendant(
  of: find.byType(FlashcardsPage),
  matching: find.byType(Scrollable),
);

Finder _richText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
  description: 'RichText("$text")',
);

Rect _visibleTextRect(WidgetTester tester, String text) {
  final viewportSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  Rect? bestRect;
  var bestArea = 0.0;

  for (final element in find.text(text).evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      continue;
    }

    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final visibleRect = Rect.fromLTRB(
      math.max(rect.left, 0),
      math.max(rect.top, 0),
      math.min(rect.right, viewportSize.width),
      math.min(rect.bottom, viewportSize.height),
    );
    final visibleArea = visibleRect.width * visibleRect.height;
    if (visibleArea > bestArea) {
      bestArea = visibleArea;
      bestRect = visibleRect;
    }
  }

  if (bestRect != null && bestArea > 0) {
    return bestRect;
  }

  throw StateError('No visible text widget found for "$text".');
}

Rect _visibleFinderRect(WidgetTester tester, Finder finder) {
  final viewportSize = tester.view.physicalSize / tester.view.devicePixelRatio;
  Rect? bestRect;
  var bestArea = 0.0;

  for (final element in finder.evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      continue;
    }

    final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final visibleRect = Rect.fromLTRB(
      math.max(rect.left, 0),
      math.max(rect.top, 0),
      math.min(rect.right, viewportSize.width),
      math.min(rect.bottom, viewportSize.height),
    );
    final visibleArea = visibleRect.width * visibleRect.height;
    if (visibleArea > bestArea) {
      bestArea = visibleArea;
      bestRect = visibleRect;
    }
  }

  if (bestRect != null && bestArea > 0) {
    return bestRect;
  }

  throw StateError('No visible widget found for finder "$finder".');
}

Offset _visibleTextCenter(WidgetTester tester, String text) {
  return _visibleTextRect(tester, text).center;
}

Future<void> _dragUntilVisibleText(
  WidgetTester tester,
  Finder scrollable,
  String text,
  Offset step, {
  int maxDrags = 50,
}) async {
  for (var index = 0; index < maxDrags; index++) {
    try {
      _visibleTextRect(tester, text);
      return;
    } on StateError {
      await tester.drag(scrollable, step);
      await tester.pumpAndSettle();
    }
  }

  throw TestFailure('Could not make "$text" visible after $maxDrags drags.');
}

Future<void> _dragUntilFinderVisible(
  WidgetTester tester,
  Finder scrollable,
  Finder finder,
  Offset step, {
  int maxDrags = 50,
}) async {
  for (var index = 0; index < maxDrags; index++) {
    try {
      _visibleFinderRect(tester, finder);
      return;
    } on StateError {
      await tester.drag(scrollable, step);
      await tester.pumpAndSettle();
    }
  }

  throw TestFailure(
    'Could not make finder "$finder" visible after $maxDrags drags.',
  );
}

void _expectLineStudyButtonState({
  required String kind,
  required int order,
  required bool isSaved,
}) {
  final key = ValueKey('line-study-$kind-button-$order');
  expect(
    find.byWidgetPredicate(
      (widget) => widget is FilledButton && widget.key == key,
      description: 'FilledButton($key)',
    ),
    isSaved ? findsOneWidget : findsNothing,
  );
  expect(
    find.byWidgetPredicate(
      (widget) => widget is OutlinedButton && widget.key == key,
      description: 'OutlinedButton($key)',
    ),
    isSaved ? findsNothing : findsOneWidget,
  );
}

Future<void> _selectChineseFontOption(
  WidgetTester tester,
  String optionLabel,
) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('chinese-font-selector')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('chinese-font-selector')),
      matching: find.byIcon(Icons.arrow_drop_down),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
}

CharacterComponentsDataset _largeCharacterComponentsDataset({int count = 35}) {
  return CharacterComponentsDataset(
    title: 'Large Components',
    standard: 'GF0014-2009',
    groupedComponentCount: count,
    rawComponentCount: count,
    entries: [
      for (var index = 0; index < count; index++)
        CharacterComponentEntry(
          groupId: index + 1,
          frequencyRank: index + 1,
          groupOccurrenceCount: 1,
          groupConstructionCount: 1,
          canonicalForm: String.fromCharCode(0x4E00 + index),
          canonicalName: 'Component ${index + 1}',
          forms: [String.fromCharCode(0x4E00 + index)],
          variantForms: const [],
          names: ['Component ${index + 1}'],
          sourceExampleCharacters: const [],
          memberCount: 1,
        ),
    ],
  );
}

FlashcardEntry _testFlashcard({
  required String id,
  required String simplified,
  required String traditional,
  List<String> zhuyin = const [],
  List<String> pinyin = const [],
  List<String> glossEn = const [],
  String translationEn = '',
  String sourceWork = '',
  int weight = 1,
  int savedAtEpochMilliseconds = 1,
}) {
  return FlashcardEntry(
    id: id,
    traditional: traditional,
    simplified: simplified,
    zhuyin: zhuyin,
    pinyin: pinyin,
    glossEn: glossEn,
    translationEn: translationEn,
    originKind: 'test',
    sourceWork: sourceWork,
    weight: weight,
    savedAtEpochMilliseconds: savedAtEpochMilliseconds,
  );
}

class _SequenceRandom implements math.Random {
  _SequenceRandom(this._values, {List<bool> boolValues = const [false]})
    : _boolValues = boolValues;

  final List<int> _values;
  final List<bool> _boolValues;
  int _index = 0;
  int _boolIndex = 0;

  @override
  bool nextBool() {
    return _boolValues[_boolIndex < _boolValues.length
        ? _boolIndex++
        : _boolValues.length - 1];
  }

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) {
    final nextValue =
        _values[_index < _values.length ? _index++ : _values.length - 1];
    return nextValue % max;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesFlashcardStore.instance.debugReset();
  });

  test('weighted flashcard sampling uses card weight', () {
    final sampled = sampleWeightedFlashcardEntry([
      _testFlashcard(
        id: 'character:light',
        simplified: '轻',
        traditional: '輕',
        weight: 1,
      ),
      _testFlashcard(
        id: 'character:heavy',
        simplified: '重',
        traditional: '重',
        weight: 3,
      ),
    ], random: _SequenceRandom([1]));

    expect(sampled?.id, 'character:heavy');
  });

  test('weighted flashcard ordering samples without replacement', () {
    final ordered = sampleWeightedFlashcardEntries([
      _testFlashcard(
        id: 'character:light-a',
        simplified: '甲',
        traditional: '甲',
        weight: 1,
      ),
      _testFlashcard(
        id: 'character:heavy',
        simplified: '重',
        traditional: '重',
        weight: 4,
      ),
      _testFlashcard(
        id: 'character:light-b',
        simplified: '乙',
        traditional: '乙',
        weight: 1,
      ),
    ], random: _SequenceRandom([0, 2, 0]));

    expect(ordered.map((entry) => entry.id), [
      'character:light-a',
      'character:heavy',
      'character:light-b',
    ]);
  });

  testWidgets('enters readings and expands chapters inline from a book page', (
    WidgetTester tester,
  ) async {
    final client = RecordingGuidedChatBackendClient();

    await tester.pumpWidget(DaxueApp(client: client));
    await tester.pumpAndSettle();

    expect(find.text('Da Xue'), findsOneWidget);
    expect(find.text('Start where Chinese learning starts.'), findsOneWidget);
    expect(
      find.text(
        'Skip the phrasebook openers like ni hao and xie xie. Da Xue gives you the texts, characters, and ideas that have rooted Chinese culture for generations.',
      ),
      findsOneWidget,
    );
    expect(find.text('Enter library'), findsOneWidget);
    expect(find.text('Line-by-line discussion'), findsOneWidget);
    expect(
      find.text(
        'Start with the Four Books in the Confucian tradition. Then enjoy the extended curriculum.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Read closely, then draft your own translations and responses to these classic texts.',
      ),
      findsOneWidget,
    );
    expect(find.text('Character explosion'), findsOneWidget);
    expect(
      find.text(
        'Follow linked Hanzi into their components to see how the language is built from the inside.',
      ),
      findsOneWidget,
    );
    expect(find.text('Flashcards'), findsNWidgets(2));
    expect(
      find.text(
        'Save characters worth keeping, then revisit them as flashcards inside the app.',
      ),
      findsOneWidget,
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Readings'), findsOneWidget);
    expect(find.text('Flashcards'), findsNWidgets(2));
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. Demo Book'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Readings'), findsWidgets);
    expect(find.text('1. Demo Book'), findsOneWidget);
    expect(find.text('1 chapter • 2 lines • 10 chars'), findsOneWidget);
    expect(find.text('1. Chapter One'), findsNothing);

    await tester.tap(find.text('1. Demo Book'));
    await tester.pumpAndSettle();

    expect(find.text('1. Chapter One'), findsOneWidget);
    expect(find.text('2 lines • 10 chars'), findsOneWidget);
    expect(find.text('Opening lines'), findsNothing);

    await tester.tap(find.text('1. Chapter One'));
    await tester.pumpAndSettle();

    expect(find.text('1. Chapter One'), findsWidgets);
    expect(
      find.text('Heaven and earth are dark and yellow.'),
      findsNWidgets(2),
    );
    expect(find.text('The cosmos is vast and wild.'), findsNothing);
    expect(find.text('2 lines • 10 chars'), findsOneWidget);
    expect(find.text('Opening lines'), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '1',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('bottom-line-number-jump-field')),
          )
          .controller
          ?.text,
      '1',
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-prev-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-go-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-next-button')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('bottom-line-number-jump-field')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('bottom-line-number-jump-prev-button')),
            )
            .dy,
      ),
    );
    expect(
      find.byKey(const ValueKey('embedded-reading-line-1-top-character-天-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('embedded-reading-line-2-top-character-宇-0')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('guided-chat-fab')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('bottom-line-number-jump-next-button')),
    );
    await tester.pumpAndSettle();
    final chapterTitlePositionBeforeNext = tester
        .getTopLeft(find.text('1. Chapter One').first)
        .dy;
    await tester.tap(
      find.byKey(const ValueKey('bottom-line-number-jump-next-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Heaven and earth are dark and yellow.'), findsNothing);
    expect(find.text('The cosmos is vast and wild.'), findsNWidgets(2));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '2',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('bottom-line-number-jump-field')),
          )
          .controller
          ?.text,
      '2',
    );
    expect(
      tester.getTopLeft(find.text('1. Chapter One').first).dy,
      greaterThan(chapterTitlePositionBeforeNext),
    );
    expect(
      find.byKey(const ValueKey('embedded-reading-line-1-top-character-天-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('embedded-reading-line-2-top-character-宇-0')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('guided-chat-fab')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
    await tester.pumpAndSettle();
    await tester.pump();

    expect(find.byKey(const ValueKey('guided-chat-sheet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guided-chat-sheet-title')),
      findsOneWidget,
    );
    expect(find.text('Guided chat'), findsNothing);
    expect(find.text('Current context'), findsNothing);
    expect(find.text('Work: Demo Book'), findsNothing);
    expect(find.text('Chapter: 1. Chapter One'), findsNothing);
    expect(find.text('Line 2: 宇宙洪荒。'), findsNothing);
    expect(find.text('Guide'), findsNothing);
    expect(client.requestHistory, hasLength(1));
    expect(
      client.requestHistory.single.single.content,
      contains('Start the guided chat for the current line.'),
    );
    expect(
      client.requestHistory.single.single.content,
      contains('Current line:\n宇宙洪荒。'),
    );
  });

  testWidgets('preserves the active line when the chapter reader rebuilds', (
    WidgetTester tester,
  ) async {
    final bucket = PageStorageBucket();
    const readerKey = PageStorageKey<String>('demo-chapter-reader');

    Future<void> pumpReader() async {
      await tester.pumpWidget(
        MaterialApp(
          home: PageStorage(
            bucket: bucket,
            child: ChapterReaderPage(
              key: readerKey,
              client: FakeBackendClient(),
              bookTitle: 'Demo Book',
              bookId: 'demo-book',
              chapterId: 'chapter-001',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpReader();

    expect(find.text('Line 1 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('top-reading-nav-next-button')));
    await tester.pumpAndSettle();
    expect(find.text('Line 2 of 2'), findsOneWidget);

    await pumpReader();

    expect(find.text('Line 2 of 2'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '2',
    );
  });

  testWidgets('embedded bottom line jump field can jump to a line', (
    WidgetTester tester,
  ) async {
    final client = FakeBackendClient();
    final book = await client.fetchBook('demo-book');

    await tester.pumpWidget(
      MaterialApp(
        home: BookChaptersPage(
          client: client,
          book: book,
          characterIndex: CharacterIndex.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1. Chapter One'));
    await tester.pumpAndSettle();

    final bottomLineJumpField = find.byKey(
      const ValueKey('bottom-line-number-jump-field'),
    );
    expect(bottomLineJumpField, findsOneWidget);
    expect(tester.widget<TextField>(bottomLineJumpField).controller?.text, '1');

    await tester.enterText(bottomLineJumpField, '2');
    await tester.ensureVisible(
      find.byKey(const ValueKey('bottom-line-number-jump-go-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bottom-line-number-jump-go-button')),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(bottomLineJumpField).controller?.text, '2');
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '2',
    );
    expect(find.text('The cosmos is vast and wild.'), findsNWidgets(2));
  });

  testWidgets('reopens a book at the saved chapter and line', (
    WidgetTester tester,
  ) async {
    final readingProgressStore = MemoryReadingProgressStore();

    await tester.pumpWidget(
      MaterialApp(
        home: ReadingMenuPage(
          client: MultiChapterLineBackendClient(chapterCount: 8),
          readingProgressStore: readingProgressStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. Demo Book'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1. Demo Book'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('6. Chapter 6'),
      200,
      scrollable: _bookChaptersScrollable(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('6. Chapter 6'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('line-number-jump-next-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Translation for chapter 6, line 2.'), findsNWidgets(2));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '2',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. Demo Book'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1. Demo Book'));
    await tester.pumpAndSettle();

    expect(find.text('Translation for chapter 6, line 2.'), findsNWidgets(2));
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '2',
    );
  });

  testWidgets(
    'reopens the components reference at the saved chapter and line',
    (WidgetTester tester) async {
      final readingProgressStore = MemoryReadingProgressStore();
      final restoredCharacter = String.fromCharCode(0x4E00 + 32);

      await tester.pumpWidget(
        MaterialApp(
          home: ReadingMenuPage(
            client: LargeComponentsBackendClient(),
            readingProgressStore: readingProgressStore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('0. 參考：漢字部件').first);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Chapter 2'),
        200,
        scrollable: _characterComponentsScrollable(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chapter 2'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('line-number-jump-field')),
        '3',
      );
      await tester.tap(
        find.byKey(const ValueKey('line-number-jump-go-button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('component-heading-33-$restoredCharacter-0')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('line-number-jump-field')),
            )
            .controller
            ?.text,
        '3',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('0. 參考：漢字部件').first);
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('component-heading-33-$restoredCharacter-0')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('line-number-jump-field')),
            )
            .controller
            ?.text,
        '3',
      );
    },
  );

  testWidgets('jumps to a specific line from the line number field', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: FakeBackendClient(),
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lineJumpField = find.byKey(const ValueKey('line-number-jump-field'));
    expect(lineJumpField, findsOneWidget);
    expect(tester.widget<TextField>(lineJumpField).controller?.text, '1');

    await tester.enterText(lineJumpField, '2');
    await tester.tap(find.byKey(const ValueKey('line-number-jump-go-button')));
    await tester.pumpAndSettle();

    expect(find.text('Line 2 of 2'), findsOneWidget);
    expect(tester.widget<TextField>(lineJumpField).controller?.text, '2');
    expect(find.text('The cosmos is vast and wild.'), findsNWidgets(2));
  });

  testWidgets('line number jump field uses a compact width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: FakeBackendClient(),
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lineJumpField = find.byKey(const ValueKey('line-number-jump-field'));
    final goButton = find.byKey(const ValueKey('line-number-jump-go-button'));

    expect(tester.getSize(lineJumpField).width, 72);
    expect(tester.widget<TextField>(lineJumpField).textAlign, TextAlign.center);
    expect(
      tester.getCenter(goButton).dx,
      greaterThan(tester.getCenter(lineJumpField).dx),
    );
  });

  testWidgets('top Next button advances to the next line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: FakeBackendClient(),
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final topPreviousButton = find.byKey(
      const ValueKey('top-reading-nav-prev-button'),
    );
    final topNextButton = find.byKey(
      const ValueKey('top-reading-nav-next-button'),
    );
    final bottomPreviousButton = find.byKey(
      const ValueKey('bottom-reading-nav-prev-button'),
    );
    final bottomNextButton = find.byKey(
      const ValueKey('bottom-reading-nav-next-button'),
    );
    final topLineJumpField = find.byKey(
      const ValueKey('line-number-jump-field'),
    );
    final firstChoiceChip = find.byType(ChoiceChip).first;
    expect(topPreviousButton, findsOneWidget);
    expect(topNextButton, findsOneWidget);
    expect(bottomPreviousButton, findsOneWidget);
    expect(bottomNextButton, findsOneWidget);
    expect(topLineJumpField, findsOneWidget);
    expect(
      tester.getTopLeft(topPreviousButton).dx,
      lessThan(tester.getTopLeft(topNextButton).dx),
    );
    expect(
      tester.getTopLeft(bottomPreviousButton).dx,
      lessThan(tester.getTopLeft(bottomNextButton).dx),
    );
    expect(
      tester.getTopLeft(bottomPreviousButton).dy,
      greaterThan(tester.getTopLeft(topPreviousButton).dy),
    );
    expect(
      tester.getTopLeft(topLineJumpField).dy,
      greaterThan(tester.getTopLeft(topPreviousButton).dy),
    );
    expect(
      tester.getTopLeft(topLineJumpField).dy,
      lessThan(tester.getTopLeft(firstChoiceChip).dy),
    );

    await tester.tap(topNextButton);
    await tester.pumpAndSettle();

    expect(find.text('Line 2 of 2'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '2',
    );
    expect(find.text('The cosmos is vast and wild.'), findsNWidgets(2));
  });

  testWidgets('bottom Prev button returns to the previous line', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: FakeBackendClient(),
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bottomNextButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('bottom-reading-nav-next-button')),
    );
    expect(bottomNextButton.onPressed, isNotNull);
    bottomNextButton.onPressed!.call();
    await tester.pumpAndSettle();

    final bottomPreviousButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('bottom-reading-nav-prev-button')),
    );
    expect(bottomPreviousButton.onPressed, isNotNull);
    bottomPreviousButton.onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Line 1 of 2'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '1',
    );
    expect(
      find.text('Heaven and earth are dark and yellow.'),
      findsNWidgets(2),
    );
  });

  testWidgets('chapter reader shows a bottom line jump field', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: FakeBackendClient(),
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('bottom-line-number-jump-field')),
          )
          .controller
          ?.text,
      '1',
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-prev-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-go-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-next-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('bottom-reading-nav-prev-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-reading-nav-next-button')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('bottom-line-number-jump-field')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(const ValueKey('bottom-reading-nav-prev-button')),
            )
            .dy,
      ),
    );
  });

  testWidgets(
    'chapter list scrolls past the top and bottom without a hard stop',
    (WidgetTester tester) async {
      final client = MultiChapterBackendClient();

      await tester.pumpWidget(
        MaterialApp(
          home: BookChaptersPage(
            client: client,
            book: client.bookDetail,
            characterIndex: CharacterIndex.empty(),
            readingProgressStore: MemoryReadingProgressStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = _bookChaptersScrollable();
      final initialOffset = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;

      expect(() => _visibleTextRect(tester, '1. Chapter 1'), returnsNormally);
      expect(
        () => _visibleTextRect(tester, '12. Chapter 12'),
        throwsStateError,
      );

      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(() => _visibleTextRect(tester, '12. Chapter 12'), returnsNormally);

      await tester.pumpWidget(
        MaterialApp(
          home: BookChaptersPage(
            client: client,
            book: client.bookDetail,
            characterIndex: CharacterIndex.empty(),
            readingProgressStore: MemoryReadingProgressStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final resetScrollable = _bookChaptersScrollable();

      await _dragUntilVisibleText(
        tester,
        resetScrollable,
        '12. Chapter 12',
        const Offset(0, 200),
      );
      final offsetAboveStart = tester
          .state<ScrollableState>(resetScrollable)
          .position
          .pixels;
      expect(find.text('12. Chapter 12'), findsWidgets);
      expect((offsetAboveStart - initialOffset).abs(), greaterThan(100));

      await tester.pumpWidget(
        MaterialApp(
          home: BookChaptersPage(
            client: client,
            book: client.bookDetail,
            characterIndex: CharacterIndex.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final forwardScrollable = _bookChaptersScrollable();
      await _dragUntilVisibleText(
        tester,
        forwardScrollable,
        '12. Chapter 12',
        const Offset(0, -200),
      );
      final offsetAtLastChapter = tester
          .state<ScrollableState>(forwardScrollable)
          .position
          .pixels;
      await tester.drag(forwardScrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
      final offsetPastLastChapter = tester
          .state<ScrollableState>(forwardScrollable)
          .position
          .pixels;

      expect(
        (offsetPastLastChapter - offsetAtLastChapter).abs(),
        greaterThan(100),
      );
    },
  );

  testWidgets(
    'opening a later chapter scrolls it to the top of the book page',
    (WidgetTester tester) async {
      final client = MultiChapterLineBackendClient(chapterCount: 12);

      await tester.pumpWidget(
        MaterialApp(
          home: BookChaptersPage(
            client: client,
            book: await client.fetchBook('demo-book'),
            characterIndex: CharacterIndex.empty(),
            readingProgressStore: MemoryReadingProgressStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _dragUntilVisibleText(
        tester,
        _bookChaptersScrollable(),
        '8. Chapter 8',
        const Offset(0, -250),
      );
      final chapterTopBeforeOpen = _visibleTextRect(tester, '8. Chapter 8').top;
      await tester.tapAt(_visibleTextCenter(tester, '8. Chapter 8'));
      await tester.pumpAndSettle();

      expect(find.text('Translation for chapter 8, line 1.'), findsNWidgets(2));
      expect(
        _visibleTextRect(tester, '8. Chapter 8').top,
        lessThanOrEqualTo(chapterTopBeforeOpen),
      );
      expect(_visibleTextRect(tester, '8. Chapter 8').top, lessThan(140));
    },
  );

  testWidgets(
    'top Next button opens the next chapter when the current chapter ends',
    (WidgetTester tester) async {
      final client = MultiChapterBackendClient();

      await tester.pumpWidget(
        MaterialApp(
          home: BookChaptersPage(
            client: client,
            book: client.bookDetail,
            characterIndex: CharacterIndex.empty(),
            readingProgressStore: MemoryReadingProgressStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      const chapterTitle = '10. Chapter 10';
      final nextChapterTitle = find.text('11. Chapter 11');

      await _dragUntilVisibleText(
        tester,
        _bookChaptersScrollable(),
        chapterTitle,
        const Offset(0, -250),
      );
      final chapterTile = find.ancestor(
        of: find.text(chapterTitle),
        matching: find.byType(ListTile),
      );
      await tester.tapAt(_visibleFinderRect(tester, chapterTile).center);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('line-number-jump-field')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('line-number-jump-prev-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('line-number-jump-go-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('line-number-jump-next-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('bottom-line-number-jump-field')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('bottom-line-number-jump-prev-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('bottom-line-number-jump-go-button')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('bottom-line-number-jump-next-button')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('line-number-jump-next-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Translation for chapter 11.'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('line-number-jump-field')),
        findsNothing,
      );
      expect(nextChapterTitle, findsOneWidget);
    },
  );

  testWidgets(
    'root tabs switch between home, flashcards, settings, readings, and theme modes',
    (WidgetTester tester) async {
      await tester.pumpWidget(DaxueApp(client: FakeBackendClient()));
      await tester.pumpAndSettle();
      final appFinder = find.byType(MaterialApp);

      expect(find.text('Da Xue'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(tester.widget<MaterialApp>(appFinder).themeMode, ThemeMode.system);

      await tester.tap(find.text('Flashcards'));
      await tester.pumpAndSettle();

      expect(find.text('Flashcards'), findsWidgets);
      expect(find.text('No flashcards saved yet'), findsOneWidget);
      expect(
        find.text(
          'Save a character from the exploded view to review it later.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
      expect(
        find.text('Current API base URL: http://fake-backend'),
        findsOneWidget,
      );
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-mode-light')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-mode-dark')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-mode-system')), findsOneWidget);
      expect(
        find.text('Match the device appearance automatically.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
      await tester.pumpAndSettle();

      expect(tester.widget<MaterialApp>(appFinder).themeMode, ThemeMode.dark);
      expect(find.text('Always use the dark reading surface.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('theme-mode-light')));
      await tester.pumpAndSettle();

      expect(tester.widget<MaterialApp>(appFinder).themeMode, ThemeMode.light);
      expect(
        find.text('Always use the light reading surface.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('theme-mode-system')));
      await tester.pumpAndSettle();

      expect(tester.widget<MaterialApp>(appFinder).themeMode, ThemeMode.system);

      await tester.tap(find.text('Readings'));
      await tester.pumpAndSettle();

      expect(find.text('Readings'), findsWidgets);
      expect(find.text('Choose a reading from the library.'), findsNothing);
      expect(
        find.text(
          'The curriculum spine keeps the Hanzi reference at the top of the reading list.',
        ),
        findsNothing,
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();

      expect(find.text('Da Xue'), findsOneWidget);
      expect(find.text('Enter library'), findsOneWidget);
      expect(find.text('No flashcards saved yet'), findsNothing);
    },
  );

  testWidgets(
    'saving a character from the exploded view adds it to flashcards',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: ChineseTitleBackendClient(),
            bookTitle: '四書章句集注 : 大學章句',
            bookId: 'da-xue',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.byKey(
        const ValueKey('current-reading-repeat-character-大-0'),
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      final saveButton = find.byKey(
        const ValueKey('exploder-save-flashcard-button'),
      );
      expect(saveButton, findsOneWidget);
      expect(
        find.descendant(of: saveButton, matching: find.byIcon(Icons.style)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: saveButton,
          matching: find.byIcon(Icons.style_outlined),
        ),
        findsOneWidget,
      );

      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Saved 大 to flashcards.'), findsOneWidget);
      final savedFlashcardIcon = find.descendant(
        of: saveButton,
        matching: find.byIcon(Icons.style),
      );
      expect(savedFlashcardIcon, findsOneWidget);
      expect(
        tester.widget<Icon>(savedFlashcardIcon).color,
        Theme.of(tester.element(saveButton)).colorScheme.primary,
      );

      final flashcards = SharedPreferencesFlashcardStore.instance.entries;
      expect(flashcards, hasLength(1));
      expect(flashcards.first.displayCharacter, '大');
      expect(flashcards.first.readingLabel, 'dà (ㄉㄚˋ)');
      expect(flashcards.first.glossLabel, 'big; great');

      Navigator.of(tester.element(saveButton)).pop();
      await tester.pumpAndSettle();

      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      final reopenedSaveButton = find.byKey(
        const ValueKey('exploder-save-flashcard-button'),
      );
      expect(reopenedSaveButton, findsOneWidget);
      expect(
        find.descendant(
          of: reopenedSaveButton,
          matching: find.byIcon(Icons.style),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(DaxueApp(client: FakeBackendClient()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Flashcards'));
      await tester.pumpAndSettle();

      expect(find.text('No flashcards saved yet'), findsNothing);
      expect(
        find.byKey(const ValueKey('flashcard-card-character:大')),
        findsOneWidget,
      );

      final leftCharacter = find.byKey(
        const ValueKey('flashcard-left-character-character:大-大-0'),
      );
      if (leftCharacter.evaluate().isEmpty) {
        await tester.tap(
          find.byKey(const ValueKey('flashcard-show-left-button-character:大')),
        );
        await tester.pumpAndSettle();
      }

      expect(leftCharacter, findsOneWidget);

      final readingLabel = find.byKey(
        const ValueKey('flashcard-reading-label-character:大'),
      );
      if (readingLabel.evaluate().isEmpty) {
        await tester.tap(
          find.byKey(const ValueKey('flashcard-show-right-button-character:大')),
        );
        await tester.pumpAndSettle();
      }

      expect(leftCharacter, findsOneWidget);
      expect(readingLabel, findsOneWidget);
      expect(
        find.byKey(const ValueKey('flashcard-english-label-character:大')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'reload button shows a loading indicator while asking GLM for a fresh explosion',
    (WidgetTester tester) async {
      final client = DelayedReloadingExplosionBackendClient();

      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: client,
            bookTitle: '四書章句集注 : 大學章句',
            bookId: 'da-xue',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.byKey(
        const ValueKey('current-reading-repeat-character-大-0'),
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(find.text('big; great'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('exploder-reload-button')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('exploder-reload-loading-indicator')),
        findsOneWidget,
      );
      expect(
        find.text('Waiting for a fresh GLM-generated explosion...'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('analysis-tree-row-root')),
        findsNothing,
      );

      client.finishReload();
      await tester.pumpAndSettle();

      expect(client.reloadCount, 1);
      expect(client.lastReloadedCharacter, '大');
      expect(find.text('fresh reload 1'), findsOneWidget);
    },
  );

  testWidgets(
    'flashcards toggle each side independently while keeping one visible',
    (WidgetTester tester) async {
      await SharedPreferencesFlashcardStore.instance.saveEntry(
        _testFlashcard(
          id: 'character:da',
          simplified: '大',
          traditional: '大',
          pinyin: const ['dà'],
          zhuyin: const ['ㄉㄚˋ'],
          glossEn: const ['big; great'],
          weight: 1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: FlashcardsPage(
            flashcardStore: SharedPreferencesFlashcardStore.instance,
            random: _SequenceRandom([0], boolValues: const [false]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('flashcard-left-side-character:da')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('flashcard-right-side-character:da')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('flashcard-left-character-character:da-大-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('flashcard-reading-label-character:da')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey('flashcard-show-right-button-character:da')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('flashcard-left-character-character:da-大-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('flashcard-reading-label-character:da')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('flashcard-english-label-character:da')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('flashcard-show-left-button-character:da')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('flashcard-left-character-character:da-大-0')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('flashcard-reading-label-character:da')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('flashcard-show-right-button-character:da')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('flashcard-reading-label-character:da')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('flashcard-left-character-character:da-大-0')),
        findsOneWidget,
      );
    },
  );

  testWidgets('flashcards can initially show the reading side', (
    WidgetTester tester,
  ) async {
    await SharedPreferencesFlashcardStore.instance.saveEntry(
      _testFlashcard(
        id: 'character:da',
        simplified: '大',
        traditional: '大',
        pinyin: const ['dà'],
        zhuyin: const ['ㄉㄚˋ'],
        glossEn: const ['big; great'],
        weight: 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardsPage(
          flashcardStore: SharedPreferencesFlashcardStore.instance,
          random: _SequenceRandom([0], boolValues: const [true]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('flashcard-reading-label-character:da')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('flashcard-english-label-character:da')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('flashcard-left-character-character:da-大-0')),
      findsNothing,
    );
  });

  testWidgets('flashcard cards expand vertically for longer content', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    Future<double> measureCardHeight(FlashcardEntry entry) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      SharedPreferences.setMockInitialValues({});
      SharedPreferencesFlashcardStore.instance.debugReset();
      await SharedPreferencesFlashcardStore.instance.saveEntry(entry);

      await tester.pumpWidget(
        MaterialApp(
          home: FlashcardsPage(
            flashcardStore: SharedPreferencesFlashcardStore.instance,
            random: _SequenceRandom([0], boolValues: const [true]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      return tester
          .getSize(find.byKey(ValueKey('flashcard-card-${entry.id}')))
          .height;
    }

    final shortHeight = await measureCardHeight(
      _testFlashcard(
        id: 'character:short',
        simplified: '大',
        traditional: '大',
        pinyin: const ['dà'],
        zhuyin: const ['ㄉㄚˋ'],
        glossEn: const ['big; great'],
        weight: 1,
      ),
    );

    final longHeight = await measureCardHeight(
      _testFlashcard(
        id: 'character:long',
        simplified: '學',
        traditional: '學',
        pinyin: const ['xué'],
        zhuyin: const ['ㄒㄩㄝˊ'],
        glossEn: const [
          'study; learning; disciplined inquiry; repeated practice that keeps returning to the line until the argument, image, and cadence become clear in context',
        ],
        weight: 1,
      ),
    );

    expect(longHeight, greaterThan(shortHeight));
  });

  testWidgets('flashcard Chinese characters open the exploded view', (
    WidgetTester tester,
  ) async {
    await SharedPreferencesFlashcardStore.instance.saveEntry(
      _testFlashcard(
        id: 'character:da',
        simplified: '大',
        traditional: '大',
        pinyin: const ['dà'],
        zhuyin: const ['ㄉㄚˋ'],
        glossEn: const ['big; great'],
        weight: 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardsPage(
          client: ChineseTitleBackendClient(),
          flashcardStore: SharedPreferencesFlashcardStore.instance,
          random: _SequenceRandom([0], boolValues: const [false]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(
      const ValueKey('flashcard-left-character-character:da-大-0'),
    );
    expect(target, findsOneWidget);

    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(find.text('Exploded view'), findsOneWidget);
    expect(find.text('big; great'), findsWidgets);
    expect(
      find.byKey(const ValueKey('analysis-tree-row-root')),
      findsOneWidget,
    );
  });

  testWidgets('flashcard weight icon buttons persist changes', (
    WidgetTester tester,
  ) async {
    await SharedPreferencesFlashcardStore.instance.saveEntry(
      _testFlashcard(
        id: 'character:da',
        simplified: '大',
        traditional: '大',
        pinyin: const ['dà'],
        zhuyin: const ['ㄉㄚˋ'],
        glossEn: const ['big; great'],
        weight: 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardsPage(
          flashcardStore: SharedPreferencesFlashcardStore.instance,
          random: _SequenceRandom([0], boolValues: const [false]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Text weightLabel() => tester.widget<Text>(
      find.byKey(const ValueKey('flashcard-weight-label-character:da')),
    );

    expect(weightLabel().data, 'Priority level 1');

    await tester.tap(
      find.byKey(
        const ValueKey('flashcard-weight-increase-button-character:da'),
      ),
    );
    await tester.pumpAndSettle();

    expect(SharedPreferencesFlashcardStore.instance.entries.single.weight, 2);
    expect(weightLabel().data, 'Priority level 2');

    await tester.tap(
      find.byKey(
        const ValueKey('flashcard-weight-decrease-button-character:da'),
      ),
    );
    await tester.pumpAndSettle();

    expect(SharedPreferencesFlashcardStore.instance.entries.single.weight, 1);
    expect(weightLabel().data, 'Priority level 1');
  });

  testWidgets('canceling minus at priority level 1 keeps the flashcard', (
    WidgetTester tester,
  ) async {
    await SharedPreferencesFlashcardStore.instance.saveEntry(
      _testFlashcard(
        id: 'character:da',
        simplified: '大',
        traditional: '大',
        pinyin: const ['dà'],
        zhuyin: const ['ㄉㄚˋ'],
        glossEn: const ['big; great'],
        weight: 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardsPage(
          flashcardStore: SharedPreferencesFlashcardStore.instance,
          random: _SequenceRandom([0], boolValues: const [false]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('flashcard-weight-decrease-button-character:da'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This will remove the flashcard.'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(SharedPreferencesFlashcardStore.instance.entries, hasLength(1));
    expect(
      find.byKey(const ValueKey('flashcard-card-character:da')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('flashcard-weight-label-character:da')),
          )
          .data,
      'Priority level 1',
    );
  });

  testWidgets('confirming minus at priority level 1 removes the flashcard', (
    WidgetTester tester,
  ) async {
    await SharedPreferencesFlashcardStore.instance.saveEntry(
      _testFlashcard(
        id: 'character:da',
        simplified: '大',
        traditional: '大',
        pinyin: const ['dà'],
        zhuyin: const ['ㄉㄚˋ'],
        glossEn: const ['big; great'],
        weight: 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardsPage(
          flashcardStore: SharedPreferencesFlashcardStore.instance,
          random: _SequenceRandom([0], boolValues: const [false]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(
        const ValueKey('flashcard-weight-decrease-button-character:da'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This will remove the flashcard.'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(SharedPreferencesFlashcardStore.instance.entries, isEmpty);
    expect(find.text('No flashcards saved yet'), findsOneWidget);
  });

  testWidgets('flashcards loop smoothly past the first and last cards', (
    WidgetTester tester,
  ) async {
    for (var index = 0; index < 31; index++) {
      await SharedPreferencesFlashcardStore.instance.saveEntry(
        _testFlashcard(
          id: 'character:$index',
          simplified: String.fromCharCode(0x4E00 + index),
          traditional: String.fromCharCode(0x4E00 + index),
          pinyin: ['pinyin $index'],
          glossEn: ['meaning $index'],
          weight: 1,
          savedAtEpochMilliseconds: index + 1,
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardsPage(
          flashcardStore: SharedPreferencesFlashcardStore.instance,
          random: _SequenceRandom(const [0]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = _flashcardsScrollable();
    final firstCard = find.byKey(const ValueKey('flashcard-card-character:30'));
    final lastCard = find.byKey(const ValueKey('flashcard-card-character:0'));

    expect(() => _visibleFinderRect(tester, firstCard), returnsNormally);
    expect(() => _visibleFinderRect(tester, lastCard), throwsStateError);

    await tester.drag(scrollable, const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(() => _visibleFinderRect(tester, lastCard), returnsNormally);

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardsPage(
          flashcardStore: SharedPreferencesFlashcardStore.instance,
          random: _SequenceRandom(const [0]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final resetScrollable = _flashcardsScrollable();
    await _dragUntilFinderVisible(
      tester,
      resetScrollable,
      lastCard,
      const Offset(0, 300),
    );
    expect(() => _visibleFinderRect(tester, lastCard), returnsNormally);

    await tester.pumpWidget(
      MaterialApp(
        home: FlashcardsPage(
          flashcardStore: SharedPreferencesFlashcardStore.instance,
          random: _SequenceRandom(const [0]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final forwardScrollable = _flashcardsScrollable();
    await _dragUntilFinderVisible(
      tester,
      forwardScrollable,
      lastCard,
      const Offset(0, -300),
    );
    await _dragUntilFinderVisible(
      tester,
      forwardScrollable,
      firstCard,
      const Offset(0, -300),
    );
    expect(() => _visibleFinderRect(tester, firstCard), returnsNormally);
  });

  testWidgets('flashcards reshuffle by weight when returning to the tab', (
    WidgetTester tester,
  ) async {
    await SharedPreferencesFlashcardStore.instance.saveEntry(
      _testFlashcard(
        id: 'character:heavy',
        simplified: '重',
        traditional: '重',
        pinyin: const ['zhòng'],
        glossEn: const ['heavy'],
        weight: 4,
      ),
    );
    await SharedPreferencesFlashcardStore.instance.saveEntry(
      _testFlashcard(
        id: 'character:light',
        simplified: '輕',
        traditional: '輕',
        pinyin: const ['qīng'],
        glossEn: const ['light'],
        weight: 1,
      ),
    );

    const pageKey = ValueKey('flashcards-page');
    final random = _SequenceRandom([0, 0, 1, 0], boolValues: const [false]);

    Future<void> pumpFlashcards({required bool isActive}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FlashcardsPage(
            key: pageKey,
            flashcardStore: SharedPreferencesFlashcardStore.instance,
            random: random,
            isActive: isActive,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await pumpFlashcards(isActive: true);

    double cardTop(String entryId) {
      return tester
          .getTopLeft(find.byKey(ValueKey('flashcard-card-$entryId')))
          .dy;
    }

    expect(cardTop('character:light'), lessThan(cardTop('character:heavy')));

    await pumpFlashcards(isActive: false);
    await pumpFlashcards(isActive: true);

    expect(cardTop('character:heavy'), lessThan(cardTop('character:light')));
  });

  testWidgets(
    'settings chinese font selector exposes more options and updates preview',
    (WidgetTester tester) async {
      await tester.pumpWidget(DaxueApp(client: ChineseTitleBackendClient()));
      await tester.pumpAndSettle();
      final appFinder = find.byType(MaterialApp);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('chinese-font-selector')),
        findsOneWidget,
      );

      final previewBefore = tester.widget<Text>(
        find.byKey(const ValueKey('chinese-font-preview')),
      );
      expect(previewBefore.style?.fontFamily, isNot('DaxueSongTiSC'));
      expect(
        tester
            .widget<MaterialApp>(appFinder)
            .theme
            ?.extension<ChineseTextTheme>()
            ?.fontOption,
        ChineseFontOption.systemSans,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('chinese-font-selector')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('chinese-font-selector')),
          matching: find.byIcon(Icons.arrow_drop_down),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ping Fang'), findsWidgets);
      expect(find.text('Hei Ti'), findsWidgets);
      expect(find.text('Song Ti'), findsWidgets);
      expect(find.text('Fang Song'), findsWidgets);
      expect(find.text('Kai Ti'), findsWidgets);

      await tester.tap(find.text('Fang Song').last);
      await tester.pumpAndSettle();

      final previewAfter = tester.widget<Text>(
        find.byKey(const ValueKey('chinese-font-preview')),
      );
      expect(previewAfter.style?.fontFamily, 'STFangsong');
      expect(
        previewAfter.style?.fontFamilyFallback,
        contains('DaxueFangSongSC'),
      );
      expect(
        find.text(
          'Printed Fang Song style suited to classical text and notes.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<MaterialApp>(appFinder)
            .theme
            ?.textTheme
            .bodyMedium
            ?.fontFamily,
        'STFangsong',
      );
      expect(
        tester
            .widget<MaterialApp>(appFinder)
            .theme
            ?.extension<ChineseTextTheme>()
            ?.fontOption,
        ChineseFontOption.fangSong,
      );

      await _selectChineseFontOption(tester, 'Kai Ti');

      final previewAfterSecondChange = tester.widget<Text>(
        find.byKey(const ValueKey('chinese-font-preview')),
      );
      expect(previewAfterSecondChange.style?.fontFamily, 'Kaiti SC');
      expect(
        previewAfterSecondChange.style?.fontFamilyFallback,
        contains('DaxueKaiTiSC'),
      );
      expect(
        find.text('Brush-inspired Kai style for a calligraphic feel.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('selected chinese font applies to inherited app text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: ChineseTitleBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await _selectChineseFontOption(tester, 'Fang Song');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final overlayEntry = OverlayEntry(
      builder: (context) => const Align(
        alignment: Alignment.topLeft,
        child: Material(
          type: MaterialType.transparency,
          child: Text('大學之道', key: ValueKey('inherited-chinese-text')),
        ),
      ),
    );
    addTearDown(overlayEntry.remove);
    navigator.overlay!.insert(overlayEntry);
    await tester.pump();

    final inheritedText = tester.widget<RichText>(_richText('大學之道'));
    expect(inheritedText.text.style?.fontFamily, 'STFangsong');
  });

  testWidgets('renders translations for Chinese book and chapter titles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: ChineseTitleBackendClient()));
    await tester.pumpAndSettle();

    expect(find.text('Da Xue'), findsOneWidget);

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. 大學'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('xué (ㄒㄩㄝˊ)'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();
    await _dragUntilVisibleText(
      tester,
      _readingMenuScrollable(),
      '1. 大學',
      const Offset(0, 60),
    );
    final xueSupportCharacter = find.byKey(
      const ValueKey('title-support-大學-2-学-0'),
    );
    expect(find.text('The Great Learning'), findsWidgets);
    expect(find.text('Start here!'), findsOneWidget);
    expect(find.text('1 chapter • 1 line • 16 chars'), findsOneWidget);
    expect(find.text('Character support'), findsNothing);
    expect(find.text('English Definition'), findsNothing);
    expect(xueSupportCharacter, findsOneWidget);
    expect(find.text('xué (ㄒㄩㄝˊ)'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('1 chapter • 1 line • 16 chars')).dy,
      greaterThan(tester.getTopLeft(find.text('xué (ㄒㄩㄝˊ)')).dy),
    );
    final xuePosition = tester.getTopLeft(xueSupportCharacter);
    final xueReadingPosition = tester.getTopLeft(find.text('xué (ㄒㄩㄝˊ)'));
    expect(xueReadingPosition.dy, greaterThan(xuePosition.dy));
    expect((xueReadingPosition.dx - xuePosition.dx).abs(), lessThan(1.0));
    expect(find.text('1. 大學之道'), findsNothing);
    expect(find.text('四書章句集注 : 大學章句'), findsNothing);

    final client = ChineseTitleBackendClient();
    final book = await client.fetchBook('da-xue');
    final characterIndex = await client.fetchCharacterIndex();

    await tester.pumpWidget(
      MaterialApp(
        home: BookChaptersPage(
          client: client,
          book: book,
          characterIndex: characterIndex,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1. 大學之道'), findsOneWidget);
    expect(find.text('The Way of Great Learning'), findsOneWidget);
    expect(find.text('1 line • 16 chars'), findsOneWidget);
    expect(find.text('Character support'), findsNothing);
    expect(find.text('dào (ㄉㄠˋ)'), findsOneWidget);
    expect(find.text('way; path'), findsOneWidget);
    expect(find.text('在明明德，在親民，在止於至善'), findsNothing);
    expect(
      tester.getTopLeft(find.text('1 line • 16 chars')).dy,
      greaterThan(tester.getTopLeft(find.text('way; path')).dy),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: ChineseTitleBackendClient(),
          bookTitle: '四書章句集注 : 大學章句',
          bookId: 'da-xue',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1. 大學之道'), findsOneWidget);
    expect(find.text('The Way of Great Learning'), findsWidgets);
    expect(
      find.byKey(const ValueKey('title-support-大學之道-2-学-0')),
      findsOneWidget,
    );
    expect(find.text('dào (ㄉㄠˋ)'), findsNWidgets(2));
    expect(find.text('way; path'), findsNWidgets(2));
    expect(find.text('1 line • 16 chars'), findsOneWidget);
    expect(find.text('大學之道，在明明德，在親民，在止於至善。'), findsNothing);
  });

  testWidgets('uses Daodejing incipits for numbered chapter titles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: DaodejingTitleBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. 道德經'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1. 道德經'));
    await tester.pumpAndSettle();

    expect(find.text('1. 江海所以能為百谷王者'), findsOneWidget);
    expect(find.text('Chapter 1'), findsOneWidget);
    expect(find.text('1. 第1章'), findsNothing);
    expect(find.text('1. 江海所以能為百谷王者，以其善下之，故能為百谷王'), findsNothing);

    await tester.tap(find.text('1. 江海所以能為百谷王者'));
    await tester.pumpAndSettle();

    expect(find.text('1. 江海所以能為百谷王者'), findsWidgets);
    expect(find.text('Chapter 1'), findsWidgets);
    expect(find.text('1. 第1章'), findsNothing);
    expect(find.text('1. 江海所以能為百谷王者，以其善下之，故能為百谷王'), findsNothing);
  });

  testWidgets(
    'book title translations match character support table English size',
    (WidgetTester tester) async {
      await tester.pumpWidget(DaxueApp(client: ChineseTitleBackendClient()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter library'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1. 大學'),
        200,
        scrollable: _readingMenuScrollable(),
      );
      await tester.pumpAndSettle();

      final bookTitleTranslation = tester.widget<Text>(
        find.text('The Great Learning'),
      );
      final supportTableEnglishText = tester.widget<Text>(
        find.text('big; great'),
      );

      expect(
        bookTitleTranslation.style?.fontSize,
        supportTableEnglishText.style?.fontSize,
      );
    },
  );

  testWidgets('expanded chapter cards remove title support table from layout', (
    WidgetTester tester,
  ) async {
    final client = ChineseTitleBackendClient();
    final book = await client.fetchBook('da-xue');
    final characterIndex = await client.fetchCharacterIndex();
    const supportTableKey = ValueKey(
      'chapter-title-support-table-da-xue-chapter-001',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BookChaptersPage(
          client: client,
          book: book,
          characterIndex: characterIndex,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1. 大學之道'), findsOneWidget);
    expect(find.text('way; path'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
    expect(find.byKey(supportTableKey), findsOneWidget);

    final chapterCountSummary = find.text('1 line • 16 chars');
    final collapsedSummaryY = tester.getTopLeft(chapterCountSummary).dy;

    await tester.tap(find.text('1. 大學之道'));
    await tester.pumpAndSettle();

    expect(chapterCountSummary, findsOneWidget);
    expect(find.byKey(supportTableKey), findsNothing);
    expect(
      tester.getTopLeft(chapterCountSummary).dy,
      lessThan(collapsedSummaryY),
    );
    expect(
      find.text(
        'The way of great learning lies in illuminating luminous virtue, renewing the people, and resting in the highest good.',
      ),
      findsNWidgets(2),
    );
  });

  testWidgets(
    'chapter cards show saved translation and response counts from local study data',
    (WidgetTester tester) async {
      final lineStudyStore = MemoryLineStudyStore();
      final client = RecordingTranslationFeedbackBackendClient();
      final book = await client.fetchBook('demo-book');

      await lineStudyStore.saveLineEntry(
        bookId: 'demo-book',
        chapterId: 'chapter-001',
        readingUnitId: 'chapter-001-line-001',
        entry: const LineStudyEntry(
          translation: 'Heaven and earth begin in mystery.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BookChaptersPage(
            client: client,
            book: book,
            characterIndex: CharacterIndex.empty(),
            lineStudyStore: lineStudyStore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 translation • 0 responses'), findsOneWidget);
      expect(find.text('2 lines • 10 chars'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('2 lines • 10 chars')).style?.fontSize,
        tester
            .widget<Text>(find.text('1 translation • 0 responses'))
            .style
            ?.fontSize,
      );

      await tester.tap(find.text('1. Chapter One'));
      await tester.pumpAndSettle();

      expect(find.text('1 translation • 0 responses'), findsOneWidget);
      _expectLineStudyButtonState(kind: 'translation', order: 1, isSaved: true);
      _expectLineStudyButtonState(kind: 'response', order: 1, isSaved: false);
      expect(find.textContaining('Saved locally:'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const ValueKey('line-study-response-button-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('line-study-response-button-1')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('line-study-editor-field')),
        'The paired images feel like a compressed opening frame.',
      );
      await tester.tap(
        find.byKey(const ValueKey('line-study-editor-save-button')),
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('1 translation • 1 response'), findsOneWidget);
      _expectLineStudyButtonState(kind: 'translation', order: 1, isSaved: true);
      _expectLineStudyButtonState(kind: 'response', order: 1, isSaved: true);
      expect(find.textContaining('Saved locally:'), findsNothing);
    },
  );

  testWidgets(
    'book cards show saved translation and response counts from local study data',
    (WidgetTester tester) async {
      final lineStudyStore = MemoryLineStudyStore();
      await lineStudyStore.saveLineEntry(
        bookId: 'demo-book',
        chapterId: 'chapter-001',
        readingUnitId: 'chapter-001-line-001',
        entry: const LineStudyEntry(
          translation: 'Heaven and earth begin in mystery.',
          response: 'The paired images feel like a compressed opening frame.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReadingMenuPage(
            client: FakeBackendClient(),
            lineStudyStore: lineStudyStore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1 translation • 1 response'),
        200,
        scrollable: _readingMenuScrollable(),
      );
      await tester.pumpAndSettle();

      expect(find.text('1. Demo Book'), findsOneWidget);
      expect(find.text('1 chapter • 2 lines • 10 chars'), findsOneWidget);
      expect(find.text('1 translation • 1 response'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.text('1 chapter • 2 lines • 10 chars'))
            .style
            ?.fontSize,
        tester
            .widget<Text>(find.text('1 translation • 1 response'))
            .style
            ?.fontSize,
      );
    },
  );

  testWidgets('book menu arrow icons are highlighted in green', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ReadingMenuPage(client: FakeBackendClient())),
    );
    await tester.pumpAndSettle();

    final readingMenuArrows = tester.widgetList<Icon>(
      find.descendant(
        of: find.byType(ReadingMenuPage),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    expect(readingMenuArrows, isNotEmpty);
    for (final icon in readingMenuArrows) {
      expect(icon.color, const Color(0xFF0B6E4F));
    }

    final client = FakeBackendClient();
    final book = await client.fetchBook('demo-book');

    await tester.pumpWidget(
      MaterialApp(
        home: BookChaptersPage(
          client: client,
          book: book,
          characterIndex: CharacterIndex.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chapterArrow = tester.widget<Icon>(find.byIcon(Icons.expand_more));
    expect(chapterArrow.color, const Color(0xFF0B6E4F));
  });

  testWidgets('returning from a book preserves the book menu scroll position', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ReadingMenuPage(client: TenthWorkBackendClient())),
    );
    await tester.pumpAndSettle();

    await _dragUntilVisibleText(
      tester,
      _readingMenuScrollable(),
      '10. 成語目錄',
      const Offset(0, -200),
    );

    final scrollOffsetBeforeOpen = tester
        .state<ScrollableState>(_readingMenuScrollable())
        .position
        .pixels;

    await tester.tapAt(_visibleTextCenter(tester, '10. 成語目錄'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final scrollOffsetAfterReturn = tester
        .state<ScrollableState>(_readingMenuScrollable())
        .position
        .pixels;
    expect(scrollOffsetAfterReturn, closeTo(scrollOffsetBeforeOpen, 24));
  });

  testWidgets(
    'reading menu scrolls past the top and bottom without a hard stop',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ReadingMenuPage(client: TenthWorkBackendClient())),
      );
      await tester.pumpAndSettle();

      final scrollable = _readingMenuScrollable();
      final initialOffset = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;

      expect(() => _visibleTextRect(tester, '0. 參考：漢字部件'), returnsNormally);
      expect(() => _visibleTextRect(tester, '10. 成語目錄'), throwsStateError);

      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(() => _visibleTextRect(tester, '10. 成語目錄'), returnsNormally);

      await tester.pumpWidget(
        MaterialApp(home: ReadingMenuPage(client: TenthWorkBackendClient())),
      );
      await tester.pumpAndSettle();

      final resetScrollable = _readingMenuScrollable();

      await _dragUntilVisibleText(
        tester,
        resetScrollable,
        '10. 成語目錄',
        const Offset(0, 200),
      );
      final offsetAboveStart = tester
          .state<ScrollableState>(resetScrollable)
          .position
          .pixels;
      expect(find.text('10. 成語目錄'), findsWidgets);
      expect((offsetAboveStart - initialOffset).abs(), greaterThan(100));

      await tester.pumpWidget(
        MaterialApp(home: ReadingMenuPage(client: TenthWorkBackendClient())),
      );
      await tester.pumpAndSettle();

      final forwardScrollable = _readingMenuScrollable();
      await _dragUntilVisibleText(
        tester,
        forwardScrollable,
        '10. 成語目錄',
        const Offset(0, -200),
      );
      final offsetAtLastBook = tester
          .state<ScrollableState>(forwardScrollable)
          .position
          .pixels;
      await tester.drag(forwardScrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
      final offsetPastLastBook = tester
          .state<ScrollableState>(forwardScrollable)
          .position
          .pixels;

      expect((offsetPastLastBook - offsetAtLastBook).abs(), greaterThan(100));
    },
  );

  testWidgets('opens the components reference as component chapters', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: FakeBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    expect(find.text('0. 參考：漢字部件'), findsWidgets);

    await tester.tap(find.text('0. 參考：漢字部件').first);
    await tester.pumpAndSettle();

    expect(find.text('參考：漢字部件'), findsOneWidget);
    expect(find.text('Reference: Character components'), findsOneWidget);
    expect(find.text('Characters'), findsNothing);
    expect(find.text('Components'), findsNothing);
    expect(find.text('Modern Common Character Components'), findsNothing);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Chapter 1: 1-2'), findsOneWidget);
    expect(find.text('2 lines • 3 chars'), findsOneWidget);
    expect(find.byKey(const ValueKey('component-heading-1-口-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('component-index-reference-lookup-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('component-index-reference-lookup-go-button')),
      findsNothing,
    );

    await tester.tap(find.text('Chapter 1: 1-2'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('line-number-jump-prev-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('line-number-jump-next-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('line-number-jump-go-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-prev-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-next-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bottom-line-number-jump-go-button')),
      findsOneWidget,
    );

    final componentHeading = find.byKey(
      const ValueKey('component-heading-1-口-0'),
    );
    expect(componentHeading, findsOneWidget);
    expect(find.byKey(const ValueKey('component-heading-2-卬-0')), findsNothing);
    expect(find.text('kǒu (ㄎㄡˇ)'), findsOneWidget);
    expect(find.text('mouth; entrance, gate, opening'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('component-header-divider-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('component-example-1-0-吃-0')),
      findsOneWidget,
    );
    expect(find.text('chī (ㄔ)'), findsOneWidget);
    expect(find.text('to eat'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('component-example-1-1-嗎-0')),
      findsOneWidget,
    );
    expect(find.text('ma (ㄇㄚ˙)'), findsOneWidget);
    expect(find.text('question particle'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('component-example-1-2-唱-0')),
      findsOneWidget,
    );
    expect(find.text('chàng (ㄔㄤˋ)'), findsOneWidget);
    expect(find.text('to sing'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('component-example-word-1-0-五-0')),
      findsNothing,
    );
    expect(
      find.text('wǔ wèi lìng rén kǒu shuǎng (ㄨˇ ㄨㄟˋ ㄌㄧㄥˋ ㄖㄣˊ ㄎㄡˇ ㄕㄨㄤˇ)'),
      findsNothing,
    );
    expect(
      find.text(
        'Literal gloss: five + taste + to cause + person + mouth + refreshed',
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('component-example-word-1-1-道-0')),
      findsNothing,
    );
    expect(
      find.text('dào zhī chū kǒu (ㄉㄠˋ ㄓ ㄔㄨ ㄎㄡˇ)'),
      findsNothing,
    );
    expect(
      find.text(
        'Literal gloss: way + it; possessive marker + to go out, to issue forth + mouth',
      ),
      findsNothing,
    );
    final kouPosition = tester.getTopLeft(componentHeading);
    final firstExampleCharacterPosition = tester.getTopLeft(
      find.byKey(const ValueKey('component-example-1-0-吃-0')),
    );
    final firstExampleEnglishPosition = tester.getTopLeft(
      find.text('to eat'),
    );
    final readingPosition = tester.getTopLeft(find.text('kǒu (ㄎㄡˇ)'));
    final meaningPosition = tester.getTopLeft(
      find.text('mouth; entrance, gate, opening'),
    );
    final dividerPosition = tester.getTopLeft(
      find.byKey(const ValueKey('component-header-divider-1')),
    );
    expect((readingPosition.dx - kouPosition.dx).abs(), lessThan(1.0));
    expect((meaningPosition.dx - kouPosition.dx).abs(), lessThan(1.0));
    expect(kouPosition.dy, lessThan(readingPosition.dy));
    expect(readingPosition.dy, lessThan(meaningPosition.dy));
    expect(dividerPosition.dy, greaterThan(readingPosition.dy));
    expect(dividerPosition.dy, greaterThan(meaningPosition.dy));
    expect(firstExampleEnglishPosition.dx, greaterThan(firstExampleCharacterPosition.dx));
    expect(firstExampleEnglishPosition.dy, greaterThan(dividerPosition.dy));
    expect(firstExampleCharacterPosition.dy, greaterThan(dividerPosition.dy));

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. Demo Book'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    expect(find.text('0. 參考：漢字部件'), findsWidgets);
    expect(find.text('1. Demo Book'), findsWidgets);
  });

  testWidgets(
    'component heading opens the exploded view and keeps its font size',
    (WidgetTester tester) async {
      final client = ChineseTitleBackendClient();

      await tester.pumpWidget(DaxueApp(client: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter library'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1. 大學'),
        200,
        scrollable: _readingMenuScrollable(),
      );
      await tester.pumpAndSettle();

      final supportTableCharacter = find.byKey(
        const ValueKey('title-support-大學-1-大-0'),
      );
      expect(supportTableCharacter, findsOneWidget);

      final supportTableText = tester.widget<Text>(
        find.descendant(of: supportTableCharacter, matching: find.byType(Text)),
      );

      final characterIndex = await client.fetchCharacterIndex();
      final dataset = await client.fetchCharacterComponents();

      await tester.pumpWidget(
        MaterialApp(
          home: CharacterComponentsPage(
            client: client,
            dataset: dataset,
            characterIndex: characterIndex,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chapter 1: 1-2'));
      await tester.pumpAndSettle();

      final componentHeading = find.byKey(
        const ValueKey('component-heading-1-口-0'),
      );
      expect(componentHeading, findsOneWidget);

      final componentHeadingText = tester.widget<Text>(
        find.descendant(of: componentHeading, matching: find.byType(Text)),
      );
      expect(
        componentHeadingText.style?.fontSize,
        supportTableText.style?.fontSize,
      );

      await tester.tap(componentHeading);
      await tester.pumpAndSettle();

      expect(find.text('Exploded view'), findsOneWidget);
    },
  );

  testWidgets(
    'component example characters open the exploded view and match support table size',
    (WidgetTester tester) async {
      final client = ChineseTitleBackendClient();

      await tester.pumpWidget(DaxueApp(client: client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter library'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1. 大學'),
        200,
        scrollable: _readingMenuScrollable(),
      );
      await tester.pumpAndSettle();

      final supportTableCharacter = find.byKey(
        const ValueKey('title-support-大學-1-大-0'),
      );
      expect(supportTableCharacter, findsOneWidget);

      final supportTableText = tester.widget<Text>(
        find.descendant(of: supportTableCharacter, matching: find.byType(Text)),
      );

      final characterIndex = await client.fetchCharacterIndex();
      final dataset = await client.fetchCharacterComponents();

      await tester.pumpWidget(
        MaterialApp(
          home: CharacterComponentsPage(
            client: client,
            dataset: dataset,
            characterIndex: characterIndex,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chapter 1: 1-2'));
      await tester.pumpAndSettle();

      final exampleCharacter = find.byKey(
        const ValueKey('component-example-1-0-吃-0'),
      );
      expect(exampleCharacter, findsOneWidget);
      await tester.ensureVisible(exampleCharacter);
      await tester.pumpAndSettle();

      final exampleText = tester.widget<Text>(
        find.descendant(of: exampleCharacter, matching: find.byType(Text)),
      );
      expect(exampleText.style?.fontSize, supportTableText.style?.fontSize);
      final exampleCharacterPosition = tester.getTopLeft(exampleCharacter);
      final exampleReadingPosition = tester.getTopLeft(find.text('chī (ㄔ)'));
      expect(
        (exampleReadingPosition.dx - exampleCharacterPosition.dx).abs(),
        lessThan(1.0),
      );
      expect(exampleCharacterPosition.dy, lessThan(exampleReadingPosition.dy));

      await tester.tap(exampleCharacter);
      await tester.pumpAndSettle();

      expect(find.text('Exploded view'), findsOneWidget);
    },
  );

  testWidgets(
    'component lines hide broken placeholder variants but keep canonical forms',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        DaxueApp(client: ComponentDecompositionBackendClient()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter library'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('0. 參考：漢字部件').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chapter 1: 1-2'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('component-heading-1-水-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('component-heading-1-氵-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('component-heading-1-氺-6')),
        findsOneWidget,
      );
      expect(find.text('{⿱䒑八}'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('line-number-jump-next-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('component-heading-2-月-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('component-heading-2-肉-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('component-heading-2-⺝-6')),
        findsOneWidget,
      );
      expect(find.text('𱼀'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('line-number-jump-field')),
        '3',
      );
      await tester.tap(
        find.byKey(const ValueKey('line-number-jump-go-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('component-heading-3-𫜹-0')),
        findsOneWidget,
      );
      expect(find.text('𰀂'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('bottom-line-number-jump-field')),
        '4',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('bottom-line-number-jump-go-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('bottom-line-number-jump-go-button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('component-heading-4-奥-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('component-heading-4-字-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('component-heading-4-头-2')),
        findsOneWidget,
      );
      expect(find.text('{⿱丿𭁨}'), findsNothing);
    },
  );

  testWidgets('presents character components in chapter sections of 30', (
    WidgetTester tester,
  ) async {
    final dataset = _largeCharacterComponentsDataset();
    final firstCharacter = String.fromCharCode(0x4E00);
    final thirtyFirstCharacter = String.fromCharCode(0x4E00 + 30);

    await tester.pumpWidget(
      MaterialApp(
        home: CharacterComponentsPage(
          client: FakeBackendClient(),
          dataset: dataset,
          characterIndex: CharacterIndex.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chapter 1: 1-30'), findsOneWidget);
    expect(find.text('30 lines • 30 chars'), findsOneWidget);
    expect(find.text('Chapter 2: 31-35'), findsOneWidget);
    expect(find.text('5 lines • 5 chars'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Load more'), findsNothing);
    expect(
      find.byKey(ValueKey('component-heading-1-$firstCharacter-0')),
      findsNothing,
    );
    expect(find.text(thirtyFirstCharacter), findsNothing);

    await tester.tap(find.text('Chapter 1: 1-30'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('component-heading-1-$firstCharacter-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey('component-heading-2-${String.fromCharCode(0x4E00 + 1)}-0'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('component-heading-31-$thirtyFirstCharacter-0')),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.text('Chapter 2: 31-35'),
      200,
      scrollable: _characterComponentsScrollable(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chapter 2: 31-35'));
    await tester.pumpAndSettle();

    expect(find.text('Load more'), findsNothing);
    expect(
      find.byKey(ValueKey('component-heading-1-$firstCharacter-0')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('component-heading-31-$thirtyFirstCharacter-0')),
      findsOneWidget,
    );
  });

  testWidgets(
    'opening a later component chapter scrolls it to the top and collapses the previous one',
    (WidgetTester tester) async {
      final dataset = _largeCharacterComponentsDataset(count: 35);
      final firstCharacter = String.fromCharCode(0x4E00);
      final thirtyFirstCharacter = String.fromCharCode(0x4E00 + 30);

      await tester.pumpWidget(
        MaterialApp(
          home: CharacterComponentsPage(
            client: FakeBackendClient(),
            dataset: dataset,
            characterIndex: CharacterIndex.empty(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chapter 1: 1-30'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('component-heading-1-$firstCharacter-0')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('Chapter 2: 31-35'),
        200,
        scrollable: _characterComponentsScrollable(),
      );
      await tester.pumpAndSettle();

      final chapterTopBeforeOpen = _visibleTextRect(tester, 'Chapter 2: 31-35').top;
      await tester.tap(find.text('Chapter 2: 31-35'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('component-heading-1-$firstCharacter-0')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('component-heading-31-$thirtyFirstCharacter-0')),
        findsOneWidget,
      );
      expect(
        _visibleTextRect(tester, 'Chapter 2: 31-35').top,
        lessThanOrEqualTo(chapterTopBeforeOpen),
      );
      expect(_visibleTextRect(tester, 'Chapter 2: 31-35').top, lessThan(160));
    },
  );

  testWidgets(
    'component chapter list scrolls past the top and bottom without a hard stop',
    (WidgetTester tester) async {
      final dataset = _largeCharacterComponentsDataset(count: 185);

      Future<void> pumpComponentsPage() async {
        await tester.pumpWidget(
          MaterialApp(
            home: CharacterComponentsPage(
              client: FakeBackendClient(),
              dataset: dataset,
              characterIndex: CharacterIndex.empty(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpComponentsPage();

      final scrollable = _characterComponentsScrollable();
      final initialOffset = tester
          .state<ScrollableState>(scrollable)
          .position
          .pixels;

      expect(() => _visibleTextRect(tester, 'Chapter 1: 1-30'), returnsNormally);
      expect(() => _visibleTextRect(tester, 'Chapter 7: 181-185'), throwsStateError);

      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(() => _visibleTextRect(tester, 'Chapter 7: 181-185'), returnsNormally);

      await pumpComponentsPage();

      final resetScrollable = _characterComponentsScrollable();
      await _dragUntilVisibleText(
        tester,
        resetScrollable,
        'Chapter 7: 181-185',
        const Offset(0, 200),
      );
      final offsetAboveStart = tester
          .state<ScrollableState>(resetScrollable)
          .position
          .pixels;
      expect(find.text('Chapter 7: 181-185'), findsWidgets);
      expect((offsetAboveStart - initialOffset).abs(), greaterThan(100));

      await pumpComponentsPage();

      final forwardScrollable = _characterComponentsScrollable();
      await _dragUntilVisibleText(
        tester,
        forwardScrollable,
        'Chapter 7: 181-185',
        const Offset(0, -200),
      );
      final offsetAtLastChapter = tester
          .state<ScrollableState>(forwardScrollable)
          .position
          .pixels;
      await tester.drag(forwardScrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
      final offsetPastLastChapter = tester
          .state<ScrollableState>(forwardScrollable)
          .position
          .pixels;

      expect(
        (offsetPastLastChapter - offsetAtLastChapter).abs(),
        greaterThan(100),
      );
    },
  );

  testWidgets('component page does not show a component lookup form', (
    WidgetTester tester,
  ) async {
    final client = FakeBackendClient();
    final characterIndex = await client.fetchCharacterIndex();
    final dataset = await client.fetchCharacterComponents();

    await tester.pumpWidget(
      MaterialApp(
        home: CharacterComponentsPage(
          client: client,
          dataset: dataset,
          characterIndex: characterIndex,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chapter 1: 1-2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('component-index-reference-lookup-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('component-index-reference-lookup-go-button')),
      findsNothing,
    );

    await tester.tap(find.text('Chapter 1: 1-2'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('component-index-reference-lookup-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('component-index-reference-lookup-go-button')),
      findsNothing,
    );
  });

  testWidgets('character index lookup jumps to matching entries', (
    WidgetTester tester,
  ) async {
    final client = FakeBackendClient();
    final characterIndex = await client.fetchCharacterIndex();

    await tester.pumpWidget(
      MaterialApp(
        home: CharacterIndexPage(
          client: client,
          characterIndex: characterIndex,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('character-index-heading-1-参-0')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('character-index-reference-lookup-field')),
      'study',
    );
    await tester.tap(
      find.byKey(const ValueKey('character-index-reference-lookup-go-button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('character-index-heading-7-学-0')),
      findsOneWidget,
    );
    expect(find.text('study; learning'), findsOneWidget);
  });

  testWidgets('uses larger font sizes for Chinese primary text', (
    WidgetTester tester,
  ) async {
    final textTheme = ThemeData(useMaterial3: true).textTheme;
    final menuBaseline = textTheme.titleMedium?.fontSize ?? 16;
    final readingBaseline = textTheme.headlineSmall?.fontSize ?? 24;

    await tester.pumpWidget(DaxueApp(client: ChineseTitleBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. 大學'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    final menuTitle = tester.widget<Text>(find.text('1. 大學'));
    expect(menuTitle.style?.fontSize ?? 0, closeTo(menuBaseline * 2, 0.01));

    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: FakeBackendClient(),
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final readingLine = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('current-reading-character-天-0')),
        matching: find.byType(Text),
      ),
    );
    expect(
      readingLine.style?.fontSize ?? 0,
      closeTo(readingBaseline * 1.2, 0.01),
    );
  });

  testWidgets('renders English translations and opens guided chat from a FAB', (
    WidgetTester tester,
  ) async {
    final client = RecordingGuidedChatBackendClient();

    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: client,
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 lines • 10 chars'), findsOneWidget);
    final chapterCounter = tester.widget<Text>(find.text('2 lines • 10 chars'));
    final chapterCounterContext = tester.element(
      find.text('2 lines • 10 chars'),
    );
    expect(
      chapterCounter.style?.fontSize,
      Theme.of(chapterCounterContext).textTheme.bodySmall?.fontSize,
    );
    expect(find.text('Opening lines'), findsNothing);
    expect(find.text('天地玄黃。宇宙洪荒。'), findsNothing);
    expect(find.text('Line 1 of 2'), findsOneWidget);
    expect(
      find.text('Heaven and earth are dark and yellow.'),
      findsNWidgets(2),
    );
    expect(find.byKey(const ValueKey('guided-chat-fab')), findsOneWidget);

    await tester.tap(find.byType(ChoiceChip).at(1));
    await tester.pumpAndSettle();

    expect(find.text('Line 2 of 2'), findsOneWidget);
    expect(find.text('The cosmos is vast and wild.'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guided-chat-sheet')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guided-chat-sheet-title')),
      findsOneWidget,
    );
    expect(find.text('Guided chat'), findsNothing);
    expect(find.text('Current context'), findsNothing);
    expect(find.text('Work: Demo Book'), findsNothing);
    expect(find.text('Chapter: 1. Chapter One'), findsNothing);
    expect(find.text('Line 2: 宇宙洪荒。'), findsNothing);
    expect(find.text("The guide's replies will appear here."), findsNothing);
    expect(find.text('Guide'), findsNothing);
    expect(
      find.text(
        'Notice how line 2 reframes the imagery, then compare its movement with the previous line.',
      ),
      findsOneWidget,
    );
    expect(client.requestHistory, hasLength(1));
    expect(client.lastBookId, 'demo-book');
    expect(client.lastChapterId, 'chapter-001');
    expect(client.lastReadingUnitId, 'chapter-001-line-002');
    expect(client.lastLearnerTranslation, isEmpty);
    expect(client.lastLearnerResponse, isEmpty);
    expect(client.lastMessages, hasLength(1));
    expect(client.lastMessages!.single.isUser, isTrue);
    expect(client.lastMessages!.single.isVisible, isFalse);
    expect(
      client.lastMessages!.single.content,
      contains('Start the guided chat for the current line.'),
    );
    expect(
      client.lastMessages!.single.content,
      contains('Current line:\n宇宙洪荒。'),
    );
    final sheetBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('guided-chat-sheet')))
        .dy;
    final messageFieldBottom = tester
        .getBottomLeft(
          find.byKey(const ValueKey('guided-chat-sheet-message-field')),
        )
        .dy;
    expect(sheetBottom - messageFieldBottom, lessThan(120));
    final messageFieldCenter = tester
        .getCenter(
          find.byKey(const ValueKey('guided-chat-sheet-message-field')),
        )
        .dy;
    final sendButtonCenter = tester
        .getCenter(find.byKey(const ValueKey('guided-chat-send-button')))
        .dy;
    expect((messageFieldCenter - sendButtonCenter).abs(), lessThan(12));

    await tester.enterText(
      find.byKey(const ValueKey('guided-chat-sheet-message-field')),
      'What changes in the second line?',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guided-chat-send-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(client.lastBookId, 'demo-book');
    expect(client.lastChapterId, 'chapter-001');
    expect(client.lastReadingUnitId, 'chapter-001-line-002');
    expect(client.lastLearnerTranslation, isEmpty);
    expect(client.lastLearnerResponse, isEmpty);
    expect(client.requestHistory, hasLength(2));
    expect(client.lastMessages, hasLength(3));
    expect(client.lastPreviousLines, hasLength(1));
    expect(client.lastMessages!.last.isUser, isTrue);
    expect(client.lastMessages!.last.isVisible, isTrue);
    expect(
      client.lastPreviousLines!.single.readingUnitId,
      'chapter-001-line-001',
    );
    expect(client.lastPreviousLines!.single.order, 1);
    expect(client.lastPreviousLines!.single.text, '天地玄黃。');
    expect(
      client.lastPreviousLines!.single.translationEn,
      'Heaven and earth are dark and yellow.',
    );
    expect(client.lastPreviousLines!.single.learnerTranslation, isEmpty);
    expect(client.lastPreviousLines!.single.learnerResponse, isEmpty);
    expect(
      client.lastMessages!.last.content,
      'What changes in the second line?',
    );
    expect(find.text('You'), findsOneWidget);
    expect(find.text('What changes in the second line?'), findsOneWidget);
    expect(find.text('Guide'), findsNothing);
    expect(
      find.text(
        'Notice how line 2 reframes the imagery, then compare its movement with the previous line.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'The second line widens the scale from earth to cosmos, so compare that expansion with the grounded imagery before it.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('guided chat loading bar spans the full sheet content width', (
    WidgetTester tester,
  ) async {
    final requestGate = Completer<void>();
    final client = DelayedGuidedChatBackendClient(requestGate);

    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: client,
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final loadingBar = find.byKey(const ValueKey('guided-chat-loading-bar'));
    expect(loadingBar, findsOneWidget);

    final loadingBarRect = tester.getRect(loadingBar);
    final scrollableRect = tester.getRect(
      find.byKey(const ValueKey('guided-chat-sheet-scrollable')),
    );
    expect(loadingBarRect.left, closeTo(scrollableRect.left + 24, 0.1));
    expect(loadingBarRect.right, closeTo(scrollableRect.right - 24, 0.1));

    requestGate.complete();
    await tester.pump();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'guided chat loading text is generic when no learner translation is saved',
    (WidgetTester tester) async {
      final requestGate = Completer<void>();
      final client = DelayedGuidedChatBackendClient(requestGate);

      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: client,
            bookTitle: 'Demo Book',
            bookId: 'demo-book',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('The guide is responding...'), findsOneWidget);
      expect(
        find.text('Loading the default translation for the guide...'),
        findsNothing,
      );
      expect(
        find.text('Loading your translation for the guide...'),
        findsNothing,
      );

      requestGate.complete();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'guided chat loading text stays generic when a learner translation is saved',
    (WidgetTester tester) async {
      final requestGate = Completer<void>();
      final client = DelayedGuidedChatBackendClient(requestGate);
      final lineStudyStore = MemoryLineStudyStore();

      await lineStudyStore.saveLineEntry(
        bookId: 'demo-book',
        chapterId: 'chapter-001',
        readingUnitId: 'chapter-001-line-001',
        entry: const LineStudyEntry(
          translation: 'Heaven and earth begin in mystery.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: client,
            bookTitle: 'Demo Book',
            bookId: 'demo-book',
            chapterId: 'chapter-001',
            lineStudyStore: lineStudyStore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('The guide is responding...'), findsOneWidget);
      expect(
        find.text('Loading the default translation for the guide...'),
        findsNothing,
      );
      expect(
        find.text('Loading your translation for the guide...'),
        findsNothing,
      );

      requestGate.complete();
      await tester.pump();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'guided chat scrolls to the top when the first visible message arrives',
    (WidgetTester tester) async {
      final requestGate = Completer<void>();
      final client = LongReplyGuidedChatBackendClient(requestGate);

      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: client,
            bookTitle: 'Demo Book',
            bookId: 'demo-book',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      requestGate.complete();
      await tester.pump();
      await tester.pumpAndSettle();

      final scrollable = tester.widget<ListView>(
        find.byKey(const ValueKey('guided-chat-sheet-scrollable')),
      );
      final controller = scrollable.controller!;

      expect(controller.position.maxScrollExtent, greaterThan(0));
      expect(
        controller.position.pixels,
        closeTo(controller.position.maxScrollExtent, 0.1),
      );
    },
  );

  testWidgets(
    'guided chat Chinese characters open the exploder at support-table size',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DaxueApp(client: ChineseGuidedChatBackendClient())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter library'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1. 大學'),
        200,
        scrollable: _readingMenuScrollable(),
      );
      await tester.pumpAndSettle();

      final supportTableCharacter = find.byKey(
        const ValueKey('title-support-大學-1-大-0'),
      );
      expect(supportTableCharacter, findsOneWidget);
      final supportTableText = tester.widget<Text>(
        find.descendant(of: supportTableCharacter, matching: find.byType(Text)),
      );

      await tester.tap(find.text('1. 大學'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1. 大學之道'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('guided-chat-sheet-message-field')),
        'Explain the first line.',
      );
      await tester.tap(find.byKey(const ValueKey('guided-chat-send-button')));
      await tester.pump();
      await tester.pumpAndSettle();

      final chatCharacter = find.byKey(
        const ValueKey('guided-chat-message-2-character-大-0'),
      );
      expect(chatCharacter, findsOneWidget);

      final chatCharacterText = tester.widget<Text>(
        find.descendant(of: chatCharacter, matching: find.byType(Text)),
      );
      expect(
        chatCharacterText.style?.fontSize,
        supportTableText.style?.fontSize,
      );

      await tester.tap(chatCharacter);
      await tester.pumpAndSettle();

      expect(find.text('Exploded view'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('大'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'chengyu reader keeps the gloss and category chip before auto-starting chat',
    (WidgetTester tester) async {
      final client = ChengyuGuidedChatBackendClient();

      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: client,
            bookTitle: '成語目錄',
            bookId: 'chengyu-catalog',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Line 1 of 2'), findsOneWidget);
      expect(find.text('to persevere'), findsNWidgets(2));
      expect(find.text('学习与积累'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reading-unit-category-chip-1')),
        findsOneWidget,
      );
      expect(client.requestHistory, isEmpty);
      final idiomPosition = tester.getTopLeft(
        find.byKey(const ValueKey('current-reading-character-持-0')),
      );
      final categoryChipPosition = tester.getTopLeft(
        find.byKey(const ValueKey('reading-unit-category-chip-1')),
      );
      final glossPosition = tester.getTopLeft(find.text('to persevere').first);
      expect(idiomPosition.dy, lessThan(categoryChipPosition.dy));
      expect(categoryChipPosition.dy, lessThan(glossPosition.dy));
      expect(
        find.byKey(const ValueKey('inline-analysis-heading-1')),
        findsNothing,
      );
      expect(
        find.text(
          'This chengyu frames perseverance as sustained intention rather than a burst of effort.',
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
      await tester.pumpAndSettle();

      expect(client.requestHistory, hasLength(1));
      expect(client.lastReadingUnitId, 'chapter-001-line-001');
      expect(
        client.lastMessages!.single.content,
        contains('Start the guided chat for the current line.'),
      );
      expect(find.byKey(const ValueKey('guided-chat-sheet')), findsOneWidget);
      expect(
        find.text(
          'This chengyu frames perseverance as sustained intention rather than a burst of effort.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'translation and response feedback Chinese characters open the exploder at support-table size',
    (WidgetTester tester) async {
      await tester.pumpWidget(DaxueApp(client: ChineseFeedbackBackendClient()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter library'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1. 大學'),
        200,
        scrollable: _readingMenuScrollable(),
      );
      await tester.pumpAndSettle();

      final supportTableCharacter = find.byKey(
        const ValueKey('title-support-大學-1-大-0'),
      );
      expect(supportTableCharacter, findsOneWidget);
      final supportTableText = tester.widget<Text>(
        find.descendant(of: supportTableCharacter, matching: find.byType(Text)),
      );

      await tester.tap(find.text('1. 大學'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1. 大學之道'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('line-study-translation-button-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('line-study-translation-button-1')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('line-study-editor-field')),
        'Great learning begins here.',
      );
      await tester.tap(
        find.byKey(const ValueKey('line-study-editor-save-button')),
      );
      await tester.pumpAndSettle();

      final translationFeedbackCharacter = find.byKey(
        const ValueKey('line-study-editor-feedback-character-大-0'),
      );
      expect(translationFeedbackCharacter, findsOneWidget);
      final translationFeedbackText = tester.widget<Text>(
        find.descendant(
          of: translationFeedbackCharacter,
          matching: find.byType(Text),
        ),
      );
      expect(
        translationFeedbackText.style?.fontSize,
        supportTableText.style?.fontSize,
      );

      await tester.tap(translationFeedbackCharacter);
      await tester.pumpAndSettle();

      expect(find.text('Exploded view'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('大'),
        ),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const ValueKey('line-study-response-button-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('line-study-response-button-1')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('line-study-editor-field')),
        'The line opens on an ambitious scale.',
      );
      await tester.tap(
        find.byKey(const ValueKey('line-study-editor-save-button')),
      );
      await tester.pumpAndSettle();

      final responseFeedbackCharacter = find.byKey(
        const ValueKey('line-study-editor-feedback-character-大-0'),
      );
      expect(responseFeedbackCharacter, findsOneWidget);
      final responseFeedbackText = tester.widget<Text>(
        find.descendant(
          of: responseFeedbackCharacter,
          matching: find.byType(Text),
        ),
      );
      expect(
        responseFeedbackText.style?.fontSize,
        supportTableText.style?.fontSize,
      );

      await tester.ensureVisible(responseFeedbackCharacter);
      await tester.pumpAndSettle();
      await tester.tap(responseFeedbackCharacter);
      await tester.pumpAndSettle();

      expect(find.text('Exploded view'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('大'),
        ),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('line-study-response-feedback')),
        findsNothing,
      );
    },
  );

  testWidgets('stores local translation and response notes per line', (
    WidgetTester tester,
  ) async {
    final lineStudyStore = MemoryLineStudyStore();
    final client = RecordingTranslationFeedbackBackendClient();

    Future<void> pumpReader() async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: client,
            bookTitle: 'Demo Book',
            bookId: 'demo-book',
            chapterId: 'chapter-001',
            lineStudyStore: lineStudyStore,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpReader();

    expect(
      find.byKey(const ValueKey('line-study-translation-button-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('line-study-response-button-1')),
      findsOneWidget,
    );
    expect(find.widgetWithText(ChoiceChip, '1'), findsOneWidget);
    _expectLineStudyButtonState(kind: 'translation', order: 1, isSaved: false);
    _expectLineStudyButtonState(kind: 'response', order: 1, isSaved: false);
    expect(find.textContaining('Saved locally:'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('line-study-translation-button-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('line-study-translation-button-1')),
    );
    await tester.pumpAndSettle();
    final lineStudyEditorSheet = find.byKey(
      const ValueKey('line-study-editor-sheet'),
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Translate'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Translate line 1'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.byKey(
          const ValueKey('line-study-editor-reading-unit-天-0'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Heaven and earth are dark and yellow.'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: lineStudyEditorSheet, matching: find.text('Save')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Save and get feedback'),
      ),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('line-study-editor-field')),
      'Heaven and earth begin in mystery.',
    );
    await tester.tap(
      find.byKey(const ValueKey('line-study-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(lineStudyEditorSheet, findsOneWidget);
    expect(client.lastBookId, 'demo-book');
    expect(client.lastChapterId, 'chapter-001');
    expect(client.lastReadingUnitId, 'chapter-001-line-001');
    expect(client.lastMessages, hasLength(1));
    expect(
      client.lastMessages?.single.content,
      contains('Heaven and earth begin in mystery.'),
    );
    expect(
      client.lastMessages?.single.content,
      contains('Evaluate it against the current line only.'),
    );
    expect(
      client.lastMessages?.single.content,
      contains('Respond as a careful researcher, philosopher, and linguist'),
    );
    expect(
      find.byKey(const ValueKey('line-study-editor-feedback')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Feedback'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Saved feedback'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text(
          'Accurate opening move. The main issue is that the cosmological force of the line is understated. Revision: The mandate of Heaven is called nature.',
        ),
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '1 T'), findsOneWidget);
    _expectLineStudyButtonState(kind: 'translation', order: 1, isSaved: true);
    _expectLineStudyButtonState(kind: 'response', order: 1, isSaved: false);
    expect(find.textContaining('Saved locally:'), findsNothing);
    expect(find.text('Translation feedback'), findsNothing);
    expect(
      find.text(
        'Accurate opening move. The main issue is that the cosmological force of the line is understated. Revision: The mandate of Heaven is called nature.',
      ),
      findsNothing,
    );

    final translationOnlyEntries = await lineStudyStore.loadChapterEntries(
      bookId: 'demo-book',
      chapterId: 'chapter-001',
    );
    final savedTranslationOnlyEntry =
        translationOnlyEntries['chapter-001-line-001'];
    expect(savedTranslationOnlyEntry, isNotNull);
    expect(savedTranslationOnlyEntry?.translationFeedback, isEmpty);

    await tester.ensureVisible(
      find.byKey(const ValueKey('line-study-translation-button-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('line-study-translation-button-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Translate'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-study-editor-field')),
          )
          .controller
          ?.text,
      'Heaven and earth begin in mystery.',
    );
    expect(
      find.byKey(const ValueKey('line-study-editor-feedback')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('line-study-editor-field')),
      'Heaven and earth emerge from primal obscurity.',
    );
    await tester.tap(
      find.byKey(const ValueKey('line-study-editor-save-button')),
    );
    await tester.pumpAndSettle();
    expect(
      client.lastMessages?.single.content,
      contains(
        'My previous English translation of this line:\nHeaven and earth begin in mystery.',
      ),
    );
    expect(
      client.lastMessages?.single.content,
      contains(
        'My updated English translation of this line:\nHeaven and earth emerge from primal obscurity.',
      ),
    );
    expect(
      client.lastMessages?.single.content,
      contains(
        'Compare the updated version against both the current line and the previous draft.',
      ),
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('line-study-response-button-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('line-study-response-button-1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: lineStudyEditorSheet, matching: find.text('Respond')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Respond to line 1'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.byKey(
          const ValueKey('line-study-editor-reading-unit-天-0'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Heaven and earth are dark and yellow.'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Your translation'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Heaven and earth emerge from primal obscurity.'),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('line-study-editor-field')),
      'The paired images feel like a compressed opening frame.',
    );
    await tester.tap(
      find.byKey(const ValueKey('line-study-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(lineStudyEditorSheet, findsOneWidget);
    expect(
      client.lastMessages?.single.content,
      contains('Current Classical Chinese line:'),
    );
    expect(
      client.lastMessages?.single.content,
      contains('My translation of this line:'),
    );
    expect(
      client.lastMessages?.single.content,
      contains('Respond as a careful researcher, philosopher, and linguist'),
    );
    expect(
      client.lastMessages?.single.content,
      contains('Avoid generic encouragement.'),
    );
    expect(
      find.byKey(const ValueKey('line-study-editor-feedback')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Feedback'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text('Saved feedback'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: lineStudyEditorSheet,
        matching: find.text(
          'Strong observation of the compressed frame. Push one step further by naming what the paired images are doing in the line. Revision question: what movement or contrast makes the response sharper?',
        ),
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '1 T R'), findsOneWidget);
    _expectLineStudyButtonState(kind: 'translation', order: 1, isSaved: true);
    _expectLineStudyButtonState(kind: 'response', order: 1, isSaved: true);
    expect(client.requestHistory, hasLength(3));
    expect(
      client.lastMessages?.single.content,
      contains('Current Classical Chinese line:\n天地玄黃。'),
    );
    expect(
      client.lastMessages?.single.content,
      contains(
        'My translation of this line:\nHeaven and earth emerge from primal obscurity.',
      ),
    );
    expect(
      client.lastMessages?.single.content,
      contains('The paired images feel like a compressed opening frame.'),
    );
    expect(
      find.text(
        'Strong observation of the compressed frame. Push one step further by naming what the paired images are doing in the line. Revision question: what movement or contrast makes the response sharper?',
      ),
      findsNothing,
    );
    expect(find.textContaining('Saved locally:'), findsNothing);

    final entries = await lineStudyStore.loadChapterEntries(
      bookId: 'demo-book',
      chapterId: 'chapter-001',
    );
    final savedEntry = entries['chapter-001-line-001'];
    expect(savedEntry, isNotNull);
    expect(savedEntry?.responseFeedback, isEmpty);

    await tester.ensureVisible(
      find.byKey(const ValueKey('line-study-response-button-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('line-study-response-button-1')),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-study-editor-field')),
          )
          .controller
          ?.text,
      'The paired images feel like a compressed opening frame.',
    );
    expect(
      find.byKey(const ValueKey('line-study-editor-feedback')),
      findsNothing,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '2'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '2'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('line-number-jump-field')),
          )
          .controller
          ?.text,
      '2',
    );
    _expectLineStudyButtonState(kind: 'translation', order: 2, isSaved: false);
    _expectLineStudyButtonState(kind: 'response', order: 2, isSaved: false);
    expect(find.textContaining('Saved locally:'), findsNothing);

    await pumpReader();

    expect(find.widgetWithText(ChoiceChip, '1 T R'), findsOneWidget);
    expect(find.textContaining('Saved locally:'), findsNothing);
  });

  testWidgets('keeps the translation saved if feedback generation fails', (
    WidgetTester tester,
  ) async {
    final lineStudyStore = MemoryLineStudyStore();
    final client = FailingTranslationFeedbackBackendClient();

    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: client,
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
          lineStudyStore: lineStudyStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('line-study-translation-button-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('line-study-translation-button-1')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('line-study-editor-field')),
      'Heaven and earth begin in mystery.',
    );
    await tester.tap(
      find.byKey(const ValueKey('line-study-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(client.lastBookId, 'demo-book');
    expect(client.lastChapterId, 'chapter-001');
    expect(client.lastReadingUnitId, 'chapter-001-line-001');
    expect(
      find.byKey(const ValueKey('line-study-editor-error')),
      findsOneWidget,
    );

    final entries = await lineStudyStore.loadChapterEntries(
      bookId: 'demo-book',
      chapterId: 'chapter-001',
    );
    final savedEntry = entries['chapter-001-line-001'];
    expect(savedEntry, isNotNull);
    expect(savedEntry?.translation, 'Heaven and earth begin in mystery.');
    expect(savedEntry?.translationFeedback, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '1 T'), findsOneWidget);
    _expectLineStudyButtonState(kind: 'translation', order: 1, isSaved: true);
    _expectLineStudyButtonState(kind: 'response', order: 1, isSaved: false);
    expect(find.textContaining('Saved locally:'), findsNothing);
    expect(find.text('Translation feedback'), findsNothing);
  });

  testWidgets('keeps the response saved if feedback generation fails', (
    WidgetTester tester,
  ) async {
    final lineStudyStore = MemoryLineStudyStore();
    final client = FailingTranslationFeedbackBackendClient();

    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: client,
          bookTitle: 'Demo Book',
          bookId: 'demo-book',
          chapterId: 'chapter-001',
          lineStudyStore: lineStudyStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('line-study-response-button-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('line-study-response-button-1')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('line-study-editor-field')),
      'The paired images feel like a compressed opening frame.',
    );
    await tester.tap(
      find.byKey(const ValueKey('line-study-editor-save-button')),
    );
    await tester.pumpAndSettle();

    expect(client.lastBookId, 'demo-book');
    expect(client.lastChapterId, 'chapter-001');
    expect(client.lastReadingUnitId, 'chapter-001-line-001');
    expect(
      find.byKey(const ValueKey('line-study-editor-error')),
      findsOneWidget,
    );

    final entries = await lineStudyStore.loadChapterEntries(
      bookId: 'demo-book',
      chapterId: 'chapter-001',
    );
    final savedEntry = entries['chapter-001-line-001'];
    expect(savedEntry, isNotNull);
    expect(
      savedEntry?.response,
      'The paired images feel like a compressed opening frame.',
    );
    expect(savedEntry?.responseFeedback, isEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '1 R'), findsOneWidget);
    _expectLineStudyButtonState(kind: 'translation', order: 1, isSaved: false);
    _expectLineStudyButtonState(kind: 'response', order: 1, isSaved: true);
    expect(find.textContaining('Saved locally:'), findsNothing);
    expect(find.text('Response feedback'), findsNothing);
  });

  testWidgets(
    'passes current line translation and response into guided chat context',
    (WidgetTester tester) async {
      final lineStudyStore = MemoryLineStudyStore();
      final bucket = PageStorageBucket();
      await lineStudyStore.saveLineEntry(
        bookId: 'demo-book',
        chapterId: 'chapter-001',
        readingUnitId: 'chapter-001-line-002',
        entry: const LineStudyEntry(
          translation: 'The cosmos is primal and untamed.',
          response: 'The line abruptly widens the scale from earth to cosmos.',
        ),
      );
      final client = RecordingGuidedChatBackendClient();

      await tester.pumpWidget(
        MaterialApp(
          home: PageStorage(
            bucket: bucket,
            child: Builder(
              builder: (context) {
                bucket.writeState(
                  context,
                  1,
                  identifier: 'chapter-reader:demo-book:chapter-001:full',
                );
                return ChapterReaderPage(
                  client: client,
                  bookTitle: 'Demo Book',
                  bookId: 'demo-book',
                  chapterId: 'chapter-001',
                  lineStudyStore: lineStudyStore,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
      await tester.pumpAndSettle();

      expect(client.lastReadingUnitId, 'chapter-001-line-002');
      expect(client.requestHistory, hasLength(1));
      expect(
        client.lastLearnerTranslation,
        'The cosmos is primal and untamed.',
      );
      expect(
        client.lastLearnerResponse,
        'The line abruptly widens the scale from earth to cosmos.',
      );
      expect(
        client.lastMessages!.single.content,
        contains('Current line:\n宇宙洪荒。'),
      );
      expect(
        client.lastMessages!.single.content,
        contains(
          'My translation of this line:\nThe cosmos is primal and untamed.',
        ),
      );
      expect(
        client.lastMessages!.single.content,
        contains(
          'My response to this line:\nThe line abruptly widens the scale from earth to cosmos.',
        ),
      );
    },
  );

  testWidgets(
    'passes previous line translations and responses into guided chat context',
    (WidgetTester tester) async {
      final lineStudyStore = MemoryLineStudyStore();
      final bucket = PageStorageBucket();
      await lineStudyStore.saveLineEntry(
        bookId: 'demo-book',
        chapterId: 'chapter-001',
        readingUnitId: 'chapter-001-line-001',
        entry: const LineStudyEntry(
          translation: 'Heaven and earth begin in mystery.',
          response: 'The paired images feel like a compressed opening frame.',
        ),
      );
      final client = RecordingGuidedChatBackendClient();

      await tester.pumpWidget(
        MaterialApp(
          home: PageStorage(
            bucket: bucket,
            child: Builder(
              builder: (context) {
                bucket.writeState(
                  context,
                  1,
                  identifier: 'chapter-reader:demo-book:chapter-001:full',
                );
                return ChapterReaderPage(
                  client: client,
                  bookTitle: 'Demo Book',
                  bookId: 'demo-book',
                  chapterId: 'chapter-001',
                  lineStudyStore: lineStudyStore,
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
      await tester.pumpAndSettle();

      expect(client.requestHistory, hasLength(1));
      expect(client.lastReadingUnitId, 'chapter-001-line-002');
      expect(client.lastPreviousLines, hasLength(1));
      expect(
        client.lastPreviousLines!.single.readingUnitId,
        'chapter-001-line-001',
      );
      expect(client.lastPreviousLines!.single.order, 1);
      expect(client.lastPreviousLines!.single.text, '天地玄黃。');
      expect(
        client.lastPreviousLines!.single.translationEn,
        'Heaven and earth are dark and yellow.',
      );
      expect(
        client.lastPreviousLines!.single.learnerTranslation,
        'Heaven and earth begin in mystery.',
      );
      expect(
        client.lastPreviousLines!.single.learnerResponse,
        'The paired images feel like a compressed opening frame.',
      );
    },
  );

  testWidgets(
    'chengyu guided chat omits previous lines because each idiom is independent',
    (WidgetTester tester) async {
      final client = ChengyuGuidedChatBackendClient();
      final bucket = PageStorageBucket();

      await tester.pumpWidget(
        MaterialApp(
          home: PageStorage(
            bucket: bucket,
            child: Builder(
              builder: (context) {
                bucket.writeState(
                  context,
                  1,
                  identifier: 'chapter-reader:chengyu-catalog:chapter-001:full',
                );
                return ChapterReaderPage(
                  client: client,
                  bookTitle: '成語目錄',
                  bookId: 'chengyu-catalog',
                  chapterId: 'chapter-001',
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(client.requestHistory, isEmpty);
      expect(client.lastReadingUnitId, isNull);
      expect(client.lastPreviousLines, isNull);

      await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
      await tester.pumpAndSettle();

      expect(client.requestHistory, hasLength(1));
      expect(client.lastReadingUnitId, 'chapter-001-line-002');
      expect(client.lastPreviousLines, isEmpty);
      expect(
        client.lastMessages!.single.content,
        contains('Start the guided chat for the current line.'),
      );
      expect(
        client.lastMessages!.single.content,
        contains('Current line:\n厚积薄发'),
      );

      await tester.enterText(
        find.byKey(const ValueKey('guided-chat-sheet-message-field')),
        'How does this differ from the first idiom?',
      );
      await tester.tap(find.byKey(const ValueKey('guided-chat-send-button')));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(client.lastReadingUnitId, 'chapter-001-line-002');
      expect(client.lastPreviousLines, isEmpty);
      expect(client.requestHistory, hasLength(2));
      expect(
        client.lastMessages!.last.content,
        'How does this differ from the first idiom?',
      );
    },
  );

  testWidgets(
    'tapping linked Hanzi in the exploded view retargets the open sheet',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: ChineseTitleBackendClient(),
            bookTitle: '四書章句集注 : 大學章句',
            bookId: 'da-xue',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.byKey(
        const ValueKey('current-reading-repeat-character-大-0'),
      );
      final chapterLineCharacter = find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == '大',
          description: 'Text("大")',
        ),
      );
      final chapterLineCharacterSize = tester
          .widget<Text>(chapterLineCharacter)
          .style
          ?.fontSize;
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(find.text('Exploded view'), findsOneWidget);
      final backButton = find.byKey(const ValueKey('exploder-back-button'));
      final forwardButton = find.byKey(
        const ValueKey('exploder-forward-button'),
      );
      expect(backButton, findsOneWidget);
      expect(forwardButton, findsOneWidget);
      expect(tester.widget<IconButton>(backButton).onPressed, isNull);
      expect(tester.widget<IconButton>(forwardButton).onPressed, isNull);
      expect(find.text('1 character in the exploder'), findsNothing);
      expect(find.text('Exploder list'), findsNothing);
      expect(find.text('Analysis'), findsNothing);
      expect(find.text('Expression'), findsNothing);
      expect(
        find.byKey(const ValueKey('analysis-tree-row-root')),
        findsOneWidget,
      );
      expect(find.text('├─'), findsNothing);
      expect(find.text('└─'), findsNothing);
      expect(find.text('│'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('大'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('dà (ㄉㄚˋ)'),
        ),
        findsOneWidget,
      );
      final rootCharacter = find.descendant(
        of: find.byKey(const ValueKey('analysis-tree-row-root')),
        matching: find.text('大'),
      );
      expect(tester.widget<Text>(rootCharacter).style?.fontSize, 64);
      expect(find.byKey(const ValueKey('analysis-tree-row-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('analysis-tree-row-1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-0')),
          matching: find.text('rén (ㄖㄣˊ)'),
        ),
        findsOneWidget,
      );
      final branchCharacter = find.descendant(
        of: find.byKey(const ValueKey('analysis-tree-row-0')),
        matching: find.text('人'),
      );
      expect(
        tester.widget<Text>(branchCharacter).style?.fontSize,
        closeTo(chapterLineCharacterSize ?? 0, 0.01),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-0')),
          matching: find.text('person'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1')),
          matching: find.text('yī (ㄧ)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1')),
          matching: find.text('one'),
        ),
        findsOneWidget,
      );
      expect(find.text('人'), findsWidgets);
      expect(find.text('一'), findsWidgets);
      expect(find.text('Synthesis'), findsNothing);
      expect(find.text('Containing characters'), findsOneWidget);
      expect(find.text('tiān (ㄊㄧㄢ)'), findsOneWidget);
      expect(find.text('heaven; sky'), findsOneWidget);
      expect(find.text('fū (ㄈㄨ)'), findsOneWidget);
      expect(find.text('man'), findsOneWidget);
      expect(find.text('Phrase use'), findsOneWidget);
      expect(find.text('dà xué (ㄉㄚˋ ㄒㄩㄝˊ)'), findsOneWidget);
      expect(find.text('Literal gloss: big + study'), findsOneWidget);
      expect(find.text('dà rén (ㄉㄚˋ ㄖㄣˊ)'), findsOneWidget);
      expect(find.text('Literal gloss: big + person'), findsOneWidget);
      expect(find.text('Homophones (same tone)'), findsOneWidget);
      expect(find.text('dài (ㄉㄞˋ)'), findsOneWidget);
      expect(find.text('substitute'), findsOneWidget);
      expect(find.text('Homophones (different tone)'), findsOneWidget);
      expect(find.text('dá (ㄉㄚˊ)'), findsOneWidget);
      expect(find.text('answer'), findsOneWidget);
      final synonyms = find.text('Synonyms');
      await tester.scrollUntilVisible(
        synonyms,
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Meaning Map'), findsNothing);
      expect(synonyms, findsOneWidget);
      expect(find.text('guǎng (ㄍㄨㄤˇ)'), findsOneWidget);
      expect(find.text('broad'), findsOneWidget);
      expect(find.text('廣'), findsOneWidget);
      expect(find.text('Antonyms'), findsOneWidget);
      expect(find.text('xiǎo (ㄒㄧㄠˇ)'), findsOneWidget);
      expect(find.text('small'), findsOneWidget);
      expect(find.text('小'), findsOneWidget);

      final inSheetTarget = find.descendant(
        of: find.byKey(const ValueKey('analysis-tree-row-0')),
        matching: find.text('人'),
      );
      expect(inSheetTarget, findsOneWidget);
      await tester.ensureVisible(inSheetTarget);
      await tester.pumpAndSettle();
      await tester.tap(inSheetTarget);
      await tester.pumpAndSettle();

      final firstRootRow = find
          .byKey(const ValueKey('analysis-tree-row-root'))
          .first;
      expect(
        find.descendant(of: firstRootRow, matching: find.text('人')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstRootRow, matching: find.text('rén (ㄖㄣˊ)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstRootRow, matching: find.text('person')),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(backButton).onPressed, isNotNull);
      expect(tester.widget<IconButton>(forwardButton).onPressed, isNull);

      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('大'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('dà (ㄉㄚˋ)'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(backButton).onPressed, isNull);
      expect(tester.widget<IconButton>(forwardButton).onPressed, isNotNull);

      await tester.tap(forwardButton);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('人'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('rén (ㄖㄣˊ)'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(backButton).onPressed, isNotNull);
      expect(tester.widget<IconButton>(forwardButton).onPressed, isNull);
    },
  );

  testWidgets(
    'analysis tree recursively decomposes known component characters',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: FakeBackendClient(),
            bookTitle: 'Demo Book',
            bookId: 'demo-book',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.byKey(
        const ValueKey('current-reading-repeat-character-天-0'),
      );
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('天'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('tiān (ㄊㄧㄢ)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-root')),
          matching: find.text('heaven; sky'),
        ),
        findsOneWidget,
      );
      expect(find.text('heaven; sky'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-0')),
          matching: find.text('一'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-0')),
          matching: find.text('yī (ㄧ)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-0')),
          matching: find.text('one'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1')),
          matching: find.text('大'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1')),
          matching: find.text('dà (ㄉㄚˋ)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1')),
          matching: find.text('big; great'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1-0')),
          matching: find.text('人'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1-0')),
          matching: find.text('rén (ㄖㄣˊ)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1-0')),
          matching: find.text('person'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1-1')),
          matching: find.text('一'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1-1')),
          matching: find.text('yī (ㄧ)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('analysis-tree-row-1-1')),
          matching: find.text('one'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('numbers the top-level menu in curriculum order', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: CurriculumBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    final daXueLabel = find.text('1. 大學');
    final zhongYongLabel = find.text('2. 中庸');

    await tester.scrollUntilVisible(
      daXueLabel,
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    expect(daXueLabel, findsOneWidget);
    expect(find.text('The Great Learning'), findsWidgets);
    expect(find.text('Start here!'), findsOneWidget);

    await tester.scrollUntilVisible(
      zhongYongLabel,
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    expect(zhongYongLabel, findsOneWidget);
    expect(find.text('The Doctrine of the Mean'), findsWidgets);
  });

  testWidgets(
    'zhong yong chapter cards keep counters in the shared details column',
    (WidgetTester tester) async {
      final client = CurriculumBackendClient();
      final book = await client.fetchBook('zhong-yong');

      await tester.pumpWidget(
        MaterialApp(
          home: BookChaptersPage(
            client: client,
            book: book,
            characterIndex: CharacterIndex.empty(),
            lineStudyStore: MemoryLineStudyStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chapterTitle = find.text('1. 天命之謂性');
      final chapterCountSummary = find.text('5 lines • 109 chars');
      final lineStudySummary = find.text('0 translations • 0 responses');

      expect(chapterTitle, findsOneWidget);
      expect(chapterCountSummary, findsOneWidget);
      expect(lineStudySummary, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: chapterCountSummary,
        ),
        findsNothing,
      );
      expect(
        (tester.getTopLeft(chapterTitle).dx -
                tester.getTopLeft(chapterCountSummary).dx)
            .abs(),
        lessThan(1.0),
      );
      expect(
        (tester.getTopLeft(chapterCountSummary).dx -
                tester.getTopLeft(lineStudySummary).dx)
            .abs(),
        lessThan(1.0),
      );
    },
  );

  testWidgets('renders zhong yong chapter titles in the chapter reader', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChapterReaderPage(
          client: CurriculumBackendClient(),
          bookTitle: '中庸章句',
          bookId: 'zhong-yong',
          chapterId: 'chapter-001',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1. 天命之謂性'), findsOneWidget);
    expect(find.text('5 lines • 109 chars'), findsOneWidget);
    expect(find.text('1. Chapter One'), findsNothing);
  });

  testWidgets('character support table indexes do not wrap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: LongTitleBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. 天地玄黃宇宙洪荒日月盈昃'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    final indexText = tester.widget<Text>(find.text('10'));
    expect(indexText.maxLines, 1);
    expect(indexText.softWrap, isFalse);
  });

  testWidgets(
    'character support table English text and indexes match line translation size',
    (WidgetTester tester) async {
      const translation =
          'The way of great learning lies in illuminating luminous virtue, renewing the people, and resting in the highest good.';

      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: ChineseTitleBackendClient(),
            bookTitle: '四書章句集注 : 大學章句',
            bookId: 'da-xue',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final supportTable = find.byType(Table).last;
      final indexText = tester.widget<Text>(
        find.descendant(of: supportTable, matching: find.text('1')).first,
      );
      final englishText = tester.widget<Text>(
        find.descendant(of: supportTable, matching: find.text('way; path')),
      );
      final translationText = tester.widget<Text>(find.text(translation).first);

      expect(indexText.style?.fontSize, translationText.style?.fontSize);
      expect(englishText.style?.fontSize, translationText.style?.fontSize);
    },
  );

  testWidgets('support table Chinese characters open the exploded view', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: ChineseTitleBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. 大學'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(const ValueKey('title-support-大學-1-大-0'));
    expect(target, findsOneWidget);

    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(find.text('Exploded view'), findsOneWidget);
    expect(find.text('big; great'), findsWidgets);
    expect(
      find.byKey(const ValueKey('analysis-tree-row-root')),
      findsOneWidget,
    );

    final inSheetTarget = find.descendant(
      of: find.byKey(const ValueKey('analysis-tree-row-0')),
      matching: find.text('人'),
    );
    expect(inSheetTarget, findsOneWidget);
    await tester.tap(inSheetTarget);
    await tester.pumpAndSettle();

    final firstRootRow = find
        .byKey(const ValueKey('analysis-tree-row-root'))
        .first;
    expect(
      find.descendant(of: firstRootRow, matching: find.text('人')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstRootRow, matching: find.text('rén (ㄖㄣˊ)')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: firstRootRow, matching: find.text('person')),
      findsOneWidget,
    );

    final backButton = find.byKey(const ValueKey('exploder-back-button'));
    final forwardButton = find.byKey(const ValueKey('exploder-forward-button'));
    expect(tester.widget<IconButton>(backButton).onPressed, isNotNull);
    expect(tester.widget<IconButton>(forwardButton).onPressed, isNull);

    await tester.tap(backButton);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('analysis-tree-row-root')),
        matching: find.text('大'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('analysis-tree-row-root')),
        matching: find.text('dà (ㄉㄚˋ)'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<IconButton>(backButton).onPressed, isNull);
    expect(tester.widget<IconButton>(forwardButton).onPressed, isNotNull);

    await tester.tap(forwardButton);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('analysis-tree-row-root')),
        matching: find.text('人'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('analysis-tree-row-root')),
        matching: find.text('rén (ㄖㄣˊ)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('support table explosions label teachable component units', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      DaxueApp(client: TeachableComponentBackendClient()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1. 德'),
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(const ValueKey('title-support-德-1-德-0'));
    expect(target, findsOneWidget);

    await tester.tap(target);
    await tester.pumpAndSettle();

    final componentRow = find.byKey(const ValueKey('analysis-tree-row-0'));
    expect(componentRow, findsOneWidget);
    expect(
      find.descendant(of: componentRow, matching: find.text('彳')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: componentRow, matching: find.text('Component: 双立人')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: componentRow,
        matching: find.text('Examples: 往 彻 惩 覆'),
      ),
      findsOneWidget,
    );

    final directRow = find.byKey(const ValueKey('analysis-tree-row-1'));
    expect(
      find.descendant(of: directRow, matching: find.text('直')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: directRow, matching: find.text('zhí (ㄓˊ)')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: directRow, matching: find.text('straight; direct')),
      findsOneWidget,
    );
  });

  testWidgets(
    'chapter support table Chinese characters match reading line size',
    (WidgetTester tester) async {
      await tester.pumpWidget(DaxueApp(client: ChineseTitleBackendClient()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter library'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1. 大學'),
        200,
        scrollable: _readingMenuScrollable(),
      );
      await tester.pumpAndSettle();

      final supportTableCharacter = find.byKey(
        const ValueKey('title-support-大學-1-大-0'),
      );
      expect(supportTableCharacter, findsOneWidget);

      final supportTableText = tester.widget<Text>(
        find.descendant(of: supportTableCharacter, matching: find.byType(Text)),
      );

      await tester.tap(find.text('1. 大學'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1. 大學之道'));
      await tester.pumpAndSettle();

      final readingLineCharacter = find.byKey(
        const ValueKey('embedded-reading-line-1-top-character-大-0'),
      );
      expect(readingLineCharacter, findsOneWidget);

      final readingLineText = tester.widget<Text>(
        find.descendant(of: readingLineCharacter, matching: find.byType(Text)),
      );

      expect(supportTableText.style?.fontSize, readingLineText.style?.fontSize);
    },
  );

  testWidgets('shows chengyu counts for the chengyu catalog menu item', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(DaxueApp(client: TenthWorkBackendClient()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enter library'));
    await tester.pumpAndSettle();

    final tenthWorkLabel = find.text('10. 成語目錄');

    await tester.scrollUntilVisible(
      tenthWorkLabel,
      200,
      scrollable: _readingMenuScrollable(),
    );
    await tester.pump();

    expect(tenthWorkLabel, findsOneWidget);
    expect(find.text('Chengyu Catalog'), findsWidgets);
    expect(find.text('99 chengyu'), findsOneWidget);
    expect(find.text('9 chapters • 99 lines • 999 chars'), findsNothing);
  });

  testWidgets('opens current-line chat for expanded chengyu chapters', (
    WidgetTester tester,
  ) async {
    final client = ChengyuGuidedChatBackendClient();
    final book = await client.fetchBook('chengyu-catalog');
    final characterIndex = await client.fetchCharacterIndex();

    await tester.pumpWidget(
      MaterialApp(
        home: BookChaptersPage(
          client: client,
          book: book,
          characterIndex: characterIndex,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1. 学习与积累'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guided-chat-fab')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guided-chat-fab')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('guided-chat-sheet')), findsOneWidget);
    expect(client.requestHistory, hasLength(1));
    expect(
      find.text(
        'This chengyu frames perseverance as sustained intention rather than a burst of effort.',
      ),
      findsOneWidget,
    );
    expect(client.lastBookId, 'chengyu-catalog');
    expect(client.lastChapterId, 'chapter-001');
    expect(client.lastReadingUnitId, 'chapter-001-line-001');
    expect(client.lastMessages, hasLength(1));
    expect(client.requestHistory, hasLength(1));
    expect(
      client.lastMessages!.single.content,
      contains('Start the guided chat for the current line.'),
    );
    expect(
      client.lastMessages!.single.content,
      contains('Current line:\n持之以恒'),
    );
  });
}

class FakeBackendClient implements BackendClient {
  @override
  String get baseUrl => 'http://fake-backend';

  @override
  Future<CharacterIndex> fetchCharacterIndex() async => CharacterIndex(
    entryCount: 29,
    entries: const [
      CharacterEntry(
        character: '參',
        simplified: '参',
        traditional: '參',
        pinyin: ['cān'],
        zhuyin: ['ㄘㄢ'],
        english: ['to take part in, to intervene', 'ginseng'],
      ),
      CharacterEntry(
        character: '考',
        simplified: '考',
        traditional: '考',
        pinyin: ['kǎo'],
        zhuyin: ['ㄎㄠˇ'],
        english: ['to test, to investigate, to examine'],
      ),
      CharacterEntry(
        character: '天',
        simplified: '天',
        traditional: '天',
        pinyin: ['tiān'],
        zhuyin: ['ㄊㄧㄢ'],
        english: ['heaven', 'sky'],
        explosion: CharacterExplosion(
          analysis: CharacterExplosionAnalysis(
            expression: '一 + 大',
            parts: ['一', '大'],
          ),
        ),
      ),
      CharacterEntry(
        character: '大',
        simplified: '大',
        traditional: '大',
        pinyin: ['dà'],
        zhuyin: ['ㄉㄚˋ'],
        english: ['big', 'great'],
        exampleWords: ['大學', '大人'],
        explosion: CharacterExplosion(
          analysis: CharacterExplosionAnalysis(
            expression: '人 + 一',
            parts: ['人', '一'],
          ),
          synthesis: CharacterExplosionSynthesis(
            containingCharacters: ['天', '夫'],
            phraseUse: ['大學', '大人'],
            homophones: CharacterExplosionHomophones(
              sameTone: ['代'],
              differentTone: ['答'],
            ),
          ),
          meaningMap: CharacterExplosionMeaningMap(
            synonyms: ['廣'],
            antonyms: ['小'],
          ),
        ),
      ),
      CharacterEntry(
        character: '人',
        simplified: '人',
        traditional: '人',
        pinyin: ['rén'],
        zhuyin: ['ㄖㄣˊ'],
        english: ['person'],
        explosion: CharacterExplosion(
          analysis: CharacterExplosionAnalysis(expression: '人', parts: ['人']),
        ),
      ),
      CharacterEntry(
        character: '一',
        simplified: '一',
        traditional: '一',
        pinyin: ['yī'],
        zhuyin: ['ㄧ'],
        english: ['one'],
        explosion: CharacterExplosion(
          analysis: CharacterExplosionAnalysis(expression: '一', parts: ['一']),
        ),
      ),
      CharacterEntry(
        character: '学',
        simplified: '学',
        traditional: '學',
        pinyin: ['xué'],
        zhuyin: ['ㄒㄩㄝˊ'],
        english: ['study', 'learning'],
        explosion: CharacterExplosion(
          analysis: CharacterExplosionAnalysis(
            expression: '冖 + 子',
            parts: ['冖', '子'],
          ),
        ),
      ),
      CharacterEntry(
        character: '中',
        simplified: '中',
        traditional: '中',
        pinyin: ['zhōng'],
        zhuyin: ['ㄓㄨㄥ'],
        english: ['center', 'middle'],
      ),
      CharacterEntry(
        character: '庸',
        simplified: '庸',
        traditional: '庸',
        pinyin: ['yōng'],
        zhuyin: ['ㄩㄥ'],
        english: ['ordinary', 'constant'],
      ),
      CharacterEntry(
        character: '道',
        simplified: '道',
        traditional: '道',
        pinyin: ['dào'],
        zhuyin: ['ㄉㄠˋ'],
        english: ['way', 'path'],
      ),
      CharacterEntry(
        character: '五',
        simplified: '五',
        traditional: '五',
        pinyin: ['wǔ'],
        zhuyin: ['ㄨˇ'],
        english: ['five'],
      ),
      CharacterEntry(
        character: '味',
        simplified: '味',
        traditional: '味',
        pinyin: ['wèi'],
        zhuyin: ['ㄨㄟˋ'],
        english: ['taste', 'flavor'],
      ),
      CharacterEntry(
        character: '令',
        simplified: '令',
        traditional: '令',
        pinyin: ['lìng'],
        zhuyin: ['ㄌㄧㄥˋ'],
        english: ['to cause', 'to make'],
      ),
      CharacterEntry(
        character: '爽',
        simplified: '爽',
        traditional: '爽',
        pinyin: ['shuǎng'],
        zhuyin: ['ㄕㄨㄤˇ'],
        english: ['refreshed', 'clear-headed'],
      ),
      CharacterEntry(
        character: '之',
        simplified: '之',
        traditional: '之',
        pinyin: ['zhī'],
        zhuyin: ['ㄓ'],
        english: ['it; possessive marker'],
      ),
      CharacterEntry(
        character: '出',
        simplified: '出',
        traditional: '出',
        pinyin: ['chū'],
        zhuyin: ['ㄔㄨ'],
        english: ['to go out, to issue forth'],
      ),
      CharacterEntry(
        character: '夫',
        simplified: '夫',
        traditional: '夫',
        pinyin: ['fū'],
        zhuyin: ['ㄈㄨ'],
        english: ['man'],
      ),
      CharacterEntry(
        character: '代',
        simplified: '代',
        traditional: '代',
        pinyin: ['dài'],
        zhuyin: ['ㄉㄞˋ'],
        english: ['substitute'],
      ),
      CharacterEntry(
        character: '答',
        simplified: '答',
        traditional: '答',
        pinyin: ['dá'],
        zhuyin: ['ㄉㄚˊ'],
        english: ['answer'],
      ),
      CharacterEntry(
        character: '廣',
        simplified: '广',
        traditional: '廣',
        pinyin: ['guǎng'],
        zhuyin: ['ㄍㄨㄤˇ'],
        english: ['broad'],
      ),
      CharacterEntry(
        character: '小',
        simplified: '小',
        traditional: '小',
        pinyin: ['xiǎo'],
        zhuyin: ['ㄒㄧㄠˇ'],
        english: ['small'],
      ),
      CharacterEntry(
        character: '仰',
        simplified: '仰',
        traditional: '仰',
        pinyin: ['yǎng'],
        zhuyin: ['ㄧㄤˇ'],
        english: ['to look up'],
      ),
      CharacterEntry(
        character: '昂',
        simplified: '昂',
        traditional: '昂',
        pinyin: ['áng'],
        zhuyin: ['ㄤˊ'],
        english: ['high', 'lofty'],
      ),
      CharacterEntry(
        character: '迎',
        simplified: '迎',
        traditional: '迎',
        pinyin: ['yíng'],
        zhuyin: ['ㄧㄥˊ'],
        english: ['to welcome'],
      ),
      CharacterEntry(
        character: '吃',
        simplified: '吃',
        traditional: '吃',
        pinyin: ['chī'],
        zhuyin: ['ㄔ'],
        english: ['to eat'],
        exampleWords: ['吃飯', '吃茶'],
      ),
      CharacterEntry(
        character: '嗎',
        simplified: '吗',
        traditional: '嗎',
        pinyin: ['ma'],
        zhuyin: ['ㄇㄚ˙'],
        english: ['question particle'],
      ),
      CharacterEntry(
        character: '唱',
        simplified: '唱',
        traditional: '唱',
        pinyin: ['chàng'],
        zhuyin: ['ㄔㄤˋ'],
        english: ['to sing'],
      ),
      CharacterEntry(
        character: '卬',
        simplified: '卬',
        traditional: '卬',
        pinyin: ['áng'],
        zhuyin: ['ㄤˊ'],
        english: ['lofty', 'high'],
        exampleWords: ['賜以寶劍卬綬'],
      ),
      CharacterEntry(
        character: '口',
        simplified: '口',
        traditional: '口',
        pinyin: ['kǒu'],
        zhuyin: ['ㄎㄡˇ'],
        english: ['mouth', 'entrance, gate, opening'],
        exampleWords: ['五味令人口爽', '道之出口'],
      ),
    ],
  );

  @override
  Future<CharacterEntry> generateCharacterExplosion(String character) async {
    final trimmedCharacter = character.trim();
    if (trimmedCharacter.isEmpty) {
      throw Exception('Character is required.');
    }

    final characterIndex = await fetchCharacterIndex();
    for (final entry in characterIndex.entries) {
      if (entry.character == trimmedCharacter ||
          entry.simplified == trimmedCharacter ||
          entry.traditional == trimmedCharacter) {
        return entry;
      }
    }

    return CharacterEntry(
      character: trimmedCharacter,
      simplified: trimmedCharacter,
      traditional: trimmedCharacter,
      pinyin: const [],
      zhuyin: const [],
      english: const [],
    );
  }

  @override
  Future<BookDetail> fetchBook(String bookId) async => BookDetail(
    id: bookId,
    title: 'Demo Book',
    chapterCount: 1,
    sourceUrl: 'https://example.com/demo-book',
    sourceProvider: 'fixture',
    chapters: const [
      ChapterSummary(
        id: 'chapter-001',
        order: 1,
        title: 'Chapter One',
        summary: 'Opening lines',
        characterCount: 10,
        readingUnitCount: 2,
      ),
    ],
  );

  @override
  Future<List<BookSummary>> fetchBooks() async => const [
    BookSummary(
      id: 'demo-book',
      title: 'Demo Book',
      chapterCount: 1,
      sourceUrl: 'https://example.com/demo-book',
      sourceProvider: 'fixture',
    ),
  ];

  @override
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId) async =>
      const ChapterDetail(
        id: 'chapter-001',
        order: 1,
        title: 'Chapter One',
        summary: 'Opening lines',
        text: '天地玄黃。宇宙洪荒。',
        characterCount: 10,
        readingUnitCount: 2,
        readingUnits: [
          ReadingUnit(
            id: 'chapter-001-line-001',
            order: 1,
            text: '天地玄黃。',
            translationEn: 'Heaven and earth are dark and yellow.',
            characterCount: 5,
          ),
          ReadingUnit(
            id: 'chapter-001-line-002',
            order: 2,
            text: '宇宙洪荒。',
            translationEn: 'The cosmos is vast and wild.',
            characterCount: 5,
          ),
        ],
      );

  @override
  Future<CharacterComponentsDataset> fetchCharacterComponents() async =>
      CharacterComponentsDataset(
        title: 'Modern Common Character Components',
        standard: 'GF0014-2009',
        groupedComponentCount: 2,
        rawComponentCount: 3,
        entries: [
          CharacterComponentEntry(
            groupId: 1,
            frequencyRank: 291,
            groupOccurrenceCount: 4,
            groupConstructionCount: 4,
            canonicalForm: '卬',
            canonicalName: '昂字底',
            forms: ['卬'],
            variantForms: [],
            names: ['昂字底'],
            sourceExampleCharacters: ['仰', '昂', '迎'],
            memberCount: 2,
          ),
          CharacterComponentEntry(
            groupId: 2,
            frequencyRank: 98,
            groupOccurrenceCount: 12,
            groupConstructionCount: 8,
            canonicalForm: '口',
            canonicalName: '口字旁',
            forms: ['口'],
            variantForms: [],
            names: ['口字旁'],
            sourceExampleCharacters: ['嗎', '唱', '吃'],
            memberCount: 1,
          ),
        ],
      );

  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    return const GuidedChatReply(
      message: GuidedConversationMessage(
        role: 'assistant',
        content:
            'Notice how the line opens with paired images, then return to the text and compare it with the next line.',
      ),
      provider: 'z.ai',
      model: 'glm-5-turbo',
    );
  }
}

class ComponentDecompositionBackendClient extends FakeBackendClient {
  @override
  Future<CharacterIndex> fetchCharacterIndex() async {
    final base = await super.fetchCharacterIndex();
    return CharacterIndex(
      entryCount: base.entryCount + 3,
      entries: [
        ...base.entries,
        const CharacterEntry(
          character: '月',
          simplified: '月',
          traditional: '月',
          pinyin: ['yuè'],
          zhuyin: ['ㄩㄝˋ'],
          english: ['moon', 'month'],
        ),
        const CharacterEntry(
          character: '肉',
          simplified: '肉',
          traditional: '肉',
          pinyin: ['ròu'],
          zhuyin: ['ㄖㄡˋ'],
          english: ['meat', 'flesh'],
        ),
        const CharacterEntry(
          character: '水',
          simplified: '水',
          traditional: '水',
          pinyin: ['shuǐ'],
          zhuyin: ['ㄕㄨㄟˇ'],
          english: ['water, liquid'],
        ),
      ],
    );
  }

  @override
  Future<CharacterComponentsDataset> fetchCharacterComponents() async =>
      CharacterComponentsDataset(
        title: 'Modern Common Character Components',
        standard: 'GF0014-2009',
        groupedComponentCount: 4,
        rawComponentCount: 11,
        entries: [
          CharacterComponentEntry(
            groupId: 302,
            frequencyRank: 5,
            groupOccurrenceCount: 231,
            groupConstructionCount: 231,
            canonicalForm: '水',
            canonicalName: '水',
            forms: ['水', '氵', '氺', '{⿱䒑八}'],
            variantForms: ['氵', '氺', '{⿱䒑八}'],
            names: ['水', '三点水', '水底', '益字头'],
            sourceExampleCharacters: ['冰', '河', '暴', '益'],
            memberCount: 4,
          ),
          CharacterComponentEntry(
            groupId: 409,
            frequencyRank: 7,
            groupOccurrenceCount: 186,
            groupConstructionCount: 179,
            canonicalForm: '月',
            canonicalName: '月',
            forms: ['月', '肉', '⺝', '𱼀'],
            variantForms: ['肉', '⺝', '𱼀'],
            names: ['月', '肉', '青字底', '然左角'],
            sourceExampleCharacters: ['期', '胆', '青', '燃'],
            memberCount: 4,
          ),
          CharacterComponentEntry(
            groupId: 360,
            frequencyRank: 93,
            groupOccurrenceCount: 25,
            groupConstructionCount: 25,
            canonicalForm: '𫜹',
            canonicalName: '雪字底',
            forms: ['𫜹', '𰀂'],
            variantForms: ['𰀂'],
            names: ['雪字底', '虐字底'],
            sourceExampleCharacters: ['归', '雪', '急', '虐'],
            memberCount: 2,
          ),
          CharacterComponentEntry(
            groupId: 500,
            frequencyRank: 292,
            groupOccurrenceCount: 1,
            groupConstructionCount: 1,
            canonicalForm: '{⿱丿𭁨}',
            canonicalName: '奥字头',
            forms: ['{⿱丿𭁨}'],
            variantForms: [],
            names: ['奥字头'],
            sourceExampleCharacters: ['奥'],
            memberCount: 1,
          ),
        ],
      );
}

class RecordingGuidedChatBackendClient extends FakeBackendClient {
  String? lastBookId;
  String? lastChapterId;
  String? lastReadingUnitId;
  String? lastLearnerTranslation;
  String? lastLearnerResponse;
  List<GuidedConversationMessage>? lastMessages;
  List<GuidedChatPreviousLine>? lastPreviousLines;
  final List<List<GuidedConversationMessage>> requestHistory = [];

  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    lastBookId = bookId;
    lastChapterId = chapterId;
    lastReadingUnitId = readingUnitId;
    lastLearnerTranslation = learnerTranslation;
    lastLearnerResponse = learnerResponse;
    lastMessages = List<GuidedConversationMessage>.from(messages);
    lastPreviousLines = List<GuidedChatPreviousLine>.from(previousLines);
    requestHistory.add(List<GuidedConversationMessage>.from(messages));

    final replyContent = requestHistory.length == 1
        ? 'Notice how line 2 reframes the imagery, then compare its movement with the previous line.'
        : 'The second line widens the scale from earth to cosmos, so compare that expansion with the grounded imagery before it.';

    return GuidedChatReply(
      message: GuidedConversationMessage(
        role: 'assistant',
        content: replyContent,
      ),
      provider: 'z.ai',
      model: 'glm-5-turbo',
    );
  }
}

class ChengyuGuidedChatBackendClient extends RecordingGuidedChatBackendClient {
  @override
  Future<BookDetail> fetchBook(String bookId) async {
    if (bookId != 'chengyu-catalog') {
      return super.fetchBook(bookId);
    }

    return const BookDetail(
      id: 'chengyu-catalog',
      title: '成語目錄',
      chapterCount: 1,
      sourceUrl: 'bundled://chengyu-catalog',
      sourceProvider: 'bundled',
      chapters: [
        ChapterSummary(
          id: 'chapter-001',
          order: 1,
          title: '入门常用·学习与积累',
          summary: '持之以恒',
          characterCount: 8,
          readingUnitCount: 2,
        ),
      ],
    );
  }

  @override
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId) async {
    if (bookId != 'chengyu-catalog' || chapterId != 'chapter-001') {
      return super.fetchChapter(bookId, chapterId);
    }

    return const ChapterDetail(
      id: 'chapter-001',
      order: 1,
      title: '入门常用·学习与积累',
      summary: '持之以恒',
      text: '持之以恒\n厚积薄发',
      characterCount: 8,
      readingUnitCount: 2,
      readingUnits: [
        ReadingUnit(
          id: 'chapter-001-line-001',
          order: 1,
          text: '持之以恒',
          category: '学习与积累',
          translationEn: 'to persevere',
          characterCount: 4,
        ),
        ReadingUnit(
          id: 'chapter-001-line-002',
          order: 2,
          text: '厚积薄发',
          category: '学习与积累',
          translationEn: 'to build depth before release',
          characterCount: 4,
        ),
      ],
    );
  }

  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    await super.sendGuidedReadingMessage(
      bookId: bookId,
      chapterId: chapterId,
      readingUnitId: readingUnitId,
      messages: messages,
      learnerTranslation: learnerTranslation,
      learnerResponse: learnerResponse,
      previousLines: previousLines,
    );

    return GuidedChatReply(
      message: GuidedConversationMessage(
        role: 'assistant',
        content: readingUnitId == null
            ? 'Notice how the chapter clusters idioms around disciplined study and cumulative practice, then test one entry against the rest of the set.'
            : 'This chengyu frames perseverance as sustained intention rather than a burst of effort.',
      ),
      provider: 'z.ai',
      model: 'glm-5-turbo',
    );
  }
}

class DelayedGuidedChatBackendClient extends RecordingGuidedChatBackendClient {
  DelayedGuidedChatBackendClient(this._requestGate);

  final Completer<void> _requestGate;

  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    final reply = await super.sendGuidedReadingMessage(
      bookId: bookId,
      chapterId: chapterId,
      readingUnitId: readingUnitId,
      messages: messages,
      learnerTranslation: learnerTranslation,
      learnerResponse: learnerResponse,
      previousLines: previousLines,
    );
    await _requestGate.future;
    return reply;
  }
}

class LongReplyGuidedChatBackendClient
    extends RecordingGuidedChatBackendClient {
  LongReplyGuidedChatBackendClient(this._requestGate);

  final Completer<void> _requestGate;

  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    lastBookId = bookId;
    lastChapterId = chapterId;
    lastReadingUnitId = readingUnitId;
    lastLearnerTranslation = learnerTranslation;
    lastLearnerResponse = learnerResponse;
    lastMessages = List<GuidedConversationMessage>.from(messages);
    lastPreviousLines = List<GuidedChatPreviousLine>.from(previousLines);
    requestHistory.add(List<GuidedConversationMessage>.from(messages));

    await _requestGate.future;

    return GuidedChatReply(
      message: GuidedConversationMessage(
        role: 'assistant',
        content: List<String>.filled(
          80,
          'The guide keeps unpacking the line in detail.',
        ).join('\n'),
      ),
      provider: 'z.ai',
      model: 'glm-5-turbo',
    );
  }
}

class MultiChapterBackendClient extends FakeBackendClient {
  MultiChapterBackendClient({this.chapterCount = 12});

  final int chapterCount;

  late final List<ChapterSummary> _chapters = List<ChapterSummary>.generate(
    chapterCount,
    (index) => ChapterSummary(
      id: 'chapter-${(index + 1).toString().padLeft(3, '0')}',
      order: index + 1,
      title: 'Chapter ${index + 1}',
      summary: 'Summary for chapter ${index + 1}',
      characterCount: 5,
      readingUnitCount: 1,
    ),
  );

  BookDetail get bookDetail => BookDetail(
    id: 'demo-book',
    title: 'Demo Book',
    chapterCount: _chapters.length,
    sourceUrl: 'https://example.com/demo-book',
    sourceProvider: 'fixture',
    chapters: _chapters,
  );

  @override
  Future<BookDetail> fetchBook(String bookId) async => bookDetail;

  @override
  Future<List<BookSummary>> fetchBooks() async => [
    BookSummary(
      id: 'demo-book',
      title: 'Demo Book',
      chapterCount: _chapters.length,
      sourceUrl: 'https://example.com/demo-book',
      sourceProvider: 'fixture',
    ),
  ];

  @override
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId) async {
    final chapter = _chapters.firstWhere((entry) => entry.id == chapterId);
    return ChapterDetail(
      id: chapter.id,
      order: chapter.order,
      title: chapter.title,
      summary: chapter.summary,
      text: '示例文本${chapter.order}。',
      characterCount: chapter.characterCount,
      readingUnitCount: chapter.readingUnitCount,
      readingUnits: [
        ReadingUnit(
          id: '${chapter.id}-line-001',
          order: 1,
          text: '示例文本${chapter.order}。',
          translationEn: 'Translation for chapter ${chapter.order}.',
          characterCount: chapter.characterCount,
        ),
      ],
    );
  }
}

class MultiChapterLineBackendClient extends FakeBackendClient {
  MultiChapterLineBackendClient({this.chapterCount = 8});

  final int chapterCount;

  late final List<ChapterSummary> _chapters = List<ChapterSummary>.generate(
    chapterCount,
    (index) => ChapterSummary(
      id: 'chapter-${(index + 1).toString().padLeft(3, '0')}',
      order: index + 1,
      title: 'Chapter ${index + 1}',
      summary: 'Summary for chapter ${index + 1}',
      characterCount: 12,
      readingUnitCount: 2,
    ),
  );

  @override
  Future<BookDetail> fetchBook(String bookId) async => BookDetail(
    id: 'demo-book',
    title: 'Demo Book',
    chapterCount: _chapters.length,
    sourceUrl: 'https://example.com/demo-book',
    sourceProvider: 'fixture',
    chapters: _chapters,
  );

  @override
  Future<List<BookSummary>> fetchBooks() async => [
    BookSummary(
      id: 'demo-book',
      title: 'Demo Book',
      chapterCount: _chapters.length,
      sourceUrl: 'https://example.com/demo-book',
      sourceProvider: 'fixture',
    ),
  ];

  @override
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId) async {
    final chapter = _chapters.firstWhere((entry) => entry.id == chapterId);
    return ChapterDetail(
      id: chapter.id,
      order: chapter.order,
      title: chapter.title,
      summary: chapter.summary,
      text: '第${chapter.order}章第一行。第${chapter.order}章第二行。',
      characterCount: chapter.characterCount,
      readingUnitCount: chapter.readingUnitCount,
      readingUnits: [
        ReadingUnit(
          id: '${chapter.id}-line-001',
          order: 1,
          text: '第${chapter.order}章第一行。',
          translationEn: 'Translation for chapter ${chapter.order}, line 1.',
          characterCount: 6,
        ),
        ReadingUnit(
          id: '${chapter.id}-line-002',
          order: 2,
          text: '第${chapter.order}章第二行。',
          translationEn: 'Translation for chapter ${chapter.order}, line 2.',
          characterCount: 6,
        ),
      ],
    );
  }
}

class LargeComponentsBackendClient extends FakeBackendClient {
  @override
  Future<CharacterComponentsDataset> fetchCharacterComponents() async =>
      _largeCharacterComponentsDataset(count: 35);
}

class RecordingTranslationFeedbackBackendClient extends FakeBackendClient {
  String? lastBookId;
  String? lastChapterId;
  String? lastReadingUnitId;
  List<GuidedConversationMessage>? lastMessages;
  List<GuidedChatPreviousLine>? lastPreviousLines;
  final List<List<GuidedConversationMessage>> requestHistory = [];

  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    lastBookId = bookId;
    lastChapterId = chapterId;
    lastReadingUnitId = readingUnitId;
    lastMessages = List<GuidedConversationMessage>.from(messages);
    lastPreviousLines = List<GuidedChatPreviousLine>.from(previousLines);
    requestHistory.add(List<GuidedConversationMessage>.from(messages));

    final prompt = messages.single.content;
    final replyContent = prompt.contains('English translation')
        ? 'Accurate opening move. The main issue is that the cosmological force of the line is understated. Revision: The mandate of Heaven is called nature.'
        : 'Strong observation of the compressed frame. Push one step further by naming what the paired images are doing in the line. Revision question: what movement or contrast makes the response sharper?';

    return GuidedChatReply(
      message: GuidedConversationMessage(
        role: 'assistant',
        content: replyContent,
      ),
      provider: 'z.ai',
      model: 'glm-5-turbo',
    );
  }
}

class FailingTranslationFeedbackBackendClient extends FakeBackendClient {
  String? lastBookId;
  String? lastChapterId;
  String? lastReadingUnitId;

  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    lastBookId = bookId;
    lastChapterId = chapterId;
    lastReadingUnitId = readingUnitId;
    throw Exception('Could not fetch translation feedback.');
  }
}

class DaodejingTitleBackendClient extends FakeBackendClient {
  @override
  Future<BookDetail> fetchBook(String bookId) async => BookDetail(
    id: 'daodejing',
    title: 'Dao De Jing',
    chapterCount: 1,
    sourceUrl: 'https://example.com/daodejing',
    sourceProvider: 'fixture',
    chapters: const [
      ChapterSummary(
        id: 'chapter-001',
        order: 1,
        title: '第1章',
        summary: '江海所以能為百谷王者，以其善下之，故能為百谷王',
        characterCount: 37,
        readingUnitCount: 1,
      ),
    ],
  );

  @override
  Future<List<BookSummary>> fetchBooks() async => const [
    BookSummary(
      id: 'daodejing',
      title: 'Dao De Jing',
      chapterCount: 1,
      sourceUrl: 'https://example.com/daodejing',
      sourceProvider: 'fixture',
    ),
  ];

  @override
  Future<ChapterDetail> fetchChapter(
    String bookId,
    String chapterId,
  ) async => const ChapterDetail(
    id: 'chapter-001',
    order: 1,
    title: '第1章',
    summary: '江海所以能為百谷王者，以其善下之，故能為百谷王',
    text: '江海所以能為百谷王者，以其善下之，故能為百谷王。是以聖人欲上民，必以言下之；欲先民，必以身後之。',
    characterCount: 37,
    readingUnitCount: 1,
    readingUnits: [
      ReadingUnit(
        id: 'chapter-001-line-001',
        order: 1,
        text: '江海所以能為百谷王者，以其善下之，故能為百谷王。是以聖人欲上民，必以言下之；欲先民，必以身後之。',
        translationEn:
            'Rivers and seas can be kings of the hundred valleys because they are skilled at staying below them.',
        characterCount: 37,
      ),
    ],
  );
}

class ChineseTitleBackendClient extends FakeBackendClient {
  @override
  Future<BookDetail> fetchBook(String bookId) async => BookDetail(
    id: 'da-xue',
    title: '四書章句集注 : 大學章句',
    chapterCount: 1,
    sourceUrl: 'https://example.com/da-xue',
    sourceProvider: 'fixture',
    chapters: const [
      ChapterSummary(
        id: 'chapter-001',
        order: 1,
        title: '大學之道',
        summary: '在明明德，在親民，在止於至善',
        characterCount: 16,
        readingUnitCount: 1,
      ),
    ],
  );

  @override
  Future<List<BookSummary>> fetchBooks() async => const [
    BookSummary(
      id: 'da-xue',
      title: '四書章句集注 : 大學章句',
      chapterCount: 1,
      sourceUrl: 'https://example.com/da-xue',
      sourceProvider: 'fixture',
    ),
  ];

  @override
  Future<ChapterDetail> fetchChapter(
    String bookId,
    String chapterId,
  ) async => const ChapterDetail(
    id: 'chapter-001',
    order: 1,
    title: '大學之道',
    summary: '在明明德，在親民，在止於至善',
    text: '大學之道，在明明德，在親民，在止於至善。',
    characterCount: 16,
    readingUnitCount: 1,
    readingUnits: [
      ReadingUnit(
        id: 'chapter-001-line-001',
        order: 1,
        text: '大學之道，在明明德，在親民，在止於至善。',
        translationEn:
            'The way of great learning lies in illuminating luminous virtue, renewing the people, and resting in the highest good.',
        characterCount: 16,
      ),
    ],
  );
}

class ReloadingExplosionBackendClient extends ChineseTitleBackendClient {
  int reloadCount = 0;
  String? lastReloadedCharacter;

  @override
  Future<CharacterEntry> generateCharacterExplosion(String character) async {
    reloadCount += 1;
    lastReloadedCharacter = character;

    final baseEntry =
        (await fetchCharacterIndex()).entryFor(character) ??
        await super.generateCharacterExplosion(character);

    return CharacterEntry(
      character: baseEntry.character,
      simplified: baseEntry.simplified,
      traditional: baseEntry.traditional,
      aliases: baseEntry.aliases,
      pinyin: baseEntry.pinyin,
      zhuyin: baseEntry.zhuyin,
      english: ['fresh reload $reloadCount'],
      explosion: CharacterExplosion(
        analysis: CharacterExplosionAnalysis(
          expression: reloadCount == 1 ? '人 + 一 + 新' : '人 + 一 + 再',
          parts: reloadCount == 1 ? ['人', '一', '新'] : ['人', '一', '再'],
        ),
        synthesis: CharacterExplosionSynthesis(
          phraseUse: [reloadCount == 1 ? '刷新一' : '刷新二'],
        ),
      ),
    );
  }
}

class DelayedReloadingExplosionBackendClient
    extends ReloadingExplosionBackendClient {
  final Completer<void> _reloadCompleter = Completer<void>();

  void finishReload() {
    if (_reloadCompleter.isCompleted) {
      return;
    }
    _reloadCompleter.complete();
  }

  @override
  Future<CharacterEntry> generateCharacterExplosion(String character) async {
    await _reloadCompleter.future;
    return super.generateCharacterExplosion(character);
  }
}

class TeachableComponentBackendClient extends FakeBackendClient {
  @override
  Future<CharacterIndex> fetchCharacterIndex() async => CharacterIndex(
    entryCount: 3,
    entries: [
      CharacterEntry(
        character: '德',
        simplified: '德',
        traditional: '德',
        pinyin: ['dé'],
        zhuyin: ['ㄉㄜˊ'],
        english: ['virtue'],
        explosion: CharacterExplosion(
          analysis: CharacterExplosionAnalysis(
            expression: '彳 + 直 + 心',
            parts: ['彳', '直', '心'],
          ),
        ),
      ),
      CharacterEntry(
        character: '直',
        simplified: '直',
        traditional: '直',
        pinyin: ['zhí'],
        zhuyin: ['ㄓˊ'],
        english: ['straight', 'direct'],
      ),
      CharacterEntry(
        character: '心',
        simplified: '心',
        traditional: '心',
        pinyin: ['xīn'],
        zhuyin: ['ㄒㄧㄣ'],
        english: ['heart', 'mind'],
      ),
    ],
  );

  @override
  Future<BookDetail> fetchBook(String bookId) async => BookDetail(
    id: 'teachable-components',
    title: '德',
    chapterCount: 1,
    sourceUrl: 'https://example.com/teachable-components',
    sourceProvider: 'fixture',
    chapters: const [
      ChapterSummary(
        id: 'chapter-001',
        order: 1,
        title: '德',
        summary: 'Virtue',
        characterCount: 1,
        readingUnitCount: 1,
      ),
    ],
  );

  @override
  Future<List<BookSummary>> fetchBooks() async => const [
    BookSummary(
      id: 'teachable-components',
      title: '德',
      chapterCount: 1,
      sourceUrl: 'https://example.com/teachable-components',
      sourceProvider: 'fixture',
    ),
  ];

  @override
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId) async =>
      const ChapterDetail(
        id: 'chapter-001',
        order: 1,
        title: '德',
        summary: 'Virtue',
        text: '德。',
        characterCount: 1,
        readingUnitCount: 1,
        readingUnits: [
          ReadingUnit(
            id: 'chapter-001-line-001',
            order: 1,
            text: '德。',
            translationEn: 'Virtue.',
            characterCount: 1,
          ),
        ],
      );

  @override
  Future<CharacterComponentsDataset> fetchCharacterComponents() async =>
      const CharacterComponentsDataset(
        title: 'Modern Common Character Components',
        standard: 'GF0014-2009',
        groupedComponentCount: 1,
        rawComponentCount: 1,
        entries: [
          CharacterComponentEntry(
            groupId: 1,
            frequencyRank: 120,
            groupOccurrenceCount: 4,
            groupConstructionCount: 4,
            canonicalForm: '彳',
            canonicalName: '双立人',
            forms: ['彳'],
            variantForms: [],
            names: ['双立人'],
            sourceExampleCharacters: ['往', '彻', '惩', '覆'],
            memberCount: 1,
          ),
        ],
      );
}

class ChineseGuidedChatBackendClient extends ChineseTitleBackendClient {
  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    return const GuidedChatReply(
      message: GuidedConversationMessage(
        role: 'assistant',
        content: '大字先抓住，再回到句子。',
      ),
      provider: 'z.ai',
      model: 'glm-5-turbo',
    );
  }
}

class ChineseFeedbackBackendClient extends ChineseTitleBackendClient {
  @override
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  }) async {
    final prompt = messages.single.content;
    final replyContent = prompt.contains('English translation')
        ? '大字先抓，再收紧英文。'
        : '大字先扣住，再收紧论点。';

    return GuidedChatReply(
      message: GuidedConversationMessage(
        role: 'assistant',
        content: replyContent,
      ),
      provider: 'z.ai',
      model: 'glm-5-turbo',
    );
  }
}

class CurriculumBackendClient extends FakeBackendClient {
  @override
  Future<List<BookSummary>> fetchBooks() async => const [
    BookSummary(
      id: 'zhong-yong',
      title: '中庸章句',
      chapterCount: 1,
      sourceUrl: 'https://example.com/zhong-yong',
      sourceProvider: 'fixture',
    ),
    BookSummary(
      id: 'da-xue',
      title: '四書章句集注 : 大學章句',
      chapterCount: 1,
      sourceUrl: 'https://example.com/da-xue',
      sourceProvider: 'fixture',
    ),
  ];

  @override
  Future<BookDetail> fetchBook(String bookId) async {
    switch (bookId) {
      case 'da-xue':
        return BookDetail(
          id: 'da-xue',
          title: '四書章句集注 : 大學章句',
          chapterCount: 1,
          sourceUrl: 'https://example.com/da-xue',
          sourceProvider: 'fixture',
          chapters: const [
            ChapterSummary(
              id: 'chapter-001',
              order: 1,
              title: '大學之道',
              summary: '在明明德，在親民，在止於至善',
              characterCount: 16,
              readingUnitCount: 1,
            ),
          ],
        );
      case 'zhong-yong':
        return BookDetail(
          id: 'zhong-yong',
          title: '中庸章句',
          chapterCount: 1,
          sourceUrl: 'https://example.com/zhong-yong',
          sourceProvider: 'fixture',
          chapters: const [
            ChapterSummary(
              id: 'chapter-001',
              order: 1,
              title: '天命之謂性',
              summary: '',
              characterCount: 109,
              readingUnitCount: 5,
            ),
          ],
        );
      default:
        return super.fetchBook(bookId);
    }
  }

  @override
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId) async {
    switch (bookId) {
      case 'zhong-yong':
        return const ChapterDetail(
          id: 'chapter-001',
          order: 1,
          title: '天命之謂性',
          summary: '',
          text:
              '天命之謂性，率性之謂道，脩道之謂教。\n道也者，不可須臾離也，可離非道也。是故君子戒慎乎其所不睹，恐懼乎其所不聞。\n莫見乎隱，莫顯乎微，故君子慎其獨也。\n喜怒哀樂之未發，謂之中；發而皆中節，謂之和。中也者，天下之大本也；和也者，天下之達道也。\n致中和，天地位焉，萬物育焉。',
          characterCount: 109,
          readingUnitCount: 5,
          readingUnits: [
            ReadingUnit(
              id: 'chapter-001-line-001',
              order: 1,
              text: '天命之謂性，率性之謂道，脩道之謂教。',
              translationEn:
                  'What Heaven has conferred is called nature; following that nature is called the Way; cultivating the Way is called teaching.',
              characterCount: 15,
            ),
            ReadingUnit(
              id: 'chapter-001-line-002',
              order: 2,
              text: '道也者，不可須臾離也，可離非道也。是故君子戒慎乎其所不睹，恐懼乎其所不聞。',
              translationEn:
                  'The Way cannot be left for an instant; if it can be left, it is not the Way.',
              characterCount: 32,
            ),
            ReadingUnit(
              id: 'chapter-001-line-003',
              order: 3,
              text: '莫見乎隱，莫顯乎微，故君子慎其獨也。',
              translationEn:
                  'Nothing is more visible than what is hidden, so the gentleman is watchful over himself when alone.',
              characterCount: 15,
            ),
            ReadingUnit(
              id: 'chapter-001-line-004',
              order: 4,
              text: '喜怒哀樂之未發，謂之中；發而皆中節，謂之和。中也者，天下之大本也；和也者，天下之達道也。',
              translationEn:
                  'Before joy, anger, sorrow, and pleasure are aroused, there is equilibrium; when aroused and all in due measure, there is harmony.',
              characterCount: 36,
            ),
            ReadingUnit(
              id: 'chapter-001-line-005',
              order: 5,
              text: '致中和，天地位焉，萬物育焉。',
              translationEn:
                  'When equilibrium and harmony are brought to completion, Heaven and Earth take their proper places and the ten thousand things are nourished.',
              characterCount: 11,
            ),
          ],
        );
      default:
        return super.fetchChapter(bookId, chapterId);
    }
  }
}

class TenthWorkBackendClient extends FakeBackendClient {
  static const Map<String, String> _titlesByBookId = {
    'da-xue': '四書章句集注 : 大學章句',
    'zhong-yong': '四書章句集注 : 中庸章句',
    'lunyu': '四書章句集注 : 論語集注',
    'mengzi': '四書章句集注 : 孟子集注',
    'sunzi-bingfa': '孫子兵法',
    'daodejing': '道德經',
    'san-zi-jing': '三字經',
    'qian-zi-wen': '千字文',
    'sanguo-yanyi': '三國演義',
    'chengyu-catalog': '成語目錄',
  };

  @override
  Future<List<BookSummary>> fetchBooks() async => _titlesByBookId.entries
      .map(
        (entry) => BookSummary(
          id: entry.key,
          title: entry.value,
          chapterCount: entry.key == 'chengyu-catalog' ? 9 : 2,
          sourceUrl: 'https://example.com/${entry.key}',
          sourceProvider: 'fixture',
        ),
      )
      .toList();

  @override
  Future<BookDetail> fetchBook(String bookId) async {
    final title = _titlesByBookId[bookId];
    if (title == null) {
      return super.fetchBook(bookId);
    }

    if (bookId == 'chengyu-catalog') {
      return _buildBookDetail(
        id: bookId,
        title: title,
        chapterCount: 9,
        lineCount: 99,
        characterCount: 999,
      );
    }

    return _buildBookDetail(
      id: bookId,
      title: title,
      chapterCount: 2,
      lineCount: 3,
      characterCount: 20,
    );
  }

  BookDetail _buildBookDetail({
    required String id,
    required String title,
    required int chapterCount,
    required int lineCount,
    required int characterCount,
  }) {
    return BookDetail(
      id: id,
      title: title,
      chapterCount: chapterCount,
      sourceUrl: 'https://example.com/$id',
      sourceProvider: 'fixture',
      chapters: [
        ChapterSummary(
          id: 'chapter-001',
          order: 1,
          title: '',
          summary: '',
          characterCount: characterCount,
          readingUnitCount: lineCount,
        ),
      ],
    );
  }
}

class LongTitleBackendClient extends FakeBackendClient {
  static const String _title = '天地玄黃宇宙洪荒日月盈昃';

  @override
  Future<List<BookSummary>> fetchBooks() async => const [
    BookSummary(
      id: 'long-title-book',
      title: _title,
      chapterCount: 1,
      sourceUrl: 'https://example.com/long-title-book',
      sourceProvider: 'fixture',
    ),
  ];

  @override
  Future<BookDetail> fetchBook(String bookId) async => const BookDetail(
    id: 'long-title-book',
    title: _title,
    chapterCount: 1,
    sourceUrl: 'https://example.com/long-title-book',
    sourceProvider: 'fixture',
    chapters: [
      ChapterSummary(
        id: 'chapter-001',
        order: 1,
        title: 'Chapter One',
        summary: 'Opening lines',
        characterCount: 10,
        readingUnitCount: 2,
      ),
    ],
  );
}
