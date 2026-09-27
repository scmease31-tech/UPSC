// Visual review captures for the canonical study libraries.
// Run explicitly: flutter test tool/screenshots/study_libraries_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/models/study_library_content.dart';
import 'package:upsc_daily_edge/providers/daily_progress_provider.dart';
import 'package:upsc_daily_edge/screens/features/flashcard_screen.dart';
import 'package:upsc_daily_edge/screens/features/upsc_must_know_screen.dart';
import 'package:upsc_daily_edge/screens/features/vocabulary_screen.dart';

import '../../test/support/load_app_fonts.dart';

final _key = GlobalKey();
const _out = 'build/screenshots';

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary =
      _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  });
  if (bytes == null) return;
  Directory(_out).createSync(recursive: true);
  File('$_out/$name.png').writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('CAPTURED $_out/$name.png');
}

Widget _host(Widget child) => RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: child,
      ),
    );

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    // Screenshot harnesses intentionally use the plugin's in-memory test store.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('vocabulary library', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final words = List.generate(
        24,
        (index) => <String, dynamic>{
              'docId': 'word-$index',
              'word': index == 0 ? 'Perspicacious' : 'Editorial Word $index',
              'partOfSpeech': index.isEven ? 'adjective' : 'noun',
              'meaning':
                  'A precise, news-derived definition useful in UPSC answer writing.',
              'example':
                  'The editorial used this word while examining a public-policy dilemma.',
              'synonyms': ['Astute', 'Discerning'],
              'antonyms': ['Unperceptive'],
              'category': index.isEven ? 'Governance' : 'Economy',
              'publishedDate': '2026-09-26',
              'newspaper': 'The Hindu',
              'upscPaper': 'GS-II',
              'sourceUrl': 'https://example.com/article-$index',
            });
    await tester.pumpWidget(_host(VocabularyBuilderScreen(
      loadVocabulary: () async => words,
      refreshVocabulary: () async => words,
      lastErrorReader: () => null,
      openSource: (_) async => true,
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _capture(tester, 'library-vocabulary');
  });

  testWidgets('daily flashcards', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cards = List.generate(
        12,
        (index) => StudyFlashcard.tryFromDocument(
              StudyContentDocument('fc-$index', {
                'front': index == 0
                    ? 'Why is fiscal federalism important for India?'
                    : 'Revision question $index',
                'back':
                    'It divides fiscal powers and responsibilities across Union and State governments.',
                'category': index.isEven ? 'Polity' : 'Economy',
                'kind': 'section',
                'publishedDate': '2026-09-26',
                'newspaper': 'Indian Express',
                'upscPaper': 'GS-II',
                'sourceUrl': 'https://example.com/flash-$index',
              }),
            )!).toList();
    final result = StudyContentResult<StudyFlashcard>(
      items: cards,
      state: StudyContentLoadState.fresh,
      source: StudyContentCollectionSource.firestore,
      loadedAt: DateTime(2026, 9, 27),
    );
    await tester.pumpWidget(_host(FlashcardScreen(
      now: () => DateTime(2026, 9, 27),
      loadLibrary: ({bool forceRefresh = false}) async => result,
      loadMastery: () async => {},
      saveMastery: (_) async {},
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await _capture(tester, 'library-flashcards-daily');
  });

  testWidgets('daily Must Know', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bundles = List.generate(
        5,
        (index) => DailyFactBundle.tryFromDocument(
              StudyContentDocument('kf-$index', {
                'title': index == 0
                    ? 'Fiscal Federalism Review'
                    : 'Daily briefing $index',
                'category': index.isEven ? 'Polity' : 'Economy',
                'facts': [
                  'Article 280 provides for a Finance Commission to recommend tax devolution.',
                  'The commission is normally constituted every five years by the President.',
                ],
                'publishedDate': '2026-09-26',
                'newspaper': 'The Hindu',
                'upscPaper': 'GS-II',
                'sourceUrl': 'https://example.com/fact-$index',
              }),
            )!).toList();
    final result = StudyContentResult<DailyFactBundle>(
      items: bundles,
      state: StudyContentLoadState.fresh,
      source: StudyContentCollectionSource.firestore,
      loadedAt: DateTime(2026, 9, 27),
    );
    await tester.pumpWidget(RepaintBoundary(
      key: _key,
      child: ChangeNotifierProvider(
        create: (_) => DailyProgressProvider(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: UpscMustKnowScreen(
            now: () => DateTime(2026, 9, 27),
            loadLibrary: ({bool forceRefresh = false}) async => result,
            loadSupplemental: () async => [],
            clearDailyFactCache: () async {},
            clearSupplementalCache: () async {},
          ),
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await _capture(tester, 'library-must-know-daily');
  });
}
