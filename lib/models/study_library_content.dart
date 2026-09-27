import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:crypto/crypto.dart';

/// The two user-facing ways of browsing the study archives.
enum StudyLibraryMode { daily, fullLibrary }

extension StudyLibraryModeLabel on StudyLibraryMode {
  String get label => this == StudyLibraryMode.daily ? 'Daily' : 'Full Library';
}

/// Provenance of an individual card or fact bundle.
enum StudyContentOrigin { foundation, newsDerived, external }

extension StudyContentOriginLabel on StudyContentOrigin {
  String get label {
    switch (this) {
      case StudyContentOrigin.foundation:
        return 'Foundation';
      case StudyContentOrigin.newsDerived:
        return 'News-derived';
      case StudyContentOrigin.external:
        return 'External';
    }
  }
}

/// Freshness state for a content load.
enum StudyContentLoadState { fresh, cached, stale, fallback }

/// Collection that supplied a load result.
enum StudyContentCollectionSource { firestore, foundation }

/// A raw document boundary used by [DailyContentManager] and focused tests.
class StudyContentDocument {
  StudyContentDocument(String id, Map<String, dynamic> data)
      : id = id.trim(),
        data = Map<String, dynamic>.unmodifiable(data);

  final String id;
  final Map<String, dynamic> data;
}

typedef StudyContentDocumentLoader = Future<List<StudyContentDocument>>
    Function(String collection, int limit);

/// Explicit data, freshness, source, error, and truncation state.
class StudyContentResult<T> {
  StudyContentResult({
    required List<T> items,
    required this.state,
    required this.source,
    required this.loadedAt,
    this.error,
    this.truncated = false,
    this.queriedCount = 0,
    this.discardedCount = 0,
  }) : items = List<T>.unmodifiable(items);

  final List<T> items;
  final StudyContentLoadState state;
  final StudyContentCollectionSource source;
  final DateTime loadedAt;
  final Object? error;
  final bool truncated;
  final int queriedCount;
  final int discardedCount;

  bool get hasError => error != null;
  bool get isFallback => state == StudyContentLoadState.fallback;
  bool get isStale => state == StudyContentLoadState.stale;

  String? get errorMessage {
    final value = error?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  StudyContentResult<T> withState(
    StudyContentLoadState nextState, {
    Object? error,
  }) {
    return StudyContentResult<T>(
      items: items,
      state: nextState,
      source: source,
      loadedAt: loadedAt,
      error: error,
      truncated: truncated,
      queriedCount: queriedCount,
      discardedCount: discardedCount,
    );
  }
}

/// One robust, provenance-preserving flashcard record.
class StudyFlashcard {
  const StudyFlashcard({
    required this.id,
    required this.front,
    required this.normalizedFront,
    required this.back,
    required this.category,
    required this.origin,
    this.schemaVersion,
    this.kind = '',
    this.articleRef = '',
    this.sourceUrl = '',
    this.upscPaper = '',
    this.publishedDate,
    this.newspaper = '',
  });

  final String id;
  final int? schemaVersion;
  final String front;
  final String normalizedFront;
  final String back;
  final String category;
  final String kind;
  final String articleRef;
  final String sourceUrl;
  final String upscPaper;
  final DateTime? publishedDate;
  final String newspaper;
  final StudyContentOrigin origin;

  String get categoryKey => StudyCategory.key(category);
  String get publishedDateLabel => StudyText.formatDate(publishedDate);

  String get searchableText => StudyText.searchKey([
        front,
        back,
        category,
        kind,
        articleRef,
        sourceUrl,
        upscPaper,
        newspaper,
        publishedDateLabel,
        origin.label,
      ].join(' '));

