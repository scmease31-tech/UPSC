/// One article or official publication used to build a government-scheme note.
///
/// Source records are intentionally typed here because older Firestore rows can
/// contain partial maps or malformed values. The UI can therefore render source
/// metadata without casting schemaless data.
class GovernmentSchemeSource {
  const GovernmentSchemeSource({
    required this.articleId,
    required this.title,
    required this.url,
    required this.publisher,
    required this.publishedDate,
    required this.official,
  });

  final String articleId;
  final String title;
  final String url;
  final String publisher;
  final String publishedDate;

  /// True only when [url] is an HTTPS URL on gov.in or nic.in. A legacy
  /// `official: true` flag is never trusted without validating the URL.
  final bool official;

  factory GovernmentSchemeSource.fromMap(Map<Object?, Object?> map) {
    final values = <String, dynamic>{
      for (final entry in map.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    final url = GovernmentScheme.text(values, 'url');
    return GovernmentSchemeSource(
      articleId: GovernmentScheme.text(values, 'articleId'),
      title: GovernmentScheme.text(values, 'title'),
      url: url,
      publisher: GovernmentScheme.text(values, 'publisher'),
      publishedDate: GovernmentScheme.text(values, 'publishedDate'),
      official: GovernmentScheme.isVerifiedOfficialUrl(url),
    );
  }

  bool get hasContent =>
      articleId.isNotEmpty ||
      title.isNotEmpty ||
      url.isNotEmpty ||
      publisher.isNotEmpty ||
      publishedDate.isNotEmpty;

  /// A source article may be any ordinary HTTP(S) page. Official actions use
  /// the stricter government-domain validator instead.
  Uri? get webUri {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return uri;
  }

  String get searchableText => <String>[
        articleId,
        title,
        url,
        publisher,
        publishedDate,
        official.toString(),
      ].join(' ').toLowerCase();

  Map<String, dynamic> toMap() => <String, dynamic>{
        'articleId': articleId,
        'title': title,
        'url': url,
        'publisher': publisher,
        'publishedDate': publishedDate,
        'official': official,
      };
}

/// A normalized government-scheme record safe for direct UI rendering.
///
/// Firestore is schemaless and this collection has existed through several
/// generator versions. Production documents therefore contain strings,
/// numbers, nulls, scalar/list fields, partial source objects, and fields absent
/// from older records. Widgets must never cast that raw data directly.
class GovernmentScheme {
  const GovernmentScheme({
    required this.id,
    required this.schemaVersion,
    required this.normalizedName,
    required this.name,
    required this.fullForm,
    required this.description,
    required this.detailedDescription,
    required this.sector,
    required this.sourceSector,
    required this.year,
    required this.coverageYear,
    required this.launchYear,
    required this.ministry,
    required this.keyFeatures,
    required this.objective,
    required this.beneficiaries,
    required this.eligibility,
    required this.benefits,
    required this.funding,
    required this.implementation,
    required this.officialUrl,
    required this.sources,
    required this.upscRelevance,
    required this.iconName,
    required this.colorHex,
  });

  final String id;
  final int schemaVersion;
  final String normalizedName;
  final String name;
  final String fullForm;
  final String description;
  final String detailedDescription;
  final String sector;
  final String sourceSector;

  /// Legacy producer field. It represented the article coverage year, never a
  /// guaranteed scheme launch year. New UI should use [coverageYear].
  final String year;
  final String coverageYear;

  /// Populated only from the explicit canonical field. It never falls back to
  /// [coverageYear] or legacy [year].
  final String launchYear;
  final String ministry;
  final List<String> keyFeatures;
  final String objective;
  final List<String> beneficiaries;
  final List<String> eligibility;
  final List<String> benefits;
  final String funding;
  final String implementation;
  final String officialUrl;
  final List<GovernmentSchemeSource> sources;
  final String upscRelevance;
  final String iconName;
  final String colorHex;

  static const _arrayFields = <String>{
    'keyFeatures',
    'beneficiaries',
    'eligibility',
    'benefits',
  };

  static const _scalarFields = <String>{
    'name',
    'fullForm',
    'description',
    'detailedDescription',
    'sector',
    'sourceSector',
    'ministry',
    'objective',
    'funding',
    'implementation',
    'launchYear',
    'upscRelevance',
    'iconName',
    'colorHex',
  };

  static String text(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString().trim();
    // Maps/lists in a scalar field indicate malformed data. Showing a Dart map
    // dump is worse than omitting it; the rest of the record remains usable.
    return '';
  }

  static int integer(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static List<String> stringList(Map<String, dynamic> map, String key) {
    final value = map[key];
    final items = <String>[];
    if (value is List) {
      for (final item in value) {
        if (item is String || item is num || item is bool) {
          final normalized = item.toString().trim();
          if (normalized.isNotEmpty) items.add(normalized);
        }
      }
    } else if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <String>[];
      // Some hand-entered records used newline/semicolon/bullet text instead of
      // an array. Recover each point without splitting ordinary prose on commas.
      items.addAll(
        trimmed
            .split(RegExp(r'(?:\r?\n|\s*[;•]\s*)'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty),
      );
    }
    return _mergeStringLists(const <String>[], items);
  }

  static List<GovernmentSchemeSource> sourceList(
    Map<String, dynamic> map,
    String key,
  ) {
    final value = map[key];
    final candidates = <Map<Object?, Object?>>[];
    if (value is Map) {
      candidates.add(value);
    } else if (value is List) {
      candidates.addAll(value.whereType<Map>());
    }
    final normalized = candidates
        .map(GovernmentSchemeSource.fromMap)
        .where((source) => source.hasContent);
    return _mergeSources(const <GovernmentSchemeSource>[], normalized);
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
    final name = text(map, 'name');
    final explicitNormalizedName = text(map, 'normalizedName');
    final normalized = explicitNormalizedName.isNotEmpty
        ? explicitNormalizedName
        : normalizeName(name);
    final explicitCoverageYear = text(map, 'coverageYear');
    final legacyYear = text(map, 'year');
    final coverageYear =
        explicitCoverageYear.isNotEmpty ? explicitCoverageYear : legacyYear;
    final sourceSector = text(map, 'sourceSector').isNotEmpty
        ? text(map, 'sourceSector')
        : text(map, 'sector');
    final sector = text(map, 'sector');
    final rawOfficialUrl = text(map, 'officialUrl');
    final id = text(map, 'docId').isNotEmpty
        ? text(map, 'docId')
        : (text(map, 'id').isNotEmpty ? text(map, 'id') : normalized);

    return GovernmentScheme(
      id: id,
      schemaVersion: integer(map, 'schemaVersion'),
      normalizedName: normalized,
      name: name,
      fullForm: text(map, 'fullForm'),
      description: text(map, 'description'),
      detailedDescription: text(map, 'detailedDescription'),
      sector: canonicalSector(sector.isNotEmpty ? sector : sourceSector),
      sourceSector: sourceSector,
      year: legacyYear.isNotEmpty ? legacyYear : coverageYear,
      coverageYear: coverageYear,
      launchYear: text(map, 'launchYear'),
      ministry: text(map, 'ministry'),
      keyFeatures: stringList(map, 'keyFeatures'),
      objective: text(map, 'objective'),
      beneficiaries: stringList(map, 'beneficiaries'),
      eligibility: stringList(map, 'eligibility'),
      benefits: stringList(map, 'benefits'),
      funding: text(map, 'funding'),
      implementation: text(map, 'implementation'),
      officialUrl: isVerifiedOfficialUrl(rawOfficialUrl) ? rawOfficialUrl : '',
      sources: sourceList(map, 'sources'),
      upscRelevance: text(map, 'upscRelevance'),
      iconName: text(map, 'iconName'),
      colorHex: text(map, 'colorHex'),
    );
  }

  String get body =>
      detailedDescription.isNotEmpty ? detailedDescription : description;

  bool get hasVerifiedOfficialSource =>
      officialUrl.isNotEmpty || sources.any((source) => source.official);

  int get structuredDetailCount => <bool>[
        objective.isNotEmpty,
        beneficiaries.isNotEmpty,
        eligibility.isNotEmpty,
        benefits.isNotEmpty,
        funding.isNotEmpty,
        implementation.isNotEmpty,
        keyFeatures.isNotEmpty,
        upscRelevance.isNotEmpty,
      ].where((present) => present).length;

  String get searchableText => <String>[
        id,
        schemaVersion.toString(),
        normalizedName,
        name,
        fullForm,
        description,
        detailedDescription,
        sector,
        sourceSector,
        year,
        coverageYear,
        launchYear,
        ministry,
        ...keyFeatures,
        objective,
        ...beneficiaries,
        ...eligibility,
        ...benefits,
        funding,
        implementation,
        officialUrl,
        ...sources.map((source) => source.searchableText),
        upscRelevance,
        iconName,
        colorHex,
      ].join(' ').toLowerCase();

  Map<String, dynamic> toMap() => <String, dynamic>{
        'docId': id,
        'id': id,
        'schemaVersion': schemaVersion,
        'normalizedName': normalizedName,
        'name': name,
        'fullForm': fullForm,
        'description': description,
        'detailedDescription': detailedDescription,
        'sector': sector,
        'sourceSector': sourceSector,
        'year': year,
        'coverageYear': coverageYear,
        'launchYear': launchYear,
        'ministry': ministry,
        'keyFeatures': List<String>.unmodifiable(keyFeatures),
        'objective': objective,
        'beneficiaries': List<String>.unmodifiable(beneficiaries),
        'eligibility': List<String>.unmodifiable(eligibility),
        'benefits': List<String>.unmodifiable(benefits),
        'funding': funding,
        'implementation': implementation,
        'officialUrl': officialUrl,
        'sources':
            sources.map((source) => source.toMap()).toList(growable: false),
        'upscRelevance': upscRelevance,
        'iconName': iconName,
        'colorHex': colorHex,
      };

  static String normalizeName(String value) => value
      .toLowerCase()
      .replaceFirst(RegExp(r'^(the|a|an)\s+'), '')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Only an explicit HTTPS URL on gov.in or nic.in is an official page.
  /// Subdomain-boundary checks reject lookalikes such as gov.in.example.com.
  static bool isVerifiedOfficialUrl(Object? value) {
    final raw = value is String ? value.trim() : '';
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return const <String>['gov.in', 'nic.in']
        .any((domain) => host == domain || host.endsWith('.$domain'));
  }

  static String _stringKey(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<String> _mergeStringLists(
    Iterable<String> first,
    Iterable<String> second,
  ) {
    final values = <String>[];
    final seen = <String>{};
    for (final value in <String>[...first, ...second]) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(_stringKey(trimmed))) continue;
      values.add(trimmed);
    }
    return List<String>.unmodifiable(values);
  }

  static String _sourceUrlKey(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority) return _stringKey(value);
    final normalized = uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      fragment: '',
    );
    final text = normalized.toString();
    return text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  }

