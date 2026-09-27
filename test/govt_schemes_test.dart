// Opening a scheme must actually show the scheme.
//
// Scheme documents arrive in two shapes and the detail sheet has to read both:
//
//   • OfflineContent's embedded set is complete — ministry,
//     detailedDescription, keyFeatures, upscRelevance.
//   • The scraper-derived `govtSchemes` docs, which WIN over the embedded set
//     whenever Firestore returns anything, are built by
//     generators.js:generateSchemes and carry only id, name, fullForm,
//     description, sector, year, iconName, colorHex.
//
// The sheet used to read detailedDescription / keyFeatures / upscRelevance
// unguarded, so against a scraper doc it rendered a title, an empty badge, a
// "Key Features" heading with nothing under it and an empty "UPSC Relevance"
// box — blank, while the card behind it looked complete because the card guards
// its optional fields and falls back to `description`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/data/offline_content.dart';
import 'package:upsc_daily_edge/models/government_scheme.dart';
import 'package:upsc_daily_edge/screens/features/govt_schemes_screen.dart';
import 'package:upsc_daily_edge/screens/features/scheme_detail_sheet.dart';

import 'support/load_app_fonts.dart';

/// Exactly the field set generators.js:generateSchemes writes. Nothing else.
Map<String, dynamic> scraperScheme() => <String, dynamic>{
      'id': 'gs-abcdef',
      'name': 'Gaganyaan Mission',
      'fullForm': 'GM',
      'description':
          'India\'s first crewed orbital spaceflight programme, targeting a '
              'three-member crew in low Earth orbit.',
      'sector': 'Science & Technology',
      'year': '2026',
      'iconName': '',
      'colorHex': '',
    };

