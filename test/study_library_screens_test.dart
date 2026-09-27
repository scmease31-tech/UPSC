import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/models/study_library_content.dart';
import 'package:upsc_daily_edge/providers/daily_progress_provider.dart';
import 'package:upsc_daily_edge/screens/features/flashcard_screen.dart';
import 'package:upsc_daily_edge/screens/features/upsc_must_know_screen.dart';

StudyFlashcard screenCard(
  String id, {
  required String front,
  required String category,
  String date = '2026-06-03',
  StudyContentOrigin origin = StudyContentOrigin.newsDerived,
}) {
  return StudyFlashcard.tryFromDocument(
    StudyContentDocument(id, <String, dynamic>{
      'schemaVersion': 2,
      'front': front,
      'back': 'Answer for $front',
      'normalizedFront': front.toLowerCase(),
      'category': category,
      'kind': 'term',
      'articleRef': 'articles/$id',
      'sourceUrl': 'https://example.com/$id',
      'upscPaper': 'GS-II',
      'publishedDate': date,
      'newspaper': 'The Hindu',
    }),
    origin: origin,
  )!;
}

DailyFactBundle screenBundle(
  String id, {
  required String title,
  required String category,
  String date = '2026-06-03',
  List<String> facts = const ['A durable source fact'],
}) {
  return DailyFactBundle.tryFromDocument(
    StudyContentDocument(id, <String, dynamic>{
      'schemaVersion': 2,
      'title': title,
      'category': category,
      'facts': facts,
      'articleRef': 'articles/$id',
      'sourceUrl': 'https://example.com/$id',
      'upscPaper': 'GS-III',
      'publishedDate': date,
      'newspaper': 'Indian Express',
    }),
  )!;
}

StudyContentResult<T> freshResult<T>(List<T> items) {
  return StudyContentResult<T>(
    items: items,
    state: StudyContentLoadState.fresh,
    source: StudyContentCollectionSource.firestore,
    loadedAt: DateTime(2026, 6, 3),
  );
}

