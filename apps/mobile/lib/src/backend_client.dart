import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract class BackendClient {
  Future<List<BookSummary>> fetchBooks();
  Future<BookDetail> fetchBook(String bookId);
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId);
  Future<CharacterIndex> fetchCharacterIndex();
  Future<CharacterEntry> generateCharacterExplosion(String character);
  Future<CharacterComponentsDataset> fetchCharacterComponents();
  Future<GuidedChatReply> sendGuidedReadingMessage({
    required String bookId,
    required String chapterId,
    String? readingUnitId,
    required List<GuidedConversationMessage> messages,
    String learnerTranslation = '',
    String learnerResponse = '',
    List<GuidedChatPreviousLine> previousLines = const [],
  });

  String get baseUrl;
}

String resolveBackendBaseUrl({
  String? explicitBaseUrl,
  String? configuredBaseUrl,
  bool? isWeb,
  bool? isDebugMode,
  Uri? currentUri,
  TargetPlatform? defaultPlatform,
}) {
  final resolvedConfiguredBaseUrl =
      configuredBaseUrl ?? const String.fromEnvironment('API_BASE_URL');
  final resolvedIsWeb = isWeb ?? kIsWeb;
  final resolvedIsDebugMode = isDebugMode ?? kDebugMode;
  final resolvedDefaultPlatform = defaultPlatform ?? defaultTargetPlatform;
  final trimmedExplicitBaseUrl = explicitBaseUrl?.trim() ?? '';
  if (trimmedExplicitBaseUrl.isNotEmpty) {
    return trimmedExplicitBaseUrl;
  }

  if (resolvedConfiguredBaseUrl.isNotEmpty) {
    return resolvedConfiguredBaseUrl;
  }

  if (resolvedIsWeb) {
    final resolvedCurrentUri = currentUri ?? Uri.base;
    if (resolvedIsDebugMode &&
        _shouldUseLocalWebDebugApiOrigin(resolvedCurrentUri)) {
      return Uri(
        scheme: 'http',
        host: resolvedCurrentUri.host,
        port: 8080,
      ).origin;
    }

    return resolvedCurrentUri.origin;
  }

  switch (resolvedDefaultPlatform) {
    case TargetPlatform.android:
      return 'http://10.0.2.2:8080';
    default:
      return 'http://127.0.0.1:8080';
  }
}

bool _shouldUseLocalWebDebugApiOrigin(Uri currentUri) {
  const localHosts = {'localhost', '127.0.0.1', '0.0.0.0', '::1'};
  return localHosts.contains(currentUri.host) && currentUri.port != 8080;
}

