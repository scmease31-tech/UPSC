import 'package:intl/intl.dart';

import '../../models/article.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// NewsFeedQuery — the PURE selection logic behind the News screen.
///
/// This is the search + category + source + date-range + bookmark pipeline that
/// used to live inline inside `_NewsScreenState.build`. It is factored out here
/// so the feed's behaviour (which stories show, which one leads the Editorial
/// Briefing, which days the 7-day strip offers) can be verified without a
/// Firestore connection, a provider tree, or a rendered frame.
///
/// Every method is side-effect free and depends only on its arguments.
/// ──────────────────────────────────────────────────────────────────────────────
class NewsFeedQuery {
  const NewsFeedQuery({
    this.searchQuery = '',
    this.selectedCategory,
    this.selectedNewspaper,
    this.selectedDateFrom,
    this.selectedDateTo,
    this.showBookmarks = false,
  });

  /// Free-text search. Matched as ALL words (each longer than one character)
  /// against the article's full searchable surface, case-insensitively.
  final String searchQuery;

  /// Category tag filter, or null for "All".
  final String? selectedCategory;

  /// Source newspaper filter, or null for every source.
  final String? selectedNewspaper;

  /// Inclusive `yyyy-MM-dd` lower bound, or null for unbounded.
  final String? selectedDateFrom;

  /// Inclusive `yyyy-MM-dd` upper bound, or null for unbounded.
  final String? selectedDateTo;

  /// When true, restrict the feed to bookmarked articles.
  final bool showBookmarks;

  static final DateFormat _dayKey = DateFormat('yyyy-MM-dd');

  /// Canonical `yyyy-MM-dd` key for a date, ignoring any time component.
  static String dayKey(DateTime date) => _dayKey.format(dateOnly(date));

  /// Strips the time component so two instants on the same calendar day compare
  /// equal. Date filtering and the quick-date strip both work in whole days.
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool get hasDateFilter =>
      selectedDateFrom != null || selectedDateTo != null;

  /// True when any filter narrows the feed. Drives the "clear filters" chip row.
  bool get hasAnyFilter =>
      searchQuery.isNotEmpty ||
      selectedCategory != null ||
      selectedNewspaper != null ||
      hasDateFilter ||
      showBookmarks;

  /// Applies every active filter and returns the result sorted newest-first.
  ///
  /// Filters compose as AND. [bookmarkedIds] is only consulted when
  /// [showBookmarks] is set, so callers may pass an empty set otherwise.
  List<Article> apply(
    List<Article> articles, {
    Set<String> bookmarkedIds = const <String>{},
  }) {
    var filtered = articles;

    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      final queryWords =
          q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      filtered = filtered.where((a) {
        final searchableText = [
          a.title,
          a.summary,
          a.content,
          a.newspaper,
          a.upscPaper,
          a.syllabusMapping,
          a.analysisNote,
          ...a.categoryTags,
          ...a.relatedTopics,
          ...a.keyPoints,
          ...a.shortNotes,
          ...a.keyTerms.keys,
          ...a.keyTerms.values,
        ].join(' ').toLowerCase();
        return queryWords.every((word) => searchableText.contains(word));
      }).toList();
    }

    if (selectedCategory != null) {
      filtered = filtered
          .where((a) => a.categoryTags
              .any((t) => t.toLowerCase() == selectedCategory!.toLowerCase()))
          .toList();
    }

    if (selectedNewspaper != null) {
      filtered = filtered
          .where(
              (a) => a.newspaper.toLowerCase() == selectedNewspaper!.toLowerCase())
          .toList();
    }

    if (hasDateFilter) {
      // tryParse, not parse: an unparseable bound is ignored rather than
      // thrown, so a malformed persisted filter cannot take down the feed.
      final from = selectedDateFrom == null
          ? null
          : DateTime.tryParse(selectedDateFrom!);
      final to =
          selectedDateTo == null ? null : DateTime.tryParse(selectedDateTo!);
      filtered = filtered.where((a) {
        final d = dateOnly(a.publishedDate);
        if (from != null && d.isBefore(dateOnly(from))) return false;
        if (to != null && d.isAfter(dateOnly(to))) return false;
        return true;
      }).toList();
    }

    if (showBookmarks) {
      filtered = filtered.where((a) => bookmarkedIds.contains(a.id)).toList();
    }

