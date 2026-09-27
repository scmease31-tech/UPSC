import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/data/offline_content.dart';
import 'package:upsc_daily_edge/models/government_scheme.dart';
import 'package:upsc_daily_edge/screens/features/govt_schemes_screen.dart';
import 'package:upsc_daily_edge/screens/features/scheme_detail_sheet.dart';

import 'support/load_app_fonts.dart';

Map<String, dynamic> _legacyScheme() => <String, dynamic>{
      'id': 'gs-legacy',
      'name': 'Gaganyaan Mission',
      'description': 'India\'s first crewed orbital spaceflight programme.',
      'sector': 'Science & Technology',
      // Legacy year is article coverage, never an inferred launch year.
      'year': '2026',
    };

Map<String, dynamic> _canonicalScheme() => <String, dynamic>{
      'id': 'gs-canonical',
      'schemaVersion': 2,
      'normalizedName': 'canonicalartisanmission',
      'name': 'Canonical Artisan Mission',
      'fullForm': 'CAM',
      'description': 'A concise artisan-support scheme summary.',
      'detailedDescription':
          'A national mission supporting traditional artisans through skills, '
              'credit, market access and modern toolkits.',
      'ministry': 'Ministry of Micro, Small and Medium Enterprises',
      'sector': 'Financial',
      'year': '2026',
      'coverageYear': '2026',
      'launchYear': '2023',
      'objective': 'Strengthen the artisan value chain sustainably.',
      'beneficiaries': <String>[
        'Traditional artisans',
        'Craft workers in notified trades',
      ],
      'eligibility': <String>[
        'Applicant practises a notified traditional trade',
      ],
      'benefits': <String>[
        'Collateral-free enterprise credit',
        'Toolkit and training support',
      ],
      'funding': 'Central Sector scheme with an outlay of ₹13,000 crore.',
      'implementation':
          'Implemented through state committees and district verification.',
      'keyFeatures': <String>[
        'Digital registration through assisted centres',
        'Quality certification and market linkage',
      ],
      'upscRelevance':
          'GS-III — Inclusive growth, skilling and formalisation of work.',
      'officialUrl': 'https://artisan.gov.in/scheme',
      'sources': <Map<String, dynamic>>[
        <String, dynamic>{
          'articleId': 'pib-1',
          'title': 'Cabinet approves artisan mission',
          'url': 'https://www.pib.gov.in/PressReleasePage.aspx?PRID=1',
          'publisher': 'Press Information Bureau',
          'publishedDate': '2023-08-16',
          'official': true,
        },
        <String, dynamic>{
          'articleId': 'news-1',
          'title': 'How the artisan mission will work',
          'url': 'https://example.com/artisan-explainer',
          'publisher': 'Example Daily',
          'publishedDate': '2023-08-17',
          'official': false,
        },
      ],
      'iconName': 'engineering',
      'colorHex': '#7C3AED',
    };

