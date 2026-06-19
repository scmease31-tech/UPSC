import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_profile.dart';

/// Manages authentication state, user profile data, and personalization.
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  late final StreamSubscription<User?> _authSub;

  User? _firebaseUser;
  UserProfile? _userProfile;
  bool _isLoading = false;
  bool _isSigningUp = false; // Prevents race condition during signup

  User? get firebaseUser => _firebaseUser;
  UserProfile? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _firebaseUser != null;

  AuthProvider() {
    _authSub = _auth.authStateChanges().listen((user) {
      _firebaseUser = user;
      if (user != null && !_isSigningUp) {
        _loadUserProfile();
      } else if (user == null) {
        _userProfile = null;
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  /// Sign in with Google account.
  Future<String?> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return 'Sign in cancelled';
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      _isSigningUp = true;
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user!;

      // Create or merge user profile in Firestore
      try {
        final docRef = _firestore.collection('users').doc(user.uid);
        final doc = await docRef.get();

        if (!doc.exists) {
          final profile = UserProfile(
            uid: user.uid,
            name: user.displayName ?? 'User',
            email: user.email ?? '',
            photoUrl: user.photoURL ?? '',
            lastActiveDate: DateTime.now(),
          );
          await docRef.set(profile.toMap());
          _userProfile = profile;
        } else {
          _userProfile = UserProfile.fromMap(doc.data()!);
          await docRef.update({
            'name': user.displayName ?? doc.data()!['name'],
            'photoUrl': user.photoURL ?? '',
            'lastActiveDate': DateTime.now().toIso8601String(),
          }).catchError((e) {
            debugPrint('Failed to update Google sign-in profile: $e');
          });
          _userProfile = _userProfile!.copyWith(
            name: user.displayName ?? _userProfile!.name,
            photoUrl: user.photoURL ?? '',
            lastActiveDate: DateTime.now(),
          );
        }
      } catch (_) {
        // Firestore failed — create local profile so app works
        _userProfile = UserProfile(
          uid: user.uid,
          name: user.displayName ?? 'User',
          email: user.email ?? '',
          photoUrl: user.photoURL ?? '',
          lastActiveDate: DateTime.now(),
        );
      }

      _isSigningUp = false;
      _isLoading = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      _isSigningUp = false;
      _isLoading = false;
      notifyListeners();
      return _getFriendlyAuthError(e.code);
    } on FirebaseException catch (e) {
      _isSigningUp = false;
      _isLoading = false;
      notifyListeners();
      return _getFriendlyAuthError(e.code);
    } catch (e) {
      _isSigningUp = false;
      _isLoading = false;
      notifyListeners();
      debugPrint('Google sign in error (${e.runtimeType}): $e');
      return 'Google sign in failed. Please try again.';
    }
  }

  /// Sign up with email and password.
  Future<String?> signUp(String name, String email, String password) async {
    try {
      _isLoading = true;
      _isSigningUp = true;
      notifyListeners();

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Update display name in Firebase Auth
      try {
        await credential.user?.updateDisplayName(name.trim());
      } catch (_) {}

      final profile = UserProfile(
        uid: credential.user!.uid,
        name: name.trim(),
        email: email.trim(),
        lastActiveDate: DateTime.now(),
      );

      // Write profile to Firestore
      try {
        await _firestore.collection('users').doc(credential.user!.uid).set(profile.toMap());
      } catch (e) {
        debugPrint('Firestore profile write failed: $e');
      }

      _userProfile = profile;
      _isSigningUp = false;
      _isLoading = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      _isSigningUp = false;
      _isLoading = false;
      notifyListeners();
      return _getFriendlyAuthError(e.code);
    } on FirebaseException catch (e) {
      _isSigningUp = false;
      _isLoading = false;
      notifyListeners();
      return _getFriendlyAuthError(e.code);
    } catch (e) {
      _isSigningUp = false;
      _isLoading = false;
      notifyListeners();
      debugPrint('Sign up error (${e.runtimeType}): $e');
      return 'Sign up failed. Please try again.';
    }
  }

  /// Sign in with email and password.
  Future<String?> signIn(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Bump last active
      if (_auth.currentUser != null) {
        _firestore.collection('users').doc(_auth.currentUser!.uid).update({
          'lastActiveDate': DateTime.now().toIso8601String(),
        }).catchError((e) {
          debugPrint('Failed to update last active date: $e');
        });
      }

      _isLoading = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      _isLoading = false;
      notifyListeners();
      return _getFriendlyAuthError(e.code);
    } on FirebaseException catch (e) {
      _isLoading = false;
      notifyListeners();
      return _getFriendlyAuthError(e.code);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Sign in failed. Please try again.';
    }
  }

  /// Sign out from Firebase and Google.
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    _userProfile = null;
    notifyListeners();
  }

  /// Load full user profile from Firestore.
  Future<void> _loadUserProfile() async {
    if (_firebaseUser == null) return;
    try {
      final doc = await _firestore.collection('users').doc(_firebaseUser!.uid).get();
      if (doc.exists) {
        _userProfile = UserProfile.fromMap(doc.data()!);
        // Update streak
        _updateStreak();
      } else {
        _userProfile = UserProfile(
          uid: _firebaseUser!.uid,
          name: _firebaseUser!.displayName ?? 'User',
          email: _firebaseUser!.email ?? '',
          photoUrl: _firebaseUser!.photoURL ?? '',
          lastActiveDate: DateTime.now(),
        );
        await _firestore.collection('users').doc(_firebaseUser!.uid).set(_userProfile!.toMap());
      }
    } catch (_) {
      _userProfile = UserProfile(
        uid: _firebaseUser!.uid,
        name: _firebaseUser!.displayName ?? 'User',
        email: _firebaseUser!.email ?? '',
        photoUrl: _firebaseUser!.photoURL ?? '',
      );
    }
    notifyListeners();
  }

  /// Update daily streak.
  void _updateStreak() {
    if (_userProfile == null) return;
    final now = DateTime.now();
    final lastActive = _userProfile!.lastActiveDate;

    int newStreak = _userProfile!.streakDays;
    if (lastActive != null) {
      final diff = DateTime(now.year, now.month, now.day)
          .difference(DateTime(lastActive.year, lastActive.month, lastActive.day))
          .inDays;
      if (diff == 1) {
        newStreak = _userProfile!.streakDays + 1;
      } else if (diff > 1) {
        newStreak = 1;
      }
    } else {
      newStreak = 1;
    }

    _userProfile = _userProfile!.copyWith(
      streakDays: newStreak,
      lastActiveDate: now,
    );

    _firestore.collection('users').doc(_firebaseUser!.uid).update({
      'streakDays': newStreak,
      'lastActiveDate': now.toIso8601String(),
    }).catchError((e) {
      debugPrint('Failed to update streak: $e');
    });
  }

  /// Save quiz score to user profile in Firestore.
  Future<void> saveQuizScore(QuizScore score) async {
    if (_userProfile == null || _firebaseUser == null) return;

    final updatedScores = [..._userProfile!.quizScores, score];
    _userProfile = _userProfile!.copyWith(quizScores: updatedScores);
    notifyListeners();

    await _firestore.collection('users').doc(_firebaseUser!.uid).update({
      'quizScores': updatedScores.map((s) => s.toMap()).toList(),
    }).catchError((e) {
      debugPrint('Failed to save quiz score: $e');
    });
  }

  /// Sync bookmarks to Firestore.
  Future<void> syncBookmarks(Set<String> bookmarkedIds) async {
    if (_userProfile == null || _firebaseUser == null) return;

    _userProfile = _userProfile!.copyWith(
      bookmarkedArticleIds: bookmarkedIds.toList(),
    );

    await _firestore.collection('users').doc(_firebaseUser!.uid).update({
      'bookmarkedArticleIds': bookmarkedIds.toList(),
    }).catchError((e) {
      debugPrint('Failed to sync bookmarks: $e');
    });
  }

  /// Get saved bookmarks from profile.
  Set<String> getSavedBookmarks() {
    return _userProfile?.bookmarkedArticleIds.toSet() ?? {};
  }

  /// Update preferred categories.
  Future<void> updatePreferences(List<String> categories) async {
    if (_userProfile == null || _firebaseUser == null) return;

    _userProfile = _userProfile!.copyWith(preferredCategories: categories);
    notifyListeners();

    await _firestore.collection('users').doc(_firebaseUser!.uid).update({
      'preferredCategories': categories,
    }).catchError((e) {
      debugPrint('Failed to update preferences: $e');
    });
  }

  /// Update daily goal.
  Future<void> updateDailyGoal(int minutes) async {
    if (_userProfile == null || _firebaseUser == null) return;

    _userProfile = _userProfile!.copyWith(dailyGoalMinutes: minutes);
    notifyListeners();

    await _firestore.collection('users').doc(_firebaseUser!.uid).update({
      'dailyGoalMinutes': minutes,
    }).catchError((e) {
      debugPrint('Failed to update daily goal: $e');
    });
  }

  /// Update display name.
  Future<void> updateDisplayName(String name) async {
    if (_firebaseUser == null) return;

    await _firebaseUser!.updateDisplayName(name);
    _userProfile = _userProfile?.copyWith(name: name);
    notifyListeners();

    await _firestore.collection('users').doc(_firebaseUser!.uid).update({
      'name': name,
    }).catchError((e) {
      debugPrint('Failed to update display name: $e');
    });
  }

  /// Get total quizzes taken.
  int get totalQuizzesTaken => _userProfile?.quizScores.length ?? 0;

  /// Get average quiz accuracy.
  double get averageAccuracy {
    final scores = _userProfile?.quizScores ?? [];
    if (scores.isEmpty) return 0;
    final totalCorrect = scores.fold<int>(0, (sum, s) => sum + s.score);
    final totalQuestions = scores.fold<int>(0, (sum, s) => sum + s.totalQuestions);
    return totalQuestions > 0 ? totalCorrect / totalQuestions : 0;
  }

  /// Get best quiz score percentage.
  double get bestScore {
    final scores = _userProfile?.quizScores ?? [];
    if (scores.isEmpty) return 0;
    return scores
        .map((s) => s.totalQuestions > 0 ? s.score / s.totalQuestions : 0.0)
        .reduce((a, b) => a > b ? a : b);
  }

  /// Convert Firebase error codes to user-friendly messages.
  String _getFriendlyAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Try signing in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email. Please sign up first.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled. Contact support.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}
