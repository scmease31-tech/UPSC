// FirebaseServices.initialize() must be safe to call when an app already
// exists and when none does.
//
// The regression this pins down: initialize() used to detect "no app yet" by
// calling Firebase.app() inside `try { } on FirebaseException`. Android throws
// FirebaseException there, but firebase_core_web throws a raw TypeError, so on
// web the guard missed, the error escaped initialize(), and main() rendered the
// startup error screen on every launch. Probing Firebase.apps removes the
// dependency on which exception type a platform happens to throw.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/services/firebase_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(setupFirebaseCoreMocks);

  test('initialize() succeeds when no app exists yet', () async {
    await FirebaseServices.initialize();
    expect(Firebase.apps, isNotEmpty);
    expect(FirebaseServices.contentApp, isNotNull);
  });

  test('initialize() is idempotent and reuses the existing app', () async {
    await FirebaseServices.initialize();
    final first = FirebaseServices.contentApp;
    final appCount = Firebase.apps.length;

    await FirebaseServices.initialize();

    expect(Firebase.apps, hasLength(appCount),
        reason: 'a second call must not register another app');
    expect(FirebaseServices.contentApp.name, first.name);
  });

  test('content and auth share one app', () async {
    await FirebaseServices.initialize();
    expect(FirebaseServices.contentApp.name, FirebaseServices.authApp.name);
  });
}
