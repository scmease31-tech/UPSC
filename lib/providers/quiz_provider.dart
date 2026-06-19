import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/quiz_question.dart';
import '../data/dummy_data.dart';
import '../services/gemini_service.dart';

/// Manages quiz state: questions, timer, scoring, and results.
class QuizProvider extends ChangeNotifier {
  List<QuizQuestion> _questions = [];
  int _currentIndex = 0;
  int _score = 0;
  int? _selectedOptionIndex;
  bool _answered = false;
  bool _quizComplete = false;
  bool _isLoading = false;
  List<int?> _userAnswers = [];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<QuizQuestion> get questions => _questions;
  int get currentIndex => _currentIndex;
  int get score => _score;
  int? get selectedOptionIndex => _selectedOptionIndex;
  bool get answered => _answered;
  bool get quizComplete => _quizComplete;
  QuizQuestion? get currentQuestion =>
      _questions.isNotEmpty ? _questions[_currentIndex] : null;
  int get totalQuestions => _questions.length;
  List<int?> get userAnswers => _userAnswers;
  bool get isLoading => _isLoading;

  /// Load quiz questions from Firestore → AI generation → dummy data fallback.
  /// Optionally filter by [category]. Pass null or empty for all categories.
  Future<void> loadQuiz({String? category}) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Step 1: Try Firestore
      final snapshot = await _firestore.collection('quizQuestions').get();

      if (snapshot.docs.isNotEmpty) {
        _questions = snapshot.docs
            .map((doc) => QuizQuestion.fromMap(doc.data(), doc.id))
            .toList();
      } else {
        // Step 2: Try AI generation if Gemini is configured
        _questions = await _tryAIQuizGeneration(category);

        // Step 3: Fallback to dummy data
        if (_questions.isEmpty) {
          _questions = List.from(DummyData.quizQuestions);
        }
      }
    } catch (e) {
      debugPrint('[QuizProvider] Firestore load error: $e');
      // Try AI generation before falling back to dummy data
      _questions = await _tryAIQuizGeneration(category);
      if (_questions.isEmpty) {
        _questions = List.from(DummyData.quizQuestions);
      }
    }

    // Filter by category if specified
    if (category != null && category.isNotEmpty) {
      final filtered = _questions.where((q) =>
        q.category.toLowerCase().contains(category.toLowerCase()) ||
        category.toLowerCase().contains(q.category.toLowerCase())
      ).toList();
      if (filtered.isNotEmpty) {
        _questions = filtered;
      }
    }

    _questions.shuffle();

    _currentIndex = 0;
    _score = 0;
    _selectedOptionIndex = null;
    _answered = false;
    _quizComplete = false;
    _isLoading = false;
    _userAnswers = List.filled(_questions.length, null);
    notifyListeners();
  }

  /// Try generating quiz questions via Gemini AI.
  Future<List<QuizQuestion>> _tryAIQuizGeneration(String? category) async {
    if (!GeminiService.isConfigured) return [];

    try {
      final topic = category ?? 'UPSC General Studies (Polity, Economy, Geography, History, Science)';
      debugPrint('[QuizProvider] Generating AI quiz for: $topic');

      final aiQuestions = await GeminiService.generateQuizQuestions(topic, count: 10);

      if (aiQuestions.isNotEmpty) {
        return aiQuestions.asMap().entries.map((entry) {
          final i = entry.key;
          final q = entry.value;
          return QuizQuestion(
            id: 'ai_${DateTime.now().millisecondsSinceEpoch}_$i',
            question: q['question'] ?? '',
            options: List<String>.from(q['options'] ?? []),
            correctAnswerIndex: q['correctAnswerIndex'] ?? 0,
            explanation: q['explanation'] ?? '',
            category: q['category'] ?? category ?? 'General',
            difficulty: q['difficulty'] ?? 'Medium',
            source: 'ai_generated',
          );
        }).where((q) => q.question.isNotEmpty && q.options.length == 4 && q.correctAnswerIndex >= 0 && q.correctAnswerIndex < 4).toList();
      }
    } catch (e) {
      debugPrint('[QuizProvider] AI quiz generation error: $e');
    }
    return [];
  }

  /// Select an answer for the current question. Pass -1 for timeout (no answer).
  void selectOption(int index) {
    if (_answered) return;
    if (_currentIndex < 0 || _currentIndex >= _questions.length) return;
    _selectedOptionIndex = index;
    _answered = true;
    if (_currentIndex < _userAnswers.length) {
      _userAnswers[_currentIndex] = index;
    }

    if (index >= 0 && index < _questions[_currentIndex].options.length &&
        index == _questions[_currentIndex].correctAnswerIndex) {
      _score++;
    }
    notifyListeners();
  }

  /// Move to the next question.
  void nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      _currentIndex++;
      _selectedOptionIndex = null;
      _answered = false;
      notifyListeners();
    } else {
      _quizComplete = true;
      notifyListeners();
    }
  }

  /// Reset quiz state.
  void resetQuiz() {
    _currentIndex = 0;
    _score = 0;
    _selectedOptionIndex = null;
    _answered = false;
    _quizComplete = false;
    _userAnswers = [];
    notifyListeners();
  }
}
