import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/offline_content.dart';
import 'firebase_services.dart';

/// Unified service for fetching content from Firestore with TTL-based caching.
/// All feature screens (Current Affairs, Mock Tests, Vocabulary, Govt Schemes,
/// Quick Revision) use this service instead of hardcoded data.
class FirestoreContentService {
  static final _firestore = FirebaseServices.contentFirestore;

  // In-memory caches
  static List<Map<String, dynamic>>? _currentAffairs;
  static List<Map<String, dynamic>>? _mockTests;
  static List<Map<String, dynamic>>? _vocabulary;
  static List<Map<String, dynamic>>? _govtSchemes;
  static List<Map<String, dynamic>>? _revisionNotes;
  static List<Map<String, dynamic>>? _roundups;

  // A static value without a timestamp lived forever, even after the advertised
  // six-hour disk TTL expired. Every memory hit is now subject to the same TTL.
  static final Map<String, int> _memoryCachedAt = <String, int>{};
  static final Map<String, Object> _lastErrors = <String, Object>{};

  static const _cacheTTL = Duration(hours: 6);
  static const _requestTimeout = Duration(seconds: 18);
  static const _cacheSchema = 3;

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  static T? _freshMemory<T>(String collection, T? value) {
    if (value == null) return null;
    final cachedAt = _memoryCachedAt[collection] ?? 0;
    if (_now - cachedAt >= _cacheTTL.inMilliseconds) return null;
    return value;
  }

  static T _remember<T>(String collection, T value) {
    _memoryCachedAt[collection] = _now;
    return value;
  }

  static Object? lastErrorFor(String collection) => _lastErrors[collection];

  static String _cacheStem(String collection) {
    final project = FirebaseServices.contentApp.options.projectId;
    // Project + schema scoping prevents data from the old Firebase project or an
    // old field shape surviving a migration under the same collection key.
    return 'fcs_v${_cacheSchema}_${project}_$collection';
  }

