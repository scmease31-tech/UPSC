// News feature tests — the Frosted Scholar editorial feed.
//
// Covers the cases the v1.6 spec calls out:
//   • filters: search, category, source, date range, bookmarks, and combinations
//   • date selection: the 7-day quick strip, selecting and clearing a day
//   • empty / loading / error states, including a failed live-news fetch
//   • narrow phones and long titles (no overflow)
//   • missing article art (generated cover falls back cleanly)
//   • opening an article from a card
//
// The selection logic is exercised through NewsFeedQuery, the pure surface the
// News screen delegates to, so no Firestore connection or provider tree is
// needed. The layout cases pump the real card widgets at phone widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/models/article.dart';
import 'package:upsc_daily_edge/screens/news/news_feed_query.dart';
import 'package:upsc_daily_edge/widgets/article_thumbnail.dart';
import 'package:upsc_daily_edge/widgets/editorial_news_cards.dart';

Article _article({
  String id = 'a1',
  String title = 'Cabinet clears the new coastal regulation framework',
  String summary = 'An exam-focused summary of the framework and its rollout.',
  String content = 'Body text about the framework.',
  List<String> categoryTags = const ['Environment'],
  String newspaper = 'Drishti IAS',
  String upscPaper = 'GS-III',
  DateTime? publishedDate,
  bool isTopNews = false,
  String imageUrl = 'https://example.test/art.jpg',
  List<String> keyPoints = const ['Point one'],
  String syllabusMapping = '',
  String analysisNote = '',
  Map<String, String> keyTerms = const {},
}) =>
    Article(
      id: id,
      title: title,
      summary: summary,
      content: content,
      keyPoints: keyPoints,
      examRelevance: 'Both',
      categoryTags: categoryTags,
      imageUrl: imageUrl,
      publishedDate: publishedDate ?? DateTime(2026, 9, 19),
      isTopNews: isTopNews,
      newspaper: newspaper,
      upscPaper: upscPaper,
      syllabusMapping: syllabusMapping,
      analysisNote: analysisNote,
      keyTerms: keyTerms,
    );

