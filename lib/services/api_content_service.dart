import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/article.dart';
import '../models/quiz_question.dart';

/// Centralized API service that fetches ALL content from Firestore.
/// Replaces hardcoded data with database-first architecture.
/// Implements aggressive caching to minimize network calls.
class ApiContentService {
  static final _firestore = FirebaseFirestore.instance;

  // Cache TTL
  static const _shortTTL = Duration(hours: 2);    // Articles, current affairs
  static const _mediumTTL = Duration(hours: 6);    // Quiz, flashcards
  static const _longTTL = Duration(hours: 24);     // Static content

  // In-memory caches
  static List<Map<String, dynamic>>? _flashcardsCache;
  static List<Map<String, dynamic>>? _dailyFactsCache;
  static List<Map<String, dynamic>>? _pyqCache;
  static List<Map<String, dynamic>>? _vocabularyCache;
  static List<Map<String, dynamic>>? _govtSchemesCache;
  static List<Map<String, dynamic>>? _studyNotesCache;
  static List<Map<String, dynamic>>? _currentAffairsCache;
  static List<Map<String, dynamic>>? _mockTestsCache;
  static List<Map<String, dynamic>>? _syllabusCache;
  static List<Map<String, dynamic>>? _answerWritingCache;

  // ─── Articles (paginated) ────────────────────────────────────────────

  /// Fetch articles with pagination support.
  static Future<List<Article>> fetchArticles({
    int limit = 50,
    DocumentSnapshot? startAfter,
    String? category,
    String? date,
  }) async {
    try {
      Query query = _firestore
          .collection('articles')
          .orderBy('publishedDate', descending: true)
          .limit(limit);

      if (category != null && category != 'All') {
        query = query.where('categoryTags', arrayContains: category);
      }

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => Article.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error fetching articles: $e');
      return [];
    }
  }

  /// Search articles in Firestore by keyword.
  static Future<List<Article>> searchArticles(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    try {
      // Firestore doesn't support full-text search natively,
      // so we search by title prefix and tags
      final q = query.toLowerCase().trim();
      final results = <Article>[];

      // Search by title (prefix match)
      final titleSnapshot = await _firestore
          .collection('articles')
          .orderBy('titleLower')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(limit)
          .get();

      for (final doc in titleSnapshot.docs) {
        results.add(Article.fromMap(doc.data(), doc.id));
      }

      // Also search by category tags
      if (results.length < limit) {
        final tagSnapshot = await _firestore
            .collection('articles')
            .where('categoryTags', arrayContains: q.substring(0, 1).toUpperCase() + q.substring(1))
            .limit(limit - results.length)
            .get();

        for (final doc in tagSnapshot.docs) {
          if (!results.any((a) => a.id == doc.id)) {
            results.add(Article.fromMap(doc.data(), doc.id));
          }
        }
      }

      return results;
    } catch (e) {
      debugPrint('Error searching articles: $e');
      return [];
    }
  }

  // ─── Quiz Questions ──────────────────────────────────────────────────

  /// Fetch quiz questions by category.
  static Future<List<QuizQuestion>> fetchQuizQuestions({
    String? category,
    int limit = 50,
  }) async {
    try {
      Query query = _firestore.collection('quizQuestions').limit(limit);

      if (category != null && category.isNotEmpty) {
        query = query.where('category', isEqualTo: category);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => QuizQuestion.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error fetching quiz questions: $e');
      return [];
    }
  }

  // ─── Flashcards ──────────────────────────────────────────────────────

  /// Fetch all flashcards from Firestore.
  static Future<List<Map<String, dynamic>>> fetchFlashcards({bool forceRefresh = false}) async {
    if (!forceRefresh && _flashcardsCache != null) return _flashcardsCache!;

    final data = await _fetchCollection('flashcards', _mediumTTL, forceRefresh: forceRefresh);
    _flashcardsCache = data;
    return data;
  }

  // ─── Daily Facts ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchDailyFacts({bool forceRefresh = false}) async {
    if (!forceRefresh && _dailyFactsCache != null) return _dailyFactsCache!;

    final data = await _fetchCollection('dailyFacts', _shortTTL, forceRefresh: forceRefresh);
    _dailyFactsCache = data;
    return data;
  }

