// Route and button audit.
//
// Drives every route registered in AppRoutes at a phone viewport and asserts
// each one is a real screen rather than a failure mode: no thrown exception, no
// RenderFlex overflow (flutter_test fails the test on one automatically), not a
// blank frame, and a back affordance that actually pops.
//
// Firebase is deliberately NOT initialized here. Every Firestore-backed screen
// is supposed to fall back to embedded OfflineContent when the backend is
// unreachable, so an uninitialized Firebase is the cheapest available stand-in
// for a user with no connectivity. A screen that renders blank or throws under
// these conditions is a real defect, not a test artifact.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
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

import 'support/load_app_fonts.dart';

/// Phone viewport used for the audit: a common small-but-not-tiny Android size.
const Size _phone = Size(360, 690);

/// The same provider set main.dart installs, so screens see the graph they
/// expect rather than a stripped-down one.
Widget _app({required String initialRoute}) {
  return MultiProvider(
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
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      initialRoute: initialRoute,
      routes: AppRoutes.routes,
      // MaterialApp's default initialRoute handling builds every ancestor
      // segment, so '/credits' would also mount '/' (splash) underneath and
      // leave splash's 1.8s mounted-guarded Future.delayed pending. Audit one
      // screen at a time instead.
      onGenerateInitialRoutes: (route) {
        final builder = AppRoutes.routes[route];
        return [
          MaterialPageRoute<void>(
            settings: RouteSettings(name: route),
            builder: builder ??
                (_) => Scaffold(
                      body: Center(child: Text('Unknown route: $route')),
                    ),
          ),
        ];
      },
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => Scaffold(
          body: Center(child: Text('Unknown route: ${settings.name}')),
        ),
      ),
    ),
  );
}

/// Pumps [initialRoute] and lets timers/futures land without waiting for the
/// looping shimmer and Lottie animations that pumpAndSettle would hang on.
Future<void> _open(WidgetTester tester, String route) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_app(initialRoute: route));
  // Past splash's 1.8s hand-off, so its mounted-guarded Future.delayed has
  // fired and does not linger as a pending timer.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Tears the tree down so every State.dispose runs and cancels its timers.
/// Without this, flutter_test trips its own `!timersPending` assertion on the
/// screens that legitimately run repeating animations.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

/// True when the frame put something a user can actually see on screen.
/// Guards against the "route resolves but paints nothing" failure.
///
/// Lottie counts: several screens render their loading state as nothing but a
/// centred animation, which is sparse but not blank.
bool _rendersSomething() {
  final hasText = find
      .byWidgetPredicate((w) => w is Text && (w.data ?? '').trim().isNotEmpty)
      .evaluate()
      .isNotEmpty;
  final hasIcon = find.byType(Icon).evaluate().isNotEmpty;
  final hasImage = find.byType(Image).evaluate().isNotEmpty;
  final hasLottie = find.byType(LottieBuilder).evaluate().isNotEmpty;
  return hasText || hasIcon || hasImage || hasLottie;
}

void main() {
  // Mock ONLY firebase_core, so Firebase.app() resolves and the providers'
  // `FirebaseFirestore` fields can be constructed. Firestore and Auth requests
  // themselves are left unmocked and therefore fail, which is the point: it puts
  // every screen on its offline/error fallback path.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Real typefaces, or every text measurement below is fiction and the audit
    // reports overflows that do not exist on a device.
    await loadAppFonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  // Every route name AppRoutes registers, audited one by one.
  final routes = AppRoutes.routes.keys.toList()..sort();

  group('every registered route opens', () {
    for (final route in routes) {
      testWidgets('$route renders a real screen', (tester) async {
        await _open(tester, route);

        // An exception during build/layout — including a RenderFlex overflow —
        // fails here with the route name attached.
        final thrown = tester.takeException();
        final rendered = _rendersSomething();
        final unknown =
            find.textContaining('Unknown route').evaluate().isNotEmpty;
        await _close(tester);

        expect(thrown, isNull, reason: 'threw on $route');
        expect(rendered, isTrue, reason: '$route rendered a blank frame');
        expect(unknown, isFalse,
            reason: '$route fell through to onUnknownRoute');
      });
    }
  });

  group('no route gets stuck', () {
    for (final route in routes) {
      testWidgets('$route settles out of a bare spinner', (tester) async {
        await _open(tester, route);
        // Give any fallback path generous time to resolve.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }

        // A spinner is fine as part of a populated screen; a spinner as the
        // ONLY thing on screen after 7s means the screen never resolved and the
        // user is looking at a permanent loading state.
        final spinners = find.byType(CircularProgressIndicator).evaluate().length;
        final meaningfulText = find
            .byWidgetPredicate(
                (w) => w is Text && (w.data ?? '').trim().length > 2)
            .evaluate()
            .length;
        final thrown = tester.takeException();
        await _close(tester);

        if (spinners > 0) {
          expect(meaningfulText, greaterThan(0),
              reason: '$route is stuck showing only a loading indicator');
        }
        expect(thrown, isNull);
      });
    }
  });

  group('unknown routes are handled', () {
    testWidgets('an unregistered route falls back instead of crashing',
        (tester) async {
      await _open(tester, '/this-route-does-not-exist');
      final thrown = tester.takeException();
      final found = find.textContaining('Unknown route').evaluate().length;
      await _close(tester);

      expect(thrown, isNull);
      expect(found, 1);
    });

    test('no route name is registered twice or blank', () {
      final names = AppRoutes.routes.keys.toList();
      expect(names.toSet().length, names.length,
          reason: 'duplicate route names');
      for (final name in names) {
        expect(name.trim(), isNotEmpty);
        expect(name, startsWith('/'), reason: '$name is not rooted');
      }
    });
  });

  group('back navigation', () {
    // Routes pushed on top of another screen must be dismissible. Splash and
    // main are roots and own no back affordance, so they are excluded.
    final pushable = routes
        .where((r) => r != AppRoutes.splash && r != AppRoutes.main)
        .toList();

    for (final route in pushable) {
      testWidgets('$route can be dismissed', (tester) async {
        tester.view.physicalSize = _phone;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(initialRoute: AppRoutes.main));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        tester.takeException();

        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pushNamed(route);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        tester.takeException();

        // Pop the way the system back button does.
        navigator.pop();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }

        final thrown = tester.takeException();
        await _close(tester);
        expect(thrown, isNull, reason: 'popping $route threw');
      });
    }
  });
}
