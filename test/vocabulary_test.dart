import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/data/vocabulary_data.dart';
import 'package:upsc_daily_edge/models/vocabulary_entry.dart';
import 'package:upsc_daily_edge/screens/features/vocabulary_screen.dart';

import 'support/load_app_fonts.dart';

Map<String, dynamic> remoteWord(
  int index, {
  String? word,
  String category = 'Remote category',
  String? publishedDate,
  String newspaper = '',
  String sourceUrl = '',
  String upscPaper = '',
  String upscUsage = '',
}) {
  final value = word ?? 'Remote Word ${index.toString().padLeft(3, '0')}';
  return <String, dynamic>{
    'docId': 'remote-doc-$index',
    'schemaVersion': 2,
    'word': value,
    'normalizedWord': VocabularyEntry.normalizeWord(value),
    'partOfSpeech': 'noun',
    'meaning': 'Definition for $value',
    'example': '$value appears in a policy context.',
    'synonyms': <String>['Alternative $index'],
    'antonyms': <String>['Opposite $index'],
    'category': category,
    'articleRef': 'articles/article-$index',
    if (sourceUrl.isNotEmpty) 'sourceUrl': sourceUrl,
    if (upscPaper.isNotEmpty) 'upscPaper': upscPaper,
    if (publishedDate != null) 'publishedDate': publishedDate,
    if (newspaper.isNotEmpty) 'newspaper': newspaper,
    if (upscUsage.isNotEmpty) 'upscUsage': upscUsage,
  };
}

