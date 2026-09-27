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
import 'package:upsc_daily_edge/firebase_options.dart';
import 'package:upsc_daily_edge/services/firebase_services.dart';

const testOptions = FirebaseOptions(
  apiKey: 'test-api-key',
  appId: 'test-app-id',
  messagingSenderId: 'test-sender',
  projectId: FirebaseServices.expectedProjectId,
);

class _LiveProjectFirebaseCoreMock implements TestFirebaseCoreHostApi {
  CoreFirebaseOptions get _options => CoreFirebaseOptions(
        apiKey: testOptions.apiKey,
        appId: testOptions.appId,
        messagingSenderId: testOptions.messagingSenderId,
        projectId: testOptions.projectId,
      );

  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions initializeAppRequest,
  ) async =>
      CoreInitializeResponse(
        name: appName,
        options: initializeAppRequest,
        pluginConstants: <String, Object?>{},
      );

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async =>
      <CoreInitializeResponse>[];

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async => _options;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestFirebaseCoreHostApi.setUp(_LiveProjectFirebaseCoreMock());
  });

  test('initialize() succeeds when no app exists yet', () async {
    await FirebaseServices.initialize(optionsOverride: testOptions);
    expect(Firebase.apps, isNotEmpty);
    expect(FirebaseServices.contentApp, isNotNull);
  });

  test('initialize() is idempotent and reuses the existing app', () async {
    await FirebaseServices.initialize(optionsOverride: testOptions);
    final first = FirebaseServices.contentApp;
    final appCount = Firebase.apps.length;

    await FirebaseServices.initialize(optionsOverride: testOptions);

    expect(Firebase.apps, hasLength(appCount),
        reason: 'a second call must not register another app');
    expect(FirebaseServices.contentApp.name, first.name);
  });

  test('content and auth share one app', () async {
    await FirebaseServices.initialize(optionsOverride: testOptions);
    expect(FirebaseServices.contentApp.name, FirebaseServices.authApp.name);
  });

  firebaseProjectSafetyTests();
}

void firebaseProjectSafetyTests() {
  test('Android and web use the same live project', () {
    expect(DefaultFirebaseOptions.android.projectId,
        FirebaseServices.expectedProjectId);
    expect(DefaultFirebaseOptions.web.projectId,
        FirebaseServices.expectedProjectId);
    expect(DefaultFirebaseOptions.web.projectId,
        DefaultFirebaseOptions.android.projectId);
  });

  test('refuses options for a stale or unexpected Firebase project', () async {
    const stale = FirebaseOptions(
      apiKey: 'stale',
      appId: 'stale',
      messagingSenderId: 'stale',
      projectId: 'upsc-app-e2475',
    );
    await expectLater(
      FirebaseServices.initialize(optionsOverride: stale),
      throwsA(isA<StateError>()),
    );
  });
}
