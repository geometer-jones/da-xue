import 'dart:convert';

import 'package:daxue_mobile/src/backend_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('resolveBackendBaseUrl prefers an explicit base URL', () {
    expect(
      resolveBackendBaseUrl(
        explicitBaseUrl: ' http://backend.test ',
        configuredBaseUrl: 'http://ignored.test',
        isWeb: true,
        currentUri: Uri.parse('http://localhost:53541/'),
      ),
      'http://backend.test',
    );
  });

  test(
    'resolveBackendBaseUrl uses localhost port 8080 for web debug sessions',
    () {
      expect(
        resolveBackendBaseUrl(
          isWeb: true,
          isDebugMode: true,
          currentUri: Uri.parse('http://localhost:54321/'),
        ),
        'http://localhost:8080',
      );
    },
  );

  test(
    'resolveBackendBaseUrl preserves same-origin web URLs outside local debug',
    () {
      expect(
        resolveBackendBaseUrl(
          isWeb: true,
          isDebugMode: false,
          currentUri: Uri.parse('https://app.example.com/library'),
        ),
        'https://app.example.com',
      );
    },
  );

  test('sendGuidedReadingMessage omits previousLines when empty', () async {
    final client = HttpBackendClient(
      baseUrl: 'http://backend.test',
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'http://backend.test/api/v1/guided-chat',
        );
        expect(request.method, 'POST');

        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['context'], {
          'bookId': 'demo',
          'chapterId': 'chapter-001',
          'readingUnitId': 'line-001',
        });
        expect(payload['messages'], [
          {'role': 'user', 'content': 'Help me check this translation.'},
        ]);
        expect(payload.containsKey('previousLines'), isFalse);

        return http.Response(
          jsonEncode({
            'reply': {'role': 'assistant', 'content': 'Looks good.'},
            'provider': 'z.ai',
            'model': 'glm-5-turbo',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final reply = await client.sendGuidedReadingMessage(
      bookId: 'demo',
      chapterId: 'chapter-001',
      readingUnitId: 'line-001',
      messages: const [
        GuidedConversationMessage(
          role: 'user',
          content: 'Help me check this translation.',
        ),
      ],
    );

    expect(reply.message.content, 'Looks good.');
  });

  test(
    'sendGuidedReadingMessage omits readingUnitId when context is chapter-level',
    () async {
      final client = HttpBackendClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://backend.test/api/v1/guided-chat',
          );
          expect(request.method, 'POST');

          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['context'], {
            'bookId': 'demo',
            'chapterId': 'chapter-001',
          });
          expect(payload['messages'], [
            {'role': 'user', 'content': 'What sets up this chapter?'},
          ]);

          return http.Response(
            jsonEncode({
              'reply': {
                'role': 'assistant',
                'content': 'The opening establishes the chapter scale.',
              },
              'provider': 'z.ai',
              'model': 'glm-5-turbo',
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final reply = await client.sendGuidedReadingMessage(
        bookId: 'demo',
        chapterId: 'chapter-001',
        messages: const [
          GuidedConversationMessage(
            role: 'user',
            content: 'What sets up this chapter?',
          ),
        ],
      );

      expect(
        reply.message.content,
        'The opening establishes the chapter scale.',
      );
    },
  );

  test(
    'sendGuidedReadingMessage includes learner translation and response in context when present',
    () async {
      final client = HttpBackendClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://backend.test/api/v1/guided-chat',
          );
          expect(request.method, 'POST');

          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['context'], {
            'bookId': 'demo',
            'chapterId': 'chapter-001',
            'readingUnitId': 'line-001',
            'learnerTranslation': 'Heaven and earth begin in mystery.',
            'learnerResponse':
                'The paired images feel like a compressed opening frame.',
          });
          expect(payload['messages'], [
            {'role': 'user', 'content': 'How close is this reading?'},
          ]);

          return http.Response(
            jsonEncode({
              'reply': {
                'role': 'assistant',
                'content': 'Stay closer to the paired images in the line.',
              },
              'provider': 'z.ai',
              'model': 'glm-5-turbo',
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final reply = await client.sendGuidedReadingMessage(
        bookId: 'demo',
        chapterId: 'chapter-001',
        readingUnitId: 'line-001',
        messages: const [
          GuidedConversationMessage(
            role: 'user',
            content: 'How close is this reading?',
          ),
        ],
        learnerTranslation: 'Heaven and earth begin in mystery.',
        learnerResponse:
            'The paired images feel like a compressed opening frame.',
      );

      expect(
        reply.message.content,
        'Stay closer to the paired images in the line.',
      );
    },
  );

  test(
    'sendGuidedReadingMessage includes open line and character component in context when present',
    () async {
      final client = HttpBackendClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://backend.test/api/v1/guided-chat',
          );
          expect(request.method, 'POST');

          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['context'], {
            'bookId': 'demo',
            'chapterId': 'chapter-001',
            'readingUnitId': 'line-001',
            'openLine': '天地玄黃。',
            'characterComponent': '口',
          });

          return http.Response(
            jsonEncode({
              'reply': {
                'role': 'assistant',
                'content': 'The character component is doing useful work here.',
              },
              'provider': 'z.ai',
              'model': 'glm-5-turbo',
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final reply = await client.sendGuidedReadingMessage(
        bookId: 'demo',
        chapterId: 'chapter-001',
        readingUnitId: 'line-001',
        openLine: '天地玄黃。',
        characterComponent: '口',
        messages: const [
          GuidedConversationMessage(
            role: 'user',
            content: 'Why does this symbol matter here?',
          ),
        ],
      );

      expect(
        reply.message.content,
        'The character component is doing useful work here.',
      );
    },
  );

  test('fetchCharacterIndex accepts direct payload shapes', () async {
    final client = HttpBackendClient(
      baseUrl: 'http://backend.test',
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'http://backend.test/api/v1/characters');
        return http.Response(
          jsonEncode({
            'entryCount': 1,
            'entries': [
              {
                'character': '学',
                'simplified': '学',
                'traditional': '學',
                'aliases': ['斈'],
                'pinyin': ['xue2'],
                'zhuyin': ['ㄒㄩㄝˊ'],
                'english': ['to study'],
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final index = await client.fetchCharacterIndex();

    expect(index.entryCount, 1);
    expect(index.entries, hasLength(1));
    expect(index.entries.single.character, '学');
    expect(index.entries.single.aliases, ['斈']);
    expect(index.entryFor('斈')?.character, '学');
  });

  test(
    'generateCharacterExplosion posts to the character explosion route',
    () async {
      final client = HttpBackendClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://backend.test/api/v1/characters/%E5%AD%B8/explosion',
          );
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), isEmpty);

          return http.Response(
            jsonEncode({
              'character': {
                'character': '学',
                'simplified': '学',
                'traditional': '學',
                'aliases': ['斈'],
                'pinyin': ['xué'],
                'zhuyin': ['ㄒㄩㄝˊ'],
                'english': ['study', 'learning'],
                'explosion': {
                  'analysis': {
                    'expression': '子 + 冖 + 爻',
                    'parts': ['子', '冖', '爻'],
                  },
                },
              },
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final entry = await client.generateCharacterExplosion('學');

      expect(entry.character, '学');
      expect(entry.traditional, '學');
      expect(entry.aliases, ['斈']);
      expect(entry.explosion.analysis.expression, '子 + 冖 + 爻');
      expect(entry.explosion.analysis.parts, ['子', '冖', '爻']);
    },
  );

  test(
    'fetchCharacterIndex throws BackendException for null index payloads',
    () async {
      final client = HttpBackendClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({'index': null}),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      await expectLater(
        client.fetchCharacterIndex(),
        throwsA(
          isA<BackendException>().having(
            (error) => error.message,
            'message',
            'Backend response is missing "index".',
          ),
        ),
      );
    },
  );

  test(
    'sendGuidedReadingMessage throws BackendException for empty error responses',
    () async {
      final client = HttpBackendClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((_) async {
          return http.Response('', 405);
        }),
      );

      await expectLater(
        client.sendGuidedReadingMessage(
          bookId: 'demo',
          chapterId: 'chapter-001',
          messages: const [
            GuidedConversationMessage(role: 'user', content: 'hi'),
          ],
        ),
        throwsA(
          isA<BackendException>().having(
            (error) => error.message,
            'message',
            'Backend returned status 405 with an empty response body.',
          ),
        ),
      );
    },
  );

  test(
    'sendGuidedReadingMessage throws BackendException for invalid JSON error responses',
    () async {
      final client = HttpBackendClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((_) async {
          return http.Response('<html>bad gateway</html>', 502);
        }),
      );

      await expectLater(
        client.sendGuidedReadingMessage(
          bookId: 'demo',
          chapterId: 'chapter-001',
          messages: const [
            GuidedConversationMessage(role: 'user', content: 'hi'),
          ],
        ),
        throwsA(
          isA<BackendException>().having(
            (error) => error.message,
            'message',
            'Backend returned status 502 with invalid JSON.',
          ),
        ),
      );
    },
  );
}
