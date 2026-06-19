import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
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

/// Global navigator key for notification deep-linking.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Entry point of the UPSC Daily Edge application.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style for status bar
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));

  // Lock to portrait orientation for consistent UI
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Enable offline persistence so app works without network
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 50 * 1024 * 1024, // 50 MB — prevents storage bloat on low-end devices
    );
  } catch (_) {
    // Firebase init may fail — app will degrade gracefully
  }

  // Launch the app immediately — defer non-critical services
  runApp(const UPSCDailyEdgeApp());

  // Initialize services in background — don't block app startup
  _initServicesAsync();
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
  const UPSCDailyEdgeApp({super.key});

  @override
  Widget build(BuildContext context) {
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
    );
  }
}
