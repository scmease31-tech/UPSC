import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Manages daily challenge state, streak tracking, bookmarks for revision,
/// weekly progress, and exam countdown — all persisted locally.
class DailyProgressProvider extends ChangeNotifier {
  // ── Daily Challenge ──
  bool _dailyChallengeCompleted = false;
  String _lastChallengeDate = '';
  int _dailyChallengeScore = 0;
  int _dailyChallengeTotalXp = 0;

  // ── Streak ──
  int _currentStreak = 0;
  int _longestStreak = 0;
  String _lastActiveDate = '';
  List<String> _streakHistory = []; // last 7 days: 'done' or 'missed'

  // ── Daily Progress ──
  int _articlesReadToday = 0;
  int _quizzesToday = 0;
  int _studyMinutesToday = 0;
  String _todayDate = '';

  // ── Weekly Progress ──
  int _articlesReadThisWeek = 0;
  int _quizzesThisWeek = 0;
  int _correctAnswersThisWeek = 0;
  int _totalAnswersThisWeek = 0;
  int _studyMinutesThisWeek = 0;
  String _weekStartDate = '';

  // ── Revision / Bookmarks ──
  Set<String> _readArticleIds = {};
  List<Map<String, dynamic>> _incorrectQuestions = [];
  List<String> _savedFactIds = [];

  // ── Flashcard progress ──
  int _flashcardIndex = 0;
  List<int> _masteredFlashcards = [];

  // ── Getters ──
  bool get dailyChallengeCompleted => _dailyChallengeCompleted;
  int get dailyChallengeScore => _dailyChallengeScore;
  int get dailyChallengeTotalXp => _dailyChallengeTotalXp;
  int get currentStreak => _currentStreak;
  int get longestStreak => _longestStreak;
  List<String> get streakHistory => _streakHistory;
  int get articlesReadToday => _articlesReadToday;
  int get quizzesToday => _quizzesToday;
  int get studyMinutesToday => _studyMinutesToday;
  int get articlesReadThisWeek => _articlesReadThisWeek;
  int get quizzesThisWeek => _quizzesThisWeek;
  int get correctAnswersThisWeek => _correctAnswersThisWeek;
  int get totalAnswersThisWeek => _totalAnswersThisWeek;
  int get studyMinutesThisWeek => _studyMinutesThisWeek;
  double get weeklyAccuracy =>
      _totalAnswersThisWeek > 0 ? _correctAnswersThisWeek / _totalAnswersThisWeek * 100 : 0;
  Set<String> get readArticleIds => _readArticleIds;
  List<Map<String, dynamic>> get incorrectQuestions => _incorrectQuestions;
  List<String> get savedFactIds => _savedFactIds;
  int get flashcardIndex => _flashcardIndex;
  List<int> get masteredFlashcards => _masteredFlashcards;

  // ── Exam Countdown ──
  static final DateTime upscPrelims2026 = DateTime(2026, 5, 24);
  static final DateTime upscMains2026 = DateTime(2026, 9, 18);

  int get daysToPrelimsExam {
    final now = DateTime.now();
    final target = now.isBefore(upscPrelims2026) ? upscPrelims2026 : DateTime(2027, 5, 23);
    return target.difference(now).inDays;
  }

  int get prelimsExamYear => DateTime.now().isBefore(upscPrelims2026) ? 2026 : 2027;

  int get daysToMainsExam {
    final now = DateTime.now();
    final target = now.isBefore(upscMains2026) ? upscMains2026 : DateTime(2027, 9, 17);
    return target.difference(now).inDays;
  }

  int get mainsExamYear => DateTime.now().isBefore(upscMains2026) ? 2026 : 2027;

  DailyProgressProvider() {
    _loadFromPrefs();
  }

