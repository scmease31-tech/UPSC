// Live, read-only production contract for Vocabulary, Flashcards, and Must Know.
// Run after a canonical backfill or release:
//   flutter test tool/verify_study_libraries_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/firebase_options.dart';
import 'package:upsc_daily_edge/models/study_library_content.dart';
import 'package:upsc_daily_edge/models/vocabulary_entry.dart';

Object? _value(Map<String, dynamic> field) {
  if (field.containsKey('nullValue')) return null;
  if (field.containsKey('stringValue')) return field['stringValue'];
  if (field.containsKey('integerValue')) {
    return int.tryParse(field['integerValue'].toString());
  }
  if (field.containsKey('doubleValue')) return field['doubleValue'];
  if (field.containsKey('booleanValue')) return field['booleanValue'];
  if (field.containsKey('timestampValue')) return field['timestampValue'];
  if (field['arrayValue'] case final Map<String, dynamic> array) {
    return (array['values'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(_value)
        .toList(growable: false);
  }
  if (field['mapValue'] case final Map<String, dynamic> map) {
    return _fields(
      (map['fields'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }
  return null;
}

Map<String, dynamic> _fields(Map<String, dynamic> fields) => fields.map(
      (key, value) => MapEntry(
        key,
        value is Map<String, dynamic> ? _value(value) : null,
      ),
    );

Future<List<StudyContentDocument>> _collection(String collection) async {
  final options = DefaultFirebaseOptions.web;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final documents = <StudyContentDocument>[];
  String? pageToken;
  try {
    do {
      final uri = Uri.https(
        'firestore.googleapis.com',
        '/v1/projects/${options.projectId}/databases/(default)/documents/$collection',
        <String, String>{
          'pageSize': '300',
          'key': options.apiKey,
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      final response = await (await client.getUrl(uri))
          .close()
          .timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200,
          reason: '$collection public read failed: $body');
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      for (final document
          in (decoded['documents'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()) {
        final path = document['name'].toString();
        documents.add(StudyContentDocument(
          path.split('/').last,
          _fields((document['fields'] as Map<String, dynamic>?) ??
              const <String, dynamic>{}),
        ));
      }
      pageToken = decoded['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return documents;
  } finally {
    client.close(force: true);
  }
}

DateTime? _latest(Iterable<DateTime?> values) {
  DateTime? latest;
  for (final value in values) {
    if (value != null && (latest == null || value.isAfter(latest))) {
      latest = value;
    }
  }
  return latest;
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  test('live vocabulary is complete, typed, unique, and current', () async {
    final documents = await _collection('vocabulary');
    final entries = documents
        .map((doc) => VocabularyEntry.fromMap({
              'docId': doc.id,
              ...doc.data,
            }))
        .where((entry) => entry.word.isNotEmpty && entry.meaning.isNotEmpty)
        .toList();
    final latest = _latest(entries.map((entry) => entry.publishedDate));
    final unique = entries.map((entry) => entry.normalizedWord).toSet();
    // ignore: avoid_print
    print('VOCABULARY raw=${documents.length} usable=${entries.length} '
        'unique=${unique.length} latest=${latest?.toIso8601String()}');
    expect(documents.length, greaterThan(400));
    expect(entries.length, greaterThan(400));
    expect(unique.length, entries.length);
    expect(latest, isNotNull);
    expect(latest!.isBefore(DateTime(2026, 9, 16)), isFalse,
        reason: 'vocabulary is still stuck before the missing news dates');
  });

  test('full flashcard archive is accessible with canonical provenance',
      () async {
    final documents = await _collection('flashcards');
    final cards = documents
        .map(StudyFlashcard.tryFromDocument)
        .whereType<StudyFlashcard>()
        .toList();
    final withDate = cards.where((card) => card.publishedDate != null).length;
    final withSource = cards
        .where(
            (card) => card.sourceUrl.isNotEmpty || card.articleRef.isNotEmpty)
        .length;
    final categories = StudyLibrarySelectors.flashcardCategoryCounts(cards);
    // ignore: avoid_print
    print('FLASHCARDS raw=${documents.length} usable=${cards.length} '
        'dated=$withDate sourced=$withSource categories=${categories.length}');
    expect(documents.length, greaterThan(4000));
    expect(cards.length, greaterThan(4000));
    expect(cards.length, lessThanOrEqualTo(5000),
        reason: 'raise/paginate the current app safety limit before release');
    expect(categories.length, greaterThan(5));
  });

  test('Must Know retains every article bundle and daily metadata', () async {
    final documents = await _collection('dailyFacts');
    final bundles = documents
        .map(DailyFactBundle.tryFromDocument)
        .whereType<DailyFactBundle>()
        .toList();
    final facts =
        bundles.fold<int>(0, (sum, bundle) => sum + bundle.facts.length);
    final dated =
        bundles.where((bundle) => bundle.publishedDate != null).length;
    final categories = StudyLibrarySelectors.factCategoryCounts(bundles);
    // ignore: avoid_print
    print('MUST_KNOW raw=${documents.length} bundles=${bundles.length} '
        'facts=$facts dated=$dated categories=${categories.length}');
    expect(documents.length, greaterThan(700));
    expect(bundles.length, greaterThan(700));
    expect(facts, greaterThan(1400));
    expect(categories.length, greaterThan(5));
  });
}
