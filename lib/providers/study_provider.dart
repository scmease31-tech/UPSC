import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/subject.dart';
import '../models/weekly_magazine.dart';
import '../data/dummy_data.dart';

/// Provides study material and weekly magazine data.
class StudyProvider extends ChangeNotifier {
  List<Subject> _subjects = [];
  List<WeeklyMagazine> _magazines = [];
  bool _isLoading = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Subject> get subjects => _subjects;
  List<WeeklyMagazine> get magazines => _magazines;
  bool get isLoading => _isLoading;

  StudyProvider() {
    loadData();
  }

  /// Load study subjects and magazines from Firestore; falls back to dummy data.
  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final subjectsSnapshot = await _firestore.collection('subjects').get();
      final magazinesSnapshot = await _firestore.collection('weeklyMagazines').get();

      if (subjectsSnapshot.docs.isNotEmpty) {
        try {
          _subjects = subjectsSnapshot.docs
              .map((doc) => Subject.fromMap(doc.data(), doc.id))
              .toList();
        } catch (_) {
          _subjects = DummyData.subjects;
        }
      } else {
        _subjects = DummyData.subjects;
      }

      if (magazinesSnapshot.docs.isNotEmpty) {
        try {
          _magazines = magazinesSnapshot.docs
              .map((doc) => WeeklyMagazine.fromMap(doc.data(), doc.id))
              .toList();
        } catch (_) {
          _magazines = DummyData.magazines;
        }
      } else {
        _magazines = DummyData.magazines;
      }
    } catch (e) {
      _subjects = DummyData.subjects;
      _magazines = DummyData.magazines;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Get a subject by ID.
  Subject? getSubjectById(String id) {
    try {
      return _subjects.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
}