Future<void> pumpVocabularyScreen(
  WidgetTester tester, {
  required VocabularyDataLoader loader,
  VocabularyDataLoader? refresher,
  VocabularyErrorReader? lastErrorReader,
  VocabularySourceOpener? sourceOpener,
  Duration timeout = const Duration(seconds: 2),
  Map<String, Object> preferences = const <String, Object>{},
  Duration pumpFor = const Duration(milliseconds: 500),
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: VocabularyBuilderScreen(
        loadVocabulary: loader,
        refreshVocabulary: refresher ?? loader,
        lastErrorReader: lastErrorReader,
        openSource: sourceOpener,
        loadTimeout: timeout,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(pumpFor);
  await tester.pump();
}

void vocabularyEntryTests() {
  group('VocabularyEntry normalization and selection', () {
    test('malformed and scalar legacy fields never require raw casts', () {
      final entry = VocabularyEntry.fromMap(<String, dynamic>{
        'docId': 123,
        'schemaVersion': '7',
        'word': '  Resilience  ',
        'partOfSpeech': <String>['not', 'a', 'scalar'],
        'meaning': <String, dynamic>{'bad': 'container'},
        'example': true,
        'synonyms': 'Fortitude; Endurance\nAdaptability',
        'antonyms': <Object?>[
          'Fragility',
          null,
          7,
          <String>['nested']
        ],
        'category': ' SCIENCE_and_TECHNOLOGY ',
        'articleRef': 88,
        'sourceUrl': 'http://insecure.example/story',
        'upscPaper': 3,
        'publishedDate': <String, int>{'seconds': 123},
        'newspaper': <String>['not', 'a', 'scalar'],
      });

      expect(entry.docId, '123');
      expect(entry.schemaVersion, 7);
      expect(entry.word, 'Resilience');
      expect(entry.partOfSpeech, isEmpty);
      expect(entry.meaning, isEmpty);
      expect(entry.example, 'true');
      expect(entry.synonyms, <String>[
        'Fortitude',
        'Endurance',
        'Adaptability',
      ]);
      expect(entry.antonyms, <String>['Fragility', '7']);
      expect(entry.category, 'Science & Technology');
      expect(entry.articleRef, '88');
      expect(entry.publishedDate, isNull);
      expect(entry.sourceUri, isNull, reason: 'HTTP must not be actionable');
    });

    test('427 library records merge with rather than collapse to the 50 pack',
        () {
      final library = List<Map<String, dynamic>>.generate(427, remoteWord);
      final entries = VocabularyEntry.combine(library, VocabularyData.words);

      expect(VocabularyData.words, hasLength(50));
      expect(entries, hasLength(477));
      expect(
        entries.where((entry) => entry.hasLibraryProvenance),
        hasLength(427),
      );
      expect(entries.map((entry) => entry.stableId).toSet(), hasLength(477));
    });

    test('nonblank library data enriches without erasing curated detail', () {
      final entries = VocabularyEntry.combine(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'docId': 'live-abrogation',
            'word': ' abrogation ',
            'meaning': '   ',
            'example': 'A newer verified example.',
            'synonyms': 'Rescission',
            'antonyms': <String>[],
            'category': 'governance',
            'newspaper': 'The Hindu',
            'publishedDate': '2025-03-14T08:00:00Z',
            'sourceUrl': 'https://example.com/abrogation',
          },
        ],
        VocabularyData.words,
      );
      final entry = entries.singleWhere(
        (item) => item.normalizedWord == 'abrogation',
      );

      expect(entries, hasLength(50));
      expect(entry.meaning, contains('repeal or abolition'));
      expect(entry.example, 'A newer verified example.');
      expect(entry.synonyms, containsAll(<String>['Rescission', 'Repeal']));
      expect(entry.antonyms, contains('Enactment'));
      expect(entry.docId, 'live-abrogation');
      expect(entry.hasCuratedProvenance, isTrue);
      expect(entry.hasLibraryProvenance, isTrue);
    });

    test('stable progress IDs survive document and source changes', () {
      final first = VocabularyEntry.fromMap(<String, dynamic>{
        'docId': 'doc-one',
        'id': 'legacy-one',
        'word': 'Habeas Corpus',
      });
      final second = VocabularyEntry.fromMap(<String, dynamic>{
        'docId': 'doc-two',
        'word': 'habeas-corpus',
      });

      expect(first.stableId, 'word:habeascorpus');
      expect(second.stableId, first.stableId);
      expect(
          first.progressAliases,
          containsAll(<String>[
            'doc-one',
            'doc:doc-one',
            'legacy-one',
            'word:habeascorpus',
          ]));
      expect(first.isTrackedBy(<String>{'legacy-one'}), isTrue);
      expect(first.isTrackedBy(<String>{'doc-one'}), isTrue);
    });

    test('search covers definition, example, lists, source, and UPSC usage',
        () {
      final entry = VocabularyEntry.fromMap(<String, dynamic>{
        'word': 'Perspicacious',
        'definition': 'Having penetrating discernment',
        'example': 'The committee made a farsighted choice.',
        'synonyms': <String>['Astute'],
        'antonyms': 'Obtuse',
        'newspaper': 'Indian Express',
        'sourceUrl': 'https://example.com/editorial',
        'upscPaper': 'GS-IV',
        'upscUsage': 'Useful in an ethics case study',
      });

      for (final query in <String>[
        'penetrating',
        'farsighted',
        'astute',
        'obtuse',
        'Indian Express',
        'example.com',
        'GS-IV',
        'ethics case',
      ]) {
        expect(entry.matchesQuery(query), isTrue, reason: query);
      }
    });

    test('Latest uses every record on the newest available date', () {
      final entries = VocabularyEntry.combine(
        <Map<String, dynamic>>[
          remoteWord(
            1,
            word: 'Older News Word',
            publishedDate: '2021-04-01T12:00:00Z',
            newspaper: 'Old Daily',
          ),
          remoteWord(
            2,
            word: 'Latest One',
            publishedDate: '2022-06-09T08:00:00Z',
            newspaper: 'Daily One',
          ),
          remoteWord(
            3,
            word: 'Latest Two',
            publishedDate: '2022-06-09T20:00:00Z',
            newspaper: 'Daily Two',
          ),
        ],
        VocabularyData.words,
      );

      final latest = VocabularyEntry.latestNews(entries);
      expect(latest.map((entry) => entry.word), <String>[
        'Latest One',
        'Latest Two',
      ]);
      expect(latest.first.publishedDateLabel, '9 Jun 2022');
    });

    test('category counts are normalized and remain dynamic', () {
      final entries = VocabularyEntry.combine(
        <Map<String, dynamic>>[
          remoteWord(1, category: 'SCIENCE_and_TECHNOLOGY'),
          remoteWord(2, category: 'science & technology'),
          remoteWord(3, category: 'public health'),
        ],
        const <Map<String, dynamic>>[],
      );
      final counts = VocabularyEntry.categoryCounts(entries);

      expect(counts['Science & Technology'], 2);
      expect(counts['Public Health'], 1);
    });

    test('only valid host-based HTTPS source URLs are actionable', () {
      VocabularyEntry entry(String url) =>
          VocabularyEntry.fromMap(<String, dynamic>{
            'word': 'Source Test',
            'sourceUrl': url,
          });

      expect(entry('https://example.com/story').sourceUri, isNotNull);
      expect(entry('http://example.com/story').sourceUri, isNull);
      expect(entry('https:///missing-host').sourceUri, isNull);
      expect(entry('https://user:pass@example.com/story').sourceUri, isNull);
    });
  });
}

