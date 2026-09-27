/// The source layers that contributed to a normalized vocabulary record.
enum VocabularyOrigin {
  curated,
  library,
}

/// A typed vocabulary record that is safe to render directly.
///
/// Firestore is schemaless and older vocabulary records used scalar list
/// fields, alternate names, numeric values, and occasionally malformed
/// containers. All raw values are normalized here so widgets never cast data
/// received from the backend.
class VocabularyEntry {
  const VocabularyEntry({
    required this.id,
    required this.docId,
    required this.schemaVersion,
    required this.word,
    required this.normalizedWord,
    required this.partOfSpeech,
    required this.meaning,
    required this.example,
    required this.synonyms,
    required this.antonyms,
    required this.category,
    required this.sourceCategory,
    required this.articleRef,
    required this.sourceUrl,
    required this.upscPaper,
    required this.publishedDate,
    required this.newspaper,
    required this.upscUsage,
    required this.hasCuratedProvenance,
    required this.hasLibraryProvenance,
    required this.legacyIds,
  });

  final String id;
  final String docId;
  final int? schemaVersion;
  final String word;
  final String normalizedWord;
  final String partOfSpeech;
  final String meaning;
  final String example;
  final List<String> synonyms;
  final List<String> antonyms;
  final String category;
  final String sourceCategory;
  final String articleRef;
  final String sourceUrl;
  final String upscPaper;
  final DateTime? publishedDate;
  final String newspaper;
  final String upscUsage;
  final bool hasCuratedProvenance;
  final bool hasLibraryProvenance;

  /// IDs retained from every merged source, including old curated IDs.
  final List<String> legacyIds;

  /// A source-independent key keeps progress when a live document appears,
  /// disappears, or is recreated under another Firestore document ID.
  String get stableId {
    if (normalizedWord.isNotEmpty) return 'word:$normalizedWord';
    if (docId.isNotEmpty) return 'doc:$docId';
    if (id.isNotEmpty) return 'id:$id';
    return 'word:unknown';
  }

  /// Every known historical identity for safe, additive preference migration.
  /// Callers add [stableId] when any alias matches but do not prune unknown IDs:
  /// a temporarily unavailable source must not erase valid user progress.
  Set<String> get progressAliases {
    final aliases = <String>{stableId};
    void add(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      aliases
        ..add(trimmed)
        ..add(trimmed.toLowerCase());
    }

    add(id);
    add(docId);
    add(word);
    add(normalizedWord);
    for (final legacyId in legacyIds) {
      add(legacyId);
    }
    if (id.isNotEmpty) aliases.add('id:$id');
    if (docId.isNotEmpty) aliases.add('doc:$docId');
    if (normalizedWord.isNotEmpty) {
      aliases
        ..add('vocab:$normalizedWord')
        ..add('word:$normalizedWord');
    }
    return aliases;
  }

  bool isTrackedBy(Set<String> storedIds) =>
      progressAliases.any(storedIds.contains);

  bool get isNewsDerived =>
      publishedDate != null &&
      (newspaper.isNotEmpty || articleRef.isNotEmpty || sourceUri != null);