  static StudyFlashcard? tryFromDocument(
    StudyContentDocument document, {
    StudyContentOrigin origin = StudyContentOrigin.newsDerived,
  }) {
    final data = document.data;
    final front = StudyText.scalar(data['front']);
    final back = StudyText.scalar(data['back']);
    if (front.isEmpty || back.isEmpty) return null;

    final normalizedFront = StudyText.scalar(data['normalizedFront']).isEmpty
        ? StudyText.searchKey(front)
        : StudyText.scalar(data['normalizedFront']);
    final id = StudyText.firstNonBlank([
      document.id,
      StudyText.scalar(data['docId']),
      StudyText.scalar(data['id']),
    ]);

    return StudyFlashcard(
      id: id.isNotEmpty
          ? id
          : StudyText.stableId('${origin.name}-flashcard', '$front|$back'),
      schemaVersion: StudyText.integer(data['schemaVersion']),
      front: front,
      normalizedFront: normalizedFront,
      back: back,
      category: StudyCategory.normalize(data['category']),
      kind: StudyText.scalar(data['kind']),
      articleRef: StudyText.scalar(data['articleRef']),
      sourceUrl: StudyText.scalar(data['sourceUrl']),
      upscPaper: StudyText.scalar(data['upscPaper']),
      publishedDate: StudyText.date(data['publishedDate']),
      newspaper: StudyText.scalar(data['newspaper']),
      origin: origin,
    );
  }

  Map<String, String> toLegacyMap() => {
        'front': front,
        'back': back,
        'category': category,
      };
}

/// One stable bullet inside an article-level fact bundle.
class StudyFact {
  const StudyFact({required this.id, required this.text});

  final String id;
  final String text;

  String get normalizedText => StudyText.searchKey(text);
}

/// One dailyFacts document. Article boundaries and provenance remain intact.
class DailyFactBundle {
  DailyFactBundle({
    required this.id,
    required this.category,
    required this.title,
    required List<StudyFact> facts,
    required this.origin,
    this.schemaVersion,
    this.articleRef = '',
    this.sourceUrl = '',
    this.upscPaper = '',
    this.publishedDate,
    this.newspaper = '',
    this.sourceName = '',
  }) : facts = List<StudyFact>.unmodifiable(facts);

  final String id;
  final int? schemaVersion;
  final String category;
  final String title;
  final List<StudyFact> facts;
  final String articleRef;
  final String sourceUrl;
  final String upscPaper;
  final DateTime? publishedDate;
  final String newspaper;
  final String sourceName;
  final StudyContentOrigin origin;

  String get categoryKey => StudyCategory.key(category);
  String get publishedDateLabel => StudyText.formatDate(publishedDate);

  String get searchableMetadata => StudyText.searchKey([
        title,
        category,
        articleRef,
        sourceUrl,
        upscPaper,
        newspaper,
        sourceName,
        publishedDateLabel,
        origin.label,
      ].join(' '));

  static DailyFactBundle? tryFromDocument(
    StudyContentDocument document, {
    StudyContentOrigin origin = StudyContentOrigin.newsDerived,
  }) {
    final data = document.data;
    final rawFacts = StudyText.stringList(data['facts']);
    final normalizedSeen = <String>{};
    final usableFacts = <String>[];
    for (final fact in rawFacts) {
      final normalized = StudyText.searchKey(fact);
      if (normalized.isNotEmpty && normalizedSeen.add(normalized)) {
        usableFacts.add(fact);
      }
    }
    if (usableFacts.isEmpty) return null;

    final title = StudyText.scalar(data['title']);
    final category = StudyCategory.normalize(data['category']);
    final suppliedId = StudyText.firstNonBlank([
      document.id,
      StudyText.scalar(data['docId']),
      StudyText.scalar(data['id']),
    ]);
    final bundleId = suppliedId.isNotEmpty
        ? suppliedId
        : StudyText.stableId(
            '${origin.name}-fact-bundle',
            '$category|$title|${usableFacts.join('|')}',
          );

    final facts = usableFacts
        .map(
          (fact) => StudyFact(
            id: '$bundleId:${StudyText.stableHash(StudyText.searchKey(fact))}',
            text: fact,
          ),
        )
        .toList(growable: false);

    final sourceName = StudyText.firstNonBlank([
      StudyText.scalar(data['source']),
      StudyText.scalar(data['newspaper']),
    ]);

    return DailyFactBundle(
      id: bundleId,
      schemaVersion: StudyText.integer(data['schemaVersion']),
      category: category,
      title: title.isEmpty ? category : title,
      facts: facts,
      articleRef: StudyText.scalar(data['articleRef']),
      sourceUrl: StudyText.scalar(data['sourceUrl']),
      upscPaper: StudyText.scalar(data['upscPaper']),
      publishedDate: StudyText.date(data['publishedDate']),
      newspaper: StudyText.scalar(data['newspaper']),
      sourceName: sourceName,
      origin: origin,
    );
  }