Future<void> _pumpSheet(
  WidgetTester tester,
  Map<String, dynamic> scheme, {
  ThemeMode mode = ThemeMode.light,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: mode,
    home: Scaffold(body: SchemeDetailSheet(scheme: scheme)),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void _detailSheetTests() {
  setUpAll(loadAppFonts);

  group('a complete scheme (embedded content)', () {
    final complete =
        Map<String, dynamic>.from(OfflineContent.govtSchemes.first);

    testWidgets('shows every section', (tester) async {
      await _pumpSheet(tester, complete);

      expect(find.text(complete['name'] as String), findsOneWidget);
      expect(find.text('OVERVIEW'), findsOneWidget);
      expect(
          find.text(complete['detailedDescription'] as String), findsOneWidget);
      expect(find.text('KEY FEATURES'), findsOneWidget);
      expect(
        find.text((complete['keyFeatures'] as List).cast<String>().first),
        findsOneWidget,
      );
      expect(find.text('UPSC Relevance'), findsOneWidget);
      expect(find.text(complete['upscRelevance'] as String), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the ministry, labelled', (tester) async {
      await _pumpSheet(tester, complete);
      expect(find.text('Administered by'), findsOneWidget);
      expect(find.text(complete['ministry'] as String), findsOneWidget);
    });

    testWidgets('numbers the key features', (tester) async {
      await _pumpSheet(tester, complete);
      final count = (complete['keyFeatures'] as List).length;
      // The section header carries the count, and each card is numbered.
      expect(find.text('$count'), findsWidgets);
      expect(find.text('1'), findsWidgets);
    });

    test('is not classed as sparse', () {
      expect(SchemeDetailSheet.isSparse(complete), isFalse);
    });
  });

  group('a scraper-derived scheme', () {
    testWidgets('falls back to description so the sheet is never blank',
        (tester) async {
      final s = scraperScheme();
      await _pumpSheet(tester, s);

      expect(find.text(s['name'] as String), findsOneWidget);
      expect(find.text(s['description'] as String), findsOneWidget,
          reason:
              'with no detailedDescription the sheet must show description');
      expect(tester.takeException(), isNull);
    });

    testWidgets('omits the headings for sections it has no content for',
        (tester) async {
      await _pumpSheet(tester, scraperScheme());

      expect(find.text('KEY FEATURES'), findsNothing,
          reason: 'a heading with no features under it reads as broken');
      expect(find.text('UPSC Relevance'), findsNothing,
          reason: 'an empty relevance box reads as broken');
    });

    testWidgets('renders no empty badge for the missing ministry',
        (tester) async {
      await _pumpSheet(tester, scraperScheme());

      // sector + year are present, ministry is not: two rows, not three.
      expect(find.text('Sector'), findsOneWidget);
      expect(find.text('Science & Technology'), findsOneWidget);
      expect(find.text('In coverage from'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('Administered by'), findsNothing,
          reason: 'no ministry row should appear when none is known');
      final blank = find.byWidgetPredicate(
          (w) => w is Text && w.data != null && w.data!.trim().isEmpty);
      expect(blank, findsNothing, reason: 'an empty row was rendered');
    });

    test('a name-only scheme is classed as sparse', () {
      expect(
        SchemeDetailSheet.isSparse(
            {'name': 'Some Mission', 'sector': 'Economy'}),
        isTrue,
      );
    });

    testWidgets(
        'a name-only scheme explains the gap instead of showing nothing',
        (tester) async {
      await _pumpSheet(tester, {'name': 'Some Mission', 'sector': 'Economy'});

      expect(find.text('Some Mission'), findsOneWidget);
      expect(find.textContaining('Only a brief record exists'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('UPSC relevance presentation', () {
    test('lifts a GS paper prefix out of the prose', () {
      final r = SchemeDetailSheet.splitRelevance(
        'GS-II — Government policies and interventions. Expect questions.',
      );
      expect(r.paper, 'GS-II');
      expect(
          r.rest, 'Government policies and interventions. Expect questions.');
    });

    test('handles a combined paper label', () {
      expect(
        SchemeDetailSheet.splitRelevance('GS-I / GS-II — Role of women.').paper,
        'GS-I / GS-II',
      );
    });

    test('leaves prose alone when it does not lead with a paper', () {
      // The embedded content writes "GS-II welfare delivery and GS-III ..." with
      // no separator; splitting that would mangle it.
      const text = 'GS-II welfare delivery and GS-III agricultural support.';
      final r = SchemeDetailSheet.splitRelevance(text);
      expect(r.paper, isNull);
      expect(r.rest, text);
    });

    testWidgets('shows the paper as a badge when one is present',
        (tester) async {
      await _pumpSheet(tester, {
        'name': 'X Yojana',
        'description': 'Body',
        'upscRelevance': 'GS-III — Inclusive growth. Expect questions.',
      });
      expect(find.text('GS-III'), findsOneWidget);
      expect(find.text('Inclusive growth. Expect questions.'), findsOneWidget);
    });
  });

  group('field handling', () {
    test('bodyText prefers detailedDescription, falls back to description', () {
      expect(
        SchemeDetailSheet.bodyText(
            {'detailedDescription': 'long', 'description': 'short'}),
        'long',
      );
      expect(SchemeDetailSheet.bodyText({'description': 'short'}), 'short');
      expect(SchemeDetailSheet.bodyText({}), '');
    });

    test('whitespace-only values count as absent', () {
      expect(
        SchemeDetailSheet.bodyText(
            {'detailedDescription': '   ', 'description': 'real'}),
        'real',
      );
      expect(SchemeDetailSheet.isSparse({'description': '  '}), isTrue);
    });

    testWidgets('a completely empty map renders without throwing',
        (tester) async {
      await _pumpSheet(tester, <String, dynamic>{});
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Only a brief record exists'), findsOneWidget);
    });

    testWidgets('non-string entries in keyFeatures do not crash the sheet',
        (tester) async {
      await _pumpSheet(tester, {
        'name': 'Mixed',
        'description': 'Body',
        'keyFeatures': ['real feature', 42, null, '', '  '],
      });
      expect(find.text('real feature'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('readability', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('body text has real contrast in ${mode.name} mode',
          (tester) async {
        await _pumpSheet(tester, scraperScheme(), mode: mode);

        final bg =
            (mode == ThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme)
                .scaffoldBackgroundColor;
        var checked = 0;
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          final data = t.data;
          final color = t.style?.color;
          if (data == null || data.trim().isEmpty || color == null) continue;
          final delta =
              (color.computeLuminance() - bg.computeLuminance()).abs();
          expect(delta, greaterThan(0.05),
              reason: '"$data" is nearly invisible in ${mode.name} mode');
          checked++;
        }
        expect(checked, greaterThan(2));
      });
    }
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  SchemeDataLoader loader, {
  SchemeDataLoader? refresher,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: GovtSchemesScreen(
      loadSchemes: loader,
      refreshSchemes: refresher ?? loader,
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void governmentSchemeDataTests() {
  group('GovernmentScheme normalization', () {
    test('accepts legacy scalar and string-list field shapes', () {
      final scheme = GovernmentScheme.fromMap({
        'name': 'Legacy Yojana',
        'year': 2019,
        'keyFeatures': 'First feature; Second feature\nThird feature',
        'sector': 'Financial',
      });
      expect(scheme.year, '2019');
      expect(scheme.keyFeatures,
          ['First feature', 'Second feature', 'Third feature']);
      expect(scheme.sector, 'Financial Inclusion');
    });

    test('malformed map/list scalar fields do not throw or print Dart dumps',
        () {
      final scheme = GovernmentScheme.fromMap({
        'name': ['not', 'a', 'name'],
        'year': {'seconds': 123},
        'ministry': <String>['wrong container'],
        'keyFeatures': 42,
      });
      expect(scheme.name, '');
      expect(scheme.year, '');
      expect(scheme.ministry, '');
      expect(scheme.keyFeatures, isEmpty);
    });

    test('canonicalizes every sector emitted by the generator', () {
      expect(
          GovernmentScheme.canonicalSector('Women & Child'), 'Social Welfare');
      expect(GovernmentScheme.canonicalSector('Rural'), 'Social Welfare');
      expect(
          GovernmentScheme.canonicalSector('Financial'), 'Financial Inclusion');
      expect(GovernmentScheme.canonicalSector('Energy'), 'Infrastructure');
      expect(GovernmentScheme.canonicalSector('Governance'), 'Governance');
    });

    test('curated essentials remain when remote data is non-empty', () {
      final records = GovernmentScheme.combine(
        [
          {
            'name': 'A New Remote Mission',
            'description': 'Remote-only record',
            'sector': 'Governance',
          }
        ],
        OfflineContent.govtSchemes,
      );
      expect(records.any((s) => s.name == 'A New Remote Mission'), isTrue);
      expect(records.any((s) => s.name == 'PM-KISAN'), isTrue,
          reason: 'one remote doc must not suppress all curated essentials');
      expect(records.length, OfflineContent.govtSchemes.length + 1);
    });

    test('blank remote fields cannot erase richer curated fields', () {
      final records = GovernmentScheme.combine(
        [
          {
            'name': 'PM-KISAN',
            'description': '',
            'ministry': null,
            'year': 2026,
          }
        ],
        OfflineContent.govtSchemes,
      );
      final pmKisan = records.singleWhere((s) => s.name == 'PM-KISAN');
      expect(pmKisan.description, isNotEmpty);
      expect(pmKisan.ministry, isNotEmpty);
      expect(pmKisan.year, '2026');
    });
  });

  group('Government schemes screen', () {
    testWidgets('renders remote and curated records together', (tester) async {
      await _pumpScreen(tester, () async => [scraperScheme()]);
      expect(find.text('Gaganyaan Mission'), findsWidgets);
      expect(find.text('${OfflineContent.govtSchemes.length + 1} schemes'),
          findsOneWidget,
          reason: 'the remote record must be added to all curated essentials');
      expect(tester.takeException(), isNull);
    });

    testWidgets('search includes ministry, features, and UPSC relevance',
        (tester) async {
      final remote = scraperScheme()
        ..['ministry'] = 'Ministry of Space'
        ..['keyFeatures'] = ['Crew escape system']
        ..['upscRelevance'] = 'GS-III space technology';
      await _pumpScreen(tester, () async => [remote]);

      await tester.enterText(find.byType(TextField), 'escape system');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Gaganyaan Mission'), findsWidgets);
      expect(find.textContaining('1 of '), findsOneWidget);
    });

    testWidgets('generator sector aliases match a visible filter chip',
        (tester) async {
      final remote = scraperScheme()
        ..['name'] = 'Financial Access Scheme'
        ..['sector'] = 'Financial';
      await _pumpScreen(tester, () async => [remote]);

      final chipList = find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      );
      await tester.drag(chipList, const Offset(-500, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(
        find.widgetWithText(FilterChip, 'Financial Inclusion'),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Financial Access Scheme'), findsWidgets);
      final all = GovernmentScheme.combine(
        [remote],
        OfflineContent.govtSchemes,
      );
      final matches =
          all.where((scheme) => scheme.sector == 'Financial Inclusion').length;
      expect(find.text('$matches of ${all.length} schemes'), findsOneWidget);
    });

    testWidgets('a backend failure still shows bundled essentials',
        (tester) async {
      await _pumpScreen(tester, () async => throw Exception('offline'));
      expect(find.text('${OfflineContent.govtSchemes.length} schemes'),
          findsOneWidget);
      expect(find.textContaining('Showing saved essentials'), findsOneWidget);
      expect(find.text('Failed to load schemes'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no-match state explains filters and clears them',
        (tester) async {
      await _pumpScreen(tester, () async => [scraperScheme()]);
      await tester.enterText(find.byType(TextField), 'definitely absent');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('No schemes match'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('${OfflineContent.govtSchemes.length + 1} schemes'),
          findsOneWidget);
    });
  });
}

void main() {
  _detailSheetTests();
  governmentSchemeDataTests();
}
