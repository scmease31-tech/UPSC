// Captures the scheme detail sheet for manual visual review.
//   flutter test tool/screenshots/scheme_sheet_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/screens/features/scheme_detail_sheet.dart';

import '../../test/support/load_app_fonts.dart';

final _key = GlobalKey();
const _out = 'build/screenshots';

Map<String, dynamic> _richScheme() => <String, dynamic>{
      'name': 'PM Vishwakarma Yojana',
      'fullForm': 'PMVY',
      'sector': 'Financial',
      'coverageYear': '2026',
      'launchYear': '2023',
      'ministry': 'Ministry of Micro, Small and Medium Enterprises',
      'detailedDescription':
          'A Central Sector scheme supporting traditional artisans through '
              'skills, modern tools, affordable credit and market linkages.',
      'objective':
          'Improve the quality, scale and reach of products made by artisans.',
      'beneficiaries': <String>[
        'Artisans and craftspeople in 18 notified traditional trades',
      ],
      'eligibility': <String>[
        'Applicant must work with their hands and tools in a notified trade',
      ],
      'benefits': <String>[
        'Collateral-free enterprise credit in two tranches',
        'Training stipend and toolkit incentive',
      ],
      'funding': 'Central Sector scheme with a ₹13,000 crore outlay.',
      'implementation':
          'Village, district and state committees verify and enrol applicants.',
      'keyFeatures': <String>[
        'Digital identity card and certificate',
        'Quality certification, branding and market support',
      ],
      'upscRelevance':
          'GS-III — Inclusive growth, skilling, MSMEs and formalisation.',
      'officialUrl': 'https://pmvishwakarma.gov.in/',
      'sources': <Map<String, dynamic>>[
        <String, dynamic>{
          'articleId': 'pib-pmvy',
          'title': 'Cabinet approves PM Vishwakarma',
          'url': 'https://www.pib.gov.in/PressReleasePage.aspx?PRID=1',
          'publisher': 'Press Information Bureau',
          'publishedDate': '2023-08-16',
          'official': true,
        },
        <String, dynamic>{
          'articleId': 'news-pmvy',
          'title': 'Explained: support for traditional artisans',
          'url': 'https://example.com/pm-vishwakarma',
          'publisher': 'Example Daily',
          'publishedDate': '2023-09-01',
          'official': false,
        },
      ],
      'iconName': 'engineering',
      'colorHex': '#7C3AED',
    };

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary =
      _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);
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

Future<void> _pump(
  WidgetTester tester,
  Map<String, dynamic> scheme,
  ThemeMode mode, {
  Size size = const Size(390, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        home: Scaffold(body: SchemeDetailSheet(scheme: scheme)),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('structured scheme, light', (tester) async {
    await _pump(tester, _richScheme(), ThemeMode.light);
    await _shoot(tester, 'scheme-structured-light');
  });

  testWidgets('structured scheme, dark', (tester) async {
    await _pump(tester, _richScheme(), ThemeMode.dark);
    await _shoot(tester, 'scheme-structured-dark');
  });

  testWidgets('structured scheme, narrow phone', (tester) async {
    await _pump(
      tester,
      _richScheme(),
      ThemeMode.light,
      size: const Size(320, 780),
    );
    await _shoot(tester, 'scheme-structured-narrow');
  });

  testWidgets('sparse legacy scheme', (tester) async {
    await _pump(
      tester,
      <String, dynamic>{
        'name': 'Sagarmala Mission',
        'sector': 'Infrastructure',
        'year': '2026',
      },
      ThemeMode.light,
    );
    await _shoot(tester, 'scheme-sparse-light');
  });
}