void vocabularyScreenTests() {
  group('VocabularyBuilderScreen', () {
    setUpAll(loadAppFonts);

    testWidgets('all 427 library records remain loaded and browsable',
        (tester) async {
      final library = List<Map<String, dynamic>>.generate(427, remoteWord);
      await pumpVocabularyScreen(tester, loader: () async => library);

      expect(find.text('477 words loaded'), findsOneWidget);
      expect(find.text('Live library + saved essentials'), findsOneWidget);
      final list = tester.widget<ListView>(
        find.byKey(const Key('vocabulary-list')),
      );
      expect(list.childrenDelegate.estimatedChildCount, 477);

      await tester.enterText(
        find.byKey(const Key('vocabulary-search')),
        'Remote Word 426',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(
          const ValueKey<String>(
            'vocabulary-card-word:remoteword426',
          ),
        ),
        findsOneWidget,
      );
      final filteredList = tester.widget<ListView>(
        find.byKey(const Key('vocabulary-list')),
      );
      expect(filteredList.childrenDelegate.estimatedChildCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an error is labelled saved essentials, never live',
        (tester) async {
      await pumpVocabularyScreen(
        tester,
        loader: () async => throw Exception('offline'),
      );

      expect(find.text('Showing saved essentials'), findsOneWidget);
      expect(find.text('50 words loaded'), findsOneWidget);
      expect(find.text('Live library + saved essentials'), findsNothing);
      expect(find.text('Abrogation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading is explicit and bounded by the injected timeout',
        (tester) async {
      final never = Completer<List<Map<String, dynamic>>>();
      await pumpVocabularyScreen(
        tester,
        loader: () => never.future,
        timeout: const Duration(milliseconds: 30),
        pumpFor: const Duration(milliseconds: 10),
      );

      expect(
        find.text('Loading complete vocabulary library…'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump();
      expect(find.text('Showing saved essentials'), findsOneWidget);
      expect(find.text('50 words loaded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dynamic normalized category chips show counts and filter',
        (tester) async {
      final library = <Map<String, dynamic>>[
        remoteWord(
          1,
          word: 'Aardvark Science Alpha',
          category: 'SCIENCE_and_TECHNOLOGY',
        ),
        remoteWord(
          2,
          word: 'Aardvark Science Beta',
          category: 'science & technology',
        ),
      ];
      await pumpVocabularyScreen(tester, loader: () async => library);

      final categoryList = find.byKey(const Key('vocabulary-category-list'));
      await tester.drag(categoryList, const Offset(-1100, 0));
      await tester.pump(const Duration(milliseconds: 200));
      final scienceChip = find.byKey(
        const ValueKey<String>(
          'vocabulary-category-Science & Technology',
        ),
      );
      expect(scienceChip, findsOneWidget);
      expect(find.text('Science & Technology (2)'), findsOneWidget);
      await tester.tap(scienceChip);
      await tester.pump(const Duration(milliseconds: 200));

      final list = tester.widget<ListView>(
        find.byKey(const Key('vocabulary-list')),
      );
      expect(list.childrenDelegate.estimatedChildCount, 2);
      expect(find.text('Aardvark Science Alpha'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('news provenance and UPSC attribution are visible and openable',
        (tester) async {
      Uri? opened;
      final source = remoteWord(
        1,
        word: 'Aardvark Dispatch',
        category: 'governance',
        publishedDate: '2025-03-14T08:00:00Z',
        newspaper: 'The Hindu',
        sourceUrl: 'https://example.com/editorial?id=1',
        upscPaper: 'GS-III',
        upscUsage: 'Use for constitutional safeguards in Mains answers.',
      );
      await pumpVocabularyScreen(
        tester,
        loader: () async => <Map<String, dynamic>>[source],
        sourceOpener: (uri) async {
          opened = uri;
          return true;
        },
      );

      expect(find.text('News-derived'), findsOneWidget);
      expect(find.text('GS-III'), findsOneWidget);
      expect(find.text('The Hindu • 14 Mar 2025'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('vocabulary-search')),
        'constitutional safeguards',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Aardvark Dispatch'), findsOneWidget);

      final sourceButton = find.byKey(
        const ValueKey<String>(
          'vocabulary-source-word:aardvarkdispatch',
        ),
      );
      await tester.ensureVisible(sourceButton);
      await tester.tap(sourceButton);
      await tester.pump();
      expect(opened, Uri.parse('https://example.com/editorial?id=1'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('malformed documents are skipped or rendered without crashing',
        (tester) async {
      await pumpVocabularyScreen(
        tester,
        loader: () async => <Map<String, dynamic>>[
          <String, dynamic>{
            'docId': 'bad-no-word',
            'word': <String>['not', 'a', 'word'],
            'meaning': <String, String>{'bad': 'container'},
          },
          <String, dynamic>{
            'docId': 'legacy-safe',
            'word': 'Aardvark Legacy',
            'meaning': <String>['not', 'text'],
            'synonyms': <String, String>{'bad': 'container'},
            'antonyms': <Object?>[1, null, 'Opposite'],
            'category': 99,
            'publishedDate': <String, int>{'seconds': 123},
            'sourceUrl': 42,
          },
        ],
      );

      expect(find.text('Aardvark Legacy'), findsOneWidget);
      expect(find.text('99'), findsOneWidget);
      expect(find.text('Opposite'), findsOneWidget);
      expect(find.text('Open source'), findsNothing);
      expect(find.text('51 words loaded'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refresh uses the injected refresher and replaces source state',
        (tester) async {
      var refreshCalls = 0;
      await pumpVocabularyScreen(
        tester,
        loader: () async => const <Map<String, dynamic>>[],
        refresher: () async {
          refreshCalls++;
          return <Map<String, dynamic>>[
            remoteWord(1, word: 'Aardvark Refreshed'),
          ];
        },
      );

      expect(find.text('Showing saved essentials'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vocabulary-refresh')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(refreshCalls, 1);
      expect(find.text('Live library + saved essentials'), findsOneWidget);
      expect(find.text('51 words loaded'), findsOneWidget);
      expect(find.text('Aardvark Refreshed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('legacy progress migrates additively and is not pruned',
        (tester) async {
      await pumpVocabularyScreen(
        tester,
        preferences: <String, Object>{
          'vocab_learned': jsonEncode(<String>['v_001', 'unseen-doc-id']),
          'vocab_bookmarked': jsonEncode(<String>['Abrogation']),
        },
        loader: () async => <Map<String, dynamic>>[
          <String, dynamic>{
            'docId': 'live-abrogation',
            'word': 'Abrogation',
            'category': 'Governance',
          },
        ],
      );

      expect(find.textContaining('1 learned • 1 saved'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vocabulary-learned-filter')));
      await tester.pump(const Duration(milliseconds: 200));
      final list = tester.widget<ListView>(
        find.byKey(const Key('vocabulary-list')),
      );
      expect(list.childrenDelegate.estimatedChildCount, 1);
      expect(find.text('Abrogation'), findsOneWidget);

      final preferences = await SharedPreferences.getInstance();
      final learned = (jsonDecode(
        preferences.getString('vocab_learned')!,
      ) as List<dynamic>)
          .map((item) => item.toString())
          .toSet();
      expect(learned, contains('word:abrogation'));
      expect(learned, contains('unseen-doc-id'),
          reason: 'temporarily absent source IDs must never be pruned');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Latest mode shows the newest available publication date only',
        (tester) async {
      final library = <Map<String, dynamic>>[
        remoteWord(
          1,
          word: 'Aardvark Older',
          publishedDate: '2024-02-01T10:00:00Z',
          newspaper: 'Old News',
        ),
        remoteWord(
          2,
          word: 'Aardvark Latest One',
          publishedDate: '2024-02-04T10:00:00Z',
          newspaper: 'New News',
        ),
        remoteWord(
          3,
          word: 'Aardvark Latest Two',
          publishedDate: '2024-02-04T18:00:00Z',
          newspaper: 'New News',
        ),
      ];
      await pumpVocabularyScreen(tester, loader: () async => library);

      expect(find.text('Latest available: 4 Feb 2024'), findsOneWidget);
      await tester.tap(find.byKey(const Key('vocabulary-mode-latest')));
      await tester.pump(const Duration(milliseconds: 200));

      final list = tester.widget<ListView>(
        find.byKey(const Key('vocabulary-list')),
      );
      expect(list.childrenDelegate.estimatedChildCount, 2);
      expect(find.text('Aardvark Latest One'), findsOneWidget);
      expect(find.text('Aardvark Older'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

void main() {
  vocabularyEntryTests();
  vocabularyScreenTests();
}