  // ─── Current Affairs ─────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCurrentAffairs() async {
    final memory = _freshMemory('currentAffairs', _currentAffairs);
    if (memory != null) return memory;
    var data = await _fetchWithCache('currentAffairs');
    // The dedicated `currentAffairs` collection is usually empty — the daily
    // scraper writes news into `articles`. Fall back to that so the Week/Month/
    // Important tabs show real, recent current affairs.
    if (data.isEmpty) {
      data = await _articlesAsCurrentAffairs();
    }
    if (data.isEmpty) {
      data = _copyFallback(OfflineContent.currentAffairs);
    }
    _currentAffairs = _remember('currentAffairs', data);
    return _currentAffairs!;
  }

  /// Map the scraped `articles` collection into the current-affairs card shape,
  /// tagging each with how many days old it is for the Week/Month filters.
  static Future<List<Map<String, dynamic>>> _articlesAsCurrentAffairs() async {
    try {
      final snap = await _firestore
          .collection('articles')
          .orderBy('publishedDate', descending: true)
          .limit(200)
          .get();
      final now = DateTime.now();
      return snap.docs.map((d) {
        final a = d.data();
        final tags = (a['categoryTags'] as List?) ?? const [];
        final category = tags.isNotEmpty ? tags.first.toString() : 'General';
        final rawDate = a['publishedDate'];
        final pd = switch (rawDate) {
          final Timestamp value => value.toDate(),
          final DateTime value => value,
          _ => DateTime.tryParse((rawDate ?? '').toString()),
        };
        final dateStr = pd?.toIso8601String() ?? '';
        final daysAgo = pd == null ? 9999 : now.difference(pd).inDays;
        return <String, dynamic>{
          'title': a['title'] ?? '',
          'summary': a['summary'] ?? '',
          'detail': (a['content'] ?? a['summary'] ?? '').toString(),
          'keyPoints':
              (a['keyPoints'] as List?)?.map((e) => e.toString()).toList() ??
                  <String>[],
          'category': category,
          'date': dateStr,
          'important': a['isTopNews'] == true,
          'daysAgo': daysAgo,
          'upscRelevance':
              (a['syllabusMapping'] ?? a['examRelevance'] ?? '').toString(),
          'colorHex': '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> getWeeklyAffairs(
          List<Map<String, dynamic>> all) =>
      all
          .where((a) =>
              a['period'] == 'weekly' ||
              (a['daysAgo'] is int && a['daysAgo'] <= 7))
          .toList();

  static List<Map<String, dynamic>> getMonthlyAffairs(
          List<Map<String, dynamic>> all) =>
      all
          .where((a) =>
              a['period'] == 'monthly' ||
              (a['daysAgo'] is int && a['daysAgo'] <= 31))
          .toList();

  static List<Map<String, dynamic>> getImportantAffairs(
          List<Map<String, dynamic>> all) =>
      all.where((a) => a['important'] == true).toList();

  static Future<Map<String, dynamic>?> getLatestRoundup(String period) async {
    final memory = _freshMemory('currentAffairsRoundups', _roundups);
    _roundups = memory ??
        _remember(
          'currentAffairsRoundups',
          await _fetchWithCache('currentAffairsRoundups'),
        );
    final matches = _roundups!
        .where((roundup) => roundup['period'] == period)
        .toList()
      ..sort((a, b) => (b['endDate'] ?? '')
          .toString()
          .compareTo((a['endDate'] ?? '').toString()));
    return matches.isEmpty ? null : matches.first;
  }

  // ─── Mock Tests ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getMockTests() async {
    final memory = _freshMemory('mockTests', _mockTests);
    if (memory != null) return memory;
    final remote = await _fetchWithCache('mockTests');
    _mockTests = _remember(
      'mockTests',
      remote.isNotEmpty ? remote : _copyFallback(OfflineContent.mockTests),
    );
    return _mockTests!;
  }

  // ─── Vocabulary ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getVocabulary() async {
    final memory = _freshMemory('vocabulary', _vocabulary);
    if (memory != null) return memory;
    _vocabulary = _remember(
      'vocabulary',
      await _fetchWithCache('vocabulary'),
    );
    return _vocabulary!;
  }

  // ─── Government Schemes ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getGovtSchemes() async {
    final memory = _freshMemory('govtSchemes', _govtSchemes);
    if (memory != null) return memory;
    final remote = await _fetchWithCache('govtSchemes');
    _govtSchemes = _remember(
      'govtSchemes',
      remote.isNotEmpty ? remote : _copyFallback(OfflineContent.govtSchemes),
    );
    return _govtSchemes!;
  }

  // ─── Revision Notes ──────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getRevisionNotes() async {
    final memory = _freshMemory('revisionNotes', _revisionNotes);
    if (memory != null) return memory;
    final remote = await _fetchWithCache('revisionNotes');
    _revisionNotes = _remember(
      'revisionNotes',
      remote.isNotEmpty ? remote : _copyFallback(OfflineContent.revisionNotes),
    );
    return _revisionNotes!;
  }

  static List<Map<String, dynamic>> _copyFallback(
    List<Map<String, dynamic>> source,
  ) =>
      source.map((item) => Map<String, dynamic>.from(item)).toList();

  /// Group revision notes by paper.
  static Map<String, List<Map<String, dynamic>>> groupByPaper(
      List<Map<String, dynamic>> notes) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final n in notes) {
      final paper = (n['paper'] ?? 'Other').toString().trim();
      map.putIfAbsent(paper.isEmpty ? 'Other' : paper, () => []).add(n);
    }
    return map;
  }

  // ─── Core fetch + cache logic ────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _fetchWithCache(
      String collection) async {
    SharedPreferences? prefs;
    String? cachedJson;
    var cachedTs = 0;
    final stem = _cacheStem(collection);
    final cacheKey = '${stem}_data';
    final tsKey = '${stem}_at';
    final now = _now;

    try {
      prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 4));
      cachedJson = prefs.getString(cacheKey);
      cachedTs = prefs.getInt(tsKey) ?? 0;
    } catch (error) {
      debugPrint('Local content cache unavailable for $collection: $error');
    }

    if (cachedJson != null && now - cachedTs < _cacheTTL.inMilliseconds) {
      final cached = _decodeDocuments(cachedJson);
      if (cached != null) return cached;
      // A corrupt entry cannot remain the preferred result for six hours.
      await prefs?.remove(cacheKey);
      await prefs?.remove(tsKey);
      cachedJson = null;
    }

    try {
      final snapshot = await _firestore
          .collection(collection)
          .limit(1000)
          .get()
          .timeout(_requestTimeout);
      final docs = snapshot.docs
          .map((d) => <String, dynamic>{'docId': d.id, ..._jsonSafe(d.data())})
          .toList(growable: false);
      _lastErrors.remove(collection);

      if (docs.isEmpty) {
        // A successful empty response is authoritative. The old implementation
        // fell through to an expired cache here, so deleted/pruned documents
        // could survive forever.
        await prefs?.remove(cacheKey);
        await prefs?.remove(tsKey);
        return const <Map<String, dynamic>>[];
      }

      try {
        await prefs?.setString(cacheKey, jsonEncode(docs));
        await prefs?.setInt(tsKey, now);
      } catch (error) {
        debugPrint('Could not cache $collection: $error');
      }
      return docs;
    } catch (error) {
      _lastErrors[collection] = error;
      debugPrint('Firestore $collection fetch failed: $error');
    }

    // On an actual network/permission failure, expired data is still more useful
    // than a blank route. Unlike the old code this path is distinguishable via
    // lastErrorFor(collection), so screens can say that they are showing saved
    // data rather than presenting it as current.
    if (cachedJson != null) {
      final stale = _decodeDocuments(cachedJson);
      if (stale != null) return stale;
    }
    return const <Map<String, dynamic>>[];
  }

  static List<Map<String, dynamic>>? _decodeDocuments(String encoded) {
    try {
      final value = jsonDecode(encoded);
      if (value is! List) return null;
      return value
          .whereType<Map>()
          .map((doc) => doc.map(
                (key, item) => MapEntry(key.toString(), _safeValue(item)),
              ))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  /// Convert Firestore-specific types (Timestamp, GeoPoint, DocumentReference)
  /// into JSON-serializable values so documents can be cached and safely used
  /// by the UI. Without this, a single Timestamp field (e.g. the `createdAt`
  /// the scraper/uploader writes) makes jsonEncode throw and the whole
  /// collection silently returns empty — the bug that hid vocabulary & schemes.
  static Map<String, dynamic> _jsonSafe(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    data.forEach((key, value) => out[key] = _safeValue(value));
    return out;
  }

  static dynamic _safeValue(dynamic v) {
    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();
    if (v is GeoPoint) return {'lat': v.latitude, 'lng': v.longitude};
    if (v is DocumentReference) return v.path;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _safeValue(val)));
    }
    if (v is List) return v.map(_safeValue).toList();
    return v;
  }

  /// Force-refresh a collection (bypasses memory and disk caches).
  static Future<List<Map<String, dynamic>>> refresh(String collection) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 4));
    } catch (error) {
      debugPrint('Could not clear local cache for $collection: $error');
    }
    final stem = _cacheStem(collection);
    await prefs?.remove('${stem}_data');
    await prefs?.remove('${stem}_at');
    // Remove the unscoped v1 cache too. It may belong to the stale Firebase
    // project and must never be resurrected by an older app process.
    await prefs?.remove('fcs_$collection');
    await prefs?.remove('fcs_ts_$collection');
    _memoryCachedAt.remove(collection);
    _lastErrors.remove(collection);

    switch (collection) {
      case 'currentAffairs':
        _currentAffairs = null;
        return getCurrentAffairs();
      case 'mockTests':
        _mockTests = null;
        return getMockTests();
      case 'vocabulary':
        _vocabulary = null;
        return getVocabulary();
      case 'govtSchemes':
        _govtSchemes = null;
        return getGovtSchemes();
      case 'revisionNotes':
        _revisionNotes = null;
        return getRevisionNotes();
      case 'currentAffairsRoundups':
        _roundups = null;
        return _fetchWithCache(collection);
      default:
        return _fetchWithCache(collection);
    }
  }

  // ─── Icon/Color helpers — map Firestore strings to Flutter objects ───

  static const _iconMap = <String, IconData>{
    'account_balance': Icons.account_balance_rounded,
    'trending_up': Icons.trending_up_rounded,
    'eco': Icons.eco_rounded,
    'science': Icons.science_rounded,
    'history_edu': Icons.history_edu_rounded,
    'public': Icons.public_rounded,
    'language': Icons.language_rounded,
    'newspaper': Icons.newspaper_rounded,
    'agriculture': Icons.agriculture_rounded,
    'local_hospital': Icons.local_hospital_rounded,
    'engineering': Icons.engineering_rounded,
    'cleaning_services': Icons.cleaning_services_rounded,
    'factory': Icons.factory_rounded,
    'home': Icons.home_rounded,
    'school': Icons.school_rounded,
    'water_drop': Icons.water_drop_rounded,
    'computer': Icons.computer_rounded,
    'local_fire_department': Icons.local_fire_department_rounded,
    'grass': Icons.grass_rounded,
    'rocket_launch': Icons.rocket_launch_rounded,
    'payments': Icons.payments_rounded,
    'local_shipping': Icons.local_shipping_rounded,
    'menu_book': Icons.menu_book_rounded,
    'location_city': Icons.location_city_rounded,
    'hub': Icons.hub_rounded,
    'restaurant': Icons.restaurant_rounded,
    'memory': Icons.memory_rounded,
    'qr_code': Icons.qr_code_rounded,
    'bolt': Icons.bolt_rounded,
    'lightbulb': Icons.lightbulb_rounded,
    'map': Icons.map_rounded,
    'history': Icons.history_rounded,
    'gavel': Icons.gavel_rounded,
  };

  static IconData getIcon(String? name) =>
      _iconMap[name] ?? Icons.article_rounded;

  static Color parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.blueAccent;
    try {
      return Color(int.parse(hex.replaceFirst('0x', '').replaceFirst('#', 'FF'),
          radix: 16));
    } catch (_) {
      return Colors.blueAccent;
    }
  }

  /// Map icon name strings used in revision notes to IconData.
  static const _revisionIconMap = <String, IconData>{
    'history': Icons.history_edu_rounded,
    'geography': Icons.public_rounded,
    'society': Icons.people_rounded,
    'polity': Icons.account_balance_rounded,
    'ir': Icons.language_rounded,
    'governance': Icons.admin_panel_settings_rounded,
    'economy': Icons.trending_up_rounded,
    'environment': Icons.eco_rounded,
    'science': Icons.science_rounded,
    'security': Icons.shield_rounded,
    'ethics': Icons.psychology_rounded,
    'comprehension': Icons.menu_book_rounded,
    'math': Icons.calculate_rounded,
  };

  static IconData getRevisionIcon(String? name) =>
      _revisionIconMap[name] ?? Icons.article_rounded;
}
