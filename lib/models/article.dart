/// Data model for a current affairs article.
class Article {
  final String id;
  final String title;
  final String summary;
  final String content;
  final List<String> keyPoints;
  final String examRelevance; // 'Prelims', 'Mains', 'Both'
  final List<String> categoryTags;
  final String imageUrl;
  final DateTime publishedDate;
  final bool isTopNews;

  // --- New pipeline fields ---
  final List<String> shortNotes;       // 5 bullet points for quick revision
  final String newspaper;              // Source newspaper name
  final String upscPaper;              // GS-I, GS-II, GS-III, GS-IV, Essay
  final List<String> relatedTopics;    // Related past UPSC topics
  final String analysisNote;           // Why this matters for UPSC
  final String mnemonic;               // Memory aid
  final List<String> flowchartSteps;   // Process/cause-effect flow steps

  // --- Enriched content fields ---
  final String syllabusMapping;        // Precise syllabus topic (e.g. "GS-II > Parliament > Anti-Defection")
  final List<String> previousYearQs;   // Related PYQ references (e.g. "UPSC 2019 Prelims Q.23")
  final String editorialOpinion;       // Editorial viewpoint summary
  final String constitutionalBasis;    // Constitutional/legal framework reference
  final String governmentScheme;       // Related govt scheme details if applicable
  final String sourceUrl;              // Original source URL or reference link
  final Map<String, String> keyTerms;  // Important terms with definitions
  final String answerFramework;        // Mains answer writing framework (Intro-Body-Conclusion)

  Article({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.keyPoints,
    required this.examRelevance,
    required this.categoryTags,
    required this.imageUrl,
    required this.publishedDate,
    this.isTopNews = false,
    this.shortNotes = const [],
    this.newspaper = '',
    this.upscPaper = '',
    this.relatedTopics = const [],
    this.analysisNote = '',
    this.mnemonic = '',
    this.flowchartSteps = const [],
    this.syllabusMapping = '',
    this.previousYearQs = const [],
    this.editorialOpinion = '',
    this.constitutionalBasis = '',
    this.governmentScheme = '',
    this.sourceUrl = '',
    this.keyTerms = const {},
    this.answerFramework = '',
  });

  /// Create an Article from Firestore document map.
  factory Article.fromMap(Map<String, dynamic> map, String docId) {
    return Article(
      id: docId,
      title: map['title'] ?? '',
      summary: map['summary'] ?? '',
      content: map['content'] ?? '',
      keyPoints: List<String>.from(map['keyPoints'] ?? []),
      examRelevance: map['examRelevance'] ?? 'Both',
      categoryTags: List<String>.from(map['categoryTags'] ?? []),
      imageUrl: map['imageUrl'] ?? '',
      publishedDate: DateTime.tryParse(map['publishedDate'] ?? '') ?? DateTime.now(),
      isTopNews: map['isTopNews'] ?? false,
      shortNotes: List<String>.from(map['shortNotes'] ?? []),
      newspaper: map['newspaper'] ?? '',
      upscPaper: map['upscPaper'] ?? '',
      relatedTopics: List<String>.from(map['relatedTopics'] ?? []),
      analysisNote: map['analysisNote'] ?? '',
      mnemonic: map['mnemonic'] ?? '',
      flowchartSteps: List<String>.from(map['flowchartSteps'] ?? []),
      syllabusMapping: map['syllabusMapping'] ?? '',
      previousYearQs: List<String>.from(map['previousYearQs'] ?? []),
      editorialOpinion: map['editorialOpinion'] ?? '',
      constitutionalBasis: map['constitutionalBasis'] ?? '',
      governmentScheme: map['governmentScheme'] ?? '',
      sourceUrl: map['sourceUrl'] ?? '',
      keyTerms: Map<String, String>.from(map['keyTerms'] ?? {}),
      answerFramework: map['answerFramework'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'summary': summary,
      'content': content,
      'keyPoints': keyPoints,
      'examRelevance': examRelevance,
      'categoryTags': categoryTags,
      'imageUrl': imageUrl,
      'publishedDate': publishedDate.toIso8601String(),
      'isTopNews': isTopNews,
      'shortNotes': shortNotes,
      'newspaper': newspaper,
      'upscPaper': upscPaper,
      'relatedTopics': relatedTopics,
      'analysisNote': analysisNote,
      'mnemonic': mnemonic,
      'flowchartSteps': flowchartSteps,
      'syllabusMapping': syllabusMapping,
      'previousYearQs': previousYearQs,
      'editorialOpinion': editorialOpinion,
      'constitutionalBasis': constitutionalBasis,
      'governmentScheme': governmentScheme,
      'sourceUrl': sourceUrl,
      'keyTerms': keyTerms,
      'answerFramework': answerFramework,
    };
  }
}