  static bool _sameSource(
    GovernmentSchemeSource first,
    GovernmentSchemeSource second,
  ) {
    if (first.articleId.isNotEmpty &&
        second.articleId.isNotEmpty &&
        _stringKey(first.articleId) == _stringKey(second.articleId)) {
      return true;
    }
    if (first.url.isNotEmpty &&
        second.url.isNotEmpty &&
        _sourceUrlKey(first.url) == _sourceUrlKey(second.url)) {
      return true;
    }
    final firstCitation = <String>[
      first.title,
      first.publisher,
      first.publishedDate,
    ].map(_stringKey).join('|');
    final secondCitation = <String>[
      second.title,
      second.publisher,
      second.publishedDate,
    ].map(_stringKey).join('|');
    return first.title.isNotEmpty &&
        second.title.isNotEmpty &&
        firstCitation == secondCitation;
  }

  static GovernmentSchemeSource _mergeSource(
    GovernmentSchemeSource first,
    GovernmentSchemeSource second,
  ) {
    // Retain established citation text, but prefer a verified government URL
    // over a non-official duplicate URL when both identify the same source.
    final url = first.url.isEmpty || (!first.official && second.official)
        ? second.url
        : first.url;
    return GovernmentSchemeSource(
      articleId:
          first.articleId.isNotEmpty ? first.articleId : second.articleId,
      title: first.title.isNotEmpty ? first.title : second.title,
      url: url,
      publisher:
          first.publisher.isNotEmpty ? first.publisher : second.publisher,
      publishedDate: first.publishedDate.isNotEmpty
          ? first.publishedDate
          : second.publishedDate,
      official: isVerifiedOfficialUrl(url),
    );
  }

