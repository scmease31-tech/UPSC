/// ──────────────────────────────────────────────────────────────────────────────
/// UpdateConfig — single source of truth for the DIRECT sideload in-app updater.
///
/// This app ships in two flavours:
///   • SIDELOAD build (distributed as an APK off GitHub Pages) — the in-app
///     updater is ACTIVE: it downloads the new APK inside the app and hands it
///     to the Android system installer.
///   • PLAY STORE build (a future release) — the in-app updater is DISABLED and
///     guarded; Google Play updates the app itself, and fetching/installing an
///     APK from outside Play violates the Device and Network Abuse policy.
///
/// The distinction is a compile-time constant so the whole sideload path can be
/// tree-shaken / guarded out for the Play build:
///     flutter build appbundle --dart-define=PLAY_STORE=true
/// ──────────────────────────────────────────────────────────────────────────────
library;

class UpdateConfig {
  UpdateConfig._();

  /// True when this build targets the Play Store. Flip via
  /// `--dart-define=PLAY_STORE=true`. When true, the sideload updater is a
  /// no-op: no version.json fetch, no download, no installer invocation.
  static const bool isPlayStoreBuild =
      bool.fromEnvironment('PLAY_STORE', defaultValue: false);

  /// Whether the direct sideload updater is allowed to run. It is enabled only
  /// for sideload builds; the Play build must NEVER sideload.
  static bool get sideloadUpdaterEnabled => !isPlayStoreBuild;

  /// The app is NEVER allowed to install silently. The Android system installer
  /// always shows its own final "Install?" confirmation, and we never request
  /// or attempt any silent/unattended install path. This is a hard invariant,
  /// surfaced as a constant so tests can assert it.
  static const bool silentInstall = false;

  /// Stable HTTPS manifest describing the latest release. Served from GitHub
  /// Pages (a stable URL that does not change per release, unlike a release
  /// asset URL). Fetched on launch AND on resume.
  static const String versionManifestUrl =
      'https://scmease31-tech.github.io/UPSC/update/version.json';

  /// The build number of THIS installed binary. Compared against the manifest's
  /// `build` field as a monotonically increasing integer, in ADDITION to the
  /// semantic version. Keep this in lock-step with the `+NN` suffix in
  /// pubspec.yaml's `version:` and with the CI that publishes version.json.
  static const int currentBuildNumber =
      int.fromEnvironment('BUILD_NUMBER', defaultValue: 19);

  /// Network timeout for the manifest fetch and for establishing the APK
  /// download connection.
  static const Duration networkTimeout = Duration(seconds: 15);

  /// Allowlist of HTTPS origins the updater may fetch from. BOTH the manifest
  /// URL and any APK download URL advertised inside the manifest are validated
  /// against this list before any network call is made. A manifest that points
  /// the APK at an off-list host is rejected with a security error — this is
  /// what stops a compromised or spoofed manifest from redirecting the download
  /// to an attacker-controlled binary.
  ///
  /// Deliberately ONE origin: the project's own Pages site, which is where
  /// publish-pages.yml puts the signed APK and its manifest together in a single
  /// commit. github.com, objects.githubusercontent.com and
  /// release-assets.githubusercontent.com used to be listed as well, which meant
  /// a manifest could legitimately send the updater to a repository release
  /// asset. Those are removed on purpose:
  ///
  ///   • Users are never sent to the repository to fetch a build. The APK the
  ///     app installs is the same file the download link serves, published as
  ///     one atomic unit with the manifest that describes it.
  ///   • Release assets are built per-ABI with a lower versionCode and are NOT
  ///     the binary the updater manages, so installing one from here would
  ///     desync a device from the update channel.
  ///   • A narrower allowlist is a smaller trust surface. Nothing in the app
  ///     needs those hosts.
  ///
  /// Adding a host here widens what a spoofed manifest can reach. Do not add one
  /// without a reason that survives the two points above.
  static const List<String> allowedOrigins = <String>[
    'https://scmease31-tech.github.io',
  ];

  /// Returns true when [url] is an absolute HTTPS URL whose origin
  /// (scheme+host[:port]) exactly matches an entry in [allowedOrigins].
  /// Anything non-HTTPS, malformed, or off-list returns false.
  static bool isAllowedUrl(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;
    if (!uri.hasAuthority || uri.host.isEmpty) return false;

    final String origin = uri.hasPort
        ? 'https://${uri.host}:${uri.port}'
        : 'https://${uri.host}';
    for (final allowed in allowedOrigins) {
      final Uri a = Uri.parse(allowed);
      final String allowedOrigin =
          a.hasPort ? 'https://${a.host}:${a.port}' : 'https://${a.host}';
      if (origin == allowedOrigin) return true;
    }
    return false;
  }
}
