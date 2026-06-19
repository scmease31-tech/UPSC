/// Data model for a weekly magazine issue.
class WeeklyMagazine {
  final String id;
  final String title;
  final String description;
  final String coverImageUrl;
  final String pdfUrl;
  final DateTime weekStartDate;
  final DateTime weekEndDate;

  WeeklyMagazine({
    required this.id,
    required this.title,
    required this.description,
    required this.coverImageUrl,
    required this.pdfUrl,
    required this.weekStartDate,
    required this.weekEndDate,
  });

  factory WeeklyMagazine.fromMap(Map<String, dynamic> map, String docId) {
    return WeeklyMagazine(
      id: docId,
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      coverImageUrl: map['coverImageUrl'] ?? '',
      pdfUrl: map['pdfUrl'] ?? '',
      weekStartDate: DateTime.tryParse(map['weekStartDate'] ?? '') ?? DateTime.now(),
      weekEndDate: DateTime.tryParse(map['weekEndDate'] ?? '') ?? DateTime.now(),
    );
  }
}
