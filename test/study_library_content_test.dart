import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/services/daily_content_manager.dart';

StudyContentDocument flashDocument(
  String id, {
  String front = 'Question',
  String back = 'Answer',
  Object? category = 'Polity',
  Object? publishedDate = '2026-06-03',
  String newspaper = 'The Hindu',
  String paper = 'GS-II',
  String kind = 'term',
  String sourceUrl = 'https://example.com/source',
}) {
  return StudyContentDocument(id, <String, dynamic>{
    'schemaVersion': 2,
    'front': front,
    'normalizedFront': front.toLowerCase(),
    'back': back,
    'category': category,
    'kind': kind,
    'articleRef': 'article-$id',
    'sourceUrl': sourceUrl,
    'upscPaper': paper,
    'publishedDate': publishedDate,
    'newspaper': newspaper,
  });
}

StudyContentDocument factDocument(
  String id, {
  String title = 'Article title',
  Object? category = 'Current Affairs',
  Object? facts = const ['First durable fact', 'Second durable fact'],
  Object? publishedDate = '2026-06-03',
  String newspaper = 'Indian Express',
  String paper = 'GS-III',
  String sourceUrl = 'https://example.com/article',
}) {
  return StudyContentDocument(id, <String, dynamic>{
    'schemaVersion': 2,
    'category': category,
    'title': title,
    'facts': facts,
    'articleRef': 'article-$id',
    'sourceUrl': sourceUrl,
    'upscPaper': paper,
    'publishedDate': publishedDate,
    'newspaper': newspaper,
  });
}

StudyFlashcard typedCard(
  String id,
  String date, {
  String category = 'Polity',
  String front = 'Question',
  String newspaper = 'The Hindu',
}) {
  return StudyFlashcard.tryFromDocument(
    flashDocument(
      id,
      front: front,
      category: category,
      publishedDate: date,
      newspaper: newspaper,
    ),
  )!;
}

DailyFactBundle typedBundle(
  String id,
  String date, {
  String category = 'Current Affairs',
  String title = 'Article title',
  List<String> facts = const ['Fact'],
}) {
  return DailyFactBundle.tryFromDocument(
    factDocument(
      id,
      title: title,
      category: category,
      facts: facts,
      publishedDate: date,
    ),
  )!;
}