  factory DailyFactBundle.foundation({
    required String id,
    required String category,
    required String title,
    required Iterable<String> facts,
    String sourceName = 'Built-in UPSC essentials',
  }) {
    final normalizedCategory = StudyCategory.normalize(category);
    final bundleId = id.trim().isNotEmpty
        ? id.trim()
        : StudyText.stableId('foundation-fact-bundle', title);
    final seen = <String>{};
    final typedFacts = <StudyFact>[];
    for (final rawFact in facts) {
      final fact = StudyText.clean(rawFact);
      final normalized = StudyText.searchKey(fact);
      if (fact.isEmpty || !seen.add(normalized)) continue;
      typedFacts.add(StudyFact(
        id: '$bundleId:${StudyText.stableHash(normalized)}',
        text: fact,
      ));
    }
    return DailyFactBundle(
      id: bundleId,
      category: normalizedCategory,
      title: StudyText.clean(title).isEmpty ? normalizedCategory : title.trim(),
      facts: typedFacts,
      origin: StudyContentOrigin.foundation,
      sourceName: sourceName,
    );
  }

  DailyFactBundle copyWithFacts(Iterable<StudyFact> nextFacts) {
    return DailyFactBundle(
      id: id,
      schemaVersion: schemaVersion,
      category: category,
      title: title,
      facts: nextFacts.toList(growable: false),
      articleRef: articleRef,
      sourceUrl: sourceUrl,
      upscPaper: upscPaper,
      publishedDate: publishedDate,
      newspaper: newspaper,
      sourceName: sourceName,
      origin: origin,
    );
  }
}

/// Category normalization shared by both archives and their dynamic chips.
class StudyCategory {
  const StudyCategory._();

  static String normalize(Object? value) {
    final original = StudyText.scalar(value);
    if (original.isEmpty) return 'General';
    final key = StudyText.searchKey(original)
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    const aliases = <String, String>{
      'polity': 'Polity',
      'polity governance': 'Polity',
      'polity and governance': 'Polity',
      'indian polity': 'Polity',
      'economy': 'Economy',
      'economics': 'Economy',
      'environment': 'Environment',
      'environment ecology': 'Environment',
      'environment and ecology': 'Environment',
      'ecology': 'Environment',
      'science': 'Science & Technology',
      'science technology': 'Science & Technology',
      'science and technology': 'Science & Technology',
      'technology': 'Science & Technology',
      'international': 'International Relations',
      'international relations': 'International Relations',
      'ir': 'International Relations',
      'history': 'History',
      'history culture': 'History',
      'history and culture': 'History',
      'art culture': 'History',
      'art and culture': 'History',
      'geography': 'Geography',
      'governance': 'Governance',
      'ethics': 'Ethics',
      'ethics integrity': 'Ethics',
      'ethics and integrity': 'Ethics',
      'security': 'Internal Security',
      'internal security': 'Internal Security',
      'current': 'Current Affairs',
      'current affairs': 'Current Affairs',
      'news': 'Current Affairs',
      'social': 'Social Issues',
      'society': 'Social Issues',
      'social issues': 'Social Issues',
      'indian society': 'Social Issues',
      'general': 'General',
      'misc': 'General',
      'miscellaneous': 'General',
    };
    return aliases[key] ?? _titleCase(original);
  }

  static String key(Object? value) => StudyText.searchKey(normalize(value));

  static String _titleCase(String value) {
    return StudyText.clean(value)
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word.length == 1
            ? word.toUpperCase()
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}

/// Pure deterministic selection, filtering, counting, and de-duplication.
class StudyLibrarySelectors {
  const StudyLibrarySelectors._();