Future<void> _pump(WidgetTester tester, Widget child, {double width = 360}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      routes: {
        '/article-detail': (_) => const Scaffold(body: Text('Article detail')),
      },
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('search filter', () {
    final feed = [
      _article(id: 'polity', title: 'Parliament passes the anti-defection amendment', categoryTags: const ['Polity']),
      _article(id: 'econ', title: 'RBI holds the repo rate steady', categoryTags: const ['Economy']),
    ];

    test('an empty query returns the whole feed', () {
      expect(const NewsFeedQuery().apply(feed).length, 2);
    });

    test('matches case-insensitively on the title', () {
      final r = const NewsFeedQuery(searchQuery: 'PARLIAMENT').apply(feed);
      expect(r.map((a) => a.id), ['polity']);
    });

    test('requires every word of a multi-word query to match', () {
      expect(const NewsFeedQuery(searchQuery: 'repo rate').apply(feed).map((a) => a.id), ['econ']);
      // 'repo' matches econ, 'defection' matches polity — nothing matches both.
      expect(const NewsFeedQuery(searchQuery: 'repo defection').apply(feed), isEmpty);
    });

    test('one-character words are ignored rather than excluding everything', () {
      // The stray 'a' must not filter the match out.
      final r = const NewsFeedQuery(searchQuery: 'a repo').apply(feed);
      expect(r.map((a) => a.id), ['econ']);
    });

    test('searches the deep analysis fields, not just the title', () {
      final deep = [
        _article(
          id: 'deep',
          title: 'A plain headline',
          syllabusMapping: 'GS-II > Parliament > Anti-Defection',
          analysisNote: 'Why federalism matters here',
          keyTerms: const {'Quorum': 'Minimum members required'},
        ),
      ];
      expect(const NewsFeedQuery(searchQuery: 'federalism').apply(deep), hasLength(1));
      expect(const NewsFeedQuery(searchQuery: 'quorum').apply(deep), hasLength(1));
      expect(const NewsFeedQuery(searchQuery: 'anti-defection').apply(deep), hasLength(1));
    });

    test('a query matching nothing yields an empty feed, not an error', () {
      expect(const NewsFeedQuery(searchQuery: 'cryptozoology').apply(feed), isEmpty);
    });
  });

  group('category and source filters', () {
    final feed = [
      _article(id: 'env', categoryTags: const ['Environment'], newspaper: 'The Hindu'),
      _article(id: 'pol', categoryTags: const ['Polity', 'Governance'], newspaper: 'Indian Express'),
    ];

    test('category matches any of an article\'s tags, case-insensitively', () {
      expect(const NewsFeedQuery(selectedCategory: 'governance').apply(feed).map((a) => a.id), ['pol']);
    });

    test('source filter is an exact, case-insensitive newspaper match', () {
      expect(const NewsFeedQuery(selectedNewspaper: 'the hindu').apply(feed).map((a) => a.id), ['env']);
      expect(const NewsFeedQuery(selectedNewspaper: 'The Hin').apply(feed), isEmpty);
    });

    test('filters compose as AND', () {
      final q = const NewsFeedQuery(selectedCategory: 'Environment', selectedNewspaper: 'Indian Express');
      expect(q.apply(feed), isEmpty);
    });
  });

  group('date range filter', () {
    final feed = [
      _article(id: 'd17', publishedDate: DateTime(2026, 9, 17)),
      _article(id: 'd18', publishedDate: DateTime(2026, 9, 18, 23, 59)),
      _article(id: 'd19', publishedDate: DateTime(2026, 9, 19)),
    ];

    test('both bounds are inclusive', () {
      final r = const NewsFeedQuery(selectedDateFrom: '2026-09-17', selectedDateTo: '2026-09-19').apply(feed);
      expect(r, hasLength(3));
    });

    test('a from-bound alone drops everything older', () {
      final r = const NewsFeedQuery(selectedDateFrom: '2026-09-18').apply(feed);
      expect(r.map((a) => a.id), ['d19', 'd18']);
    });

    test('a to-bound alone drops everything newer', () {
      final r = const NewsFeedQuery(selectedDateTo: '2026-09-18').apply(feed);
      expect(r.map((a) => a.id), ['d18', 'd17']);
    });

    test('a single-day range ignores the time of day', () {
      // d18 is published at 23:59 and must still land inside its own day.
      final r = const NewsFeedQuery(selectedDateFrom: '2026-09-18', selectedDateTo: '2026-09-18').apply(feed);
      expect(r.map((a) => a.id), ['d18']);
    });

    test('an inverted range selects nothing instead of throwing', () {
      final r = const NewsFeedQuery(selectedDateFrom: '2026-09-19', selectedDateTo: '2026-09-17').apply(feed);
      expect(r, isEmpty);
    });

    test('a malformed bound is ignored rather than crashing the feed', () {
      final r = const NewsFeedQuery(selectedDateFrom: 'not-a-date').apply(feed);
      expect(r, hasLength(3));
    });
  });

  group('bookmarks filter', () {
    final feed = [_article(id: 'a'), _article(id: 'b')];

    test('restricts the feed to bookmarked ids', () {
      final r = const NewsFeedQuery(showBookmarks: true).apply(feed, bookmarkedIds: {'b'});
      expect(r.map((a) => a.id), ['b']);
    });

    test('no bookmarks yields the empty state, and its own hint copy', () {
      const q = NewsFeedQuery(showBookmarks: true);
      expect(q.apply(feed), isEmpty);
      expect(q.emptyStateHint, contains('bookmarked'));
      expect(const NewsFeedQuery().emptyStateHint, contains('search or category'));
    });

    test('bookmarked ids are ignored when the toggle is off', () {
      expect(const NewsFeedQuery().apply(feed, bookmarkedIds: {'b'}), hasLength(2));
    });
  });

  group('ordering', () {
    test('the feed is sorted newest-first regardless of input order', () {
      final feed = [
        _article(id: 'old', publishedDate: DateTime(2026, 9, 10)),
        _article(id: 'new', publishedDate: DateTime(2026, 9, 20)),
        _article(id: 'mid', publishedDate: DateTime(2026, 9, 15)),
      ];
      expect(const NewsFeedQuery().apply(feed).map((a) => a.id), ['new', 'mid', 'old']);
    });

    test('apply does not mutate the caller\'s list', () {
      final feed = [
        _article(id: 'old', publishedDate: DateTime(2026, 9, 10)),
        _article(id: 'new', publishedDate: DateTime(2026, 9, 20)),
      ];
      const NewsFeedQuery().apply(feed);
      expect(feed.map((a) => a.id), ['old', 'new']);
    });
  });

  group('editorial lead story', () {
    test('prefers the top-news story from the most recent day', () {
      final feed = const NewsFeedQuery().apply([
        _article(id: 'today-plain', publishedDate: DateTime(2026, 9, 19, 8)),
        _article(id: 'today-top', publishedDate: DateTime(2026, 9, 19, 6), isTopNews: true),
        _article(id: 'yesterday-top', publishedDate: DateTime(2026, 9, 18), isTopNews: true),
      ]);
      expect(NewsFeedQuery.selectLeadArticle(feed)!.id, 'today-top');
    });

    test('falls back to the newest story when that day has no top news', () {
      final feed = const NewsFeedQuery().apply([
        _article(id: 'today-late', publishedDate: DateTime(2026, 9, 19, 18)),
        _article(id: 'today-early', publishedDate: DateTime(2026, 9, 19, 6)),
      ]);
      expect(NewsFeedQuery.selectLeadArticle(feed)!.id, 'today-late');
    });

    test('never promotes an older top story over today\'s coverage', () {
      final feed = const NewsFeedQuery().apply([
        _article(id: 'today', publishedDate: DateTime(2026, 9, 19)),
        _article(id: 'last-week-top', publishedDate: DateTime(2026, 9, 12), isTopNews: true),
      ]);
      expect(NewsFeedQuery.selectLeadArticle(feed)!.id, 'today');
    });

    test('an empty feed has no lead story', () {
      expect(NewsFeedQuery.selectLeadArticle(const []), isNull);
    });
  });

  group('quick date selection', () {
    test('offers at most 7 distinct days, newest first', () {
      final feed = [
        for (var day = 1; day <= 12; day++)
          _article(id: 'd$day', publishedDate: DateTime(2026, 9, day)),
      ];
      final dates = NewsFeedQuery.availableQuickDates(feed);
      expect(dates, hasLength(7));
      expect(dates.first, DateTime(2026, 9, 12));
      expect(dates.last, DateTime(2026, 9, 6));
    });

    test('collapses multiple stories on one day into a single chip', () {
      final feed = [
        _article(id: 'a', publishedDate: DateTime(2026, 9, 19, 7)),
        _article(id: 'b', publishedDate: DateTime(2026, 9, 19, 20)),
        _article(id: 'c', publishedDate: DateTime(2026, 9, 18)),
      ];
      expect(NewsFeedQuery.availableQuickDates(feed), [DateTime(2026, 9, 19), DateTime(2026, 9, 18)]);
    });

    test('an empty feed offers no days, so no day can be selected', () {
      expect(NewsFeedQuery.availableQuickDates(const []), isEmpty);
    });

    test('tapping a day pins the range to exactly that day', () {
      final next = const NewsFeedQuery().toggleQuickDate(DateTime(2026, 9, 18));
      expect(next.selectedDateFrom, '2026-09-18');
      expect(next.selectedDateTo, '2026-09-18');
      expect(next.isQuickDateSelected(DateTime(2026, 9, 18)), isTrue);
      expect(next.isQuickDateSelected(DateTime(2026, 9, 19)), isFalse);
    });

    test('tapping the selected day clears the range', () {
      final pinned = const NewsFeedQuery().toggleQuickDate(DateTime(2026, 9, 18));
      final cleared = pinned.toggleQuickDate(DateTime(2026, 9, 18));
      expect(cleared.selectedDateFrom, isNull);
      expect(cleared.selectedDateTo, isNull);
      expect(cleared.hasDateFilter, isFalse);
    });

    test('tapping a different day moves the selection rather than widening it', () {
      final pinned = const NewsFeedQuery().toggleQuickDate(DateTime(2026, 9, 18));
      final moved = pinned.toggleQuickDate(DateTime(2026, 9, 19));
      expect(moved.selectedDateFrom, '2026-09-19');
      expect(moved.selectedDateTo, '2026-09-19');
    });

    test('a pinned day narrows the feed to that day', () {
      final feed = [
        _article(id: 'd19', publishedDate: DateTime(2026, 9, 19)),
        _article(id: 'd18', publishedDate: DateTime(2026, 9, 18)),
      ];
      final q = const NewsFeedQuery().toggleQuickDate(DateTime(2026, 9, 18));
      expect(q.apply(feed).map((a) => a.id), ['d18']);
    });

    test('a broad range is not reported as a single-day selection', () {
      const q = NewsFeedQuery(selectedDateFrom: '2026-09-17', selectedDateTo: '2026-09-19');
      expect(q.isQuickDateSelected(DateTime(2026, 9, 18)), isFalse);
      expect(q.hasDateFilter, isTrue);
    });
  });

  group('hasAnyFilter', () {
    test('a pristine query narrows nothing', () {
      expect(const NewsFeedQuery().hasAnyFilter, isFalse);
    });

    test('each filter on its own counts', () {
      expect(const NewsFeedQuery(searchQuery: 'x').hasAnyFilter, isTrue);
      expect(const NewsFeedQuery(selectedCategory: 'Polity').hasAnyFilter, isTrue);
      expect(const NewsFeedQuery(selectedNewspaper: 'The Hindu').hasAnyFilter, isTrue);
      expect(const NewsFeedQuery(selectedDateTo: '2026-09-19').hasAnyFilter, isTrue);
      expect(const NewsFeedQuery(showBookmarks: true).hasAnyFilter, isTrue);
    });
  });

  group('feed display states', () {
    test('loading: fetching with nothing to show yet', () {
      expect(
        NewsFeedQuery.resolveDisplay(isLoading: true, filteredCount: 0),
        NewsFeedDisplay.loading,
      );
    });

    test('cached stories win over the spinner while refreshing', () {
      // A pull-to-refresh must not blank out the feed the user is reading.
      expect(
        NewsFeedQuery.resolveDisplay(isLoading: true, filteredCount: 4),
        NewsFeedDisplay.feed,
      );
    });

    test('empty: settled with no results', () {
      expect(
        NewsFeedQuery.resolveDisplay(isLoading: false, filteredCount: 0),
        NewsFeedDisplay.empty,
      );
    });

    test('feed: settled with results', () {
      expect(
        NewsFeedQuery.resolveDisplay(isLoading: false, filteredCount: 1),
        NewsFeedDisplay.feed,
      );
    });

    test('filters excluding everything shows empty, not loading', () {
      final feed = [_article(id: 'a', categoryTags: const ['Polity'])];
      final filtered = const NewsFeedQuery(selectedCategory: 'Economy').apply(feed);
      expect(
        NewsFeedQuery.resolveDisplay(isLoading: false, filteredCount: filtered.length),
        NewsFeedDisplay.empty,
      );
    });
  });

  group('live "More News Online" section', () {
    final items = [
      {'title': 'Live one', 'category': 'Polity'},
      {'title': 'Live two', 'category': 'Economy'},
    ];

    test('waiting shows the loading strip', () {
      expect(NewsFeedQuery.resolveLiveNews(waiting: true, data: null).isLoading, isTrue);
    });

    test('a failed fetch hides the strip instead of erroring the screen', () {
      // FutureBuilder surfaces an error as null data. The Firestore-primary
      // feed above must be unaffected, so the strip simply disappears.
      final r = NewsFeedQuery.resolveLiveNews(waiting: false, data: null);
      expect(r.isHidden, isTrue);
      expect(r.isLoading, isFalse);
      expect(r.items, isEmpty);
    });

    test('an empty response hides the strip', () {
      expect(NewsFeedQuery.resolveLiveNews(waiting: false, data: const []).isHidden, isTrue);
    });

    test('items are shown and counted', () {
      final r = NewsFeedQuery.resolveLiveNews(waiting: false, data: items);
      expect(r.isShown, isTrue);
      expect(r.matchCount, 2);
    });

    test('the category filter applies to live items too', () {
      final r = NewsFeedQuery.resolveLiveNews(waiting: false, data: items, selectedCategory: 'economy');
      expect(r.items.map((i) => i['title']), ['Live two']);
    });

    test('a category matching no live item hides the strip', () {
      final r = NewsFeedQuery.resolveLiveNews(waiting: false, data: items, selectedCategory: 'Geography');
      expect(r.isHidden, isTrue);
    });

    test('rendering is capped at 15 while the count reports the true total', () {
      final many = [for (var i = 0; i < 40; i++) {'title': 'Item $i', 'category': 'Polity'}];
      final r = NewsFeedQuery.resolveLiveNews(waiting: false, data: many);
      expect(r.items, hasLength(15));
      expect(r.matchCount, 40);
    });

    test('an item with no category is excluded by a category filter, not crashed on', () {
      final r = NewsFeedQuery.resolveLiveNews(
        waiting: false,
        data: [{'title': 'Uncategorised'}],
        selectedCategory: 'Polity',
      );
      expect(r.isHidden, isTrue);
    });
  });

  group('day grouping', () {
    test('groups newest day first with top news leading each day', () {
      final feed = const NewsFeedQuery().apply([
        _article(id: 'y-b', publishedDate: DateTime(2026, 9, 18), newspaper: 'B Paper'),
        _article(id: 't-plain', publishedDate: DateTime(2026, 9, 19, 9), newspaper: 'Z Paper'),
        _article(id: 't-top', publishedDate: DateTime(2026, 9, 19, 7), newspaper: 'A Paper', isTopNews: true),
      ]);
      final days = NewsFeedQuery.groupByDay(feed);

      expect(days.map((d) => d.dateKey), ['2026-09-19', '2026-09-18']);
      expect(days.first.articles.map((a) => a.id), ['t-top', 't-plain']);
      expect(days.last.articles.map((a) => a.id), ['y-b']);
    });

    test('same-day stories with no top news are ordered by source', () {
      final days = NewsFeedQuery.groupByDay([
        _article(id: 'z', newspaper: 'Z Paper'),
        _article(id: 'a', newspaper: 'A Paper'),
      ]);
      expect(days.single.articles.map((a) => a.id), ['a', 'z']);
    });

    test('an empty feed produces no day headers', () {
      expect(NewsFeedQuery.groupByDay(const []), isEmpty);
    });
  });

  group('card layout on narrow phones', () {
    testWidgets('the lead story fits a 320px screen', (tester) async {
      await _pump(tester, EditorialLeadStory(article: _article(isTopNews: true)), width: 320);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long headline does not overflow a compact card', (tester) async {
      await _pump(
        tester,
        EditorialStoryCard(
          article: _article(title: 'Union Cabinet approves a sweeping overhaul of the coastal zone regulation framework ' * 4),
        ),
        width: 300,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long headline does not overflow the lead story either', (tester) async {
      await _pump(
        tester,
        EditorialLeadStory(
          article: _article(title: 'Parliament clears the long-pending amendment after a marathon debate ' * 5),
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty headline still renders a tappable card', (tester) async {
      await _pump(tester, EditorialStoryCard(article: _article(title: '')), width: 320);
      expect(find.byType(EditorialStoryCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('missing article art', () {
    testWidgets('a card with no image falls back to generated cover art', (tester) async {
      await _pump(tester, EditorialStoryCard(article: _article(imageUrl: '')), width: 360);
      expect(find.byType(ArticleThumbnail), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the lead story survives a missing image', (tester) async {
      await _pump(tester, EditorialLeadStory(article: _article(imageUrl: '', isTopNews: true)), width: 360);
      expect(tester.takeException(), isNull);
    });
  });

  group('opening an article', () {
    testWidgets('tapping a compact card routes to the article detail', (tester) async {
      await _pump(tester, EditorialStoryCard(article: _article()));

      await tester.tap(find.byType(EditorialStoryCard));
      await tester.pumpAndSettle();

      expect(find.text('Article detail'), findsOneWidget);
    });

    testWidgets('tapping the lead story routes to the article detail', (tester) async {
      await _pump(tester, EditorialLeadStory(article: _article(isTopNews: true)));

      await tester.tap(find.byType(EditorialLeadStory));
      await tester.pumpAndSettle();

      expect(find.text('Article detail'), findsOneWidget);
    });
  });
}