  static List<GovernmentSchemeSource> _mergeSources(
    Iterable<GovernmentSchemeSource> first,
    Iterable<GovernmentSchemeSource> second,
  ) {
    final sources = <GovernmentSchemeSource>[];
    for (final source in <GovernmentSchemeSource>[...first, ...second]) {
      if (!source.hasContent) continue;
      final duplicate = sources.indexWhere((item) => _sameSource(item, source));
      if (duplicate < 0) {
        sources.add(source);
      } else {
        sources[duplicate] = _mergeSource(sources[duplicate], source);
      }
    }
    sources.sort((a, b) {
      for (final comparison in <int>[
        a.publishedDate.compareTo(b.publishedDate),
        a.articleId.compareTo(b.articleId),
        a.url.compareTo(b.url),
        a.title.compareTo(b.title),
      ]) {
        if (comparison != 0) return comparison;
      }
      return 0;
    });
    return List<GovernmentSchemeSource>.unmodifiable(sources);
  }

  static bool _hasValue(Object? value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.any(_hasValue);
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  static void _mergeInto(
    Map<String, dynamic> target,
    Map<String, dynamic> incoming, {
    required bool preserveExistingScalars,
  }) {
    bool canWrite(String field) =>
        !preserveExistingScalars || text(target, field).isEmpty;

    final incomingId = text(incoming, 'docId').isNotEmpty
        ? text(incoming, 'docId')
        : text(incoming, 'id');
    if (incomingId.isNotEmpty && canWrite('docId')) {
      target['docId'] = incomingId;
      target['id'] = incomingId;
    }

    final schemaVersion = integer(incoming, 'schemaVersion');
    if (schemaVersion > integer(target, 'schemaVersion')) {
      target['schemaVersion'] = schemaVersion;
    }

    for (final field in _scalarFields) {
      final value = text(incoming, field);
      if (value.isNotEmpty && canWrite(field)) target[field] = value;
    }

    final incomingSector = text(incoming, 'sector');
    final incomingSourceSector = text(incoming, 'sourceSector');
    if (canWrite('sourceSector')) {
      if (incomingSourceSector.isNotEmpty) {
        target['sourceSector'] = incomingSourceSector;
      } else if (incomingSector.isNotEmpty) {
        target['sourceSector'] = incomingSector;
      }
    }

    final explicitCoverage = text(incoming, 'coverageYear');
    final legacyCoverage = text(incoming, 'year');
    final coverage =
        explicitCoverage.isNotEmpty ? explicitCoverage : legacyCoverage;
    if (coverage.isNotEmpty) {
      // Coverage is rolling provenance metadata, so newer remote coverage may
      // advance it. It is never copied into the explicit launchYear field.
      target['year'] = coverage;
      target['coverageYear'] = coverage;
    }

    for (final field in _arrayFields) {
      final values = stringList(incoming, field);
      if (values.isEmpty) continue;
      target[field] = _mergeStringLists(
        stringList(target, field),
        values,
      );
    }

    final sources = sourceList(incoming, 'sources');
    if (sources.isNotEmpty) {
      target['sources'] = _mergeSources(
        sourceList(target, 'sources'),
        sources,
      ).map((source) => source.toMap()).toList(growable: false);
    }

    final officialUrl = text(incoming, 'officialUrl');
    if (isVerifiedOfficialUrl(officialUrl) &&
        (!preserveExistingScalars ||
            !isVerifiedOfficialUrl(text(target, 'officialUrl')))) {
      target['officialUrl'] = officialUrl;
    }

    final incomingNormalizedName = text(incoming, 'normalizedName');
    if (incomingNormalizedName.isNotEmpty && canWrite('normalizedName')) {
      target['normalizedName'] = incomingNormalizedName;
    }
    final name = text(target, 'name');
    if (name.isNotEmpty && text(target, 'normalizedName').isEmpty) {
      target['normalizedName'] = normalizeName(name);
    }
  }

  /// Combines live data with the curated essentials.
  ///
  /// Curated records form an authoritative floor. Valid remote scalars fill
  /// gaps instead of replacing nonblank hand-curated prose; rolling coverage
  /// metadata may advance. Arrays and citations are stable de-duplicated unions
  /// with curated ordering/content retained first.
  static List<GovernmentScheme> combine(
    Iterable<Map<String, dynamic>> remote,
    Iterable<Map<String, dynamic>> curated,
  ) {
    final merged = <String, Map<String, dynamic>>{};

    for (final raw in curated) {
      final name = text(raw, 'name');
      if (name.isEmpty) continue;
      final target = merged.putIfAbsent(
        normalizeName(name),
        () => <String, dynamic>{},
      );
      _mergeInto(target, raw, preserveExistingScalars: false);
    }

    for (final raw in remote) {
      final name = text(raw, 'name');
      if (name.isEmpty) continue;
      final target = merged.putIfAbsent(
        normalizeName(name),
        () => <String, dynamic>{},
      );
      _mergeInto(target, raw, preserveExistingScalars: true);
    }

    final records = merged.values
        .where(_hasValue)
        .map(GovernmentScheme.fromMap)
        .where((scheme) => scheme.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return records;
  }
}
