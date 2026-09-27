// Production contract check for the public Government Schemes collection.
//
// Run after data or Firebase changes:
//   flutter test tool/verify_schemes_test.dart
//
// This intentionally uses the same unauthenticated Firestore REST endpoint an
// app is allowed to read. It catches wrong-project config, undeployed read
// rules, empty collections, legacy value types, and data too thin to render.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/data/offline_content.dart';
import 'package:upsc_daily_edge/firebase_options.dart';
import 'package:upsc_daily_edge/models/government_scheme.dart';
import 'package:upsc_daily_edge/services/firebase_services.dart';

Object? _decodeValue(Map<String, dynamic> value) {
  if (value.containsKey('nullValue')) return null;
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('integerValue')) {
    return int.tryParse(value['integerValue'].toString());
  }
  if (value.containsKey('doubleValue')) return value['doubleValue'];
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('timestampValue')) return value['timestampValue'];
  if (value['arrayValue'] case final Map<String, dynamic> array) {
    return (array['values'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(_decodeValue)
        .toList(growable: false);
  }
  if (value['mapValue'] case final Map<String, dynamic> map) {
    return _decodeFields(
      (map['fields'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }
  return null;
}

Map<String, dynamic> _decodeFields(Map<String, dynamic> fields) => fields.map(
      (key, value) => MapEntry(
        key,
        value is Map<String, dynamic> ? _decodeValue(value) : null,
      ),
    );

Future<List<Map<String, dynamic>>> _fetchSchemes() async {
  final options = DefaultFirebaseOptions.web;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final docs = <Map<String, dynamic>>[];
  String? pageToken;
  try {
    do {
      final uri = Uri.https(
        'firestore.googleapis.com',
        '/v1/projects/${options.projectId}/databases/(default)/documents/govtSchemes',
        <String, String>{
          'pageSize': '300',
          'key': options.apiKey,
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      final request = await client.getUrl(uri);
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200,
          reason: 'public schemes endpoint failed: $body');
      final json = jsonDecode(body) as Map<String, dynamic>;
      docs.addAll(
        (json['documents'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map((document) {
          final name = document['name'].toString();
          final fields = (document['fields'] as Map<String, dynamic>?) ??
              const <String, dynamic>{};
          return <String, dynamic>{
            'docId': name.split('/').last,
            ..._decodeFields(fields),
          };
        }),
      );
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return docs;
  } finally {
    client.close(force: true);
  }
}

void main() {
  setUpAll(() => HttpOverrides.global = null);

  late List<Map<String, dynamic>> raw;
  late List<GovernmentScheme> schemes;

  test('web and Android target the scraper project', () {
    expect(DefaultFirebaseOptions.web.projectId,
        FirebaseServices.expectedProjectId);
    expect(DefaultFirebaseOptions.android.projectId,
        FirebaseServices.expectedProjectId);
  });

  test('the public Firestore collection is reachable and populated', () async {
    raw = await _fetchSchemes();
    expect(raw.length, greaterThan(100));
    schemes = GovernmentScheme.combine(raw, OfflineContent.govtSchemes);
    // ignore: avoid_print
    print('Live schemes: raw=${raw.length}, renderable=${schemes.length}');
  });

  test('every live document normalizes without a blank name', () {
    final normalized = raw.map(GovernmentScheme.fromMap).toList();
    expect(normalized.where((item) => item.name.isEmpty), isEmpty);
  });

  test('the collection has meaningful detail, not title-only shells', () {
    final overviews = schemes.where((item) => item.body.isNotEmpty).length;
    final relevance =
        schemes.where((item) => item.upscRelevance.isNotEmpty).length;
    final features =
        schemes.where((item) => item.keyFeatures.isNotEmpty).length;
    final ministries = schemes.where((item) => item.ministry.isNotEmpty).length;
    // ignore: avoid_print
    print('Detail: overview=$overviews relevance=$relevance '
        'features=$features ministry=$ministries');
    expect(overviews, greaterThan(100));
    expect(relevance, greaterThan(100));
    expect(features, greaterThan(20));
    expect(ministries, greaterThan(20));
  });

  test('curated essentials are present even if Firestore omits one', () {
    for (final curated in OfflineContent.govtSchemes) {
      final name = GovernmentScheme.text(curated, 'name');
      expect(schemes.any((item) => item.name == name), isTrue, reason: name);
    }
  });
}
