/// Data model for a quiz question.
class QuizQuestion {
  final String id;
  final String question;
  final List<String> options;
  final int correctAnswerIndex;
  final String explanation;
  final String category;
  final String difficulty; // 'Easy', 'Medium', 'Hard'

  // --- Enriched fields ---
  final String articleRef;     // ID of related article (empty if standalone)
  final String pyqYear;       // Previous year question year (e.g. "2019 Prelims") or empty
  final String syllabusArea;  // Specific syllabus topic
  final String source;        // "daily_news", "pyq_bank", "static_gk", "current_affairs"

  QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctAnswerIndex,
    required this.explanation,
    required this.category,
    this.difficulty = 'Medium',
    this.articleRef = '',
    this.pyqYear = '',
    this.syllabusArea = '',
    this.source = '',
  });

  factory QuizQuestion.fromMap(Map<String, dynamic> map, String docId) {
    return QuizQuestion(
      id: docId,
      question: map['question'] ?? '',
      options: List<String>.from(map['options'] ?? []),
      correctAnswerIndex: map['correctAnswerIndex'] ?? 0,
      explanation: map['explanation'] ?? '',
      category: map['category'] ?? '',
      difficulty: map['difficulty'] ?? 'Medium',
      articleRef: map['articleRef'] ?? '',
      pyqYear: map['pyqYear'] ?? '',
      syllabusArea: map['syllabusArea'] ?? '',
      source: map['source'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'question': question,
      'options': options,
      'correctAnswerIndex': correctAnswerIndex,
      'explanation': explanation,
      'category': category,
      'difficulty': difficulty,
      'articleRef': articleRef,
      'pyqYear': pyqYear,
      'syllabusArea': syllabusArea,
      'source': source,
    };
  }
}
