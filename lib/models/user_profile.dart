/// Data model for user profile information.
class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String photoUrl;
  final List<String> bookmarkedArticleIds;
  final List<QuizScore> quizScores;
  final Map<String, double> studyProgress; // subjectId -> progress (0.0 - 1.0)
  final List<String> preferredCategories;
  final int dailyGoalMinutes;
  final int streakDays;
  final DateTime? lastActiveDate;

  UserProfile({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl = '',
    this.bookmarkedArticleIds = const [],
    this.quizScores = const [],
    this.studyProgress = const {},
    this.preferredCategories = const [],
    this.dailyGoalMinutes = 30,
    this.streakDays = 0,
    this.lastActiveDate,
  });

  UserProfile copyWith({
    String? name,
    String? photoUrl,
    List<String>? bookmarkedArticleIds,
    List<QuizScore>? quizScores,
    Map<String, double>? studyProgress,
    List<String>? preferredCategories,
    int? dailyGoalMinutes,
    int? streakDays,
    DateTime? lastActiveDate,
  }) {
    return UserProfile(
      uid: uid,
      name: name ?? this.name,
      email: email,
      photoUrl: photoUrl ?? this.photoUrl,
      bookmarkedArticleIds: bookmarkedArticleIds ?? this.bookmarkedArticleIds,
      quizScores: quizScores ?? this.quizScores,
      studyProgress: studyProgress ?? this.studyProgress,
      preferredCategories: preferredCategories ?? this.preferredCategories,
      dailyGoalMinutes: dailyGoalMinutes ?? this.dailyGoalMinutes,
      streakDays: streakDays ?? this.streakDays,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
      bookmarkedArticleIds: List<String>.from(map['bookmarkedArticleIds'] ?? []),
      quizScores: (map['quizScores'] as List<dynamic>?)
              ?.map((e) => QuizScore.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      studyProgress: Map<String, double>.from(map['studyProgress'] ?? {}),
      preferredCategories: List<String>.from(map['preferredCategories'] ?? []),
      dailyGoalMinutes: map['dailyGoalMinutes'] ?? 30,
      streakDays: map['streakDays'] ?? 0,
      lastActiveDate: map['lastActiveDate'] != null
          ? DateTime.tryParse(map['lastActiveDate'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'bookmarkedArticleIds': bookmarkedArticleIds,
      'quizScores': quizScores.map((s) => s.toMap()).toList(),
      'studyProgress': studyProgress,
      'preferredCategories': preferredCategories,
      'dailyGoalMinutes': dailyGoalMinutes,
      'streakDays': streakDays,
      'lastActiveDate': lastActiveDate?.toIso8601String(),
    };
  }
}

/// A single quiz score record.
class QuizScore {
  final DateTime date;
  final int score;
  final int totalQuestions;
  final String category;

  QuizScore({
    required this.date,
    required this.score,
    required this.totalQuestions,
    required this.category,
  });

  factory QuizScore.fromMap(Map<String, dynamic> map) {
    return QuizScore(
      date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
      score: (map['score'] as num?)?.toInt() ?? 0,
      totalQuestions: ((map['totalQuestions'] as num?)?.toInt() ?? 1).clamp(1, 999),
      category: (map['category'] as String?) ?? 'General',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'score': score,
      'totalQuestions': totalQuestions,
      'category': category,
    };
  }
}
