import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Owns the app's Firebase connections.
///
/// Public study content is stored in the original `upsc-app-e2475` project,
/// while the Android OAuth client and user profiles live in
/// `upsc-app-e2475-e5c95`. Keeping both apps initialized prevents the installed
/// Android build from reading an empty content database just to make Google
/// Sign-In available.
class FirebaseServices {
  FirebaseServices._();

  static const String _contentAppName = 'upsc-content';
  static FirebaseApp? _contentApp;
  static FirebaseApp? _authApp;

  static FirebaseApp get contentApp => _contentApp ?? Firebase.app();
  static FirebaseApp get authApp => _authApp ?? Firebase.app();

  static FirebaseFirestore get contentFirestore =>
      FirebaseFirestore.instanceFor(app: contentApp);

  static FirebaseFirestore get userFirestore =>
      FirebaseFirestore.instanceFor(app: authApp);

  static FirebaseAuth get auth => FirebaseAuth.instanceFor(app: authApp);

  static Future<void> initialize() async {
    FirebaseApp primary;
    try {
      primary = Firebase.app();
    } on FirebaseException {
      primary = await Firebase.initializeApp(
        options: kIsWeb
            ? DefaultFirebaseOptions.web
            : DefaultFirebaseOptions.androidAuth,
      );
    }

    _authApp = primary;
    _contentApp = primary;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        _contentApp = Firebase.app(_contentAppName);
      } on FirebaseException {
        _contentApp = await Firebase.initializeApp(
          name: _contentAppName,
          options: DefaultFirebaseOptions.android,
        );
      }
    }
  }
}
