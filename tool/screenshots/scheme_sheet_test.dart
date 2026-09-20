// Captures the scheme detail sheet for visual review.
//   flutter test tool/screenshots/scheme_sheet_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/data/offline_content.dart';
import 'package:upsc_daily_edge/screens/features/scheme_detail_sheet.dart';

import '../../test/support/load_app_fonts.dart';

final _key = GlobalKey();
const _out = 'build/screenshots';

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final ui.Image img = await boundary.toImage(pixelRatio: 2.0);
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return d?.buffer.asUint8List();
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
  ThemeMode mode,
) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      home: Scaffold(body: SchemeDetailSheet(scheme: scheme)),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('complete scheme, light', (tester) async {
    await _pump(tester, Map<String, dynamic>.from(OfflineContent.govtSchemes.first),
        ThemeMode.light);
    await _shoot(tester, 'scheme-complete-light');
  });

  testWidgets('complete scheme, dark', (tester) async {
    await _pump(tester, Map<String, dynamic>.from(OfflineContent.govtSchemes.first),
        ThemeMode.dark);
    await _shoot(tester, 'scheme-complete-dark');
  });

  testWidgets('scraper-shaped scheme with derived detail', (tester) async {
    await _pump(tester, {
      'name': 'PM Vishwakarma Yojana',
      'fullForm': 'PMVY',
      'sector': 'Financial',
      'year': '2026',
      'ministry': 'Ministry of Micro, Small and Medium Enterprises',
      'detailedDescription':
          'The Union Cabinet has approved the PM Vishwakarma Yojana, implemented by the '
              'Ministry of Micro, Small and Medium Enterprises. PM Vishwakarma Yojana '
              'provides collateral-free credit of up to 3 lakh rupees in two tranches.',
      'keyFeatures': [
        'PM Vishwakarma Yojana provides collateral-free credit of up to 3 lakh rupees in two tranches to registered artisans.',
        'Under PM Vishwakarma Yojana, beneficiaries receive a stipend of 500 rupees per day during skill training.',
        'The scheme covers 18 traditional trades across the country.',
      ],
      'upscRelevance':
          'GS-III — Inclusive growth, mobilisation of resources and financial inclusion. '
              'Administered by the Ministry of Micro, Small and Medium Enterprises; appeared in '
              'coverage from 2026. Expect questions pairing the scheme with its ministry, '
              'objective and target group.',
      'iconName': 'engineering',
      'colorHex': '',
    }, ThemeMode.light);
    await _shoot(tester, 'scheme-derived-light');
  });

  testWidgets('sparse scheme', (tester) async {
    await _pump(tester,
        {'name': 'Sagarmala Mission', 'sector': 'Infrastructure', 'year': '2026'},
        ThemeMode.light);
    await _shoot(tester, 'scheme-sparse-light');
  });
}