  // ─── Previous Year Questions ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchPYQ({
    String? year,
    String? subject,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _pyqCache != null) {
      var results = _pyqCache!;
      if (year != null) results = results.where((q) => q['year'] == year).toList();
      if (subject != null) results = results.where((q) => q['subject'] == subject).toList();
      return results;
    }

    final data = await _fetchCollection('pyqBank', _longTTL, forceRefresh: forceRefresh);
    _pyqCache = data;

    var results = data;
    if (year != null) results = results.where((q) => q['year'] == year).toList();
    if (subject != null) results = results.where((q) => q['subject'] == subject).toList();
    return results;
  }

  // ─── Vocabulary ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchVocabulary({bool forceRefresh = false}) async {
    if (!forceRefresh && _vocabularyCache != null) return _vocabularyCache!;

    final data = await _fetchCollection('vocabulary', _mediumTTL, forceRefresh: forceRefresh);
    _vocabularyCache = data;
    return data;
  }

  // ─── Government Schemes ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchGovtSchemes({bool forceRefresh = false}) async {
    if (!forceRefresh && _govtSchemesCache != null) return _govtSchemesCache!;

    final data = await _fetchCollection('govtSchemes', _longTTL, forceRefresh: forceRefresh);
    _govtSchemesCache = data;
    return data;
  }

  // ─── Study Notes ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchStudyNotes({
    String? subject,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _studyNotesCache != null) {
      if (subject != null) {
        return _studyNotesCache!.where((n) => n['subject'] == subject).toList();
      }
      return _studyNotesCache!;
    }

    final data = await _fetchCollection('studyNotes', _longTTL, forceRefresh: forceRefresh);
    _studyNotesCache = data;

    if (subject != null) {
      return data.where((n) => n['subject'] == subject).toList();
    }
    return data;
  }

  // ─── Current Affairs ─────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchCurrentAffairs({bool forceRefresh = false}) async {
    if (!forceRefresh && _currentAffairsCache != null) return _currentAffairsCache!;

    final data = await _fetchCollection('currentAffairs', _shortTTL, forceRefresh: forceRefresh);
    _currentAffairsCache = data;
    return data;
  }

  // ─── Mock Tests ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchMockTests({bool forceRefresh = false}) async {
    if (!forceRefresh && _mockTestsCache != null) return _mockTestsCache!;

    final data = await _fetchCollection('mockTests', _longTTL, forceRefresh: forceRefresh);
    _mockTestsCache = data;
    return data;
  }

  // ─── Syllabus ────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchSyllabus({bool forceRefresh = false}) async {
    if (!forceRefresh && _syllabusCache != null) return _syllabusCache!;

    final data = await _fetchCollection('syllabus', _longTTL, forceRefresh: forceRefresh);
    _syllabusCache = data;
    return data;
  }

  // ─── Answer Writing ──────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchAnswerWritingTopics({bool forceRefresh = false}) async {
    if (!forceRefresh && _answerWritingCache != null) return _answerWritingCache!;

    final data = await _fetchCollection('answerWriting', _longTTL, forceRefresh: forceRefresh);
    _answerWritingCache = data;
    return data;
  }

  // ─── Core fetch with SharedPreferences cache ─────────────────────────

  static Future<List<Map<String, dynamic>>> _fetchCollection(
    String collection,
    Duration ttl, {
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'api_$collection';
    final tsKey = 'api_ts_$collection';

    // Check local cache validity
    if (!forceRefresh) {
      final cachedJson = prefs.getString(cacheKey);
      final cachedTs = prefs.getInt(tsKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (cachedJson != null && (now - cachedTs) < ttl.inMilliseconds) {
        try {
          return (jsonDecode(cachedJson) as List).cast<Map<String, dynamic>>();
        } catch (_) {
          // Corrupted cache, fall through to fetch
        }
      }
    }

    // Fetch from Firestore
    try {
      final snapshot = await _firestore.collection(collection).get();
      final docs = snapshot.docs
          .map((d) => <String, dynamic>{'docId': d.id, ...d.data()})
          .toList();

      if (docs.isNotEmpty) {
        await prefs.setString(cacheKey, jsonEncode(docs));
        await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
        return docs;
      }
    } catch (e) {
      debugPrint('Firestore fetch error for $collection: $e');
    }

    // Return expired cache if Firestore failed
    final cachedJson = prefs.getString(cacheKey);
    if (cachedJson != null) {
      try {
        return (jsonDecode(cachedJson) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        // Corrupted cache
      }
    }

    return [];
  }

  /// Clear all caches.
  static Future<void> clearAllCaches() async {
    _flashcardsCache = null;
    _dailyFactsCache = null;
    _pyqCache = null;
    _vocabularyCache = null;
    _govtSchemesCache = null;
    _studyNotesCache = null;
    _currentAffairsCache = null;
    _mockTestsCache = null;
    _syllabusCache = null;
    _answerWritingCache = null;

    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('api_'));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Refresh a specific collection.
  static Future<List<Map<String, dynamic>>> refresh(String collection) async {
    switch (collection) {
      case 'flashcards': _flashcardsCache = null; return fetchFlashcards(forceRefresh: true);
      case 'dailyFacts': _dailyFactsCache = null; return fetchDailyFacts(forceRefresh: true);
      case 'pyqBank': _pyqCache = null; return fetchPYQ(forceRefresh: true);
      case 'vocabulary': _vocabularyCache = null; return fetchVocabulary(forceRefresh: true);
      case 'govtSchemes': _govtSchemesCache = null; return fetchGovtSchemes(forceRefresh: true);
      case 'studyNotes': _studyNotesCache = null; return fetchStudyNotes(forceRefresh: true);
      case 'currentAffairs': _currentAffairsCache = null; return fetchCurrentAffairs(forceRefresh: true);
      case 'mockTests': _mockTestsCache = null; return fetchMockTests(forceRefresh: true);
      default: return _fetchCollection(collection, _mediumTTL, forceRefresh: true);
    }
  }
}
