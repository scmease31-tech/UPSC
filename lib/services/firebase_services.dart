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
    try {
      _app = Firebase.app();
    } on FirebaseException {
      _app = await Firebase.initializeApp(
        options: kIsWeb
            ? DefaultFirebaseOptions.web
            : DefaultFirebaseOptions.android,
      );
    }
  }
}
