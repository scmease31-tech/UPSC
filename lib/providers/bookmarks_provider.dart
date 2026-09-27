import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/article.dart';
import '../data/dummy_data.dart';
import '../services/firebase_services.dart';

/// Manages bookmarked articles with Firestore sync per user.
class BookmarksProvider extends ChangeNotifier {
  final Set<String> _bookmarkedIds = {};
  List<Article> _allArticles = [];
  String? _userId;

  final _userFirestore = FirebaseServices.userFirestore;
  final _contentFirestore = FirebaseServices.contentFirestore;

  bool _isLoading = false;
  int _loadGeneration = 0;

  Set<String> get bookmarkedIds => _bookmarkedIds;
  bool get isLoading => _isLoading;

  bool isBookmarked(String articleId) => _bookmarkedIds.contains(articleId);

  /// Load bookmarks for the current user. Each call supersedes the preceding
  /// one, so a slow account-A request cannot overwrite account B after a switch.
  Future<void> loadUserBookmarks(String userId) async {
    final generation = ++_loadGeneration;
    _isLoading = true;

    if (_userId != userId) {
      // Never display one account's bookmarks while the next account loads.
      _bookmarkedIds.clear();
      _userId = userId;
      notifyListeners();
    }

    try {
      final doc = await _userFirestore
          .collection('users')
          .doc(userId)
          .get()
          .timeout(const Duration(seconds: 15));
      if (generation != _loadGeneration || _userId != userId) return;
      final raw = doc.data()?['bookmarkedArticleIds'];
      final ids = raw is List
          ? raw
              .where((item) => item != null)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
          : const Iterable<String>.empty();
      // A missing document means this user has no bookmarks; leaving the old
      // set in place leaked the preceding user's state.
      _bookmarkedIds
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (error) {
      if (generation == _loadGeneration) {
        debugPrint('Failed to load bookmarks: $error');
      }
    } finally {
      if (generation == _loadGeneration) _isLoading = false;
    }
  }

  /// Clear bookmarks on sign out.
  void clearBookmarks() {
    _loadGeneration++;
    _isLoading = false;
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
      await _userFirestore.collection('users').doc(_userId).set({
        'bookmarkedArticleIds': _bookmarkedIds.toList(),
      }, SetOptions(merge: true));
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
    return _allArticles.where((a) => _bookmarkedIds.contains(a.id)).toList();
  }

  Future<void> _loadArticlesCache() async {
    try {
      final snapshot = await _contentFirestore
          .collection('articles')
          .limit(500)
          .get()
          .timeout(const Duration(seconds: 15));
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
