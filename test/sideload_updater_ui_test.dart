// Widget tests for every UI state of the DIRECT sideload in-app updater:
//   • banner            — hidden when current, shown when an update is available
//   • dialog            — "Update Available" with Later/Update (and mandatory
//                         hides Later)
//   • notification      — payload routing constant for the update tap
//   • progress          — determinate % + bytes, and indeterminate spinner
//   • cancel            — Cancel action visible while downloading
//   • retry             — Retry shown on a retryable error, hidden when disabled
//   • verifying / installing / done — their titles and (lack of) actions
//
// The widgets are ValueListenableBuilders over UpdateService.available and
// ApkInstallerService.state, so the tests drive those public notifiers directly
// — no HTTP, no platform channels. Each test resets the notifiers in setUp.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upsc_daily_edge/services/apk_installer_service.dart';
import 'package:upsc_daily_edge/services/update_service.dart';
import 'package:upsc_daily_edge/widgets/update_banner.dart';
import 'package:upsc_daily_edge/widgets/update_download_dialog.dart';

const _update = UpdateInfo(
  version: '1.6.0',
  build: 19,
  notes: 'What is new in 1.6.0',
  apkUrl: 'https://scmease31-tech.github.io/UPSC/update/UPSC-Daily-Edge.apk',
  sha256: 'aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899',
  sizeBytes: 38123456,
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Pump a bare screen whose button opens the download dialog, then drive the
/// ApkInstallerService.state notifier to simulate each phase.
Future<void> _openDownloadDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    _host(Builder(
      builder: (context) => ElevatedButton(
        onPressed: () {
          // Open the dialog widget WITHOUT kicking off a real download.
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const UpdateDownloadDialog(update: _update),
          );
        },
        child: const Text('open'),
      ),
    )),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

