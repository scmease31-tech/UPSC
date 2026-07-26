import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pyq_bank.dart';
import '../models/pyq_question.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// PyqService — supplies the Previous Year Questions tab.
///
/// Questions come from two places and are merged into one list:
///   1. [PyqBank] — the offline seed bank shipped with the app.
///   2. The `pyqs` Firestore collection — harvested verbatim (with exam year,
///      options and answer key) from the PYQ block Drishti appends to its daily
///      articles, so the bank grows without an app update.
///
/// Attempt state (answered / correct / bookmarked) is stored locally, so
/// progress works signed-out and offline.
/// ──────────────────────────────────────────────────────────────────────────────
class PyqService {
  PyqService._();

  static const _kAttempted = 'pyq_attempted';
  static const _kCorrect = 'pyq_correct';
  static const _kBookmarked = 'pyq_bookmarked';

  static List<PyqQuestion>? _cache;
  static DateTime? _fetchedAt;
  static const _ttl = Duration(hours: 6);

  /// Seed bank + anything harvested into Firestore, de-duplicated and sorted
  /// newest year first. Never throws: the seed bank alone is a valid result.
  static Future<List<PyqQuestion>> load({bool forceRefresh = false}) async {
    final fresh = _fetchedAt != null && DateTime.now().difference(_fetchedAt!) < _ttl;
    if (!forceRefresh && _cache != null && fresh) return _cache!;

    final merged = <String, PyqQuestion>{};
    // Seed first so a harvested duplicate (which carries the verbatim wording
    // and the verified answer key) overwrites it.
    for (final q in PyqBank.all) {
      merged[_dedupKey(q)] = q;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('pyqs')
          .orderBy('year', descending: true)
          .limit(600)
          .get();
      for (final doc in snap.docs) {
        final q = PyqQuestion.fromMap(doc.data(), doc.id);
        if (q.question.trim().length < 20 || q.year < 1990) continue;

        // The same question can arrive twice: once from an official UPSC paper
        // (authentic wording, no answer key — UPSC does not publish one) and
        // once from a Drishti article that quotes it WITH its key. Keep the
        // copy the user can actually attempt.
        final key = _dedupKey(q);
        final existing = merged[key];
        if (existing != null && existing.isAnswerable && !q.isAnswerable) continue;
        merged[key] = q;
      }
    } catch (_) {
      // Offline or rules not deployed — the seed bank still renders.
    }

    final list = merged.values.toList()
      ..sort((a, b) {
        final byYear = b.year.compareTo(a.year);
        if (byYear != 0) return byYear;
        final byType = a.type.index.compareTo(b.type.index);
        if (byType != 0) return byType;
        return a.subject.compareTo(b.subject);
      });

    _cache = list;
    _fetchedAt = DateTime.now();
    return list;
  }

  /// Questions can arrive from both sources with different ids but identical
  /// wording — key on year plus a normalised prefix of the stem.
  static String _dedupKey(PyqQuestion q) {
    final stem = q.question.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '${q.year}|${q.type.index}|${stem.substring(0, stem.length < 60 ? stem.length : 60)}';
  }

  // ── Progress ───────────────────────────────────────────────────────────────

  /// Ids the user has answered, and the subset answered correctly.
  static Future<PyqProgress> loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    return PyqProgress(
      attempted: (prefs.getStringList(_kAttempted) ?? const []).toSet(),
      correct: (prefs.getStringList(_kCorrect) ?? const []).toSet(),
      bookmarked: (prefs.getStringList(_kBookmarked) ?? const []).toSet(),
    );
  }

  static Future<void> recordAttempt(String id, bool wasCorrect) async {
    final prefs = await SharedPreferences.getInstance();
    final attempted = (prefs.getStringList(_kAttempted) ?? const []).toSet()..add(id);
    final correct = (prefs.getStringList(_kCorrect) ?? const []).toSet();
    if (wasCorrect) {
      correct.add(id);
    } else {
      correct.remove(id);
    }
    await prefs.setStringList(_kAttempted, attempted.toList());
    await prefs.setStringList(_kCorrect, correct.toList());
  }

  static Future<Set<String>> toggleBookmark(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final marks = (prefs.getStringList(_kBookmarked) ?? const []).toSet();
    if (!marks.add(id)) marks.remove(id);
    await prefs.setStringList(_kBookmarked, marks.toList());
    return marks;
  }

  static Future<void> resetProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAttempted);
    await prefs.remove(_kCorrect);
  }
}

class PyqProgress {
  final Set<String> attempted;
  final Set<String> correct;
  final Set<String> bookmarked;

  const PyqProgress({
    this.attempted = const {},
    this.correct = const {},
    this.bookmarked = const {},
  });

  int get answered => attempted.length;
  int get right => correct.length;
  double get accuracy => attempted.isEmpty ? 0 : correct.length / attempted.length;
}
