import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Owns the app's Firebase connections.
///
/// Android content, Google authentication, and private user data all use the
/// live `upsc-app-e2475-e5c95` project—the same project targeted by the daily
/// scraper service account.
class FirebaseServices {
  FirebaseServices._();

  static FirebaseApp? _app;

  static FirebaseApp get contentApp => _app ?? Firebase.app();
  static FirebaseApp get authApp => _app ?? Firebase.app();

  static FirebaseFirestore get contentFirestore =>
      FirebaseFirestore.instanceFor(app: contentApp);

  static FirebaseFirestore get userFirestore =>
      FirebaseFirestore.instanceFor(app: authApp);

  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: authApp);

  static const String expectedProjectId = 'upsc-app-e2475-e5c95';

  static Future<void> initialize({FirebaseOptions? optionsOverride}) async {
    final options = optionsOverride ?? DefaultFirebaseOptions.currentPlatform;
    if (options.projectId != expectedProjectId) {
      throw StateError(
        'Refusing Firebase project ${options.projectId}; expected $expectedProjectId.',
      );
    }

    if (_app != null) {
      _assertProject(_app!, options.projectId);
      return;
    }

    try {
      final app = await Firebase.initializeApp(options: options);
      _assertProject(app, options.projectId);
      _app = app;
      return;
    } catch (error) {
      // Android may already have a default app from google-services.json, and a
      // hot restart can retain one. Only adopt it if it points at the project we
      // explicitly requested. The old implementation adopted ANY existing app
      // after ANY initialization failure, silently turning a config error into
      // reads from the wrong database.
      if (Firebase.apps.isEmpty) rethrow;
      final app = Firebase.app();
      _assertProject(app, options.projectId);
      _app = app;
    }
  }

  static void _assertProject(FirebaseApp app, String expected) {
    final actual = app.options.projectId;
    if (actual != expected) {
      throw StateError(
        'Firebase project mismatch: initialized $actual, expected $expected.',
      );
    }
  }
}