  // ── Daily challenge ──
  void completeDailyChallenge(int score, int total) {
    final today = _todayStr();
    _dailyChallengeCompleted = true;
    _lastChallengeDate = today;
    _dailyChallengeScore = score;
    _dailyChallengeTotalXp += 50 + (score * 10);
    _checkDayReset();
    _quizzesToday++;
    _quizzesThisWeek++;
    _correctAnswersThisWeek += score;
    _totalAnswersThisWeek += total;
    _updateStreak();
    notifyListeners();
    _saveToPrefs();
  }

  bool get isChallengeAvailableToday => _lastChallengeDate != _todayStr();

  // ── Streak ──
  void _updateStreak() {
    final today = _todayStr();
    if (_lastActiveDate == today) return;

    final yesterday = _dateStr(DateTime.now().subtract(const Duration(days: 1)));
    if (_lastActiveDate == yesterday) {
      _currentStreak++;
    } else if (_lastActiveDate != today) {
      _currentStreak = 1;
    }

    if (_currentStreak > _longestStreak) _longestStreak = _currentStreak;
    _lastActiveDate = today;

    // Update streak history (keep last 7)
    _streakHistory.add('done');
    if (_streakHistory.length > 7) {
      _streakHistory = _streakHistory.sublist(_streakHistory.length - 7);
    }
  }

  void recordActivity() {
    _updateStreak();
    notifyListeners();
    _saveToPrefs();
  }

  // ── Article read tracking ──
  void markArticleRead(String articleId) {
    if (_readArticleIds.add(articleId)) {
      _checkDayReset();
      _articlesReadToday++;
      _articlesReadThisWeek++;
      _updateStreak();
      notifyListeners();
      _saveToPrefs();
    }
  }

  bool isArticleRead(String articleId) => _readArticleIds.contains(articleId);

  // ── Incorrect question tracking ──
  void addIncorrectQuestion(Map<String, dynamic> question) {
    // Avoid duplicates by question text
    if (!_incorrectQuestions.any((q) => q['question'] == question['question'])) {
      _incorrectQuestions.add(question);
      if (_incorrectQuestions.length > 50) {
        _incorrectQuestions.removeAt(0);
      }
      notifyListeners();
      _saveToPrefs();
    }
  }

  void removeIncorrectQuestion(int index) {
    if (index >= 0 && index < _incorrectQuestions.length) {
      _incorrectQuestions.removeAt(index);
      notifyListeners();
      _saveToPrefs();
    }
  }

  // ── Saved facts ──
  void toggleSavedFact(String factId) {
    if (_savedFactIds.contains(factId)) {
      _savedFactIds.remove(factId);
    } else {
      _savedFactIds.add(factId);
    }
    notifyListeners();
    _saveToPrefs();
  }

  bool isFactSaved(String factId) => _savedFactIds.contains(factId);

  // ── Flashcards ──
  void setFlashcardIndex(int index) {
    _flashcardIndex = index;
    notifyListeners();
    _saveToPrefs();
  }

  void markFlashcardMastered(int index) {
    if (!_masteredFlashcards.contains(index)) {
      _masteredFlashcards.add(index);
      notifyListeners();
      _saveToPrefs();
    }
  }

  // ── Study time ──
  void addStudyMinutes(int minutes) {
    _checkDayReset();
    _studyMinutesToday += minutes;
    _studyMinutesThisWeek += minutes;
    notifyListeners();
    _saveToPrefs();
  }

  // ── Day reset check ──
  void _checkDayReset() {
    final today = _todayStr();
    if (_todayDate != today) {
      _todayDate = today;
      _articlesReadToday = 0;
      _quizzesToday = 0;
      _studyMinutesToday = 0;
    }
  }