  static List<StudyFlashcard> sortFlashcards(
    Iterable<StudyFlashcard> cards,
  ) {
    final sorted = cards.toList(growable: false);
    sorted.sort((a, b) {
      final dateOrder =
          _compareDatesDescending(a.publishedDate, b.publishedDate);
      if (dateOrder != 0) return dateOrder;
      final categoryOrder = a.category.compareTo(b.category);
      if (categoryOrder != 0) return categoryOrder;
      return a.id.compareTo(b.id);
    });
    return List<StudyFlashcard>.unmodifiable(sorted);
  }

  static List<DailyFactBundle> sortFactBundles(
    Iterable<DailyFactBundle> bundles,
  ) {
    final sorted = bundles.toList(growable: false);
    sorted.sort((a, b) {
      final dateOrder =
          _compareDatesDescending(a.publishedDate, b.publishedDate);
      if (dateOrder != 0) return dateOrder;
      final categoryOrder = a.category.compareTo(b.category);
      if (categoryOrder != 0) return categoryOrder;
      final titleOrder = a.title.compareTo(b.title);
      if (titleOrder != 0) return titleOrder;
      return a.id.compareTo(b.id);
    });
    return List<DailyFactBundle>.unmodifiable(sorted);
  }

  /// Selects every card published today, or every card on the latest date.
  /// Undated Foundation cards remain a deterministic 15-card offline deck.
  static List<StudyFlashcard> dailyFlashcards(
    Iterable<StudyFlashcard> cards, {
    required DateTime date,
    int foundationLimit = 15,
  }) {
    final all = sortFlashcards(cards);
    final selected = _latestDated<StudyFlashcard>(
      all,
      date,
      (card) => card.publishedDate,
    );
    if (selected.isNotEmpty) return selected;
    final onlyFoundation = all.isNotEmpty &&
        all.every((card) => card.origin == StudyContentOrigin.foundation);
    if (!onlyFoundation) return const <StudyFlashcard>[];
    return List<StudyFlashcard>.unmodifiable(all.take(foundationLimit));
  }

  /// Selects every article bundle published today, or on the latest date.
  static List<DailyFactBundle> dailyFactBundles(
    Iterable<DailyFactBundle> bundles, {
    required DateTime date,
  }) {
    return _latestDated<DailyFactBundle>(
      sortFactBundles(bundles),
      date,
      (bundle) => bundle.publishedDate,
    );
  }

  static List<StudyFlashcard> filterFlashcards(
    Iterable<StudyFlashcard> cards, {
    String? category,
    String query = '',
  }) {
    final categoryKey = category == null || category.trim().isEmpty
        ? ''
        : StudyCategory.key(category);
    final queryKey = StudyText.searchKey(query);
    return List<StudyFlashcard>.unmodifiable(cards.where((card) {
      if (categoryKey.isNotEmpty && card.categoryKey != categoryKey) {
        return false;
      }
      return queryKey.isEmpty || card.searchableText.contains(queryKey);
    }));
  }

  static List<DailyFactBundle> filterFactBundles(
    Iterable<DailyFactBundle> bundles, {
    String? category,
    String query = '',
  }) {
    final categoryKey = category == null || category.trim().isEmpty
        ? ''
        : StudyCategory.key(category);
    final queryKey = StudyText.searchKey(query);
    final filtered = <DailyFactBundle>[];
    for (final bundle in bundles) {
      if (categoryKey.isNotEmpty && bundle.categoryKey != categoryKey) {
        continue;
      }
      if (queryKey.isEmpty || bundle.searchableMetadata.contains(queryKey)) {
        filtered.add(bundle);
        continue;
      }
      final matchingFacts = bundle.facts
          .where((fact) => fact.normalizedText.contains(queryKey))
          .toList(growable: false);
      if (matchingFacts.isNotEmpty) {
        filtered.add(bundle.copyWithFacts(matchingFacts));
      }
    }
    return List<DailyFactBundle>.unmodifiable(filtered);
  }

  static Map<String, int> flashcardCategoryCounts(
    Iterable<StudyFlashcard> cards,
  ) {
    final counts = <String, int>{};
    for (final card in cards) {
      counts.update(card.category, (count) => count + 1, ifAbsent: () => 1);
    }
    return _sortedCounts(counts);
  }

