import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/article.dart';
import '../data/dummy_data.dart';

/// Manages bookmarked articles with Firestore sync per user.
class BookmarksProvider extends ChangeNotifier {
  final Set<String> _bookmarkedIds = {};
  List<Article> _allArticles = [];
  String? _userId;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;

  Set<String> get bookmarkedIds => _bookmarkedIds;

  bool isBookmarked(String articleId) => _bookmarkedIds.contains(articleId);

  /// Load bookmarks for logged-in user from Firestore.
  Future<void> loadUserBookmarks(String userId) async {
    if (_isLoading) return;
    _isLoading = true;
    _userId = userId;
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        final ids = List<String>.from(doc.data()?['bookmarkedArticleIds'] ?? []);
        _bookmarkedIds.clear();
        _bookmarkedIds.addAll(ids);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load bookmarks: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Clear bookmarks on sign out.
  void clearBookmarks() {
    _bookmarkedIds.clear();
    _userId = null;
    notifyListeners();
  }

  /// Toggle bookmark status for an article and sync to Firestore.
  void toggleBookmark(String articleId) {
    if (_bookmarkedIds.contains(articleId)) {
      _bookmarkedIds.remove(articleId);
    } else {
      _bookmarkedIds.add(articleId);
    }
    notifyListeners();
    _syncToFirestore();
  }

  /// Sync bookmarks to user's Firestore document.
  Future<void> _syncToFirestore() async {
    if (_userId == null) return;
    try {
      await _firestore.collection('users').doc(_userId).update({
        'bookmarkedArticleIds': _bookmarkedIds.toList(),
      });
    } catch (e) {
      debugPrint('Bookmark sync failed: $e');
    }
  }

  /// Get bookmarked articles from Firestore or dummy data.
  List<Article> getBookmarkedArticles() {
    if (_allArticles.isEmpty) {
      _loadArticlesCache();
      return DummyData.articles
          .where((a) => _bookmarkedIds.contains(a.id))
          .toList();
    }
    return _allArticles
        .where((a) => _bookmarkedIds.contains(a.id))
        .toList();
  }

  Future<void> _loadArticlesCache() async {
    try {
      final snapshot = await _firestore.collection('articles').get();
      if (snapshot.docs.isNotEmpty) {
        _allArticles = snapshot.docs
            .map((doc) => Article.fromMap(doc.data(), doc.id))
            .toList();
      } else {
        _allArticles = DummyData.articles;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load articles cache: $e');
      _allArticles = DummyData.articles;
      notifyListeners();
    }
  }
}
