/// Data model for a study subject.
class Subject {
  final String id;
  final String name;
  final String description;
  final String iconName;
  final List<StudyNote> notes;

  Subject({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    required this.notes,
  });

  factory Subject.fromMap(Map<String, dynamic> map, String docId) {
    return Subject(
      id: docId,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      iconName: map['iconName'] ?? 'book',
      notes: (map['notes'] as List<dynamic>?)
              ?.map((n) => StudyNote.fromMap(n as Map<String, dynamic>, n['id'] ?? ''))
              .toList() ??
          [],
    );
  }
}

/// A single study note within a subject.
class StudyNote {
  final String id;
  final String title;
  final String content;
  final String? pdfUrl;
  final DateTime lastUpdated;

  StudyNote({
    required this.id,
    required this.title,
    required this.content,
    this.pdfUrl,
    required this.lastUpdated,
  });

  factory StudyNote.fromMap(Map<String, dynamic> map, String docId) {
    return StudyNote(
      id: docId,
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      pdfUrl: map['pdfUrl'],
      lastUpdated: DateTime.tryParse(map['lastUpdated'] ?? '') ?? DateTime.now(),
    );
  }
}