  static Map<String, int> factCategoryCounts(
    Iterable<DailyFactBundle> bundles,
  ) {
    final counts = <String, int>{};
    for (final bundle in bundles) {
      counts.update(
        bundle.category,
        (count) => count + bundle.facts.length,
        ifAbsent: () => bundle.facts.length,
      );
    }
    return _sortedCounts(counts);
  }

  /// Keeps one article tile per bundle while removing exact normalized facts.
  /// Earlier bundles win, so pass trusted/live bundles first.
  static List<DailyFactBundle> deduplicateFactBundles(
    Iterable<DailyFactBundle> bundles,
  ) {
    final seenFacts = <String>{};
    final seenBundles = <String>{};
    final deduplicated = <DailyFactBundle>[];
    for (final bundle in bundles) {
      if (!seenBundles.add(bundle.id)) continue;
      final uniqueFacts = <StudyFact>[];
      for (final fact in bundle.facts) {
        if (seenFacts.add(fact.normalizedText)) uniqueFacts.add(fact);
      }
      if (uniqueFacts.isNotEmpty) {
        deduplicated.add(bundle.copyWithFacts(uniqueFacts));
      }
    }
    return List<DailyFactBundle>.unmodifiable(deduplicated);
  }

  static int visibleMasteredCount(
    Iterable<StudyFlashcard> cards,
    Set<String> masteredIds,
  ) {
    return cards.where((card) => masteredIds.contains(card.id)).length;
  }

  static List<T> _latestDated<T>(
    List<T> items,
    DateTime requestedDate,
    DateTime? Function(T item) dateOf,
  ) {
    final dated = items.where((item) => dateOf(item) != null).toList();
    if (dated.isEmpty) return List<T>.unmodifiable(<T>[]);
    final target = _dateOnly(requestedDate);
    final exact = dated
        .where((item) => _sameDate(dateOf(item)!, target))
        .toList(growable: false);
    if (exact.isNotEmpty) return List<T>.unmodifiable(exact);

    var latest = _dateOnly(dateOf(dated.first)!);
    for (final item in dated.skip(1)) {
      final candidate = _dateOnly(dateOf(item)!);
      if (candidate.isAfter(latest)) latest = candidate;
    }
    return List<T>.unmodifiable(
      dated.where((item) => _sameDate(dateOf(item)!, latest)),
    );
  }

  static int _compareDatesDescending(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  static bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static Map<String, int> _sortedCounts(Map<String, int> counts) {
    final keys = counts.keys.toList()..sort();
    return Map<String, int>.unmodifiable({
      for (final key in keys) key: counts[key]!,
    });
  }
}

/// Tolerant conversions. Containers never leak as Dart debug strings.
class StudyText {
  const StudyText._();

  static String scalar(Object? value) {
    if (value is String) return clean(value);
    return '';
  }

  static String clean(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String searchKey(String value) => clean(value).toLowerCase();

  static int? integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static List<String> stringList(Object? value) {
    if (value is! Iterable || value is String) return const <String>[];
    final values = <String>[];
    for (final item in value) {
      final text = scalar(item);
      if (text.isNotEmpty) values.add(text);
    }
    return List<String>.unmodifiable(values);
  }

  static DateTime? date(Object? value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value.trim());
    if (value is num) {
      final milliseconds =
          value.abs() < 100000000000 ? value.toInt() * 1000 : value.toInt();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    if (value is Map) {
      final rawSeconds = value['seconds'] ?? value['_seconds'];
      if (rawSeconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(rawSeconds.toInt() * 1000);
      }
    }
    return null;
  }

  static String firstNonBlank(Iterable<String> values) {
    for (final value in values) {
      final cleaned = clean(value);
      if (cleaned.isNotEmpty) return cleaned;
    }
    return '';
  }

  static String stableHash(String value) =>
      sha1.convert(utf8.encode(value)).toString().substring(0, 16);

  static String stableId(String namespace, String value) =>
      '$namespace-${stableHash(searchKey(value))}';

  static String formatDate(DateTime? value) {
    if (value == null) return '';
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}
