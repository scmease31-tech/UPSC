import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'providers/auth_provider.dart';
import 'providers/articles_provider.dart';
import 'providers/quiz_provider.dart';
import 'providers/bookmarks_provider.dart';
import 'providers/study_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/daily_progress_provider.dart';
import 'services/notification_service.dart';
import 'services/ad_service.dart';
import 'services/gemini_service.dart';
import 'services/firebase_services.dart';

/// Global navigator key for notification deep-linking.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Entry point of the UPSC Daily Edge application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface the bundled fonts' licences in Flutter's licence page. Package
  // licences are collected automatically; assets we ship ourselves are not, and
  // the OFL requires its text to travel with the fonts.
  LicenseRegistry.addLicense(() async* {
    for (final entry in const <String, String>{
      'Inter': 'assets/fonts/OFL-Inter.txt',
      'Plus Jakarta Sans': 'assets/fonts/OFL-PlusJakartaSans.txt',
    }.entries) {
      final text = await rootBundle.loadString(entry.value);
      yield LicenseEntryWithLineBreaks(<String>[entry.key], text);
    }
  });

  // Set system UI overlay style for status bar (mobile only)
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));

    // Do not hold the first Flutter frame behind a platform-channel response.
    // Orientation lock is best-effort and can settle after the bootstrap paints.
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]));
  }

  // Paint immediately. Firebase initialization used to run before runApp with
  // no deadline, so a stalled platform channel produced a literal blank screen.
  // The bootstrap below gives it a bounded wait and a working retry surface.
  runApp(const UPSCDailyEdgeBootstrap());
}

class UPSCDailyEdgeBootstrap extends StatefulWidget {
  const UPSCDailyEdgeBootstrap({super.key});

  @override
  State<UPSCDailyEdgeBootstrap> createState() => _UPSCDailyEdgeBootstrapState();
}

class _UPSCDailyEdgeBootstrapState extends State<UPSCDailyEdgeBootstrap> {
  bool _initializing = true;
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!_initializing) setState(() => _initializing = true);
    try {
      await FirebaseServices.initialize().timeout(const Duration(seconds: 12));
      if (!kIsWeb) {
        FirebaseServices.contentFirestore.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: 50 * 1024 * 1024,
        );
      }
      if (!mounted) return;
      setState(() {
        _ready = true;
        _error = null;
        _initializing = false;
      });
      unawaited(_initServicesAsync());
    } catch (error, stackTrace) {
      debugPrint('Firebase startup failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _ready = false;
        _error = error;
        _initializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const UPSCDailyEdgeApp();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _initializing
          ? const _StartupLoadingScreen()
          : _StartupErrorScreen(error: _error!, onRetry: _initialize),
    );
  }
}

class _StartupLoadingScreen extends StatelessWidget {
  const _StartupLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(height: 16),
              Text('Starting UPSC Daily Edge…'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Non-critical service initialization — runs after runApp so the UI isn't blocked.
Future<void> _initServicesAsync() async {
  try {
    await NotificationService.initialize(navigatorKey);
    await NotificationService.scheduleAllDailyNotifications();
  } catch (_) {
    // Notification setup may fail on emulators — don't crash the app
  }
  try {
    await AdService.initialize();
  } catch (_) {
    // Ad SDK may fail on emulators — don't crash the app
  }
  try {
    await GeminiService.initialize();
  } catch (_) {
    // Gemini initialization is optional
  }
}

class UPSCDailyEdgeApp extends StatelessWidget {
  final Object? startupError;

  const UPSCDailyEdgeApp({super.key, this.startupError});

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: _StartupErrorScreen(error: startupError!),
      );
    }

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
      child: const _AppWithBookmarkSync(),
    );
  }
}

/// Wrapper that syncs bookmarks when auth state changes.
class _AppWithBookmarkSync extends StatefulWidget {
  const _AppWithBookmarkSync();

  @override
  State<_AppWithBookmarkSync> createState() => _AppWithBookmarkSyncState();
}

class _AppWithBookmarkSyncState extends State<_AppWithBookmarkSync> {
  String? _lastSyncedUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    if (auth.isLoggedIn && auth.firebaseUser != null) {
      final uid = auth.firebaseUser!.uid;
      if (_lastSyncedUid != uid) {
        _lastSyncedUid = uid;
        context.read<BookmarksProvider>().loadUserBookmarks(uid);
      }
    } else {
      if (_lastSyncedUid != null) {
        context.read<BookmarksProvider>().clearBookmarks();
      }
      _lastSyncedUid = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp(
      title: 'UPSC Daily Edge',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
      onUnknownRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _UnknownRouteScreen(routeName: settings.name),
      ),
      // The app uses fixed-height hero cards in several places, which cannot
      // absorb unbounded system font scaling - on "Largest" text those cards
      // overflow on any device. Clamping keeps the app usable for people who
      // enlarge text while keeping every layout intact. Raise the ceiling only
      // once those cards size themselves intrinsically.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child!,
        );
      },
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const _StartupErrorScreen({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 64, color: AppTheme.errorRed),
                const SizedBox(height: 18),
                const Text(
                  'The app could not start its data service',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Check your internet connection, close the app completely, and open it again. Your saved device data is safe.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry connection'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnknownRouteScreen extends StatelessWidget {
  final String? routeName;

  const _UnknownRouteScreen({this.routeName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page unavailable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded,
                  size: 58, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              const Text(
                'This page could not be opened.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (routeName != null) ...[
                const SizedBox(height: 6),
                Text(routeName!, style: TextStyle(color: Colors.grey.shade600)),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppRoutes.main,
                  (_) => false,
                ),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Go to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