Future<void> pumpFlashcards(
  WidgetTester tester,
  StudyContentResult<StudyFlashcard> result, {
  Set<String> initialMastery = const {},
  FlashcardMasterySaver? saveMastery,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: FlashcardScreen(
        now: () => DateTime(2026, 6, 3),
        loadLibrary: ({bool forceRefresh = false}) async => result,
        loadMastery: () async => initialMastery,
        saveMastery: saveMastery ?? (_) async {},
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> pumpMustKnow(
  WidgetTester tester, {
  required DailyFactLibraryLoader loader,
  SupplementalFactLoader? supplemental,
  StudyCacheClearer? clearDaily,
  StudyCacheClearer? clearSupplemental,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => DailyProgressProvider(),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: UpscMustKnowScreen(
          now: () => DateTime(2026, 6, 3),
          loadLibrary: loader,
          loadSupplemental: supplemental ?? () async => const [],
          clearDailyFactCache: clearDaily ?? () async {},
          clearSupplementalCache: clearSupplemental ?? () async {},
        ),
      ),
    ),
  );
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  group('FlashcardScreen', () {
    testWidgets('daily and full modes expose dynamic counts and provenance',
        (tester) async {
      final result = freshResult([
        screenCard(
          'economy-today',
          front: 'Repo rate question',
          category: 'Economy',
        ),
        screenCard(
          'polity-today',
          front: 'Article 21 question',
          category: 'Polity',
        ),
        screenCard(
          'history-old',
          front: 'Ancient treaty question',
          category: 'History',
          date: '2026-06-02',
        ),
      ]);

      await pumpFlashcards(tester, result);

      expect(find.text('Publication date 2026-06-03'), findsOneWidget);
      expect(find.text('Economy (1)'), findsOneWidget);
      expect(find.text('Polity (1)'), findsOneWidget);
      expect(find.textContaining('The Hindu'), findsWidgets);
      expect(find.text('News-derived'), findsWidgets);

      await tester.tap(
        find.byKey(const ValueKey('flashcard-mode-fullLibrary')),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('3 of 3 cards visible'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('flashcard-search')),
        'Ancient treaty',
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('1 of 3 cards visible'), findsOneWidget);
      expect(find.text('Ancient treaty question'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stable mastery is isolated across category filters',
        (tester) async {
      Set<String> saved = {};
      final result = freshResult([
        screenCard(
          'economy-card',
          front: 'Economy first',
          category: 'Economy',
        ),
        screenCard(
          'polity-card',
          front: 'Polity second',
          category: 'Polity',
        ),
      ]);
      await pumpFlashcards(
        tester,
        result,
        saveMastery: (ids) async => saved = Set<String>.from(ids),
      );

      await tester.tap(
        find.byKey(const ValueKey('toggle-flashcard-mastery')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(saved, {'economy-card'});
      expect(find.text('1/2 mastered'), findsOneWidget);

      final polityChip =
          find.byKey(const ValueKey('flashcard-category-Polity'));
      await tester.ensureVisible(polityChip);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(polityChip);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('0/1 mastered'), findsOneWidget);
      expect(find.text('Polity second'), findsOneWidget);

      final allChip = find.byKey(const ValueKey('flashcard-category-all'));
      await tester.ensureVisible(allChip);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(allChip);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('1/2 mastered'), findsOneWidget);
      expect(saved, {'economy-card'});
    });

    testWidgets('fallback is explicitly labelled Foundation', (tester) async {
      final foundation = screenCard(
        'foundation-card',
        front: 'Foundation question',
        category: 'General',
        date: '',
        origin: StudyContentOrigin.foundation,
      );
      final fallback = StudyContentResult<StudyFlashcard>(
        items: [foundation],
        state: StudyContentLoadState.fallback,
        source: StudyContentCollectionSource.foundation,
        loadedAt: DateTime(2026, 6, 3),
        error: StateError('offline'),
      );

      await pumpFlashcards(tester, fallback);

      expect(find.textContaining('Showing Foundation cards'), findsOneWidget);
      expect(find.text('Foundation'), findsOneWidget);
      expect(find.text('Foundation question'), findsOneWidget);
    });
  });

  group('UpscMustKnowScreen', () {
    testWidgets('keeps one live article bundle per tile with metadata',
        (tester) async {
      final result = freshResult([
        screenBundle(
          'article-a',
          title: 'Article A',
          category: 'Current Affairs',
          facts: const ['First article fact', 'Second article fact'],
        ),
        screenBundle(
          'article-b',
          title: 'Article B',
          category: 'Social Issues',
          facts: const ['Independent article fact'],
        ),
      ]);

      await pumpMustKnow(
        tester,
        loader: ({bool forceRefresh = false}) async => result,
      );

      expect(find.text('Article A'), findsOneWidget);
      expect(find.text('Article B'), findsOneWidget);
      expect(find.text('News-derived'), findsWidgets);

      await tester.tap(find.text('Article A'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Indian Express'), findsOneWidget);
      expect(find.textContaining('GS-III'), findsOneWidget);
      expect(find.textContaining('Source: https://example.com/article-a'),
          findsOneWidget);
      expect(find.text('First article fact'), findsOneWidget);
    });

    testWidgets('full library labels External and Foundation distinctly',
        (tester) async {
      final result = freshResult([
        screenBundle(
          'live',
          title: 'Live article',
          category: 'Current Affairs',
        ),
      ]);

      await pumpMustKnow(
        tester,
        loader: ({bool forceRefresh = false}) async => result,
        supplemental: () async => [
          <String, dynamic>{
            'title': 'External bulletin',
            'category': 'General',
            'facts': ['External source fact'],
            'source': 'Wikipedia Current Events',
            'isFromWeb': true,
          },
        ],
      );

      await tester.tap(
        find.byKey(const ValueKey('must-know-mode-fullLibrary')),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(
        find.byKey(const ValueKey('must-know-search')),
        'External bulletin',
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('External bulletin'), findsWidgets);
      expect(find.text('External'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('must-know-search')),
        'Polity & Governance',
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Polity & Governance'), findsWidgets);
      expect(find.text('Foundation'), findsOneWidget);
    });

    testWidgets('refresh clears Firestore and supplemental caches',
        (tester) async {
      var dailyClears = 0;
      var supplementalClears = 0;
      var supplementalLoads = 0;
      final forceValues = <bool>[];
      final result = freshResult([
        screenBundle(
          'refreshable',
          title: 'Refreshable article',
          category: 'Current Affairs',
        ),
      ]);

      await pumpMustKnow(
        tester,
        loader: ({bool forceRefresh = false}) async {
          forceValues.add(forceRefresh);
          if (forceRefresh) {
            return StudyContentResult<DailyFactBundle>(
              items: const [],
              state: StudyContentLoadState.fallback,
              source: StudyContentCollectionSource.foundation,
              loadedAt: DateTime(2026, 6, 3),
              error: StateError('refresh offline'),
            );
          }
          return result;
        },
        supplemental: () async {
          supplementalLoads++;
          return const [];
        },
        clearDaily: () async => dailyClears++,
        clearSupplemental: () async => supplementalClears++,
      );

      await tester.tap(find.byKey(const ValueKey('refresh-must-know')));
      for (var index = 0; index < 6; index++) {
        await tester.pump(const Duration(milliseconds: 150));
      }

      expect(forceValues, [false, true]);
      expect(dailyClears, 1);
      expect(supplementalClears, 1);
      expect(supplementalLoads, 2);
      expect(find.text('Refreshable article'), findsOneWidget);
      expect(find.textContaining('showing saved live article bundles'),
          findsOneWidget);
    });

    testWidgets('Firestore failure visibly falls back to Foundation content',
        (tester) async {
      final fallback = StudyContentResult<DailyFactBundle>(
        items: const [],
        state: StudyContentLoadState.fallback,
        source: StudyContentCollectionSource.foundation,
        loadedAt: DateTime(2026, 6, 3),
        error: StateError('offline'),
      );

      await pumpMustKnow(
        tester,
        loader: ({bool forceRefresh = false}) async => fallback,
      );

      expect(
        find.textContaining('showing labelled Foundation content'),
        findsOneWidget,
      );
      expect(find.text('Foundation'), findsWidgets);
      expect(find.text('Economy & Finance'), findsOneWidget);
    });
  });
}
