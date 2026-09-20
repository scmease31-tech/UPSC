// Renders the five main tabs and writes PNGs to build/screenshots/ for visual
// inspection.
//
// Why not drive the web build with Playwright instead: on web MainNavigation
// renders WebShell, a sidebar layout behind a marketing landing page. That is a
// different UI from the one the Android release ships. Rendering the widget tree
// here captures the actual mobile layout, at a real phone size, with the bundled
// fonts loaded, so the images reflect what a user sees.
//
// These assert nothing about pixels — they are a capture harness. The assertions
// live in route_audit_test.dart. Output goes to build/, which is not committed.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:upsc_daily_edge/config/routes.dart';
import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/providers/articles_provider.dart';
import 'package:upsc_daily_edge/providers/auth_provider.dart';
import 'package:upsc_daily_edge/providers/bookmarks_provider.dart';
import 'package:upsc_daily_edge/providers/daily_progress_provider.dart';
import 'package:upsc_daily_edge/providers/quiz_provider.dart';
import 'package:upsc_daily_edge/providers/study_provider.dart';
import 'package:upsc_daily_edge/providers/theme_provider.dart';

import '../../test/support/load_app_fonts.dart';

const String _outDir = 'build/screenshots';
final GlobalKey _shotKey = GlobalKey();

Widget _app(ThemeMode mode) => RepaintBoundary(
      key: _shotKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ArticlesProvider()),
          ChangeNotifierProvider(create: (_) => QuizProvider()),
          ChangeNotifierProvider(create: (_) => BookmarksProvider()),
          ChangeNotifierProvider(create: (_) => StudyProvider()),
          ChangeNotifierProvider(create: (_) => DailyProgressProvider()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          initialRoute: AppRoutes.main,
          routes: AppRoutes.routes,
          onGenerateInitialRoutes: (r) => [
            MaterialPageRoute<void>(
              settings: RouteSettings(name: r),
              builder: AppRoutes.routes[r]!,
            ),
          ],
        ),
      ),
    );

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary =
      _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  });
  if (bytes == null) return;
  Directory(_outDir).createSync(recursive: true);
  File('$_outDir/$name.png').writeAsBytesSync(bytes);
  // ignore: avoid_print
  print('CAPTURED $_outDir/$name.png (${bytes.length ~/ 1024}KB)');
}

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  setUp(() {
    // Only firebase_core is mocked, so Auth's token/state listeners and
    // Firestore's snapshot streams raise PlatformException off-frame — often
    // after the body has finished, which fails the test no matter where
    // takeException is called. Swallow exactly those; anything else still
    // surfaces. This harness makes no assertions, so nothing is being hidden:
    // the assertions live in route_audit_test.dart.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exception.toString();
      final isUnmockedFirebase = details.exception is PlatformException &&
          (text.contains('firebase') ||
              text.contains('Firebase') ||
              text.contains('channel-error'));
      if (isUnmockedFirebase) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  });

  const tabs = <String>['Home', 'News', 'Quiz', 'Study', 'Profile'];

  testWidgets('phone 390x844 — every tab, light', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(ThemeMode.light));
    await _settle(tester);
    tester.takeException();

    for (var i = 0; i < tabs.length; i++) {
      final label = find.text(tabs[i]);
      if (label.evaluate().isNotEmpty) {
        await tester.tap(label.first, warnIfMissed: false);
        await _settle(tester);
        tester.takeException();
      }
      await _capture(tester, 'phone-light-${i + 1}-${tabs[i].toLowerCase()}');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('phone 390x844 — every tab, dark', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(ThemeMode.dark));
    await _settle(tester);
    tester.takeException();

    for (var i = 0; i < tabs.length; i++) {
      final label = find.text(tabs[i]);
      if (label.evaluate().isNotEmpty) {
        await tester.tap(label.first, warnIfMissed: false);
        await _settle(tester);
        tester.takeException();
      }
      await _capture(tester, 'phone-dark-${i + 1}-${tabs[i].toLowerCase()}');
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('narrow 320x640 — home, the tightest supported phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(ThemeMode.light));
    await _settle(tester);
    tester.takeException();
    await _capture(tester, 'narrow-320-home');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('wide 900x1000 — tablet width on the mobile layout',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(ThemeMode.light));
    await _settle(tester);
    tester.takeException();
    await _capture(tester, 'wide-900-home');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
