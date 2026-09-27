/// A normalized government-scheme record safe for direct UI rendering.
///
/// Firestore is schemaless and this collection has existed through several
/// generator versions. Production documents therefore contain a mix of
/// strings, numbers, nulls, scalar/list `keyFeatures`, and fields absent from
/// older records. Widgets must never cast that raw data directly: one legacy
/// value such as `year: 2019` used to throw during build and could leave the
/// route or detail sheet looking blank.
class GovernmentScheme {
  const GovernmentScheme({
    required this.id,
    required this.name,
    required this.fullForm,
    required this.description,
    required this.detailedDescription,
    required this.sector,
    required this.sourceSector,
    required this.year,
    required this.ministry,
    required this.keyFeatures,
    required this.upscRelevance,
    required this.iconName,
    required this.colorHex,
  });

  final String id;
  final String name;
  final String fullForm;
  final String description;
  final String detailedDescription;
  final String sector;
  final String sourceSector;
  final String year;
  final String ministry;
  final List<String> keyFeatures;
  final String upscRelevance;
  final String iconName;
  final String colorHex;

  static String text(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString().trim();
    // Maps/lists in a scalar field indicate malformed data. Showing a Dart map
    // dump is worse than omitting it; the rest of the record remains usable.
    return '';
  }

  static List<String> stringList(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is List) {
      return value
          .where((item) => item != null)
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <String>[];
      // Some hand-entered Firestore records used a newline/semicolon string
      // instead of an array. Recover the bullets rather than dropping them.
      return trimmed
          .split(RegExp(r'(?:\r?\n|\s*[;•]\s*)'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }
    return const <String>[];
  }

  /// Maps generator-era sector names onto one stable UI taxonomy.
  static String canonicalSector(String raw) {
    final value = raw.trim();
    final lower = value.toLowerCase();
    if (lower.isEmpty) return 'Other';
    if (lower.contains('agri') || lower.contains('farmer')) {
      return 'Agriculture';
    }
    if (lower.contains('education') ||
        lower.contains('school') ||
        lower.contains('skill')) {
      return 'Education';
    }
    if (lower.contains('health') || lower.contains('medical')) return 'Health';
    if (lower.contains('employ') || lower.contains('livelihood')) {
      return 'Employment';
    }
    if (lower.contains('financial') ||
        lower.contains('bank') ||
        lower.contains('credit') ||
        lower.contains('pension')) {
      return 'Financial Inclusion';
    }
    if (lower.contains('infrastructure') ||
        lower.contains('transport') ||
        lower.contains('housing') ||
        lower == 'energy') {
      return 'Infrastructure';
    }
    if (lower.contains('women') ||
        lower.contains('child') ||
        lower.contains('rural') ||
        lower.contains('social') ||
        lower.contains('welfare')) {
      return 'Social Welfare';
    }
    if (lower.contains('environment') ||
        lower.contains('climate') ||
        lower.contains('forest')) {
      return 'Environment';
    }
    if (lower.contains('governance')) return 'Governance';
    return value;
  }

  factory GovernmentScheme.fromMap(Map<String, dynamic> map) {
    final sourceSector = text(map, 'sector');
    final name = text(map, 'name');
    return GovernmentScheme(
      id: text(map, 'docId').isNotEmpty
          ? text(map, 'docId')
          : (text(map, 'id').isNotEmpty
              ? text(map, 'id')
              : normalizedName(name)),
      name: name,
      fullForm: text(map, 'fullForm'),
      description: text(map, 'description'),
      detailedDescription: text(map, 'detailedDescription'),
      sector: canonicalSector(sourceSector),
      sourceSector: sourceSector,
      year: text(map, 'year'),
      ministry: text(map, 'ministry'),
      keyFeatures: stringList(map, 'keyFeatures'),
      upscRelevance: text(map, 'upscRelevance'),
      iconName: text(map, 'iconName'),
      colorHex: text(map, 'colorHex'),
    );
  }

  String get body =>
      detailedDescription.isNotEmpty ? detailedDescription : description;

  String get searchableText => <String>[
        name,
        fullForm,
        description,
        detailedDescription,
        sector,
        sourceSector,
        year,
        ministry,
        upscRelevance,
        ...keyFeatures,
      ].join(' ').toLowerCase();

  Map<String, dynamic> toMap() => <String, dynamic>{
        'docId': id,
        'name': name,
        'fullForm': fullForm,
        'description': description,
        'detailedDescription': detailedDescription,
        'sector': sector,
        'sourceSector': sourceSector,
        'year': year,
        'ministry': ministry,
        'keyFeatures': keyFeatures,
        'upscRelevance': upscRelevance,
        'iconName': iconName,
        'colorHex': colorHex,
      };

  static String normalizedName(String value) => value
      .toLowerCase()
      .replaceFirst(RegExp(r'^(the|a|an)\s+'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _hasValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.any(_hasValue);
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  /// Combines live data with the curated essentials.
  ///
  /// A non-empty Firestore collection used to replace the fallback wholesale,
  /// so one sparse remote document could make all eight known-good schemes
  /// disappear. The curated records now form a floor. A live record with the
  /// same normalized name wins only for fields where it has a real value; its
  /// blank legacy fields cannot erase richer bundled content.
  static List<GovernmentScheme> combine(
    Iterable<Map<String, dynamic>> remote,
    Iterable<Map<String, dynamic>> curated,
  ) {
    final merged = <String, Map<String, dynamic>>{};

    for (final raw in curated) {
      final name = text(raw, 'name');
      if (name.isEmpty) continue;
      merged[normalizedName(name)] = Map<String, dynamic>.from(raw);
    }

    for (final raw in remote) {
      final name = text(raw, 'name');
      if (name.isEmpty) continue;
      final key = normalizedName(name);
      final target = merged.putIfAbsent(key, () => <String, dynamic>{});
      for (final entry in raw.entries) {
        if (_hasValue(entry.value)) target[entry.key] = entry.value;
      }
    }

    final records = merged.values
        .map(GovernmentScheme.fromMap)
        .where((scheme) => scheme.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return records;
  }
}