class HttpBackendClient implements BackendClient {
  HttpBackendClient({String? baseUrl, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      _baseUrl = resolveBackendBaseUrl(explicitBaseUrl: baseUrl);

  final http.Client _httpClient;
  final String _baseUrl;

  @override
  String get baseUrl => _baseUrl;

  @override
  Future<List<BookSummary>> fetchBooks() async {
    final payload = await _getJson('/api/v1/books');
    final books = payload['books'] as List<dynamic>? ?? const [];
    return books
        .map((entry) => BookSummary.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<BookDetail> fetchBook(String bookId) async {
    final payload = await _getJson('/api/v1/books/$bookId');
    return BookDetail.fromJson(_readNestedObject(payload, 'book'));
  }

  @override
  Future<ChapterDetail> fetchChapter(String bookId, String chapterId) async {
    final payload = await _getJson('/api/v1/books/$bookId/chapters/$chapterId');
    return ChapterDetail.fromJson(_readNestedObject(payload, 'chapter'));
  }

  @override
  Future<CharacterIndex> fetchCharacterIndex() async {
    final payload = await _getJson('/api/v1/characters');
    return CharacterIndex.fromJson(
      _readNestedObject(
        payload,
        'index',
        fallbackKeys: const {'entries', 'entryCount'},
      ),
    );
  }

  @override
  Future<CharacterEntry> generateCharacterExplosion(String character) async {
    final trimmedCharacter = character.trim();
    if (trimmedCharacter.isEmpty) {
      throw BackendException('Character is required.');
    }

    final payload = await _postJson(
      '/api/v1/characters/${Uri.encodeComponent(trimmedCharacter)}/explosion',
      const {},
    );
    return CharacterEntry.fromJson(
      _readNestedObject(
        payload,
        'character',
        fallbackKeys: const {
          'character',
          'simplified',
          'traditional',
          'explosion',
        },
      ),
    );
  }

  @override
  Future<CharacterComponentsDataset> fetchCharacterComponents() async {
    final payload = await _getJson('/api/v1/character-components');
    return CharacterComponentsDataset.fromJson(
      _readNestedObject(
        payload,
        'dataset',
        fallbackKeys: const {
          'entries',
          'groupedComponentCount',
          'rawComponentCount',
        },
      ),
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
    final trimmedReadingUnitId = readingUnitId?.trim() ?? '';
    final trimmedLearnerTranslation = learnerTranslation.trim();
    final trimmedLearnerResponse = learnerResponse.trim();
    final context = <String, dynamic>{'bookId': bookId, 'chapterId': chapterId};
    if (trimmedReadingUnitId.isNotEmpty) {
      context['readingUnitId'] = trimmedReadingUnitId;
    }
    if (trimmedLearnerTranslation.isNotEmpty) {
      context['learnerTranslation'] = trimmedLearnerTranslation;
    }
    if (trimmedLearnerResponse.isNotEmpty) {
      context['learnerResponse'] = trimmedLearnerResponse;
    }

    final body = <String, dynamic>{
      'context': context,
      'messages': messages.map((message) => message.toJson()).toList(),
    };
    if (previousLines.isNotEmpty) {
      body['previousLines'] = previousLines
          .map((line) => line.toJson())
          .toList();
    }

    final payload = await _postJson('/api/v1/guided-chat', body);

    return GuidedChatReply.fromJson(payload);
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final response = await _httpClient.get(
      Uri.parse('$_baseUrl$path'),
      headers: const {'accept': 'application/json'},
    );
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _httpClient.post(
      Uri.parse('$_baseUrl$path'),
      headers: const {
        'accept': 'application/json',
        'content-type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _decodeJsonResponse(response);
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response response) {
    final responseBody = utf8.decode(response.bodyBytes);
    final trimmedBody = responseBody.trim();

    if (trimmedBody.isEmpty) {
      throw BackendException(
        'Backend returned status ${response.statusCode} with an empty response body.',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmedBody);
    } on FormatException {
      throw BackendException(
        'Backend returned status ${response.statusCode} with invalid JSON.',
      );
    }

    if (decoded is! Map) {
      throw BackendException('Backend returned an unexpected JSON payload.');
    }

    final payload = Map<String, dynamic>.from(decoded);

    if (response.statusCode != 200) {
      throw BackendException(
        payload['error'] as String? ??
            'Backend returned status ${response.statusCode}',
      );
    }

    return payload;
  }

  Map<String, dynamic> _readNestedObject(
    Map<String, dynamic> payload,
    String key, {
    Set<String> fallbackKeys = const {},
  }) {
    final value = payload[key];
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value == null && _matchesObjectShape(payload, fallbackKeys)) {
      return payload;
    }

    throw BackendException('Backend response is missing "$key".');
  }

  bool _matchesObjectShape(Map<String, dynamic> payload, Set<String> keys) {
    if (keys.isEmpty) {
      return false;
    }

    for (final key in keys) {
      if (payload.containsKey(key)) {
        return true;
      }
    }

    return false;
  }
}

class BookSummary {
  const BookSummary({
    required this.id,
    required this.title,
    required this.chapterCount,
    required this.sourceUrl,
    required this.sourceProvider,
  });

  factory BookSummary.fromJson(Map<String, dynamic> json) {
    return BookSummary(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      chapterCount: json['chapterCount'] as int? ?? 0,
      sourceUrl: json['sourceUrl'] as String? ?? '',
      sourceProvider: json['sourceProvider'] as String? ?? '',
    );
  }

  final String id;
  final String title;
  final int chapterCount;
  final String sourceUrl;
  final String sourceProvider;
}

class BookDetail extends BookSummary {
  const BookDetail({
    required super.id,
    required super.title,
    required super.chapterCount,
    required super.sourceUrl,
    required super.sourceProvider,
    required this.chapters,
  });

  factory BookDetail.fromJson(Map<String, dynamic> json) {
    final chapters = json['chapters'] as List<dynamic>? ?? const [];
    return BookDetail(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      chapterCount: json['chapterCount'] as int? ?? 0,
      sourceUrl: json['sourceUrl'] as String? ?? '',
      sourceProvider: json['sourceProvider'] as String? ?? '',
      chapters: chapters
          .map(
            (entry) => ChapterSummary.fromJson(entry as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final List<ChapterSummary> chapters;
}

class ChapterSummary {
  const ChapterSummary({
    required this.id,
    required this.order,
    required this.title,
    required this.summary,
    required this.characterCount,
    required this.readingUnitCount,
  });

  factory ChapterSummary.fromJson(Map<String, dynamic> json) {
    return ChapterSummary(
      id: json['id'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      characterCount: json['characterCount'] as int? ?? 0,
      readingUnitCount: json['readingUnitCount'] as int? ?? 0,
    );
  }

  final String id;
  final int order;
  final String title;
  final String summary;
  final int characterCount;
  final int readingUnitCount;
}

class ChapterDetail {
  const ChapterDetail({
    required this.id,
    required this.order,
    required this.title,
    required this.summary,
    required this.text,
    required this.characterCount,
    required this.readingUnitCount,
    required this.readingUnits,
  });

  factory ChapterDetail.fromJson(Map<String, dynamic> json) {
    final readingUnits = json['readingUnits'] as List<dynamic>? ?? const [];
    return ChapterDetail(
      id: json['id'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      text: json['text'] as String? ?? '',
      characterCount: json['characterCount'] as int? ?? 0,
      readingUnitCount: json['readingUnitCount'] as int? ?? 0,
      readingUnits: readingUnits
          .map((entry) => ReadingUnit.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;
  final int order;
  final String title;
  final String summary;
  final String text;
  final int characterCount;
  final int readingUnitCount;
  final List<ReadingUnit> readingUnits;
}

class ReadingUnit {
  const ReadingUnit({
    required this.id,
    required this.order,
    required this.text,
    this.category = '',
    this.translationEn = '',
    required this.characterCount,
  });

  factory ReadingUnit.fromJson(Map<String, dynamic> json) {
    return ReadingUnit(
      id: json['id'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      category: json['category'] as String? ?? '',
      translationEn: json['translationEn'] as String? ?? '',
      characterCount: json['characterCount'] as int? ?? 0,
    );
  }

  final String id;
  final int order;
  final String text;
  final String category;
  final String translationEn;
  final int characterCount;
}

class CharacterIndex {
  CharacterIndex({required this.entryCount, required this.entries});

  factory CharacterIndex.empty() {
    return CharacterIndex(entryCount: 0, entries: const []);
  }

  factory CharacterIndex.fromJson(Map<String, dynamic> json) {
    final entries = json['entries'] as List<dynamic>? ?? const [];
    return CharacterIndex(
      entryCount: json['entryCount'] as int? ?? entries.length,
      entries: entries
          .map(
            (entry) => CharacterEntry.fromJson(entry as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  final int entryCount;
  final List<CharacterEntry> entries;

  late final Map<String, CharacterEntry> _entriesByCharacter = {
    for (final entry in entries)
      for (final key in {
        entry.character,
        entry.simplified,
        entry.traditional,
        ...entry.aliases,
      }.where((value) => value.trim().isNotEmpty))
        key: entry,
  };

  CharacterEntry? entryFor(String character) {
    final needle = character.trim();
    if (needle.isEmpty) {
      return null;
    }

    return _entriesByCharacter[needle];
  }

  List<CharacterEntry> get orderedEntries =>
      List<CharacterEntry>.unmodifiable(entries);

  int? indexForQuery(String query) {
    final needle = query.trim();
    if (needle.isEmpty) {
      return null;
    }

    final normalizedNeedle = needle.toLowerCase();
    final ordered = orderedEntries;

    bool matches(CharacterEntry entry, {required bool exactOnly}) {
      final exactTerms = <String>{
        entry.character,
        entry.simplified,
        entry.traditional,
        ...entry.aliases,
        ...entry.pinyin,
        ...entry.zhuyin,
      };
      for (final value in exactTerms) {
        final trimmedValue = value.trim();
        if (trimmedValue.isEmpty) {
          continue;
        }
        if (trimmedValue == needle ||
            trimmedValue.toLowerCase() == normalizedNeedle) {
          return true;
        }
      }

      final fuzzyTerms = <String>[...exactTerms, ...entry.english];
      for (final value in fuzzyTerms) {
        final trimmedValue = value.trim();
        if (trimmedValue.isEmpty) {
          continue;
        }
        if (!exactOnly &&
            trimmedValue.toLowerCase().contains(normalizedNeedle)) {
          return true;
        }
      }

      return false;
    }

    for (var index = 0; index < ordered.length; index++) {
      if (matches(ordered[index], exactOnly: true)) {
        return index;
      }
    }

    for (var index = 0; index < ordered.length; index++) {
      if (matches(ordered[index], exactOnly: false)) {
        return index;
      }
    }

    return null;
  }

  CharacterIndex withEntries(Iterable<CharacterEntry> overrides) {
    final normalizedOverrides = overrides
        .where((entry) => _characterEntryAliases(entry).isNotEmpty)
        .toList(growable: false);
    if (normalizedOverrides.isEmpty) {
      return this;
    }

    final mergedEntries = <CharacterEntry>[];
    final matchedOverrideIndexes = <int>{};
    for (final existingEntry in entries) {
      CharacterEntry nextEntry = existingEntry;
      for (var index = 0; index < normalizedOverrides.length; index++) {
        final overrideEntry = normalizedOverrides[index];
        if (!_entriesReferToSameCharacter(existingEntry, overrideEntry)) {
          continue;
        }

        nextEntry = overrideEntry;
        matchedOverrideIndexes.add(index);
        break;
      }
      mergedEntries.add(nextEntry);
    }

    for (var index = 0; index < normalizedOverrides.length; index++) {
      if (matchedOverrideIndexes.contains(index)) {
        continue;
      }
      mergedEntries.add(normalizedOverrides[index]);
    }

    return CharacterIndex(
      entryCount: mergedEntries.length,
      entries: mergedEntries,
    );
  }
}

class CharacterEntry {
  const CharacterEntry({
    required this.character,
    required this.simplified,
    required this.traditional,
    this.aliases = const [],
    required this.pinyin,
    required this.zhuyin,
    required this.english,
    this.exampleWords = const [],
    this.explosion = const CharacterExplosion(),
  });

  factory CharacterEntry.fromJson(Map<String, dynamic> json) {
    final explosion = CharacterExplosion.fromJson(
      json['explosion'] as Map<String, dynamic>? ?? const {},
    );
    return CharacterEntry(
      character: json['character'] as String? ?? '',
      simplified: json['simplified'] as String? ?? '',
      traditional: json['traditional'] as String? ?? '',
      aliases: _toStringList(json['aliases']),
      pinyin: _toStringList(json['pinyin']),
      zhuyin: _toStringList(json['zhuyin']),
      english: _toStringList(json['english']),
      exampleWords: explosion.synthesis.phraseUse,
      explosion: explosion,
    );
  }

  final String character;
  final String simplified;
  final String traditional;
  final List<String> aliases;
  final List<String> pinyin;
  final List<String> zhuyin;
  final List<String> english;
  final List<String> exampleWords;
  final CharacterExplosion explosion;
}

class CharacterExplosion {
  const CharacterExplosion({
    this.analysis = const CharacterExplosionAnalysis(),
    this.synthesis = const CharacterExplosionSynthesis(),
    this.meaningMap = const CharacterExplosionMeaningMap(),
  });

  factory CharacterExplosion.fromJson(Map<String, dynamic> json) {
    return CharacterExplosion(
      analysis: CharacterExplosionAnalysis.fromJson(
        json['analysis'] as Map<String, dynamic>? ?? const {},
      ),
      synthesis: CharacterExplosionSynthesis.fromJson(
        json['synthesis'] as Map<String, dynamic>? ?? const {},
      ),
      meaningMap: CharacterExplosionMeaningMap.fromJson(
        json['meaningMap'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  final CharacterExplosionAnalysis analysis;
  final CharacterExplosionSynthesis synthesis;
  final CharacterExplosionMeaningMap meaningMap;

  bool get hasContent =>
      analysis.hasContent || synthesis.hasContent || meaningMap.hasContent;
}

class CharacterExplosionAnalysis {
  const CharacterExplosionAnalysis({
    this.expression = '',
    this.parts = const [],
  });

  factory CharacterExplosionAnalysis.fromJson(Map<String, dynamic> json) {
    return CharacterExplosionAnalysis(
      expression: json['expression'] as String? ?? '',
      parts: _toStringList(json['parts']),
    );
  }

  final String expression;
  final List<String> parts;

  bool get hasContent => expression.trim().isNotEmpty || parts.isNotEmpty;
}

class CharacterExplosionSynthesis {
  const CharacterExplosionSynthesis({
    this.containingCharacters = const [],
    this.phraseUse = const [],
    this.homophones = const CharacterExplosionHomophones(),
  });

  factory CharacterExplosionSynthesis.fromJson(Map<String, dynamic> json) {
    return CharacterExplosionSynthesis(
      containingCharacters: _toStringList(json['containingCharacters']),
      phraseUse: _toStringList(json['phraseUse']),
      homophones: CharacterExplosionHomophones.fromJson(
        json['homophones'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  final List<String> containingCharacters;
  final List<String> phraseUse;
  final CharacterExplosionHomophones homophones;

  bool get hasContent =>
      containingCharacters.isNotEmpty ||
      phraseUse.isNotEmpty ||
      homophones.hasContent;
}

class CharacterExplosionHomophones {
  const CharacterExplosionHomophones({
    this.sameTone = const [],
    this.differentTone = const [],
  });

  factory CharacterExplosionHomophones.fromJson(Map<String, dynamic> json) {
    return CharacterExplosionHomophones(
      sameTone: _toStringList(json['sameTone']),
      differentTone: _toStringList(json['differentTone']),
    );
  }

  final List<String> sameTone;
  final List<String> differentTone;

  bool get hasContent => sameTone.isNotEmpty || differentTone.isNotEmpty;
}

class CharacterExplosionMeaningMap {
  const CharacterExplosionMeaningMap({
    this.synonyms = const [],
    this.antonyms = const [],
  });

  factory CharacterExplosionMeaningMap.fromJson(Map<String, dynamic> json) {
    return CharacterExplosionMeaningMap(
      synonyms: _toStringList(json['synonyms']),
      antonyms: _toStringList(json['antonyms']),
    );
  }

  final List<String> synonyms;
  final List<String> antonyms;

  bool get hasContent => synonyms.isNotEmpty || antonyms.isNotEmpty;
}

Set<String> _characterEntryAliases(CharacterEntry entry) {
  return {
    entry.character.trim(),
    entry.simplified.trim(),
    entry.traditional.trim(),
    ...entry.aliases.map((value) => value.trim()),
  }.where((value) => value.isNotEmpty).toSet();
}

bool _entriesReferToSameCharacter(CharacterEntry left, CharacterEntry right) {
  final leftAliases = _characterEntryAliases(left);
  if (leftAliases.isEmpty) {
    return false;
  }

  final rightAliases = _characterEntryAliases(right);
  if (rightAliases.isEmpty) {
    return false;
  }

  return leftAliases.intersection(rightAliases).isNotEmpty;
}

class CharacterComponentsDataset {
  const CharacterComponentsDataset({
    required this.title,
    required this.standard,
    required this.groupedComponentCount,
    required this.rawComponentCount,
    required this.entries,
  });

  factory CharacterComponentsDataset.fromJson(Map<String, dynamic> json) {
    final entries = json['entries'] as List<dynamic>? ?? const [];
    return CharacterComponentsDataset(
      title: json['title'] as String? ?? '',
      standard: json['standard'] as String? ?? '',
      groupedComponentCount: json['groupedComponentCount'] as int? ?? 0,
      rawComponentCount: json['rawComponentCount'] as int? ?? 0,
      entries: entries
          .map(
            (entry) =>
                CharacterComponentEntry.fromJson(entry as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  factory CharacterComponentsDataset.empty() {
    return CharacterComponentsDataset(
      title: '',
      standard: '',
      groupedComponentCount: 0,
      rawComponentCount: 0,
      entries: [],
    );
  }

  final String title;
  final String standard;
  final int groupedComponentCount;
  final int rawComponentCount;
  final List<CharacterComponentEntry> entries;

  List<CharacterComponentEntry> get orderedEntries {
    final ordered = entries.toList();
    ordered.sort((left, right) {
      if (left.frequencyRank == right.frequencyRank) {
        return left.groupId.compareTo(right.groupId);
      }

      return left.frequencyRank.compareTo(right.frequencyRank);
    });
    return ordered;
  }

  Map<String, CharacterComponentEntry> get _entriesByForm {
    final entriesByForm = <String, CharacterComponentEntry>{};
    for (final entry in entries) {
      for (final form in [
        entry.canonicalForm,
        ...entry.forms,
        ...entry.variantForms,
      ]) {
        final trimmed = form.trim();
        if (trimmed.isEmpty || entriesByForm.containsKey(trimmed)) {
          continue;
        }
        entriesByForm[trimmed] = entry;
      }
    }
    return entriesByForm;
  }

  CharacterComponentEntry? entryFor(String form) {
    final needle = form.trim();
    if (needle.isEmpty) {
      return null;
    }

    return _entriesByForm[needle];
  }

  int? indexForQuery(String query) {
    final needle = query.trim();
    if (needle.isEmpty) {
      return null;
    }

    final normalizedNeedle = needle.toLowerCase();
    final ordered = orderedEntries;

    bool matches(CharacterComponentEntry entry, {required bool exactOnly}) {
      final exactTerms = <String>{
        entry.canonicalForm,
        entry.canonicalName,
        ...entry.forms,
        ...entry.variantForms,
        ...entry.names,
        ...entry.sourceExampleCharacters,
      };
      for (final value in exactTerms) {
        final trimmedValue = value.trim();
        if (trimmedValue.isEmpty) {
          continue;
        }
        if (trimmedValue == needle ||
            trimmedValue.toLowerCase() == normalizedNeedle) {
          return true;
        }
      }

      for (final value in exactTerms) {
        final trimmedValue = value.trim();
        if (trimmedValue.isEmpty) {
          continue;
        }
        if (!exactOnly &&
            trimmedValue.toLowerCase().contains(normalizedNeedle)) {
          return true;
        }
      }

      return false;
    }

    for (var index = 0; index < ordered.length; index++) {
      if (matches(ordered[index], exactOnly: true)) {
        return index;
      }
    }

    for (var index = 0; index < ordered.length; index++) {
      if (matches(ordered[index], exactOnly: false)) {
        return index;
      }
    }

    return null;
  }
}

class CharacterComponentEntry {
  const CharacterComponentEntry({
    required this.groupId,
    required this.frequencyRank,
    required this.groupOccurrenceCount,
    required this.groupConstructionCount,
    required this.canonicalForm,
    required this.canonicalName,
    required this.forms,
    required this.variantForms,
    required this.names,
    required this.sourceExampleCharacters,
    required this.memberCount,
  });

  factory CharacterComponentEntry.fromJson(Map<String, dynamic> json) {
    return CharacterComponentEntry(
      groupId: json['groupId'] as int? ?? 0,
      frequencyRank: json['frequencyRank'] as int? ?? 0,
      groupOccurrenceCount: json['groupOccurrenceCount'] as int? ?? 0,
      groupConstructionCount: json['groupConstructionCount'] as int? ?? 0,
      canonicalForm: json['canonicalForm'] as String? ?? '',
      canonicalName: json['canonicalName'] as String? ?? '',
      forms: _toStringList(json['forms']),
      variantForms: _toStringList(json['variantForms']),
      names: _toStringList(json['names']),
      sourceExampleCharacters: _toStringList(json['sourceExampleCharacters']),
      memberCount: json['memberCount'] as int? ?? 0,
    );
  }

  final int groupId;
  final int frequencyRank;
  final int groupOccurrenceCount;
  final int groupConstructionCount;
  final String canonicalForm;
  final String canonicalName;
  final List<String> forms;
  final List<String> variantForms;
  final List<String> names;
  final List<String> sourceExampleCharacters;
  final int memberCount;
}

class GuidedConversationMessage {
  const GuidedConversationMessage({
    required this.role,
    required this.content,
    this.isVisible = true,
  });

  factory GuidedConversationMessage.fromJson(Map<String, dynamic> json) {
    return GuidedConversationMessage(
      role: json['role'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  final String role;
  final String content;
  final bool isVisible;

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() {
    return {'role': role, 'content': content};
  }
}

class GuidedChatPreviousLine {
  const GuidedChatPreviousLine({
    required this.readingUnitId,
    required this.order,
    required this.text,
    this.translationEn = '',
    this.learnerTranslation = '',
    this.learnerResponse = '',
  });

  final String readingUnitId;
  final int order;
  final String text;
  final String translationEn;
  final String learnerTranslation;
  final String learnerResponse;

  Map<String, dynamic> toJson() {
    return {
      'readingUnitId': readingUnitId,
      'order': order,
      'text': text,
      'translationEn': translationEn,
      'learnerTranslation': learnerTranslation,
      'learnerResponse': learnerResponse,
    };
  }
}

class GuidedChatReply {
  const GuidedChatReply({
    required this.message,
    required this.provider,
    required this.model,
    this.requestId = '',
  });

  factory GuidedChatReply.fromJson(Map<String, dynamic> json) {
    return GuidedChatReply(
      message: GuidedConversationMessage.fromJson(
        json['reply'] as Map<String, dynamic>? ?? const {},
      ),
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      requestId: json['requestId'] as String? ?? '',
    );
  }

  final GuidedConversationMessage message;
  final String provider;
  final String model;
  final String requestId;
}

List<String> _toStringList(Object? value) {
  final items = value as List<dynamic>? ?? const [];
  return items.map((item) => item.toString()).toList();
}

class BackendException implements Exception {
  BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}
