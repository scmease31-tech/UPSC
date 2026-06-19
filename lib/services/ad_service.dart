import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

/// Centralized ad management for UPSC Daily Edge.
/// Uses test ad unit IDs — replace with real ones before production release.
class AdService {
  AdService._();

  static bool _initialized = false;

  /// Initialize the Mobile Ads SDK. Call once at app start.
  static Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
  }

  // ─── Test Ad Unit IDs (Google-provided, safe for dev) ───
  // TODO: Replace with your real AdMob ad unit IDs before publishing
  static String get bannerAdUnitId {
    if (kIsWeb) return '';
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111'; // Android test banner
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // iOS test banner
    }
    return '';
  }

  /// Creates and loads a banner ad. Returns null on failure.
  static BannerAd? createBannerAd({
    AdSize size = AdSize.banner,
    required void Function(Ad) onAdLoaded,
    required void Function(Ad, LoadAdError) onAdFailedToLoad,
  }) {
    if (kIsWeb) return null;
    final ad = BannerAd(
      adUnitId: bannerAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner ad failed to load: ${error.message}');
          ad.dispose();
          onAdFailedToLoad(ad, error);
        },
      ),
    );
    ad.load();
    return ad;
  }
}