void main() {
  setUp(DailyContentManager.clearStudyLibraryCaches);
  tearDown(DailyContentManager.clearStudyLibraryCaches);

  group('typed study content', () {
    test('preserves canonical flashcard identity and provenance', () {
      final card = StudyFlashcard.tryFromDocument(
        flashDocument('fc-stable', category: 'science'),
      )!;

      expect(card.id, 'fc-stable');
      expect(card.schemaVersion, 2);
      expect(card.category, 'Science & Technology');
      expect(card.kind, 'term');
      expect(card.articleRef, 'article-fc-stable');
      expect(card.sourceUrl, 'https://example.com/source');
      expect(card.upscPaper, 'GS-II');
      expect(card.publishedDateLabel, '2026-06-03');
      expect(card.newspaper, 'The Hindu');
      expect(card.origin, StudyContentOrigin.newsDerived);
    });

    test('malformed scalar containers are rejected without hard casts', () {
      final invalidCard = StudyFlashcard.tryFromDocument(
        StudyContentDocument('bad-card', <String, dynamic>{
          'front': ['not', 'text'],
          'back': {'not': 'text'},
          'category': 42,
        }),
      );
      final invalidBundle = DailyFactBundle.tryFromDocument(
        StudyContentDocument('bad-facts', <String, dynamic>{
          'title': {'not': 'text'},
          'facts': {'not': 'a list'},
        }),
      );
      final mixedBundle = DailyFactBundle.tryFromDocument(
        StudyContentDocument('mixed-facts', <String, dynamic>{
          'title': 'Usable article',
          'facts': [
            'Valid fact',
            42,
            {'bad': true},
            '  valid   fact  '
          ],
          'category': {'bad': true},
        }),
      )!;

      expect(invalidCard, isNull);
      expect(invalidBundle, isNull);
      expect(mixedBundle.category, 'General');
      expect(mixedBundle.facts.map((fact) => fact.text), ['Valid fact']);
    });

    test('fact bundle keeps article grouping and stable fact IDs', () {
      final bundle = DailyFactBundle.tryFromDocument(
        factDocument(
          'kf-article',
          title: 'A single source article',
          facts: const ['One fact', 'Two facts'],
        ),
      )!;

      expect(bundle.id, 'kf-article');
      expect(bundle.title, 'A single source article');
      expect(bundle.facts, hasLength(2));
      expect(bundle.facts.map((fact) => fact.id).toSet(), hasLength(2));
      expect(bundle.newspaper, 'Indian Express');
      expect(bundle.upscPaper, 'GS-III');
      expect(bundle.sourceUrl, 'https://example.com/article');
    });
  });

  group('daily/latest selection and filtering', () {
    test('daily selection uses the exact date, otherwise the latest date', () {
      final cards = [
        typedCard('today-b', '2026-06-03', category: 'Economy'),
        typedCard('older', '2026-06-02'),
        typedCard('today-a', '2026-06-03'),
      ];

      final exact = StudyLibrarySelectors.dailyFlashcards(
        cards.reversed,
        date: DateTime(2026, 6, 3),
      );
      final fallbackLatest = StudyLibrarySelectors.dailyFlashcards(
        cards,
        date: DateTime(2026, 6, 4),
      );

      expect(exact.map((card) => card.id), ['today-b', 'today-a']);
      expect(fallbackLatest.map((card) => card.id), ['today-b', 'today-a']);
    });

    test('daily fact selection keeps every article on the selected date', () {
      final bundles = [
        typedBundle('latest-b', '2026-06-05', title: 'Article B'),
        typedBundle('older', '2026-06-04'),
        typedBundle('latest-a', '2026-06-05', title: 'Article A'),
      ];

      final selected = StudyLibrarySelectors.dailyFactBundles(
        bundles,
        date: DateTime(2026, 6, 6),
      );

      expect(selected.map((bundle) => bundle.id), ['latest-a', 'latest-b']);
    });

    test('dynamic categories include current, social, and general', () {
      final cards = [
        typedCard('current', '2026-06-03', category: 'current affairs'),
        typedCard('social', '2026-06-03', category: 'society'),
        StudyFlashcard.tryFromDocument(
          flashDocument('general', category: {'malformed': true}),
        )!,
      ];

      final counts = StudyLibrarySelectors.flashcardCategoryCounts(cards);

      expect(counts, <String, int>{
        'Current Affairs': 1,
        'General': 1,
        'Social Issues': 1,
      });
      expect(StudyCategory.normalize('Polity & Governance'), 'Polity');
      expect(StudyCategory.normalize('Environment & Ecology'), 'Environment');
    });

    test('full-text search includes answer, source, paper, and category', () {
      final cards = [
        typedCard('economy', '2026-06-03', category: 'Economy'),
        typedCard(
          'environment',
          '2026-06-03',
          category: 'Environment',
          newspaper: 'Indian Express',
        ),
      ];

      expect(
        StudyLibrarySelectors.filterFlashcards(cards, query: 'indian express')
            .single
            .id,
        'environment',
      );
      expect(
        StudyLibrarySelectors.filterFlashcards(cards, query: 'gs-ii'),
        hasLength(2),
      );
      expect(
        StudyLibrarySelectors.filterFlashcards(
          cards,
          category: 'Economy',
        ).single.id,
        'economy',
      );
    });

    test('fact search preserves bundles and narrows only matching bullets', () {
      final bundle = typedBundle(
        'article',
        '2026-06-03',
        title: 'Monetary policy update',
        facts: const ['Repo rate unchanged', 'Monsoon reached Kerala'],
      );

      final factMatch = StudyLibrarySelectors.filterFactBundles(
        [bundle],
        query: 'monsoon',
      ).single;
      final titleMatch = StudyLibrarySelectors.filterFactBundles(
        [bundle],
        query: 'monetary policy',
      ).single;

      expect(factMatch.id, bundle.id);
      expect(
          factMatch.facts.map((fact) => fact.text), ['Monsoon reached Kerala']);
      expect(titleMatch.facts, hasLength(2));
    });

    test('deduplication is exact after normalized full text only', () {
      final first = typedBundle(
        'first',
        '2026-06-03',
        facts: const ['The repo rate is 6.5 percent.'],
      );
      final second = typedBundle(
        'second',
        '2026-06-03',
        facts: const [
          '  THE repo rate is 6.5 percent.  ',
          'The repo rate remains near 6.5 percent.',
        ],
      );

      final deduplicated =
          StudyLibrarySelectors.deduplicateFactBundles([first, second]);

      expect(deduplicated, hasLength(2));
      expect(deduplicated.last.facts.map((fact) => fact.text),
          ['The repo rate remains near 6.5 percent.']);
    });

    test('stable-ID mastery never transfers after reorder or filtering', () {
      final mastered = {'card-b'};
      final cards = [
        typedCard('card-a', '2026-06-03'),
        typedCard('card-b', '2026-06-03', category: 'Economy'),
      ];
      final reordered = cards.reversed.toList();
      final polityOnly = StudyLibrarySelectors.filterFlashcards(
        reordered,
        category: 'Polity',
      );

      expect(StudyLibrarySelectors.visibleMasteredCount(cards, mastered), 1);
      expect(
          StudyLibrarySelectors.visibleMasteredCount(reordered, mastered), 1);
      expect(
          StudyLibrarySelectors.visibleMasteredCount(polityOnly, mastered), 0);
    });
  });

  group('DailyContentManager archives', () {
    test('all 4,375 flashcard-style records remain available in library',
        () async {
      var observedLimit = 0;
      final result = await DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        now: DateTime(2026, 6, 3),
        documentLoader: (collection, limit) async {
          expect(collection, 'flashcards');
          observedLimit = limit;
          return List.generate(
            4375,
            (index) => flashDocument(
              'fc-${index.toString().padLeft(4, '0')}',
              front: 'Question $index',
              back: 'Answer $index',
            ),
          );
        },
      );

      expect(observedLimit, DailyContentManager.maxFlashcards + 1);
      expect(result.items, hasLength(4375));
      expect(result.truncated, isFalse);
      expect(result.source, StudyContentCollectionSource.firestore);
    });

    test('flashcard safety bound exposes explicit truncation', () async {
      final result = await DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        documentLoader: (_, __) async => List.generate(
          DailyContentManager.maxFlashcards + 1,
          (index) => flashDocument(
            'fc-$index',
            front: 'Question $index',
            back: 'Answer $index',
          ),
        ),
      );

      expect(result.items, hasLength(DailyContentManager.maxFlashcards));
      expect(result.truncated, isTrue);
      expect(result.queriedCount, DailyContentManager.maxFlashcards + 1);
    });

    test('all 745 fact documents remain separate article bundles', () async {
      var observedLimit = 0;
      final result = await DailyContentManager.loadDailyFactLibrary(
        forceRefresh: true,
        documentLoader: (collection, limit) async {
          expect(collection, 'dailyFacts');
          observedLimit = limit;
          return List.generate(
            745,
            (index) => factDocument(
              'kf-$index',
              title: 'Article $index',
              category: index.isEven ? 'Current Affairs' : 'Social Issues',
              facts: ['Fact from article $index'],
            ),
          );
        },
      );

      expect(observedLimit, DailyContentManager.maxDailyFactBundles + 1);
      expect(result.items, hasLength(745));
      expect(result.items.map((bundle) => bundle.id).toSet(), hasLength(745));
      expect(result.items.singleWhere((bundle) => bundle.id == 'kf-10').title,
          'Article 10');
    });

    test('force refresh, TTL expiry, and clear all invalidate memory cache',
        () async {
      var calls = 0;
      Future<List<StudyContentDocument>> loader(_, __) async {
        calls++;
        return [
          flashDocument(
            'fc-$calls',
            front: 'Question $calls',
            back: 'Answer $calls',
          ),
        ];
      }

      final first = await DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        documentLoader: loader,
        now: DateTime(2026, 6, 3, 10),
      );
      final cached = await DailyContentManager.loadFlashcardLibrary(
        documentLoader: loader,
        now: DateTime(2026, 6, 3, 10, 5),
      );
      final forced = await DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        documentLoader: loader,
        now: DateTime(2026, 6, 3, 10, 6),
      );
      final expired = await DailyContentManager.loadFlashcardLibrary(
        documentLoader: loader,
        now: DateTime(2026, 6, 3, 10, 30),
      );
      DailyContentManager.clearFlashcardCache();
      final afterClear = await DailyContentManager.loadFlashcardLibrary(
        documentLoader: loader,
        now: DateTime(2026, 6, 3, 10, 31),
      );

      expect(first.items.single.id, 'fc-1');
      expect(cached.state, StudyContentLoadState.cached);
      expect(forced.items.single.id, 'fc-2');
      expect(expired.items.single.id, 'fc-3');
      expect(afterClear.items.single.id, 'fc-4');
      expect(calls, 4);
    });

    test('failed refresh returns explicit stale cache state', () async {
      final good = await DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        documentLoader: (_, __) async => [flashDocument('saved')],
      );
      final stale = await DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        documentLoader: (_, __) async => throw StateError('offline'),
      );

      expect(good.state, StudyContentLoadState.fresh);
      expect(stale.state, StudyContentLoadState.stale);
      expect(stale.items.single.id, 'saved');
      expect(stale.errorMessage, contains('offline'));
    });

    test('errors and malformed snapshots clearly use Foundation fallback',
        () async {
      final offline = await DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        documentLoader: (_, __) async => throw StateError('offline'),
      );
      DailyContentManager.clearFlashcardCache();
      final malformed = await DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        documentLoader: (_, __) async => [
          StudyContentDocument('bad', <String, dynamic>{
            'front': ['bad'],
            'back': null,
          }),
        ],
      );

      expect(offline.state, StudyContentLoadState.fallback);
      expect(offline.source, StudyContentCollectionSource.foundation);
      expect(offline.items, isNotEmpty);
      expect(
        offline.items.every(
          (card) => card.origin == StudyContentOrigin.foundation,
        ),
        isTrue,
      );
      expect(malformed.state, StudyContentLoadState.fallback);
      expect(malformed.discardedCount, 1);
      expect(malformed.hasError, isTrue);
    });

    test('clearing during a request prevents late cache repopulation',
        () async {
      final firstRequest = Completer<List<StudyContentDocument>>();
      var calls = 0;
      Future<List<StudyContentDocument>> loader(_, __) {
        calls++;
        if (calls == 1) return firstRequest.future;
        return Future.value([flashDocument('new')]);
      }

      final pending = DailyContentManager.loadFlashcardLibrary(
        forceRefresh: true,
        documentLoader: loader,
      );
      await Future<void>.delayed(Duration.zero);
      DailyContentManager.clearFlashcardCache();
      firstRequest.complete([flashDocument('old')]);
      await pending;
      final next = await DailyContentManager.loadFlashcardLibrary(
        documentLoader: loader,
      );

      expect(calls, 2);
      expect(next.items.single.id, 'new');
    });

    test('daily-fact cache clear forces a new Firestore-style read', () async {
      var calls = 0;
      Future<List<StudyContentDocument>> loader(_, __) async {
        calls++;
        return [factDocument('kf-$calls', title: 'Article $calls')];
      }

      await DailyContentManager.loadDailyFactLibrary(
        forceRefresh: true,
        documentLoader: loader,
      );
      await DailyContentManager.loadDailyFactLibrary(documentLoader: loader);
      DailyContentManager.clearDailyFactCache();
      final refreshed = await DailyContentManager.loadDailyFactLibrary(
        documentLoader: loader,
      );

      expect(calls, 2);
      expect(refreshed.items.single.id, 'kf-2');
    });
  });
}
