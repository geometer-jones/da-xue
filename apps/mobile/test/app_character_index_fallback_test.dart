import 'dart:convert';

import 'package:daxue_mobile/src/app.dart';
import 'package:daxue_mobile/src/backend_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _readingMenuScrollable() => find.descendant(
  of: find.byType(ReadingMenuPage),
  matching: find.byType(Scrollable),
);

Future<void> _pumpBriefly(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'readings still load when the character index endpoint is unavailable',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        DaxueApp(client: _buildClientWithMissingCharacterIndex()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter library'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1. Demo Book'),
        200,
        scrollable: _readingMenuScrollable(),
      );
      await tester.pumpAndSettle();

      expect(find.text('0. 參考：漢字部件'), findsWidgets);
      expect(find.text('漢'), findsOneWidget);
      expect(find.text('1. Demo Book'), findsWidgets);
      expect(find.text('1 chapter • 1 line • 4 chars'), findsOneWidget);
    },
  );

  testWidgets(
    'component examples fall back to raw characters when the character index endpoint is unavailable',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        DaxueApp(client: _buildClientWithMissingCharacterIndex()),
      );
      await _pumpBriefly(tester);

      await tester.tap(find.text('Enter library'));
      await _pumpBriefly(tester);

      await tester.tap(find.text('0. 參考：漢字部件').first);
      await _pumpBriefly(tester);

      await tester.tap(find.text('Chapter 1'));
      await _pumpBriefly(tester);

      final exampleCharacter = find.byKey(
        const ValueKey('component-example-1-0-地-0'),
      );
      expect(exampleCharacter, findsOneWidget);
      expect(find.text('地'), findsOneWidget);
      expect(find.textContaining('ㄉㄧˋ'), findsNothing);
      expect(find.textContaining('earth'), findsNothing);

      await tester.tap(exampleCharacter);
      await _pumpBriefly(tester);

      expect(find.text('Exploded view'), findsOneWidget);
      expect(
        find.text('No exploded view is available for 地 yet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'exploded view falls back gracefully when the character index endpoint is unavailable',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderPage(
            client: _buildClientWithMissingCharacterIndex(),
            bookTitle: 'Demo Book',
            bookId: 'demo-book',
            chapterId: 'chapter-001',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final target = find.byKey(
        const ValueKey('current-reading-character-天-0'),
      );
      expect(target, findsOneWidget);

      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(find.text('Exploded view'), findsOneWidget);
      expect(
        find.text('No exploded view is available for 天 yet.'),
        findsOneWidget,
      );
    },
  );
}

BackendClient _buildClientWithMissingCharacterIndex() {
  return HttpBackendClient(
    baseUrl: 'http://backend.test',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      switch (path) {
        case '/api/v1/books':
          return _jsonResponse({
            'books': [
              {
                'id': 'demo-book',
                'title': 'Demo Book',
                'chapterCount': 1,
                'sourceUrl': 'https://example.com/demo-book',
                'sourceProvider': 'fixture',
              },
            ],
          });
        case '/api/v1/books/demo-book':
          return _jsonResponse({
            'book': {
              'id': 'demo-book',
              'title': 'Demo Book',
              'chapterCount': 1,
              'sourceUrl': 'https://example.com/demo-book',
              'sourceProvider': 'fixture',
              'chapters': [
                {
                  'id': 'chapter-001',
                  'order': 1,
                  'title': 'Chapter One',
                  'summary': 'Opening lines',
                  'characterCount': 4,
                  'readingUnitCount': 1,
                },
              ],
            },
          });
        case '/api/v1/books/demo-book/chapters/chapter-001':
          return _jsonResponse({
            'chapter': {
              'id': 'chapter-001',
              'order': 1,
              'title': 'Chapter One',
              'summary': 'Opening lines',
              'text': '天地。',
              'characterCount': 4,
              'readingUnitCount': 1,
              'readingUnits': [
                {
                  'id': 'chapter-001-line-001',
                  'order': 1,
                  'text': '天地。',
                  'translationEn': 'Heaven and earth.',
                  'characterCount': 4,
                },
              ],
            },
          });
        case '/api/v1/character-components':
          return _jsonResponse({
            'dataset': {
              'title': 'Character Components',
              'standard': 'fixture',
              'groupedComponentCount': 1,
              'rawComponentCount': 1,
              'entries': [
                {
                  'groupId': 1,
                  'frequencyRank': 1,
                  'groupOccurrenceCount': 1,
                  'groupConstructionCount': 1,
                  'canonicalForm': '天',
                  'canonicalName': 'heaven',
                  'forms': ['天'],
                  'variantForms': const [],
                  'names': ['heaven'],
                  'sourceExampleCharacters': ['地'],
                  'memberCount': 1,
                },
              ],
            },
          });
        case '/api/v1/characters':
          return _jsonResponse({
            'service': 'api',
            'environment': 'development',
            'message': 'Da Xue API is running',
          });
        default:
          return http.Response('not found', 404);
      }
    }),
  );
}

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json'},
  );
}