    return List<Article>.from(filtered)
      ..sort((a, b) => b.publishedDate.compareTo(a.publishedDate));
  }

  /// The Editorial Briefing lead story: the top-news article from the most
  /// recent day present in [articles], falling back to that day's first story.
  ///
  /// Expects [articles] already sorted newest-first (as [apply] returns).
  /// Returns null for an empty feed so callers can render the empty state.
  static Article? selectLeadArticle(List<Article> articles) {
    if (articles.isEmpty) return null;
    final newestDay = dateOnly(articles.first.publishedDate);
    final sameDay = articles
        .where((article) => dateOnly(article.publishedDate) == newestDay)
        .toList();
    return sameDay.firstWhere(
      (article) => article.isTopNews,
      orElse: () => sameDay.first,
    );
  }

  /// The up-to-7 most recent distinct publication days, newest first. These are
  /// the days the quick-date strip offers, so a day with no stories is never
  /// selectable.
  static List<DateTime> availableQuickDates(List<Article> articles) {
    final unique = <String, DateTime>{};
    for (final article in articles) {
      final day = dateOnly(article.publishedDate);
      unique[dayKey(day)] = day;
    }
    final dates = unique.values.toList()..sort((a, b) => b.compareTo(a));
    return dates.take(7).toList();
  }

  /// True when the date range is pinned to exactly [date] — the selected state
  /// of a chip in the quick-date strip.
  bool isQuickDateSelected(DateTime date) {
    final key = dayKey(date);
    return selectedDateFrom == key && selectedDateTo == key;
  }

  /// Result of tapping the quick-date chip for [date]: selecting it pins the
  /// range to that single day, tapping the selected one clears the range.
  NewsFeedQuery toggleQuickDate(DateTime date) {
    final key = dayKey(date);
    final selected = isQuickDateSelected(date);
    return copyWith(
      selectedDateFrom: selected ? null : key,
      selectedDateTo: selected ? null : key,
    );
  }

  /// Groups a feed into date-keyed buckets, newest day first, with each day's
  /// stories ordered top-news-first then by source. Mirrors the order the
  /// SliverList renders date headers and cards in.
  static List<({String dateKey, List<Article> articles})> groupByDay(
      List<Article> articles) {
    final grouped = <String, List<Article>>{};
    for (final article in articles) {
      grouped.putIfAbsent(dayKey(article.publishedDate), () => []).add(article);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final key in sortedDates)
        (
          dateKey: key,
          articles: grouped[key]!
            ..sort((a, b) {
              if (a.isTopNews != b.isTopNews) return a.isTopNews ? -1 : 1;
              return a.newspaper.compareTo(b.newspaper);
            }),
        ),
    ];
  }

  /// Which of the three mutually exclusive feed bodies the News screen renders.
  ///
  /// Mirrors the branch order in `_NewsScreenState.build`: shimmer placeholders
  /// only while the provider is still loading AND has nothing to show, then the
  /// empty state, then the real date-grouped feed.
  static NewsFeedDisplay resolveDisplay({
    required bool isLoading,
    required int filteredCount,
  }) {
    if (isLoading && filteredCount == 0) return NewsFeedDisplay.loading;
    if (filteredCount == 0) return NewsFeedDisplay.empty;
    return NewsFeedDisplay.feed;
  }

  /// The copy shown under "No articles found". Bookmarks-only gets its own
  /// wording because "try a different search" is useless advice there.
  String get emptyStateHint => showBookmarks
      ? "You haven't bookmarked any articles yet"
      : 'Try a different search or category';

  /// Resolution of the supplementary "More News Online" section. A failed fetch
  /// is NOT an error screen: the section hides itself and the Firestore-primary
  /// feed above it carries on unaffected.
  static LiveNewsDisplay resolveLiveNews({
    required bool waiting,
    required List<Map<String, dynamic>>? data,
    String? selectedCategory,
  }) {
    if (waiting) return const LiveNewsDisplay.loading();
    final all = data ?? const <Map<String, dynamic>>[];
    final items = selectedCategory == null
        ? all
        : all
            .where((n) =>
                (n['category'] as String? ?? '').toLowerCase() ==
                selectedCategory.toLowerCase())
            .toList();
    if (items.isEmpty) return const LiveNewsDisplay.hidden();
    return LiveNewsDisplay.shown(
      items.take(15).toList(),
      matchCount: items.length,
    );
  }

  NewsFeedQuery copyWith({
    String? searchQuery,
    String? selectedCategory,
    String? selectedNewspaper,
    String? selectedDateFrom,
    String? selectedDateTo,
    bool? showBookmarks,
    bool clearCategory = false,
    bool clearNewspaper = false,
  }) {
    return NewsFeedQuery(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategory:
          clearCategory ? null : (selectedCategory ?? this.selectedCategory),
      selectedNewspaper:
          clearNewspaper ? null : (selectedNewspaper ?? this.selectedNewspaper),
      selectedDateFrom: selectedDateFrom,
      selectedDateTo: selectedDateTo,
      showBookmarks: showBookmarks ?? this.showBookmarks,
    );
  }
}

/// The three mutually exclusive bodies of the News feed.
enum NewsFeedDisplay {
  /// Shimmer placeholders: still fetching and nothing cached to show yet.
  loading,

  /// "No articles found" — either genuinely no stories, or filters excluded
  /// everything.
  empty,

  /// The date-grouped list of story cards.
  feed,
}

/// Outcome for the supplementary "More News Online" strip.
class LiveNewsDisplay {
  const LiveNewsDisplay.loading()
      : items = const <Map<String, dynamic>>[],
        matchCount = 0,
        isLoading = true,
        isHidden = false;

  const LiveNewsDisplay.hidden()
      : items = const <Map<String, dynamic>>[],
        matchCount = 0,
        isLoading = false,
        isHidden = true;

  const LiveNewsDisplay.shown(this.items, {required this.matchCount})
      : isLoading = false,
        isHidden = false;

  /// The items actually rendered, capped at 15.
  final List<Map<String, dynamic>> items;

  /// How many items matched the category filter before the 15-item cap. This is
  /// the number the "N updates" label reports.
  final int matchCount;

  final bool isLoading;
  final bool isHidden;

  bool get isShown => !isLoading && !isHidden;
}
