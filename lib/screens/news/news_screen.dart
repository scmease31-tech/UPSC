import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/article.dart';
import '../../providers/articles_provider.dart';
import '../../providers/bookmarks_provider.dart';
import '../../services/news_api_service.dart';
import '../../widgets/editorial_news_cards.dart';
import '../../widgets/category_chip.dart';
import '../../utils/constants.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// NewsScreen — Editorial daily briefing with a lead story, quick date strip,
/// subject and source filters, compact reading cards, bookmarks, and more news online.
/// ──────────────────────────────────────────────────────────────────────────────
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedNewspaper;
  String? _selectedDateFrom;
  String? _selectedDateTo;
  bool _showBookmarks = false;
  late TextEditingController _searchCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  final ScrollController _scrollController = ScrollController();
  late Future<List<Map<String, dynamic>>> _liveNewsFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _liveNewsFuture = NewsApiService.fetchLatestNews();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final articles = context.watch<ArticlesProvider>();
    final bookmarks = context.watch<BookmarksProvider>();
    final dark = AppTheme.isDark(context);

    var filteredArticles = articles.articles;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      final queryWords = q.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      filteredArticles = filteredArticles
          .where((a) {
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
          })
          .toList();
    }

    if (_selectedCategory != null) {
      filteredArticles = filteredArticles
          .where((a) => a.categoryTags.any((t) => t.toLowerCase() == _selectedCategory!.toLowerCase()))
          .toList();
    }

    if (_selectedNewspaper != null) {
      filteredArticles = filteredArticles
          .where((a) => a.newspaper.toLowerCase() == _selectedNewspaper!.toLowerCase())
          .toList();
    }

    if (_selectedDateFrom != null || _selectedDateTo != null) {
      filteredArticles = filteredArticles.where((a) {
        final d = DateTime(a.publishedDate.year, a.publishedDate.month, a.publishedDate.day);
        if (_selectedDateFrom != null) {
          final from = DateTime.parse(_selectedDateFrom!);
          if (d.isBefore(from)) return false;
        }
        if (_selectedDateTo != null) {
          final to = DateTime.parse(_selectedDateTo!);
          if (d.isAfter(to)) return false;
        }
        return true;
      }).toList();
    }

    if (_showBookmarks) {
      final bmIds = bookmarks.bookmarkedIds;
      filteredArticles = filteredArticles.where((a) => bmIds.contains(a.id)).toList();
    }

    final categories = ['All', 'Polity', 'Economy', 'Environment', 'Science & Technology', 'International Relations', 'Social Issues', 'Geography', 'History', 'Governance'];

    filteredArticles = List<Article>.from(filteredArticles)
      ..sort((a, b) => b.publishedDate.compareTo(a.publishedDate));

    final leadArticle = _selectLeadArticle(filteredArticles);
    final briefingArticles = leadArticle == null
        ? filteredArticles
        : filteredArticles.where((article) => article.id != leadArticle.id).toList();
    final quickDates = _availableQuickDates(articles.allArticles);
    final feedItems = _buildEditorialFeedItems(briefingArticles);

    final Widget content = FadeTransition(
        opacity: _fadeAnim,
        child: Column(
          children: [
            // ── STICKY HEADER ──
            Padding(
              padding: const EdgeInsets.fromLTRB(kIsWeb ? 28 : 20, kIsWeb ? 12 : 16, kIsWeb ? 28 : 20, 6),
              child: Row(
                children: [
                  if (!kIsWeb)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Briefing',
                            style: AppFonts.plusJakartaSans(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textP(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _briefingSubtitle(filteredArticles),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textS(context),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const Spacer(),
                  _iconBtn(
                    icon: Icons.tune_rounded,
                    color: (_selectedNewspaper != null || _selectedDateFrom != null || _selectedDateTo != null)
                        ? AppTheme.primaryColor
                        : AppTheme.textS(context),
                    onTap: () => _showFilterSheet(context, dark),
                  ),
                  const SizedBox(width: 8),
                  _iconBtn(
                    icon: _showBookmarks ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                    color: _showBookmarks ? AppTheme.primaryColor : AppTheme.textS(context),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _showBookmarks = !_showBookmarks);
                    },
                  ),
                ],
              ),
            ),

            // ── STICKY SEARCH BAR ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: RepaintBoundary(
                child: Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _searchQuery.isNotEmpty
                            ? AppTheme.primaryColor.withValues(alpha: 0.4)
                            : (dark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.2)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: dark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: AppFonts.inter(fontSize: 15, color: AppTheme.textP(context)),
                      decoration: InputDecoration(
                        hintText: 'Search articles & topics',
                        hintStyle: AppFonts.inter(fontSize: 14, color: AppTheme.textT(context).withValues(alpha: 0.6)),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 8),
                          child: Icon(Icons.search_rounded, color: _searchQuery.isNotEmpty ? AppTheme.primaryColor : AppTheme.textT(context), size: 22),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close_rounded, color: AppTheme.textT(context), size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 0),
                        fillColor: Colors.transparent,
                        filled: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── QUICK DATE STRIP ──
            if (quickDates.isNotEmpty)
              _buildQuickDateStrip(quickDates),

            // ── SUBJECT FILTERS ──
            SizedBox(
              height: 46,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final cat = categories[i];
                  final isSelected = (cat == 'All' && _selectedCategory == null) ||
                      cat.toLowerCase() == _selectedCategory?.toLowerCase();
                  final iconPath = AppConstants.categoryIcons[cat];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: CategoryChip(
                      label: cat,
                      iconPath: iconPath,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat == 'All' ? null : cat;
                        });
                      },
                    ),
                  );
                },
              ),
            ),

            // Active filter indicator
            if (_selectedNewspaper != null || _selectedDateFrom != null || _selectedDateTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_selectedNewspaper != null)
                      _buildFilterTag(
                        icon: Icons.newspaper_rounded,
                        label: _selectedNewspaper!,
                        onRemove: () => setState(() => _selectedNewspaper = null),
                        dark: dark,
                      ),
                    if (_selectedDateFrom != null || _selectedDateTo != null)
                      _buildFilterTag(
                        icon: Icons.date_range_rounded,
                        label: _buildDateRangeLabel(),
                        onRemove: () => setState(() { _selectedDateFrom = null; _selectedDateTo = null; }),
                        dark: dark,
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 4),

            // ── SCROLLABLE CONTENT ──
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  NewsApiService.clearCache();
                  setState(() => _liveNewsFuture = NewsApiService.fetchLatestNews(forceRefresh: true));
                  await articles.loadArticles();
                },
                color: AppTheme.primaryColor,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    if (leadArticle != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildBriefingOverview(filteredArticles),
                              const SizedBox(height: 12),
                              EditorialLeadStory(article: leadArticle),
                            ],
                          ),
                        ),
                      ),

            // ═══ LIVE NEWS FROM WEB (auto-fetched, no Telegram needed) ═══
            if (!_showBookmarks && _searchQuery.isEmpty)
              SliverToBoxAdapter(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _liveNewsFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.7)],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text('More News Online', style: AppFonts.inter(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
                                      )),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildShimmerCard(dark),
                          ],
                        ),
                      );
                    }

                    final allLiveNews = snap.data ?? [];
                    // Apply category filter
                    final liveNews = _selectedCategory == null
                        ? allLiveNews
                        : allLiveNews.where((n) {
                            final cat = (n['category'] as String? ?? '').toLowerCase();
                            return cat == _selectedCategory!.toLowerCase();
                          }).toList();

                    if (liveNews.isEmpty) return const SizedBox.shrink();

                    // Show up to 10 live news items as a horizontal scrollable + vertical list
                    final displayNews = liveNews.take(15).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.7)],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text('More News Online', style: AppFonts.inter(
                                      fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
                                    )),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text('${liveNews.length} updates', style: AppFonts.inter(
                                fontSize: 11, color: AppTheme.textT(context),
                              )),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  NewsApiService.clearCache();
                                  setState(() => _liveNewsFuture = NewsApiService.fetchLatestNews(forceRefresh: true));
                                },
                                child: const Icon(Icons.refresh_rounded, size: 16, color: AppTheme.primaryColor),
                              ),
                            ],
                          ),
                        ),
                        // Horizontal scrollable live news cards
                        SizedBox(
                          height: 160,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: displayNews.length,
                            itemBuilder: (context, i) => _buildLiveNewsCard(displayNews[i], dark),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ),

            // Article list
            if (articles.isLoading && filteredArticles.isEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, __) => _buildShimmerCard(dark),
                  childCount: 4,
                ),
              )
            else if (filteredArticles.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 40),
                  child: Column(
                    children: [
                      Lottie.asset(
                        'assets/animations/empty_box.json',
                        width: 160,
                        height: 160,
                        repeat: true,
                      ),
                      const SizedBox(height: 16),
                      Text('No articles found', style: AppFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textS(context))),
                      const SizedBox(height: 6),
                      Text(
                        _showBookmarks ? 'You haven\'t bookmarked any articles yet' : 'Try a different search or category',
                        style: AppFonts.inter(fontSize: 13, color: AppTheme.textT(context)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => feedItems[i],
                    childCount: feedItems.length,
                  ),
                ),
              ),

            SliverToBoxAdapter(child: SizedBox(height: AppTheme.navBarClearance(context))),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

    return kIsWeb ? content : SafeArea(bottom: false, child: content);
  }

  // ═════════════════════════════════════════════════════════════════
  // DATE-GROUPED ARTICLE LIST
  // ═════════════════════════════════════════════════════════════════

  /// Flattens the date -> source -> article hierarchy into a single flat list
  /// so the feed can be rendered lazily by a SliverList. The previous version
  /// returned one nested Column inside a SliverToBoxAdapter, which forced every
  /// card - and every network image - to be built on the first frame.
  List<Widget> _buildEditorialFeedItems(List<Article> articles) {
    final grouped = <String, List<Article>>{};
    for (final article in articles) {
      final key = DateFormat('yyyy-MM-dd').format(article.publishedDate);
      grouped.putIfAbsent(key, () => []).add(article);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    final items = <Widget>[];
    for (var index = 0; index < sortedDates.length; index++) {
      final dateKey = sortedDates[index];
      final dayArticles = grouped[dateKey]!
        ..sort((a, b) {
          if (a.isTopNews != b.isTopNews) return a.isTopNews ? -1 : 1;
          return a.newspaper.compareTo(b.newspaper);
        });
      if (index > 0) items.add(const SizedBox(height: 8));
      items.add(_buildDateHeader(dateKey, dayArticles.length));
      for (final article in dayArticles) {
        items.add(EditorialStoryCard(article: article));
      }
    }
    return items;
  }

  Article? _selectLeadArticle(List<Article> articles) {
    if (articles.isEmpty) return null;
    final newest = articles.first.publishedDate;
    final newestDay = DateTime(newest.year, newest.month, newest.day);
    final sameDay = articles.where((article) {
      final date = article.publishedDate;
      return DateTime(date.year, date.month, date.day) == newestDay;
    }).toList();
    return sameDay.firstWhere(
      (article) => article.isTopNews,
      orElse: () => sameDay.first,
    );
  }

  List<DateTime> _availableQuickDates(List<Article> articles) {
    final unique = <String, DateTime>{};
    for (final article in articles) {
      final date = article.publishedDate;
      final day = DateTime(date.year, date.month, date.day);
      unique[DateFormat('yyyy-MM-dd').format(day)] = day;
    }
    final dates = unique.values.toList()..sort((a, b) => b.compareTo(a));
    return dates.take(7).toList();
  }

  bool _isQuickDateSelected(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    return _selectedDateFrom == key && _selectedDateTo == key;
  }

  void _toggleQuickDate(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final selected = _isQuickDateSelected(date);
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDateFrom = selected ? null : key;
      _selectedDateTo = selected ? null : key;
    });
  }

  Widget _buildQuickDateStrip(List<DateTime> dates) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final date = dates[index];
          final selected = _isQuickDateSelected(date);
          return GestureDetector(
            onTap: () => _toggleQuickDate(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primaryColor
                    : AppTheme.card(context).withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppTheme.primaryColor
                      : AppTheme.divider(context).withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    index == 0 ? 'LATEST' : DateFormat('EEE').format(date).toUpperCase(),
                    style: AppFonts.inter(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: selected ? Colors.white70 : AppTheme.textT(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d MMM').format(date),
                    style: AppFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppTheme.textP(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _briefingSubtitle(List<Article> articles) {
    if (articles.isEmpty) return 'Live UPSC current affairs';
    final latest = articles.first.publishedDate;
    return '${DateFormat('EEEE, d MMMM').format(latest)} · ${articles.length} ${articles.length == 1 ? 'story' : 'stories'}';
  }

  Widget _buildBriefingOverview(List<Article> articles) {
    final sources = articles
        .map((article) => article.newspaper.trim())
        .where((source) => source.isNotEmpty)
        .toSet();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.auto_awesome_rounded, size: 19, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your UPSC briefing',
                  style: AppFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textP(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${articles.length} ${articles.length == 1 ? 'story' : 'stories'} from ${sources.isEmpty ? 'the daily feed' : '${sources.length} ${sources.length == 1 ? 'source' : 'sources'}'}',
                  style: AppFonts.inter(fontSize: 10.5, color: AppTheme.textS(context)),
                ),
              ],
            ),
          ),
          Icon(Icons.swipe_down_rounded, size: 18, color: AppTheme.textT(context)),
        ],
      ),
    );
  }

  String _dateLabel(String dateKey) {
    final date = DateTime.parse(dateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    final formatted = DateFormat('d MMMM yyyy').format(date);
    if (diff == 0) return 'Today — $formatted';
    if (diff == 1) return 'Yesterday — $formatted';
    return DateFormat('EEEE, d MMMM yyyy').format(date);
  }

  Widget _buildDateHeader(String dateKey, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _dateLabel(dateKey),
              style: AppFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppTheme.textP(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: AppFonts.inter(
                fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  /// Skeleton shaped like the real card (cover + headline + deck + meta) so the
  /// layout does not jump when content arrives.
  Widget _buildShimmerCard(bool dark) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      child: Container(
        decoration: AppTheme.premiumCard(context),
        clipBehavior: Clip.antiAlias,
        child: Shimmer.fromColors(
          baseColor: dark ? const Color(0xFF1C2333) : const Color(0xFFEDEFF3),
          highlightColor: dark ? const Color(0xFF2A3348) : const Color(0xFFF8FAFC),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 152, width: double.infinity, color: Colors.white),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 14, 15, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(double.infinity, 14),
                    bar(200, 14),
                    const SizedBox(height: 4),
                    bar(double.infinity, 10),
                    bar(150, 10),
                    const SizedBox(height: 6),
                    Row(children: [bar(56, 16), const SizedBox(width: 8), bar(72, 16)]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveNewsCard(Map<String, dynamic> item, bool dark) {
    final category = item['category'] as String? ?? 'General';
    final source = item['source'] as String? ?? '';
    final dateStr = item['dateStr'] as String? ?? '';
    final title = item['title'] as String? ?? '';
    final url = item['url'] as String? ?? '';
    final categoryColor = _getLiveCategoryColor(category);

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showLiveNewsDetail(item);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.withValues(alpha: 0.15),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(category, style: AppFonts.inter(
                        fontSize: 9, fontWeight: FontWeight.w700, color: categoryColor,
                      )),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.language_rounded, size: 9, color: Colors.green.shade700),
                          const SizedBox(width: 2),
                          Text('Web', style: AppFonts.inter(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (url.isNotEmpty)
                      GestureDetector(
                        onTap: () async {
                          final uri = Uri.tryParse(url);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: const Icon(Icons.open_in_new_rounded, size: 14, color: AppTheme.primaryColor),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(title, style: AppFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppTheme.textP(context), height: 1.4,
                  // 3, not 4: the Expanded only affords three lines at this card
                  // height, so a fourth was rendered and then clipped mid-word
                  // instead of ellipsising.
                  ), maxLines: 3, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 11, color: AppTheme.textT(context)),
                    const SizedBox(width: 4),
                    Text(dateStr, style: AppFonts.inter(fontSize: 9, color: AppTheme.textT(context))),
                    if (source.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('• $source', style: AppFonts.inter(
                          fontSize: 9, color: AppTheme.textT(context),
                        ), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLiveNewsDetail(Map<String, dynamic> item) {
    final category = item['category'] as String? ?? 'General';
    final categoryColor = _getLiveCategoryColor(category);
    final url = item['url'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(category, style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: categoryColor)),
                  ),
                  const SizedBox(width: 8),
                  if ((item['source'] as String? ?? '').isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(item['source'] ?? '', style: AppFonts.inter(fontSize: 11, color: AppTheme.textS(ctx))),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(item['title'] ?? '', style: AppFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(item['dateStr'] ?? '', style: AppFonts.inter(fontSize: 12, color: AppTheme.textS(ctx))),
              const SizedBox(height: 16),
              if ((item['summary'] as String? ?? '').isNotEmpty &&
                  item['summary'] != item['title'])
                Text(item['summary'] ?? '', style: AppFonts.inter(fontSize: 14, height: 1.7, color: AppTheme.textP(ctx))),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.school_rounded, size: 16, color: AppTheme.primaryColor),
                        const SizedBox(width: 6),
                        Text('UPSC Relevance', style: AppFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Category: $category', style: AppFonts.inter(fontSize: 13, height: 1.5)),
                    const SizedBox(height: 4),
                    Text('This topic is relevant for UPSC ${_getRelevantPaper(category)} preparation.',
                        style: AppFonts.inter(fontSize: 13, height: 1.5, color: AppTheme.textS(ctx))),
                  ],
                ),
              ),
              if (url.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(url);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Read Full Article'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Color _getLiveCategoryColor(String category) {
    switch (category) {
      case 'Polity': return Colors.blue.shade700;
      case 'Economy': return Colors.green.shade700;
      case 'International': return Colors.purple.shade700;
      case 'Environment': return Colors.teal.shade700;
      case 'Science & Tech': return Colors.orange.shade700;
      case 'Social Issues': return Colors.pink.shade700;
      case 'Government Schemes': return Colors.indigo.shade700;
      default: return Colors.blueGrey.shade600;
    }
  }

  String _getRelevantPaper(String category) {
    switch (category) {
      case 'Polity': return 'GS-II (Polity & Governance)';
      case 'Economy': return 'GS-III (Economy)';
      case 'International': return 'GS-II (International Relations)';
      case 'Environment': return 'GS-III (Environment & Ecology)';
      case 'Science & Tech': return 'GS-III (Science & Technology)';
      case 'Social Issues': return 'GS-I (Society) & GS-II';
      case 'Government Schemes': return 'GS-II (Governance & Welfare)';
      default: return 'General Studies';
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // FILTER HELPERS
  // ═════════════════════════════════════════════════════════════════

  String _formatDateLabel(String date) {
    final parts = date.split('-');
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${int.parse(parts[2])} ${months[int.parse(parts[1])]} ${parts[0]}';
  }

  String _buildDateRangeLabel() {
    if (_selectedDateFrom != null && _selectedDateTo != null) {
      return '${_formatDateLabel(_selectedDateFrom!)} — ${_formatDateLabel(_selectedDateTo!)}';
    } else if (_selectedDateFrom != null) {
      return 'From ${_formatDateLabel(_selectedDateFrom!)}';
    } else {
      return 'Until ${_formatDateLabel(_selectedDateTo!)}';
    }
  }

  Widget _buildFilterTag({
    required IconData icon,
    required String label,
    required VoidCallback onRemove,
    required bool dark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.primaryColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onRemove();
            },
            child: const Icon(Icons.close_rounded, size: 14, color: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // FILTER BOTTOM SHEET
  // ═════════════════════════════════════════════════════════════════

  void _showFilterSheet(BuildContext context, bool dark) {
    final articles = context.read<ArticlesProvider>();

    // Collect newspapers
    final newspapers = <String>{};
    for (final a in articles.allArticles) {
      if (a.newspaper.isNotEmpty) newspapers.add(a.newspaper);
    }
    final newspaperList = newspapers.toList()..sort();

    // Collect available dates for highlighting in calendar
    final availableDates = <DateTime>{};
    for (final a in articles.allArticles) {
      availableDates.add(DateTime(a.publishedDate.year, a.publishedDate.month, a.publishedDate.day));
    }

    String? tempNewspaper = _selectedNewspaper;
    DateTime? tempDateFrom = _selectedDateFrom != null
        ? DateTime.tryParse(_selectedDateFrom!)
        : null;
    DateTime? tempDateTo = _selectedDateTo != null
        ? DateTime.tryParse(_selectedDateTo!)
        : null;
    String? activePickerField; // 'from' or 'to'
    late DateTime calendarMonth;
    calendarMonth = tempDateFrom ?? tempDateTo ?? DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final sheetDark = AppTheme.isDark(ctx);
            final today = DateTime.now();

            Widget buildCalendar() {
              final firstDay = DateTime(calendarMonth.year, calendarMonth.month, 1);
              final lastDay = DateTime(calendarMonth.year, calendarMonth.month + 1, 0);
              final startWeekday = firstDay.weekday;
              final daysInMonth = lastDay.day;
              final weeks = ((daysInMonth + startWeekday - 1) / 7).ceil();

              return AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Month navigation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setSheetState(() {
                              calendarMonth = DateTime(calendarMonth.year, calendarMonth.month - 1);
                            });
                          },
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: (sheetDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.chevron_left_rounded, color: AppTheme.textS(ctx), size: 20),
                          ),
                        ),
                        Text(
                          '${_monthName(calendarMonth.month)} ${calendarMonth.year}',
                          style: AppFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textP(ctx)),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setSheetState(() {
                              calendarMonth = DateTime(calendarMonth.year, calendarMonth.month + 1);
                            });
                          },
                          child: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: (sheetDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.chevron_right_rounded, color: AppTheme.textS(ctx), size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Weekday headers
                    Row(
                      children: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
                          .map((d) => Expanded(
                                child: Center(
                                  child: Text(d,
                                      style: AppFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textT(ctx))),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 6),

                    // Day grid
                    ...List.generate(weeks, (week) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: List.generate(7, (weekday) {
                            final dayNum = week * 7 + weekday + 1 - (startWeekday - 1);
                            if (dayNum < 1 || dayNum > daysInMonth) {
                              return const Expanded(child: SizedBox(height: 36));
                            }

                            final date = DateTime(calendarMonth.year, calendarMonth.month, dayNum);
                            final hasArticles = availableDates.contains(date);
                            final isFromDate = tempDateFrom != null &&
                                tempDateFrom!.year == date.year &&
                                tempDateFrom!.month == date.month &&
                                tempDateFrom!.day == date.day;
                            final isToDate = tempDateTo != null &&
                                tempDateTo!.year == date.year &&
                                tempDateTo!.month == date.month &&
                                tempDateTo!.day == date.day;
                            final isInRange = tempDateFrom != null && tempDateTo != null &&
                                date.isAfter(tempDateFrom!) && date.isBefore(tempDateTo!);
                            final isSelected = isFromDate || isToDate;
                            final isToday = date.year == today.year &&
                                date.month == today.month &&
                                date.day == today.day;

                            return Expanded(
                              child: GestureDetector(
                                onTap: hasArticles
                                    ? () {
                                        HapticFeedback.selectionClick();
                                        setSheetState(() {
                                          if (activePickerField == 'from') {
                                            tempDateFrom = isFromDate ? null : date;
                                            if (tempDateTo != null && tempDateFrom != null && tempDateFrom!.isAfter(tempDateTo!)) {
                                              tempDateTo = null;
                                            }
                                          } else if (activePickerField == 'to') {
                                            tempDateTo = isToDate ? null : date;
                                            if (tempDateFrom != null && tempDateTo != null && tempDateTo!.isBefore(tempDateFrom!)) {
                                              tempDateFrom = null;
                                            }
                                          }
                                        });
                                      }
                                    : null,
                                child: Container(
                                  height: 36,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                        : isInRange
                                            ? AppTheme.primaryColor.withValues(alpha: 0.10)
                                            : null,
                                    borderRadius: BorderRadius.circular(8),
                                    border: isToday && !isSelected
                                        ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.4), width: 1)
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$dayNum',
                                        style: AppFonts.inter(
                                          fontSize: 13,
                                          fontWeight: isSelected || isToday ? FontWeight.w600 : FontWeight.w400,
                                          color: isSelected
                                              ? Colors.white
                                              : hasArticles
                                                  ? AppTheme.textP(ctx)
                                                  : AppTheme.textT(ctx).withValues(alpha: 0.3),
                                        ),
                                      ),
                                      if (hasArticles && !isSelected)
                                        Container(
                                          width: 4, height: 4,
                                          margin: const EdgeInsets.only(top: 1),
                                          decoration: const BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }

            return Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.72),
              decoration: BoxDecoration(
                color: sheetDark ? const Color(0xFF1A1A2E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  const SizedBox(height: 10),
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: (sheetDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text(
                          'Filters',
                          style: AppFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textP(ctx)),
                        ),
                        const Spacer(),
                        if (tempNewspaper != null || tempDateFrom != null || tempDateTo != null)
                          GestureDetector(
                            onTap: () {
                              setSheetState(() {
                                tempNewspaper = null;
                                tempDateFrom = null;
                                tempDateTo = null;
                                activePickerField = null;
                              });
                            },
                            child: Text(
                              'Reset',
                              style: AppFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textT(ctx)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: (sheetDark ? Colors.white : Colors.black).withValues(alpha: 0.06)),
                  const SizedBox(height: 16),

                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Newspaper section ──
                          if (newspaperList.isNotEmpty) ...[
                            Text(
                              'SOURCE',
                              style: AppFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textT(ctx), letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: newspaperList.map((paper) {
                                final isSelected = tempNewspaper == paper;
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setSheetState(() => tempNewspaper = isSelected ? null : paper);
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppTheme.primaryColor.withValues(alpha: 0.12)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppTheme.primaryColor
                                            : (sheetDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.2)),
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Text(
                                      paper,
                                      style: AppFonts.inter(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                        color: isSelected ? AppTheme.primaryColor : AppTheme.textP(ctx),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // ── Date range section ── Two fields: From / To
                          if (availableDates.isNotEmpty) ...[
                            Text(
                              'DATE RANGE',
                              style: AppFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textT(ctx), letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                // FROM field
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setSheetState(() {
                                        activePickerField = activePickerField == 'from' ? null : 'from';
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: activePickerField == 'from'
                                            ? AppTheme.primaryColor.withValues(alpha: 0.06)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: activePickerField == 'from' || tempDateFrom != null
                                              ? AppTheme.primaryColor.withValues(alpha: 0.5)
                                              : (sheetDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.2)),
                                          width: activePickerField == 'from' ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'From',
                                            style: AppFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textT(ctx), letterSpacing: 0.3),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.calendar_today_rounded, size: 14,
                                                  color: tempDateFrom != null ? AppTheme.primaryColor : AppTheme.textT(ctx)),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  tempDateFrom != null
                                                      ? _formatDateLabel('${tempDateFrom!.year}-${tempDateFrom!.month.toString().padLeft(2, '0')}-${tempDateFrom!.day.toString().padLeft(2, '0')}')
                                                      : 'Start date',
                                                  style: AppFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: tempDateFrom != null ? FontWeight.w600 : FontWeight.w400,
                                                    color: tempDateFrom != null ? AppTheme.textP(ctx) : AppTheme.textT(ctx),
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (tempDateFrom != null)
                                                GestureDetector(
                                                  onTap: () {
                                                    HapticFeedback.selectionClick();
                                                    setSheetState(() => tempDateFrom = null);
                                                  },
                                                  child: Icon(Icons.close_rounded, size: 16, color: AppTheme.textT(ctx)),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // TO field
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      setSheetState(() {
                                        activePickerField = activePickerField == 'to' ? null : 'to';
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: activePickerField == 'to'
                                            ? AppTheme.primaryColor.withValues(alpha: 0.06)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: activePickerField == 'to' || tempDateTo != null
                                              ? AppTheme.primaryColor.withValues(alpha: 0.5)
                                              : (sheetDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.2)),
                                          width: activePickerField == 'to' ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'To',
                                            style: AppFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textT(ctx), letterSpacing: 0.3),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.calendar_today_rounded, size: 14,
                                                  color: tempDateTo != null ? AppTheme.primaryColor : AppTheme.textT(ctx)),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  tempDateTo != null
                                                      ? _formatDateLabel('${tempDateTo!.year}-${tempDateTo!.month.toString().padLeft(2, '0')}-${tempDateTo!.day.toString().padLeft(2, '0')}')
                                                      : 'End date',
                                                  style: AppFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: tempDateTo != null ? FontWeight.w600 : FontWeight.w400,
                                                    color: tempDateTo != null ? AppTheme.textP(ctx) : AppTheme.textT(ctx),
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (tempDateTo != null)
                                                GestureDetector(
                                                  onTap: () {
                                                    HapticFeedback.selectionClick();
                                                    setSheetState(() => tempDateTo = null);
                                                  },
                                                  child: Icon(Icons.close_rounded, size: 16, color: AppTheme.textT(ctx)),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (activePickerField != null) buildCalendar(),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Apply button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedNewspaper = tempNewspaper;
                            if (tempDateFrom != null) {
                              _selectedDateFrom = '${tempDateFrom!.year}-${tempDateFrom!.month.toString().padLeft(2, '0')}-${tempDateFrom!.day.toString().padLeft(2, '0')}';
                            } else {
                              _selectedDateFrom = null;
                            }
                            if (tempDateTo != null) {
                              _selectedDateTo = '${tempDateTo!.year}-${tempDateTo!.month.toString().padLeft(2, '0')}-${tempDateTo!.day.toString().padLeft(2, '0')}';
                            } else {
                              _selectedDateTo = null;
                            }
                          });
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text(
                          'Apply',
                          style: AppFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _monthName(int month) {
    const names = ['', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    return names[month];
  }
}
