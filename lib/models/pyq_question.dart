/// ──────────────────────────────────────────────────────────────────────────────
/// PyqQuestion — one previous-year UPSC question.
///
/// The same shape covers Prelims MCQs (four options + an answer index) and
/// Mains/Essay questions (no options; a model approach instead), so the PYQ tab
/// can filter, count and sort both from a single list.
/// ──────────────────────────────────────────────────────────────────────────────
enum PyqType { prelims, mains }

class PyqQuestion {
  final String id;
  final int year;
  final PyqType type;

  /// Canonical syllabus subject — 'Polity', 'Economy', 'Essay', …
  final String subject;

  /// 'Prelims GS-I', 'GS-I' … 'GS-IV', 'Essay'.
  final String paper;

  /// Mains marks (10 / 15 / 20 / 125). Zero for Prelims.
  final int marks;

  final String question;

  /// Exactly four entries for an answerable Prelims MCQ; empty otherwise.
  final List<String> options;

  /// Index into [options]; -1 when the question is not an answerable MCQ.
  final int answer;

  /// Why the answer is right (Prelims).
  final String explanation;

  /// Model structure for the answer (Mains/Essay).
  final String approach;

  /// Where the question came from — 'UPSC', 'Drishti IAS', …
  final String source;

  /// Optional link back to the article the question was harvested from.
  final String sourceUrl;

  const PyqQuestion({
    required this.id,
    required this.year,
    required this.type,
    required this.subject,
    required this.paper,
    required this.question,
    this.marks = 0,
    this.options = const [],
    this.answer = -1,
    this.explanation = '',
    this.approach = '',
    this.source = 'UPSC',
    this.sourceUrl = '',
  });

  /// True when the question can actually be attempted (four options + answer).
  bool get isAnswerable => type == PyqType.prelims && options.length == 4 && answer >= 0 && answer < 4;

  /// Options are present but no key is — the case for questions taken straight
  /// from an official UPSC paper, since UPSC publishes papers without keys.
  bool get hasUnkeyedOptions =>
      type == PyqType.prelims && options.length == 4 && (answer < 0 || answer > 3);

  /// Free-text blob used by the search box.
  String get searchText =>
      '$question ${options.join(' ')} $explanation $approach $subject $paper $year'.toLowerCase();

  factory PyqQuestion.fromMap(Map<String, dynamic> map, String docId) {
    final rawOptions = (map['options'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final rawType = (map['type'] ?? 'prelims').toString().toLowerCase();
    return PyqQuestion(
      id: docId,
      year: (map['year'] is int) ? map['year'] as int : int.tryParse('${map['year']}') ?? 0,
      type: rawType == 'mains' ? PyqType.mains : PyqType.prelims,
      subject: (map['subject'] ?? 'General').toString(),
      paper: (map['paper'] ?? '').toString(),
      marks: (map['marks'] is int) ? map['marks'] as int : int.tryParse('${map['marks']}') ?? 0,
      question: (map['question'] ?? '').toString(),
      options: rawOptions,
      answer: (map['answer'] is int) ? map['answer'] as int : int.tryParse('${map['answer']}') ?? -1,
      explanation: (map['explanation'] ?? '').toString(),
      approach: (map['approach'] ?? '').toString(),
      source: (map['source'] ?? 'UPSC').toString(),
      sourceUrl: (map['sourceUrl'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'year': year,
        'type': type == PyqType.mains ? 'mains' : 'prelims',
        'subject': subject,
        'paper': paper,
        'marks': marks,
        'question': question,
        'options': options,
        'answer': answer,
        'explanation': explanation,
        'approach': approach,
        'source': source,
        'sourceUrl': sourceUrl,
      };
}
