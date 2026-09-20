import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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

  static Future<void> initialize() async {
    if (_app != null) return;

    final FirebaseOptions options =
        kIsWeb ? DefaultFirebaseOptions.web : DefaultFirebaseOptions.android;

    try {
      _app = await Firebase.initializeApp(options: options);
      return;
    } catch (error) {
      // Creating the app failed. The ordinary, benign reason is that a default
      // app already exists — Android auto-initializes one from
      // google-services.json, a hot restart keeps the previous one, and a
      // duplicate is reported as [core/duplicate-app]. Adopt it in that case.
      //
      // Note this deliberately does NOT filter on exception type. The previous
      // version probed with `Firebase.app()` inside `on FirebaseException`,
      // which holds on Android but not on web: firebase_core_web throws a raw
      // TypeError ("Instance of 'NullError' is not a subtype of type
      // 'JavaScriptObject'") when no app is registered. That escaped the guard,
      // propagated out of initialize(), and parked every web launch on the
      // "could not start its data service" screen.
      //
      // Checking Firebase.apps only AFTER an initializeApp attempt matters too:
      // the list is populated by the platform's initializeCore, so before the
      // first attempt it reads empty even when the native side already has a
      // default app.
      if (Firebase.apps.isEmpty) rethrow;
      _app = Firebase.app();
    }
  }
}