  // ── Week reset check ──
  void _checkWeekReset() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = _dateStr(monday);
    if (_weekStartDate != weekStart) {
      _weekStartDate = weekStart;
      _articlesReadThisWeek = 0;
      _quizzesThisWeek = 0;
      _correctAnswersThisWeek = 0;
      _totalAnswersThisWeek = 0;
      _studyMinutesThisWeek = 0;
    }
  }

  // ── Persistence ──
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _lastChallengeDate = prefs.getString('lastChallengeDate') ?? '';
    _dailyChallengeCompleted = _lastChallengeDate == _todayStr();
    _dailyChallengeScore = prefs.getInt('dailyChallengeScore') ?? 0;
    _dailyChallengeTotalXp = prefs.getInt('dailyChallengeTotalXp') ?? 0;
    _currentStreak = prefs.getInt('currentStreak') ?? 0;
    _longestStreak = prefs.getInt('longestStreak') ?? 0;
    _lastActiveDate = prefs.getString('lastActiveDate') ?? '';
    _streakHistory = prefs.getStringList('streakHistory') ?? [];
    _weekStartDate = prefs.getString('weekStartDate') ?? '';
    _articlesReadThisWeek = prefs.getInt('articlesReadThisWeek') ?? 0;
    _quizzesThisWeek = prefs.getInt('quizzesThisWeek') ?? 0;
    _correctAnswersThisWeek = prefs.getInt('correctAnswersThisWeek') ?? 0;
    _totalAnswersThisWeek = prefs.getInt('totalAnswersThisWeek') ?? 0;
    _studyMinutesThisWeek = prefs.getInt('studyMinutesThisWeek') ?? 0;
    _todayDate = prefs.getString('todayDate') ?? '';
    _articlesReadToday = prefs.getInt('articlesReadToday') ?? 0;
    _quizzesToday = prefs.getInt('quizzesToday') ?? 0;
    _studyMinutesToday = prefs.getInt('studyMinutesToday') ?? 0;
    _readArticleIds = (prefs.getStringList('readArticleIds') ?? []).toSet();
    _savedFactIds = prefs.getStringList('savedFactIds') ?? [];
    _flashcardIndex = prefs.getInt('flashcardIndex') ?? 0;
    _masteredFlashcards = (prefs.getStringList('masteredFlashcards') ?? [])
        .map((e) => int.tryParse(e) ?? 0).toList();

    final incJson = prefs.getString('incorrectQuestions');
    if (incJson != null) {
      _incorrectQuestions = List<Map<String, dynamic>>.from(
        (jsonDecode(incJson) as List).map((e) => Map<String, dynamic>.from(e)),
      );
    }

    _checkDayReset();
    _checkWeekReset();
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('lastChallengeDate', _lastChallengeDate);
    prefs.setInt('dailyChallengeScore', _dailyChallengeScore);
    prefs.setInt('dailyChallengeTotalXp', _dailyChallengeTotalXp);
    prefs.setInt('currentStreak', _currentStreak);
    prefs.setInt('longestStreak', _longestStreak);
    prefs.setString('lastActiveDate', _lastActiveDate);
    prefs.setStringList('streakHistory', _streakHistory);
    prefs.setString('weekStartDate', _weekStartDate);
    prefs.setInt('articlesReadThisWeek', _articlesReadThisWeek);
    prefs.setInt('quizzesThisWeek', _quizzesThisWeek);
    prefs.setInt('correctAnswersThisWeek', _correctAnswersThisWeek);
    prefs.setInt('totalAnswersThisWeek', _totalAnswersThisWeek);
    prefs.setInt('studyMinutesThisWeek', _studyMinutesThisWeek);
    prefs.setString('todayDate', _todayDate);
    prefs.setInt('articlesReadToday', _articlesReadToday);
    prefs.setInt('quizzesToday', _quizzesToday);
    prefs.setInt('studyMinutesToday', _studyMinutesToday);
    prefs.setStringList('readArticleIds', _readArticleIds.toList());
    prefs.setStringList('savedFactIds', _savedFactIds);
    prefs.setInt('flashcardIndex', _flashcardIndex);
    prefs.setStringList('masteredFlashcards',
        _masteredFlashcards.map((e) => e.toString()).toList());
    prefs.setString('incorrectQuestions', jsonEncode(_incorrectQuestions));
  }

  String _todayStr() => _dateStr(DateTime.now());
  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