Future<void> _pumpSheet(
  WidgetTester tester,
  Map<String, dynamic> scheme, {
  ThemeMode mode = ThemeMode.light,
  SchemeUrlLauncher? launcher,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      home: Scaffold(
        body: SchemeDetailSheet(scheme: scheme, urlLauncher: launcher),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    350,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(
  WidgetTester tester,
  SchemeDataLoader loader,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: GovtSchemesScreen(loadSchemes: loader, refreshSchemes: loader),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('GovernmentScheme canonical normalization', () {
    test('round-trips every typed field and source object', () {
      final scheme = GovernmentScheme.fromMap(_canonicalScheme());
      expect(scheme.schemaVersion, 2);
      expect(scheme.normalizedName, 'canonicalartisanmission');
      expect(scheme.coverageYear, '2026');
      expect(scheme.launchYear, '2023');
      expect(scheme.objective, contains('artisan value chain'));
      expect(scheme.beneficiaries, hasLength(2));
      expect(scheme.eligibility, hasLength(1));
      expect(scheme.benefits, hasLength(2));
      expect(scheme.funding, contains('13,000 crore'));
      expect(scheme.implementation, contains('district verification'));
      expect(scheme.sources, hasLength(2));
      expect(scheme.sources.first.official, isTrue);
      expect(scheme.sources.last.official, isFalse);
      expect(scheme.hasVerifiedOfficialSource, isTrue);

      final roundTrip = GovernmentScheme.fromMap(scheme.toMap());
      expect(roundTrip.schemaVersion, scheme.schemaVersion);
      expect(roundTrip.normalizedName, scheme.normalizedName);
      expect(roundTrip.sourceSector, scheme.sourceSector);
      expect(roundTrip.coverageYear, scheme.coverageYear);
      expect(roundTrip.launchYear, scheme.launchYear);
      expect(roundTrip.beneficiaries, scheme.beneficiaries);
      expect(
        roundTrip.sources.map((source) => source.toMap()).toList(),
        scheme.sources.map((source) => source.toMap()).toList(),
      );
    });

    test('all canonical details and source metadata are searchable', () {
      final text = GovernmentScheme.fromMap(_canonicalScheme()).searchableText;
      for (final term in <String>[
        'canonicalartisanmission',
        'artisan value chain',
        'traditional artisans',
        'notified traditional trade',
        'collateral-free',
        '13,000 crore',
        'district verification',
        'digital registration',
        'inclusive growth',
        'artisan.gov.in',
        'press information bureau',
        '2023-08-17',
        'news-1',
      ]) {
        expect(text, contains(term), reason: 'missing $term');
      }
    });

    test('keeps explicit launch year separate from legacy coverage year', () {
      final legacy = GovernmentScheme.fromMap(<String, dynamic>{
        'name': 'Legacy',
        'year': 2026,
      });
      expect(legacy.coverageYear, '2026');
      expect(legacy.launchYear, isEmpty);

      final canonical = GovernmentScheme.fromMap(<String, dynamic>{
        'name': 'Canonical',
        'year': '2024',
        'coverageYear': '2025',
        'launchYear': '2018',
      });
      expect(canonical.year, '2024');
      expect(canonical.coverageYear, '2025');
      expect(canonical.launchYear, '2018');
    });

    test('recovers legacy lists and safely omits malformed shapes', () {
      final scheme = GovernmentScheme.fromMap(<String, dynamic>{
        'name': 'Legacy Yojana',
        'schemaVersion': '2',
        'year': 2019,
        'keyFeatures': <Object?>[
          'First feature',
          42,
          null,
          <String, String>{'bad': 'shape'},
          <String>['nested'],
        ],
        'beneficiaries': 'Farmers; Tenant cultivators\nSharecroppers',
        'ministry': <String>['wrong container'],
        'sources': <Object?>[
          'not a map',
          <String, dynamic>{
            'url': <String>['wrong']
          },
          <String, dynamic>{
            'title': 'Usable partial citation',
            'official': true,
          },
        ],
      });
      expect(scheme.schemaVersion, 2);
      expect(scheme.coverageYear, '2019');
      expect(scheme.keyFeatures, <String>['First feature', '42']);
      expect(
        scheme.beneficiaries,
        <String>['Farmers', 'Tenant cultivators', 'Sharecroppers'],
      );
      expect(scheme.ministry, isEmpty);
      expect(scheme.sources, hasLength(1));
      expect(scheme.sources.single.official, isFalse,
          reason: 'a flag without a verified URL is not official');
    });

    test('validates HTTPS government domains and rejects lookalikes', () {
      for (final url in <String>[
        'https://gov.in/scheme',
        'https://www.pib.gov.in/release',
        'https://portal.nic.in/path',
        'https://myscheme.gov.in/',
      ]) {
        expect(GovernmentScheme.isVerifiedOfficialUrl(url), isTrue,
            reason: url);
      }
      for (final url in <Object?>[
        'http://pib.gov.in/release',
        'https://gov.in.evil.example/scheme',
        'https://evilgov.in/scheme',
        'https://gov.in@evil.example/scheme',
        'ftp://portal.nic.in/file',
        'not a URL',
        42,
        null,
      ]) {
        expect(GovernmentScheme.isVerifiedOfficialUrl(url), isFalse,
            reason: '$url');
      }
    });

    test('merges arrays and citations deterministically without data loss', () {
      final records = GovernmentScheme.combine(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'The Merge Yojana',
            'objective': 'Generated objective must not replace curation',
            'coverageYear': '2026',
            'launchYear': '2020',
            'keyFeatures': <String>['Curated fact', 'Remote fact'],
            'beneficiaries': <String>['Women artisans'],
            'officialUrl': 'https://gov.in.evil.example/fake',
            'sources': <Map<String, dynamic>>[
              <String, dynamic>{
                'articleId': 'a-1',
                'title': 'Changed duplicate title',
                'url': 'https://example.com/one/',
                'publisher': 'Filled Publisher',
              },
              <String, dynamic>{
                'articleId': 'a-2',
                'title': 'Official release',
                'url': 'https://press.gov.in/release',
                'publishedDate': '2025-01-01',
                'official': false,
              },
            ],
          },
        ],
        <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'Merge Yojana',
            'objective': 'Curated objective remains',
            'year': '2024',
            'keyFeatures': <String>['Curated fact'],
            'beneficiaries': <String>['Rural artisans'],
            'officialUrl': 'https://scheme.nic.in/home',
            'sources': <Map<String, dynamic>>[
              <String, dynamic>{
                'articleId': 'a-1',
                'title': 'Curated citation title',
                'url': 'https://example.com/one',
                'publishedDate': '2024-01-01',
              },
            ],
          },
        ],
      );

      final scheme = records.single;
      expect(scheme.objective, 'Curated objective remains');
      expect(scheme.coverageYear, '2026');
      expect(scheme.launchYear, '2020');
      expect(scheme.keyFeatures, <String>['Curated fact', 'Remote fact']);
      expect(
        scheme.beneficiaries,
        <String>['Rural artisans', 'Women artisans'],
      );
      expect(scheme.officialUrl, 'https://scheme.nic.in/home');
      expect(scheme.sources, hasLength(2));
      expect(scheme.sources.first.articleId, 'a-1');
      expect(scheme.sources.first.title, 'Curated citation title');
      expect(scheme.sources.first.publisher, 'Filled Publisher');
      expect(scheme.sources.last.articleId, 'a-2');
      expect(scheme.sources.last.official, isTrue,
          reason: 'domain validation, not the false flag, establishes trust');
    });

    test('curated floor survives sparse or malformed remote rows', () {
      final records = GovernmentScheme.combine(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'PM-KISAN',
            'description': '',
            'ministry': <String>['malformed'],
            'year': 2026,
            'keyFeatures': <String>[],
          },
          <String, dynamic>{
            'name': 'A New Remote Mission',
            'description': 'Remote-only record',
            'sector': 'Governance',
          },
        ],
        OfflineContent.govtSchemes,
      );
      final pmKisan =
          records.singleWhere((scheme) => scheme.name == 'PM-KISAN');
      expect(pmKisan.description, isNotEmpty);
      expect(pmKisan.ministry, isNotEmpty);
      expect(pmKisan.coverageYear, '2026');
      expect(pmKisan.launchYear, isEmpty);
      expect(pmKisan.keyFeatures, isNotEmpty);
      expect(records.any((scheme) => scheme.name == 'A New Remote Mission'),
          isTrue);
      expect(records.length, OfflineContent.govtSchemes.length + 1);
    });
  });

  group('SchemeDetailSheet', () {
    testWidgets('renders every requested section and citation label',
        (tester) async {
      await _pumpSheet(tester, _canonicalScheme());
      for (final heading in <String>[
        'AT A GLANCE',
        'OBJECTIVE',
        'INTENDED BENEFICIARIES',
        'ELIGIBILITY',
        'BENEFITS',
        'FUNDING/OUTLAY',
        'IMPLEMENTATION',
        'KEY FACTS',
        'SOURCES',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      expect(find.text('UPSC Relevance'), findsOneWidget);
      expect(find.text('Coverage year'), findsOneWidget);
      expect(find.text('Launch year'), findsOneWidget);
      expect(find.text('Verified official source'), findsOneWidget);
      expect(find.text('Source article'), findsOneWidget);
      expect(find.text('Publisher: Press Information Bureau'), findsOneWidget);
      expect(find.text('Published: 2023-08-16'), findsOneWidget);
      expect(find.text('Open official page'), findsOneWidget);
      expect(find.text('Search official government sources'), findsOneWidget);
      expect(find.textContaining('Only a brief record exists'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('omits absent sections and keeps an honest sparse note',
        (tester) async {
      await _pumpSheet(tester, <String, dynamic>{'name': 'Sparse Mission'});
      for (final heading in <String>[
        'AT A GLANCE',
        'OBJECTIVE',
        'INTENDED BENEFICIARIES',
        'ELIGIBILITY',
        'BENEFITS',
        'FUNDING/OUTLAY',
        'IMPLEMENTATION',
        'KEY FACTS',
        'SOURCES',
      ]) {
        expect(find.text(heading), findsNothing, reason: heading);
      }
      expect(find.text('UPSC Relevance'), findsNothing);
      expect(find.textContaining('Only a brief record exists'), findsOneWidget);
      expect(find.text('Search official government sources'), findsOneWidget);
    });

    testWidgets('never presents legacy coverage as a launch year',
        (tester) async {
      await _pumpSheet(tester, _legacyScheme());
      expect(
          find.text(_legacyScheme()['description']! as String), findsOneWidget);
      expect(find.text('Coverage year'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('Launch year'), findsNothing);
    });

    testWidgets('invalid official URL is omitted, not launched or cited',
        (tester) async {
      await _pumpSheet(tester, <String, dynamic>{
        'name': 'Lookalike Scheme',
        'officialUrl': 'https://gov.in.evil.example/scheme',
      });
      expect(find.text('SOURCES'), findsNothing);
      expect(find.text('Open official page'), findsNothing);
      expect(find.text('Search official government sources'), findsOneWidget);
    });

    test('constructs an encoded site-restricted search URI', () {
      final uri = SchemeDetailSheet.buildOfficialSearchUri(
        'PM Artisan & Skills Mission',
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/search');
      expect(uri.toString(), isNot(contains(' ')));
      expect(
        uri.queryParameters['q'],
        '"PM Artisan & Skills Mission" '
        '(site:myscheme.gov.in OR site:pib.gov.in OR site:gov.in OR site:nic.in)',
      );
      expect(uri.toString(), isNot(contains('.apk')));
      expect(uri.toString(), isNot(contains('github')));
    });

    testWidgets('injected launch actions run only after explicit taps',
        (tester) async {
      final launched = <Uri>[];
      await _pumpSheet(
        tester,
        _canonicalScheme(),
        launcher: (uri) async {
          launched.add(uri);
          return true;
        },
      );
      expect(launched, isEmpty);

      final official = find.byKey(const Key('open-official-page'));
      await _scrollTo(tester, official);
      await tester.tap(official);
      await tester.pump();
      expect(launched, <Uri>[Uri.parse('https://artisan.gov.in/scheme')]);

      final source = find.byKey(
        const ValueKey<String>('open-scheme-source-1'),
      );
      await _scrollTo(tester, source);
      await tester.tap(source);
      await tester.pump();
      expect(launched.last, Uri.parse('https://example.com/artisan-explainer'));

      final search = find.byKey(const Key('search-official-sources'));
      await _scrollTo(tester, search);
      await tester.tap(search);
      await tester.pump();
      expect(launched, hasLength(3));
      expect(launched.last.host, 'www.google.com');
      expect(launched.last.queryParameters['q'], contains('site:pib.gov.in'));
    });

    test('parses UPSC paper badges without mangling ordinary prose', () {
      final split = SchemeDetailSheet.splitRelevance(
        'GS-II / GS-III — Policy delivery and inclusive growth.',
      );
      expect(split.paper, 'GS-II / GS-III');
      expect(split.rest, 'Policy delivery and inclusive growth.');
      const prose = 'GS-II welfare delivery and GS-III agricultural support.';
      expect(SchemeDetailSheet.splitRelevance(prose).paper, isNull);
      expect(SchemeDetailSheet.splitRelevance(prose).rest, prose);
    });

    for (final mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      testWidgets('renders safely in ${mode.name} mode', (tester) async {
        await _pumpSheet(tester, _canonicalScheme(), mode: mode);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('renders safely on a 320px-wide phone', (tester) async {
      await _pumpSheet(
        tester,
        _canonicalScheme(),
        size: const Size(320, 780),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Government schemes screen', () {
    testWidgets('searches new fields and shows compact completeness cues',
        (tester) async {
      await _pumpScreen(
        tester,
        () async => <Map<String, dynamic>>[_canonicalScheme()],
      );
      await tester.enterText(
        find.byType(TextField),
        'district verification example daily',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Canonical Artisan Mission'), findsWidgets);
      expect(find.textContaining('1 of '), findsOneWidget);
      expect(find.text('Coverage: 2026'), findsOneWidget);
      expect(find.text('Launch: 2023'), findsOneWidget);
      expect(find.text('2 beneficiary groups'), findsOneWidget);
      expect(find.text('Verified source'), findsOneWidget);
    });

    testWidgets('card map transport retains structured detail', (tester) async {
      await _pumpScreen(
        tester,
        () async => <Map<String, dynamic>>[_canonicalScheme()],
      );
      await tester.enterText(
        find.byType(TextField),
        'Canonical Artisan Mission',
      );
      await tester.pump(const Duration(milliseconds: 200));
      // find.text also sees the TextField value; the card title is last.
      await tester.tap(find.text('Canonical Artisan Mission').last);
      await tester.pumpAndSettle();
      expect(find.text('OBJECTIVE'), findsOneWidget);
      expect(find.text('Strengthen the artisan value chain sustainably.'),
          findsOneWidget);
      expect(find.text('SOURCES'), findsOneWidget);
    });

    testWidgets('backend failure retains bundled essentials', (tester) async {
      await _pumpScreen(tester, () async => throw Exception('offline'));
      expect(
        find.text('${OfflineContent.govtSchemes.length} schemes'),
        findsOneWidget,
      );
      expect(find.textContaining('Showing saved essentials'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no-match filters can be cleared', (tester) async {
      await _pumpScreen(
        tester,
        () async => <Map<String, dynamic>>[_legacyScheme()],
      );
      await tester.enterText(find.byType(TextField), 'definitely absent');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No schemes match'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.text('${OfflineContent.govtSchemes.length + 1} schemes'),
        findsOneWidget,
      );
    });
  });
}