  /// Only HTTPS links with a real host are actionable.
  Uri? get sourceUri {
    final uri = Uri.tryParse(sourceUrl.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        !uri.hasAuthority ||
        uri.host.trim().isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  String get publishedDateLabel {
    final date = publishedDate;
    if (date == null) return '';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String get sourceName {
    if (newspaper.isNotEmpty) return newspaper;
    final uri = sourceUri;
    if (uri != null) return uri.host.replaceFirst(RegExp(r'^www\.'), '');
    if (articleRef.isNotEmpty) return articleRef;
    return '';
  }

  String get sourceAttribution {
    final values = <String>[
      if (sourceName.isNotEmpty) sourceName,
      if (publishedDateLabel.isNotEmpty) publishedDateLabel,
    ];
    return values.join(' • ');
  }

  String get provenanceLabel {
    if (isNewsDerived) return 'News-derived';
    if (hasLibraryProvenance && hasCuratedProvenance) {
      return 'Library + essential';
    }
    if (hasLibraryProvenance) return 'Library record';
    return 'Saved essential';
  }

  String get searchableText => <String>[
        word,
        normalizedWord,
        partOfSpeech,
        meaning,
        example,
        ...synonyms,
        ...antonyms,
        category,
        sourceCategory,
        articleRef,
        sourceUrl,
        newspaper,
        upscPaper,
        upscUsage,
        publishedDateLabel,
      ].join(' ').toLowerCase();

  bool matchesQuery(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty);
    return terms.every(searchableText.contains);
  }

  factory VocabularyEntry.fromMap(
    Map<String, dynamic> map, {
    VocabularyOrigin origin = VocabularyOrigin.library,
  }) {
    final word = _firstText(map, const <String>['word', 'term']);
    final suppliedNormalized =
        _firstText(map, const <String>['normalizedWord']);
    final normalized = normalizeWord(
      suppliedNormalized.isNotEmpty ? suppliedNormalized : word,
    );
    final id = text(map, 'id');
    final docId = text(map, 'docId');
    var sourceUrl = _firstText(
      map,
      const <String>['sourceUrl', 'articleUrl', 'sourceLink'],
    );
    final legacySource = text(map, 'source');
    if (sourceUrl.isEmpty &&
        legacySource.toLowerCase().startsWith('https://')) {
      sourceUrl = legacySource;
    }
    final newspaper = _firstText(
      map,
      const <String>['newspaper', 'sourceName'],
    );
    final rawCategory = _firstText(
      map,
      const <String>['category', 'normalizedCategory'],
    );

    return VocabularyEntry(
      id: id,
      docId: docId,
      schemaVersion: integer(map['schemaVersion']),
      word: word,
      normalizedWord: normalized,
      partOfSpeech: _firstText(map, const <String>['partOfSpeech', 'pos']),
      meaning: _firstText(map, const <String>['meaning', 'definition']),
      example: _firstText(
        map,
        const <String>['example', 'usageExample', 'exampleSentence'],
      ),
      synonyms: stringList(map, const <String>['synonyms', 'synonym']),
      antonyms: stringList(map, const <String>['antonyms', 'antonym']),
      category: normalizeCategory(rawCategory),
      sourceCategory: rawCategory,
      articleRef: _firstText(map, const <String>['articleRef', 'articleId']),
      sourceUrl: sourceUrl,
      upscPaper: _firstText(map, const <String>['upscPaper', 'paper']),
      publishedDate: date(
        map['publishedDate'] ?? map['publicationDate'] ?? map['date'],
      ),
      newspaper: newspaper.isNotEmpty
          ? newspaper
          : (legacySource.toLowerCase().startsWith('https://')
              ? ''
              : legacySource),
      upscUsage: _firstText(map, const <String>['upscUsage', 'upscRelevance']),
      hasCuratedProvenance: origin == VocabularyOrigin.curated,
      hasLibraryProvenance: origin == VocabularyOrigin.library,
      legacyIds: _uniqueStrings(<String>[
        id,
        docId,
        word,
        suppliedNormalized,
      ]),
    );
  }

  /// Reads a scalar without ever printing a List/Map Dart representation.
  static String text(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString().trim();
    return '';
  }

  static String _firstText(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = text(map, key);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Accepts canonical arrays plus legacy comma/semicolon/newline scalars.
  static List<String> stringList(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    Object? value;
    for (final key in keys) {
      if (map[key] != null) {
        value = map[key];
        break;
      }
    }
    final values = <String>[];
    if (value is List) {
      for (final item in value) {
        if (item is String || item is num || item is bool) {
          values.addAll(_splitListScalar(item.toString()));
        }
      }
    } else if (value is String || value is num || value is bool) {
      values.addAll(_splitListScalar(value.toString()));
    }
    return _uniqueStrings(values);
  }

  static List<String> _splitListScalar(String value) => value
      .split(RegExp(r'(?:\r?\n|\s*[,;|•]\s*)'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);

  static int? integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static DateTime? date(Object? value) {
    if (value is DateTime) return value;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return DateTime.tryParse(trimmed);
    }
    if (value is num && value.isFinite) {
      try {
        final numeric = value.toInt();
        final milliseconds = numeric.abs() < 100000000000
            ? numeric * Duration.millisecondsPerSecond
            : numeric;
        return DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        );
      } on RangeError {
        return null;
      }
    }
    return null;
  }

  static String normalizeWord(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// Normalizes case, spacing, and generator-era aliases while still allowing
  /// previously unseen categories to become dynamic filter chips.
  static String normalizeCategory(String value) {
    final spaced = value
        .trim()
        .replaceAll(RegExp(r'[_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    final lower = spaced.toLowerCase();
    if (lower.isEmpty || lower == 'uncategorized') return 'Uncategorized';
    if (lower == 'misc' || lower == 'miscellaneous') return 'General';
    const aliases = <String, String>{
      'polity': 'Governance',
      'constitution': 'Governance',
      'governance': 'Governance',
      'economic': 'Economy',
      'economics': 'Economy',
      'economy': 'Economy',
      'international relations': 'Diplomacy',
      'foreign policy': 'Diplomacy',
      'diplomacy': 'Diplomacy',
      'environment and ecology': 'Environment',
      'environment & ecology': 'Environment',
      'environment': 'Environment',
      'society': 'Social',
      'social issues': 'Social',
      'social': 'Social',
      'law': 'Legal',
      'judiciary': 'Legal',
      'legal': 'Legal',
      'ethics integrity and aptitude': 'Ethics',
      'ethics': 'Ethics',
      'science and technology': 'Science & Technology',
      'science & technology': 'Science & Technology',
      'science technology': 'Science & Technology',
      'sci tech': 'Science & Technology',
      'general': 'General',
    };
    final alias = aliases[lower];
    if (alias != null) return alias;
    return spaced
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
        .join(' ');
  }

  /// Combines the curated pack with every usable library record by normalized
  /// word. A live nonblank scalar wins, while blank values cannot erase curated
  /// detail and list values are unioned with live values first.
  static List<VocabularyEntry> combine(
    Iterable<Map<String, dynamic>> library,
    Iterable<Map<String, dynamic>> curated,
  ) {
    final merged = <String, VocabularyEntry>{};

    void add(VocabularyEntry entry) {
      if (entry.word.isEmpty || entry.normalizedWord.isEmpty) return;
      final existing = merged[entry.normalizedWord];
      merged[entry.normalizedWord] =
          existing == null ? entry : existing.overlayWith(entry);
    }

    for (final raw in curated) {
      add(VocabularyEntry.fromMap(raw, origin: VocabularyOrigin.curated));
    }
    for (final raw in library) {
      add(VocabularyEntry.fromMap(raw));
    }

    final entries = merged.values.toList(growable: false)
      ..sort((a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
    return entries;
  }

  VocabularyEntry overlayWith(VocabularyEntry overlay) {
    String prefer(String incoming, String current) =>
        incoming.isNotEmpty ? incoming : current;

    return VocabularyEntry(
      id: prefer(overlay.id, id),
      docId: prefer(overlay.docId, docId),
      schemaVersion: overlay.schemaVersion ?? schemaVersion,
      word: prefer(overlay.word, word),
      normalizedWord: prefer(overlay.normalizedWord, normalizedWord),
      partOfSpeech: prefer(overlay.partOfSpeech, partOfSpeech),
      meaning: prefer(overlay.meaning, meaning),
      example: prefer(overlay.example, example),
      synonyms: _union(overlay.synonyms, synonyms),
      antonyms: _union(overlay.antonyms, antonyms),
      category: overlay.sourceCategory.isNotEmpty ? overlay.category : category,
      sourceCategory: prefer(overlay.sourceCategory, sourceCategory),
      articleRef: prefer(overlay.articleRef, articleRef),
      sourceUrl: prefer(overlay.sourceUrl, sourceUrl),
      upscPaper: prefer(overlay.upscPaper, upscPaper),
      publishedDate: overlay.publishedDate ?? publishedDate,
      newspaper: prefer(overlay.newspaper, newspaper),
      upscUsage: prefer(overlay.upscUsage, upscUsage),
      hasCuratedProvenance:
          hasCuratedProvenance || overlay.hasCuratedProvenance,
      hasLibraryProvenance:
          hasLibraryProvenance || overlay.hasLibraryProvenance,
      legacyIds: _uniqueStrings(<String>[
        ...legacyIds,
        ...overlay.legacyIds,
        id,
        docId,
        overlay.id,
        overlay.docId,
      ]),
    );
  }

  static List<VocabularyEntry> latestNews(
    Iterable<VocabularyEntry> entries,
  ) {
    final dated =
        entries.where((entry) => entry.isNewsDerived).toList(growable: false);
    if (dated.isEmpty) return const <VocabularyEntry>[];
    var latest = dated.first.publishedDate!;
    for (final entry in dated.skip(1)) {
      final candidate = entry.publishedDate!;
      if (candidate.isAfter(latest)) latest = candidate;
    }
    final result = dated
        .where((entry) => _sameDate(entry.publishedDate!, latest))
        .toList()
      ..sort((a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
    return result;
  }

  static DateTime? latestNewsDate(Iterable<VocabularyEntry> entries) {
    final latest = latestNews(entries);
    return latest.isEmpty ? null : latest.first.publishedDate;
  }

  static Map<String, int> categoryCounts(
    Iterable<VocabularyEntry> entries,
  ) {
    final counts = <String, int>{};
    for (final entry in entries) {
      counts.update(entry.category, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static List<String> _union(List<String> preferred, List<String> fallback) =>
      _uniqueStrings(<String>[...preferred, ...fallback]);

  static List<String> _uniqueStrings(Iterable<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
      result.add(trimmed);
    }
    return List<String>.unmodifiable(result);
  }
}
