import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/article.dart';
import '../data/dummy_data.dart';
import '../services/notification_service.dart';

/// Provides current affairs articles and manages article-related state.
class ArticlesProvider extends ChangeNotifier {
  List<Article> _articles = [];
  String _selectedCategory = 'All';
  String _selectedDate = ''; // yyyy-MM-dd format; empty = all dates
  String _selectedNewspaper = ''; // empty = all newspapers
  String _searchQuery = '';
  bool _isLoading = false;
  List<Article>? _cachedFiltered;
  String _cacheKey = '';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot>? _firestoreSub;

  List<Article> get allArticles => _articles;

  List<Article> get articles {
    final key = '$_selectedDate|$_selectedCategory|$_selectedNewspaper|$_searchQuery|${_articles.length}';
    if (key == _cacheKey && _cachedFiltered != null) return _cachedFiltered!;

    var list = allArticles;

    // Filter by date
    if (_selectedDate.isNotEmpty) {
      list = list.where((a) {
        final d = '${a.publishedDate.year}-${a.publishedDate.month.toString().padLeft(2, '0')}-${a.publishedDate.day.toString().padLeft(2, '0')}';
        return d == _selectedDate;
      }).toList();
    }

    // Filter by newspaper
    if (_selectedNewspaper.isNotEmpty) {
      list = list.where((a) => a.newspaper.toLowerCase() == _selectedNewspaper.toLowerCase()).toList();
    }

    // Filter by category
    if (_selectedCategory != 'All') {
      list = list.where((a) => a.categoryTags.contains(_selectedCategory)).toList();
    }

    // Filter by search — deep search across all relevant fields for UPSC aspirants
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      final queryWords = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      list = list.where((a) {
        final searchableText = [
          a.title,
          a.summary,
          a.content,
          a.newspaper,
          a.upscPaper,
          a.syllabusMapping,
          a.analysisNote,
          a.constitutionalBasis,
          a.governmentScheme,
          a.editorialOpinion,
          ...a.categoryTags,
          ...a.relatedTopics,
          ...a.keyPoints,
          ...a.shortNotes,
          ...a.keyTerms.keys,
          ...a.keyTerms.values,
        ].join(' ').toLowerCase();
        // Match if ALL query words appear somewhere in the combined text
        return queryWords.every((word) => searchableText.contains(word));
      }).toList();
    }

    _cachedFiltered = list;
    _cacheKey = key;
    return list;
  }

  List<Article> get topNews => allArticles.where((a) => a.isTopNews).toList();

  String get selectedCategory => _selectedCategory;
  String get selectedDate => _selectedDate;
  String get selectedNewspaper => _selectedNewspaper;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;

  /// Distinct dates available (for date picker)
  List<String> get availableDates {
    final dates = <String>{};
    for (final a in allArticles) {
      dates.add('${a.publishedDate.year}-${a.publishedDate.month.toString().padLeft(2, '0')}-${a.publishedDate.day.toString().padLeft(2, '0')}');
    }
    final sorted = dates.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  /// Distinct newspapers available
  List<String> get availableNewspapers {
    final papers = <String>{};
    for (final a in allArticles) {
      if (a.newspaper.isNotEmpty) papers.add(a.newspaper);
    }
    return papers.toList()..sort();
  }

  static const List<String> categories = [
    'All',
    'Polity',
    'Economy',
    'Environment',
    'Science & Technology',
    'International Relations',
    'History',
    'Geography',
    'Governance',
    'Security',
    'Ethics',
    'Social Issues',
  ];

  ArticlesProvider() {
    loadArticles();
  }

  @override
  void dispose() {
    _firestoreSub?.cancel();
    super.dispose();
  }

  /// Load articles from Firestore with real-time listener; falls back to dummy data.
  Future<void> loadArticles() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Set up real-time listener
      _firestoreSub?.cancel();
      _firestoreSub = _firestore
          .collection('articles')
          .orderBy('publishedDate', descending: true)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          try {
            _articles = snapshot.docs
                .map((doc) {
                  try {
                    return Article.fromMap(doc.data(), doc.id);
                  } catch (e) {
                    debugPrint('Skipping bad article doc ${doc.id}: $e');
                    return null;
                  }
                })
                .whereType<Article>()
                .toList();
            if (_articles.isEmpty) _articles = DummyData.articles;
            // Update scheduled notification with latest article
            _updateNotificationWithLatest();
          } catch (_) {
            _articles = DummyData.articles;
          }
        } else {
          _articles = DummyData.articles;
        }
        _isLoading = false;
        notifyListeners();
      }, onError: (e) {
        debugPrint('Firestore articles stream error: $e');
        _articles = DummyData.articles;
        _isLoading = false;
        notifyListeners();
      });

      // Initial fetch for immediate data (before stream fires)
      final snapshot = await _firestore
          .collection('articles')
          .orderBy('publishedDate', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        _articles = snapshot.docs
            .map((doc) {
              try {
                return Article.fromMap(doc.data(), doc.id);
              } catch (e) {
                debugPrint('Skipping bad article doc ${doc.id}: $e');
                return null;
              }
            })
            .whereType<Article>()
            .toList();
        if (_articles.isEmpty) _articles = DummyData.articles;
      } else {
        _articles = DummyData.articles;
      }
    } catch (e) {
      debugPrint('Initial articles fetch error: $e');
      _articles = DummyData.articles;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Filter articles by category.
  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  /// Filter articles by date (yyyy-MM-dd). Empty string = all dates.
  void setDate(String date) {
    _selectedDate = date;
    notifyListeners();
  }

  /// Filter articles by newspaper source. Empty string = all newspapers.
  void setNewspaper(String newspaper) {
    _selectedNewspaper = newspaper;
    notifyListeners();
  }

  /// Search articles by query text. Empty = no filter.
  void setSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Update the scheduled notification with the latest article content.
  void _updateNotificationWithLatest() {
    if (_articles.isNotEmpty) {
      final latest = _articles.first;
      NotificationService.scheduleDailyNotification(
        articleTitle: latest.title,
        articleId: latest.id,
      );
    }
  }

  /// Get a single article by ID.
  Article? getArticleById(String id) {
    try {
      return allArticles.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get related articles by topic overlap.
  List<Article> getRelatedArticles(Article article, {int limit = 5}) {
    final tags = article.categoryTags.toSet();
    final topics = article.relatedTopics.map((t) => t.toLowerCase()).toSet();

    final scored = allArticles
        .where((a) => a.id != article.id)
        .map((a) {
          int score = 0;
          for (final tag in a.categoryTags) {
            if (tags.contains(tag)) score += 2;
          }
          for (final kp in a.keyPoints) {
            final kpLower = kp.toLowerCase();
            for (final topic in topics) {
              if (kpLower.contains(topic)) score++;
            }
          }
          if (a.upscPaper == article.upscPaper && article.upscPaper.isNotEmpty) score++;
          return MapEntry(a, score);
        })
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return scored.take(limit).map((e) => e.key).toList();
  }
}