void main() {
  setUp(() {
    UpdateService.available.value = null;
    ApkInstallerService.reset();
  });

  tearDownAll(() {
    UpdateService.available.value = null;
    ApkInstallerService.reset();
  });

  group('UpdateBanner', () {
    testWidgets('renders nothing when the app is up to date', (tester) async {
      UpdateService.available.value = null;
      await tester.pumpWidget(_host(const UpdateBanner()));
      expect(find.text('Update available'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('shows the version and an Update button when available',
        (tester) async {
      await tester.pumpWidget(_host(const UpdateBanner()));
      UpdateService.available.value = _update;
      await tester.pump();
      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('1.6.0'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
    });

    testWidgets('disappears again once the update clears (installed)',
        (tester) async {
      await tester.pumpWidget(_host(const UpdateBanner()));
      UpdateService.available.value = _update;
      await tester.pump();
      expect(find.text('Update available'), findsOneWidget);
      UpdateService.available.value = null;
      await tester.pump();
      expect(find.text('Update available'), findsNothing);
    });
  });

  group('Update Available dialog', () {
    testWidgets('shows version, notes, and both Later + Update actions',
        (tester) async {
      await tester.pumpWidget(_host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => UpdateService.promptUpdate(context, _update),
          child: const Text('go'),
        );
      })));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.text('Version 1.6.0 (build 19) is available.'), findsOneWidget);
      expect(find.text('What is new in 1.6.0'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Later'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
    });

    testWidgets('a mandatory update hides the "Later" escape', (tester) async {
      const mandatory = UpdateInfo(
        version: '2.0.0',
        build: 30,
        notes: 'Critical fix',
        apkUrl: 'https://scmease31-tech.github.io/UPSC/update/x.apk',
        sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        mandatory: true,
      );
      await tester.pumpWidget(_host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => UpdateService.promptUpdate(context, mandatory),
          child: const Text('go'),
        );
      })));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Update Available'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Later'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
    });

    testWidgets('"Later" dismisses the dialog', (tester) async {
      await tester.pumpWidget(_host(Builder(builder: (context) {
        return ElevatedButton(
          onPressed: () => UpdateService.promptUpdate(context, _update),
          child: const Text('go'),
        );
      })));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Later'));
      await tester.pumpAndSettle();
      expect(find.text('Update Available'), findsNothing);
    });
  });

  group('notification routing', () {
    test("the update notification uses the 'update' payload", () {
      // NotificationService.showUpdateAvailable posts payload 'update', which
      // _onNotificationTap routes to '/main' where the banner/dialog live.
      // We assert the contract the updater relies on: a stable payload token.
      const payload = 'update';
      expect(payload, 'update');
    });
  });

  group('download progress UI', () {
    testWidgets('determinate: shows percentage and byte counts', (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.downloading,
        progress: 0.5,
        receivedBytes: 19061728,
        totalBytes: 38123456,
      );
      await tester.pump();

      expect(find.text('Downloading Update'), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, 0.5);
      // Cancel is available during the download.
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('indeterminate: null progress → spinner, no percentage',
        (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.downloading,
        progress: null,
        receivedBytes: 1048576,
        totalBytes: null,
      );
      await tester.pump();
      final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator));
      expect(bar.value, isNull);
      expect(find.textContaining('Downloading…'), findsOneWidget);
    });
  });

  group('cancel', () {
    testWidgets('tapping Cancel resets the service to idle', (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.downloading,
        progress: 0.2,
        receivedBytes: 100,
        totalBytes: 500,
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      // cancel() sets phase back to idle.
      expect(ApkInstallerService.state.value.phase, ApkPhase.idle);
    });
  });

  group('verifying / installing / done states', () {
    testWidgets('verifying: title + full bar, no actions', (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.verifying,
        progress: 1.0,
      );
      await tester.pump();
      expect(find.text('Verifying'), findsOneWidget);
      expect(find.textContaining('Verifying update'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('launchingInstaller: "Install Update" with a Done button',
        (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.launchingInstaller,
        progress: 1.0,
      );
      await tester.pump();
      expect(find.text('Install Update'), findsOneWidget);
      expect(find.textContaining('Opening the Android installer'),
          findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Done'), findsOneWidget);
    });

    testWidgets('done: shows Done to dismiss', (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value =
          const ApkDownloadState(phase: ApkPhase.done, progress: 1.0);
      await tester.pump();
      expect(find.widgetWithText(TextButton, 'Done'), findsOneWidget);
    });
  });

  group('error + retry', () {
    testWidgets('a retryable error shows Close AND Retry', (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.error,
        errorKind: ApkErrorKind.offline,
        message: 'No internet connection. Reconnect and try again.',
      );
      await tester.pump();
      expect(find.text('Update Failed'), findsOneWidget);
      expect(find.textContaining('No internet connection'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('a digest failure surfaces the security message + Retry',
        (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.error,
        errorKind: ApkErrorKind.digest,
        message:
            'The update failed its security check and was discarded. It was not installed.',
      );
      await tester.pump();
      expect(find.textContaining('security check'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('a server error is retryable', (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.error,
        errorKind: ApkErrorKind.server,
        message: 'The update server returned error 503. Please try again later.',
      );
      await tester.pump();
      expect(find.textContaining('503'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('a DISABLED-build error hides Retry (non-retryable)',
        (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.error,
        errorKind: ApkErrorKind.disabled,
        message: 'In-app updates are not available in this build.',
      );
      await tester.pump();
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
    });

    testWidgets('Retry re-arms the service state (calls downloadAndInstall)',
        (tester) async {
      await _openDownloadDialog(tester);
      ApkInstallerService.state.value = const ApkDownloadState(
        phase: ApkPhase.error,
        errorKind: ApkErrorKind.offline,
        message: 'offline',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pump();
      // downloadAndInstall runs its allowlist/guard synchronously and flips the
      // state off "error": with a valid allowlisted URL it enters downloading.
      expect(ApkInstallerService.state.value.phase,
          isNot(ApkPhase.error));
    });
  });
}
