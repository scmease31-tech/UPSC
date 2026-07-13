import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified service for fetching content from Firestore with TTL-based caching.
/// All feature screens (Current Affairs, Mock Tests, Vocabulary, Govt Schemes,
/// Quick Revision) use this service instead of hardcoded data.
class FirestoreContentService {
  static final _firestore = FirebaseFirestore.instance;

  // In-memory caches
  static List<Map<String, dynamic>>? _currentAffairs;
  static List<Map<String, dynamic>>? _mockTests;
  static List<Map<String, dynamic>>? _vocabulary;
  static List<Map<String, dynamic>>? _govtSchemes;
  static List<Map<String, dynamic>>? _revisionNotes;

  // Cache TTL = 6 hours
  static const _cacheTTL = Duration(hours: 6);

  // ─── Current Affairs ─────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCurrentAffairs() async {
    if (_currentAffairs != null) return _currentAffairs!;
    var data = await _fetchWithCache('currentAffairs');
    // The dedicated `currentAffairs` collection is usually empty — the daily
    // scraper writes news into `articles`. Fall back to that so the Week/Month/
    // Important tabs show real, recent current affairs.
    if (data.isEmpty) {
      data = await _articlesAsCurrentAffairs();
    }
    _currentAffairs = data;
    return _currentAffairs ?? [];
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
        final dateStr = (a['publishedDate'] ?? '').toString();
        final pd = DateTime.tryParse(dateStr);
        final daysAgo = pd == null ? 9999 : now.difference(pd).inDays;
        return <String, dynamic>{
          'title': a['title'] ?? '',
          'summary': a['summary'] ?? '',
          'detail': (a['content'] ?? a['summary'] ?? '').toString(),
          'keyPoints': (a['keyPoints'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
          'category': category,
          'date': dateStr,
          'important': a['isTopNews'] == true,
          'daysAgo': daysAgo,
          'upscRelevance': (a['syllabusMapping'] ?? a['examRelevance'] ?? '').toString(),
          'colorHex': '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> getWeeklyAffairs(List<Map<String, dynamic>> all) =>
      all.where((a) => a['period'] == 'weekly' || (a['daysAgo'] is int && a['daysAgo'] <= 7)).toList();

  static List<Map<String, dynamic>> getMonthlyAffairs(List<Map<String, dynamic>> all) =>
      all.where((a) => a['period'] == 'monthly' || (a['daysAgo'] is int && a['daysAgo'] <= 31)).toList();

  static List<Map<String, dynamic>> getImportantAffairs(List<Map<String, dynamic>> all) =>
      all.where((a) => a['important'] == true).toList();

  // ─── Mock Tests ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getMockTests() async {
    if (_mockTests != null) return _mockTests!;
    _mockTests = await _fetchWithCache('mockTests');
    return _mockTests ?? [];
  }

  // ─── Vocabulary ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getVocabulary() async {
    if (_vocabulary != null) return _vocabulary!;
    _vocabulary = await _fetchWithCache('vocabulary');
    return _vocabulary ?? [];
  }

  // ─── Government Schemes ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getGovtSchemes() async {
    if (_govtSchemes != null) return _govtSchemes!;
    _govtSchemes = await _fetchWithCache('govtSchemes');
    return _govtSchemes ?? [];
  }

  // ─── Revision Notes ──────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getRevisionNotes() async {
    if (_revisionNotes != null) return _revisionNotes!;
    _revisionNotes = await _fetchWithCache('revisionNotes');
    return _revisionNotes ?? [];
  }

  /// Group revision notes by paper.
  static Map<String, List<Map<String, dynamic>>> groupByPaper(
      List<Map<String, dynamic>> notes) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final n in notes) {
      final paper = n['paper'] as String? ?? 'Other';
      map.putIfAbsent(paper, () => []).add(n);
    }
    return map;
  }

  // ─── Core fetch + cache logic ────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _fetchWithCache(
      String collection) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'fcs_$collection';
    final tsKey = 'fcs_ts_$collection';

    // Check local cache validity
    final cachedJson = prefs.getString(cacheKey);
    final cachedTs = prefs.getInt(tsKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (cachedJson != null && (now - cachedTs) < _cacheTTL.inMilliseconds) {
      return (jsonDecode(cachedJson) as List)
          .cast<Map<String, dynamic>>();
    }

    // Fetch from Firestore
    try {
      final snapshot = await _firestore.collection(collection).get();
      final docs = snapshot.docs
          .map((d) => <String, dynamic>{'docId': d.id, ...d.data()})
          .toList();

      if (docs.isNotEmpty) {
        await prefs.setString(cacheKey, jsonEncode(docs));
        await prefs.setInt(tsKey, now);
        return docs;
      }
    } catch (_) {
      // Fall through to cached or empty
    }

    // Return expired cache if Firestore failed
    if (cachedJson != null) {
      return (jsonDecode(cachedJson) as List)
          .cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Force-refresh a collection (bypasses cache).
  static Future<List<Map<String, dynamic>>> refresh(String collection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fcs_$collection');
    await prefs.remove('fcs_ts_$collection');

    // Clear in-memory cache
    switch (collection) {
      case 'currentAffairs': _currentAffairs = null; return getCurrentAffairs();
      case 'mockTests': _mockTests = null; return getMockTests();
      case 'vocabulary': _vocabulary = null; return getVocabulary();
      case 'govtSchemes': _govtSchemes = null; return getGovtSchemes();
      case 'revisionNotes': _revisionNotes = null; return getRevisionNotes();
      default: return _fetchWithCache(collection);
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
      return Color(int.parse(hex.replaceFirst('0x', '').replaceFirst('#', 'FF'), radix: 16));
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
