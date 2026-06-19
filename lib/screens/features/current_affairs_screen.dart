import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/firestore_content_service.dart';
import '../../services/news_api_service.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// CurrentAffairsScreen — Weekly & Monthly current affairs compilation
/// organized by topic for quick revision before exams.
/// Now includes a "Live News" tab that auto-fetches UPSC news from the internet.
/// ──────────────────────────────────────────────────────────────────────────────
class CurrentAffairsScreen extends StatefulWidget {
  const CurrentAffairsScreen({super.key});

  @override
  State<CurrentAffairsScreen> createState() => _CurrentAffairsScreenState();
}

class _CurrentAffairsScreenState extends State<CurrentAffairsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _selectedCategory = 'All';
  late Future<List<Map<String, dynamic>>> _dataFuture;
  late Future<List<Map<String, dynamic>>> _newsFuture;

  static const _categories = [
    'All', 'Polity', 'Economy', 'International', 'Environment',
    'Science & Tech', 'Social Issues', 'Government Schemes',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _dataFuture = FirestoreContentService.getCurrentAffairs();
    _newsFuture = NewsApiService.fetchLatestNews();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: 'Current Affairs',
      extendBodyBehindAppBar: false,
      bottom: TabBar(
        controller: _tabCtrl,
        indicatorColor: AppTheme.primaryColor,
        indicatorWeight: 3,
        labelColor: AppTheme.primaryColor,
        unselectedLabelColor: AppTheme.textS(context),
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(text: 'Live News'),
          Tab(text: 'This Week'),
          Tab(text: 'This Month'),
          Tab(text: 'Important'),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Category filter chips
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final selected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                    backgroundColor: AppTheme.isDark(context)
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.7),
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppTheme.primaryColor : AppTheme.textS(context),
                    ),
                    side: BorderSide(
                      color: selected ? AppTheme.primaryColor : Colors.transparent,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // Live News tab — fetched from free APIs
                _buildLiveNewsTab(),
                // Firestore-backed tabs
                _buildFirestoreTabFor('weekly'),
                _buildFirestoreTabFor('monthly'),
                _buildFirestoreTabFor('important'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveNewsTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _newsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset('assets/animations/loading.json', width: 120, height: 120),
                const SizedBox(height: 12),
                Text('Fetching latest UPSC news...',
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
              ],
            ),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 48, color: AppTheme.textT(context)),
                const SizedBox(height: 12),
                Text('Could not fetch news', style: GoogleFonts.inter(color: AppTheme.textS(context))),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => setState(() {
                    NewsApiService.clearCache();
                    _newsFuture = NewsApiService.fetchLatestNews(forceRefresh: true);
                  }),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final allNews = snap.data ?? [];
        final filtered = _selectedCategory == 'All'
            ? allNews
            : allNews.where((n) => n['category'] == _selectedCategory).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.newspaper_rounded, size: 48, color: AppTheme.textT(context)),
                const SizedBox(height: 12),
                Text(
                  _selectedCategory == 'All'
                      ? 'No news found. Pull to refresh.'
                      : 'No news in "$_selectedCategory"',
                  style: GoogleFonts.inter(color: AppTheme.textS(context)),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            NewsApiService.clearCache();
            final fresh = NewsApiService.fetchLatestNews(forceRefresh: true);
            setState(() => _newsFuture = fresh);
            await fresh;
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: filtered.length + 1, // +1 for header
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
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
                            Text('Live Updates', style: GoogleFonts.inter(
                              fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
                            )),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text('${filtered.length} articles',
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textT(context))),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() {
                          NewsApiService.clearCache();
                          _newsFuture = NewsApiService.fetchLatestNews(forceRefresh: true);
                        }),
                        child: Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                );
              }
              return _buildNewsCard(filtered[i - 1]);
            },
          ),
        );
      },
    );
  }

  Widget _buildFirestoreTabFor(String type) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dataFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120));
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.textT(context)),
                const SizedBox(height: 12),
                Text('Failed to load current affairs', style: GoogleFonts.inter(color: AppTheme.textS(context))),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => setState(() { _dataFuture = FirestoreContentService.getCurrentAffairs(); }),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        final all = snap.data ?? [];
        List<Map<String, dynamic>> items;
        switch (type) {
          case 'weekly': items = FirestoreContentService.getWeeklyAffairs(all); break;
          case 'monthly': items = FirestoreContentService.getMonthlyAffairs(all); break;
          case 'important': items = FirestoreContentService.getImportantAffairs(all); break;
          default: items = all;
        }
        return _buildAffairsList(items);
      },
    );
  }

  Widget _buildNewsCard(Map<String, dynamic> item) {
    final category = item['category'] as String? ?? 'General';
    final source = item['source'] as String? ?? '';
    final dateStr = item['dateStr'] as String? ?? '';
    final categoryColor = _getCategoryColor(category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedGlassCard(
        onTap: () {
          HapticFeedback.lightImpact();
          _showNewsDetail(item);
        },
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(category,
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: categoryColor)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.language_rounded, size: 10, color: Colors.green.shade700),
                      const SizedBox(width: 2),
                      Text('Web', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.green.shade700)),
                    ],
                  ),
                ),
                const Spacer(),
                if (source.isNotEmpty)
                  Flexible(
                    child: Text(source, style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textT(context)),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(item['title'] ?? '',
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context)),
                maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            if ((item['summary'] as String? ?? '').isNotEmpty && item['summary'] != item['title'])
              Text(item['summary'] ?? '',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context), height: 1.5),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 12, color: AppTheme.textT(context)),
                const SizedBox(width: 4),
                Text(dateStr, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textT(context))),
                const Spacer(),
                Icon(Icons.open_in_new_rounded, size: 12, color: AppTheme.primaryColor),
                const SizedBox(width: 4),
                Text('Tap to read', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primaryColor)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showNewsDetail(Map<String, dynamic> item) {
    final category = item['category'] as String? ?? 'General';
    final categoryColor = _getCategoryColor(category);
    final url = item['url'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
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
                    child: Text(category, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: categoryColor)),
                  ),
                  const SizedBox(width: 8),
                  if ((item['source'] as String? ?? '').isNotEmpty)
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(item['source'] ?? '', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(ctx)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(item['title'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(item['dateStr'] ?? '', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(ctx))),
              const SizedBox(height: 16),
              if ((item['summary'] as String? ?? '').isNotEmpty)
                Text(item['summary'] ?? '', style: GoogleFonts.inter(fontSize: 14, height: 1.7, color: AppTheme.textP(ctx))),
              const SizedBox(height: 20),
              // UPSC relevance hint
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
                        Icon(Icons.school_rounded, size: 16, color: AppTheme.primaryColor),
                        const SizedBox(width: 6),
                        Text('UPSC Relevance', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Category: $category', style: GoogleFonts.inter(fontSize: 13, height: 1.5)),
                    const SizedBox(height: 4),
                    Text('This topic is relevant for UPSC ${_getRelevantPaper(category)} preparation.',
                        style: GoogleFonts.inter(fontSize: 13, height: 1.5, color: AppTheme.textS(ctx))),
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

  Color _getCategoryColor(String category) {
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

  Widget _buildAffairsList(List<Map<String, dynamic>> items) {
    final filtered = _selectedCategory == 'All'
        ? items
        : items.where((i) => i['category'] == _selectedCategory).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 48, color: AppTheme.textT(context)),
            const SizedBox(height: 12),
            Text('No items in this category',
                style: GoogleFonts.inter(color: AppTheme.textS(context))),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: filtered.length,
      itemBuilder: (context, i) => _buildAffairCard(filtered[i]),
    );
  }

  Widget _buildAffairCard(Map<String, dynamic> item) {
    final color = FirestoreContentService.parseColor(item['colorHex'] as String?);
    final important = item['important'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedGlassCard(
        onTap: () {
          HapticFeedback.lightImpact();
          _showDetail(item);
        },
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(item['category'] ?? '',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                ),
                const SizedBox(width: 8),
                if (important)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.errorRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 10, color: AppTheme.errorRed),
                        const SizedBox(width: 2),
                        Text('Important', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.errorRed)),
                      ],
                    ),
                  ),
                const Spacer(),
                Text(item['date'] ?? '', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textT(context))),
              ],
            ),
            const SizedBox(height: 10),
            Text(item['title'] ?? '',
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context)),
                maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(item['summary'] ?? '',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context), height: 1.5),
                maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.visibility_rounded, size: 13, color: AppTheme.textT(context)),
                const SizedBox(width: 4),
                Text('Tap to read full analysis', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textT(context))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> item) {
    final color = FirestoreContentService.parseColor(item['colorHex'] as String?);
    final keyPoints = (item['keyPoints'] as List<dynamic>?)?.cast<String>() ?? [];
    final upscRelevance = item['upscRelevance'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(item['category'] ?? '', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
              ),
              const SizedBox(height: 12),
              Text(item['title'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(item['date'] ?? '', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(ctx))),
              const SizedBox(height: 16),
              Text(item['detail'] ?? '', style: GoogleFonts.inter(fontSize: 14, height: 1.7, color: AppTheme.textP(ctx))),
              const SizedBox(height: 20),
              if (keyPoints.isNotEmpty) ...[
                Text('Key Points for UPSC:', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                const SizedBox(height: 10),
                ...keyPoints.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 6, height: 6,
                        decoration: BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p, style: GoogleFonts.inter(fontSize: 13, height: 1.5))),
                    ],
                  ),
                )),
              ],
              const SizedBox(height: 16),
              if (upscRelevance.isNotEmpty) ...[
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
                          Icon(Icons.school_rounded, size: 16, color: AppTheme.primaryColor),
                          const SizedBox(width: 6),
                          Text('UPSC Relevance', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(upscRelevance, style: GoogleFonts.inter(fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
