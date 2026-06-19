import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../models/article.dart';
import '../../providers/bookmarks_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/articles_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// ArticleDetailScreen — Full article view with glassmorphic header,
/// key points, flowchart, analysis, mnemonic, and related articles.
/// ──────────────────────────────────────────────────────────────────────────────
class ArticleDetailScreen extends StatefulWidget {
  const ArticleDetailScreen({super.key});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  late ScrollController _scrollCtrl;
  bool _markedRead = false;
  final ValueNotifier<double> _readProgress = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max > 0) {
      final newProgress = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
      if ((newProgress - _readProgress.value).abs() > 0.02) {
        _readProgress.value = newProgress;
      }
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _readProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final articlesProvider = context.read<ArticlesProvider>();

    // Handle null route (direct instantiation without Navigator)
    if (args == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.article_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('No article data', style: GoogleFonts.inter(color: Colors.grey)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Support both Article object and String ID arguments
    late final Article article;
    if (args is Article) {
      article = args;
    } else if (args is String) {
      final found = articlesProvider.getArticleById(args);
      if (found == null) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.article_outlined, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text('Article not found', style: GoogleFonts.inter(color: Colors.grey)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        );
      }
      article = found;
    } else {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text('Invalid article data', style: GoogleFonts.inter(color: Colors.grey)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final bookmarks = context.watch<BookmarksProvider>();
    final auth = context.watch<AuthProvider>();
    final progress = context.watch<DailyProgressProvider>();
    final dark = AppTheme.isDark(context);
    final isBookmarked = bookmarks.isBookmarked(article.id);

    // Mark article as read (only once per screen visit)
    if (!_markedRead) {
      _markedRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) progress.markArticleRead(article.id);
      });
    }

    final relatedArticles = articlesProvider.getRelatedArticles(article);

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGradient(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Collapsing app bar with hero image
            SliverAppBar(
              expandedHeight: 280,
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: _glassBackBtn(context),
              actions: [
                _glassActionBtn(Icons.share_rounded, () {
                  HapticFeedback.lightImpact();
                  Share.share('${article.title}\n\nRead on UPSC Daily Edge');
                }),
                _glassActionBtn(
                  isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                  () {
                    HapticFeedback.mediumImpact();
                    if (!auth.isLoggedIn) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Please sign in to bookmark articles'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                      return;
                    }
                    if (auth.firebaseUser != null) {
                      bookmarks.toggleBookmark(article.id);
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(isBookmarked ? Icons.bookmark_remove_rounded : Icons.bookmark_added_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(isBookmarked ? 'Removed from bookmarks' : 'Saved to bookmarks'),
                            ],
                          ),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          margin: const EdgeInsets.all(16),
                        ),
                      );
                    }
                  },
                  color: isBookmarked ? AppTheme.primaryColor : null,
                ),
                const SizedBox(width: 8),
              ],
              // Reading progress indicator
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: ValueListenableBuilder<double>(
                  valueListenable: _readProgress,
                  builder: (_, progress, __) => AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    height: 3,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Hero image
                    CachedNetworkImage(
                      imageUrl: article.imageUrl.isNotEmpty
                          ? article.imageUrl
                          : AppImages.categoryImage(article.categoryTags.isNotEmpty ? article.categoryTags.first : null),
                      fit: BoxFit.cover,
                      memCacheWidth: 600,
                      placeholder: (_, __) => Shimmer.fromColors(
                        baseColor: dark ? Colors.grey.shade800 : Colors.grey.shade200,
                        highlightColor: dark ? Colors.grey.shade700 : Colors.grey.shade100,
                        child: Container(color: Colors.white),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _categoryColor(article.categoryTags.isNotEmpty ? article.categoryTags.first : 'General'),
                              _categoryColor(article.categoryTags.isNotEmpty ? article.categoryTags.first : 'General').withValues(alpha: 0.3),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    // Gradient overlay for readability
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.3),
                            Colors.black.withValues(alpha: 0.65),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                    // Content overlaid on image
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _imageTag(article.categoryTags.isNotEmpty ? article.categoryTags.first : 'General', _categoryColor(article.categoryTags.isNotEmpty ? article.categoryTags.first : 'General')),
                                if (article.newspaper.isNotEmpty)
                                  _imageTag(article.newspaper, AppTheme.accentViolet),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              article.title,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 22, fontWeight: FontWeight.w800,
                                color: Colors.white, height: 1.3,
                                shadows: [
                                  Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8),
                                ],
                              ),
                              maxLines: 3, overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // UPSC Relevance
                    if (article.upscPaper.isNotEmpty || article.examRelevance.isNotEmpty)
                      _infoBar(article, dark),

                    // Source URL button
                    if (article.sourceUrl.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final uri = Uri.tryParse(article.sourceUrl);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.open_in_new_rounded, size: 16, color: AppTheme.accentTeal),
                              const SizedBox(width: 8),
                              Text(
                                'Read Original on ${article.newspaper.isNotEmpty ? article.newspaper : "Source"}',
                                style: GoogleFonts.inter(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: AppTheme.accentTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Summary
                    if (article.summary.isNotEmpty) ...[
                      _sectionTitle('Summary'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          article.summary,
                          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textP(context), height: 1.7),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Content
                    if (article.content.isNotEmpty) ...[
                      _sectionTitle('Full Analysis'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          article.content,
                          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textP(context), height: 1.7),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Key Points
                    if (article.keyPoints.isNotEmpty) ...[
                      _sectionTitle('Key Points'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: article.keyPoints.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24, height: 24,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Center(child: Text('${e.key + 1}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryColor))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(e.value, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.5))),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Short Notes
                    if (article.shortNotes.isNotEmpty) ...[
                      _sectionTitle('Quick Notes'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: article.shortNotes.map((n) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.circle, size: 6, color: AppTheme.primaryColor),
                                const SizedBox(width: 10),
                                Expanded(child: Text(n, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.5))),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Syllabus Mapping
                    if (article.syllabusMapping.isNotEmpty) ...[
                      _sectionTitle('UPSC Syllabus Mapping'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.accentViolet.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.account_tree_rounded, size: 18, color: AppTheme.accentViolet),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                article.syllabusMapping,
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentViolet, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Previous Year Questions
                    if (article.previousYearQs.isNotEmpty) ...[
                      _sectionTitle('Previous Year Questions'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: article.previousYearQs.map((q) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.history_edu_rounded, size: 16, color: AppTheme.warningOrange),
                                const SizedBox(width: 10),
                                Expanded(child: Text(q, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.5))),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Key Terms & Definitions
                    if (article.keyTerms.isNotEmpty) ...[
                      _sectionTitle('Key Terms'),
                      const SizedBox(height: 8),
                      ...article.keyTerms.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                              const SizedBox(height: 4),
                              Text(e.value, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context), height: 1.5)),
                            ],
                          ),
                        ),
                      )),
                      const SizedBox(height: 12),
                    ],

                    // Constitutional/Legal Basis
                    if (article.constitutionalBasis.isNotEmpty) ...[
                      _sectionTitle('Constitutional Basis'),
                      const SizedBox(height: 8),
                      GlassCard(
                        color: const Color(0xFFFFF3E0),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.gavel_rounded, size: 20, color: Color(0xFFE65100)),
                            const SizedBox(width: 12),
                            Expanded(child: Text(article.constitutionalBasis, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFBF360C), height: 1.6))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Government Scheme
                    if (article.governmentScheme.isNotEmpty) ...[
                      _sectionTitle('Related Government Scheme'),
                      const SizedBox(height: 8),
                      GlassCard(
                        color: const Color(0xFFE8F5E9),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.policy_rounded, size: 20, color: AppTheme.successGreen),
                            const SizedBox(width: 12),
                            Expanded(child: Text(article.governmentScheme, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF1B5E20), height: 1.6))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Editorial Opinion
                    if (article.editorialOpinion.isNotEmpty) ...[
                      _sectionTitle('Editorial Perspective'),
                      const SizedBox(height: 8),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.edit_note_rounded, size: 20, color: AppTheme.accentViolet),
                            const SizedBox(width: 12),
                            Expanded(child: Text(article.editorialOpinion, style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: AppTheme.textP(context), height: 1.6))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Answer Framework
                    if (article.answerFramework.isNotEmpty) ...[
                      _sectionTitle('Mains Answer Framework'),
                      const SizedBox(height: 8),
                      GlassCard(
                        gradient: LinearGradient(
                          colors: [AppTheme.primaryColor.withValues(alpha: 0.05), AppTheme.accentViolet.withValues(alpha: 0.05)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.draw_rounded, size: 18, color: AppTheme.primaryColor),
                                const SizedBox(width: 8),
                                Text('How to structure your answer', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(article.answerFramework, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.7)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Flowchart
                    if (article.flowchartSteps.isNotEmpty) ...[
                      _sectionTitle('Flowchart'),
                      const SizedBox(height: 8),
                      ...article.flowchartSteps.asMap().entries.map((e) => _flowchartStep(context, e.key, e.value, e.key == article.flowchartSteps.length - 1)),
                      const SizedBox(height: 20),
                    ],

                    // Analysis Note
                    if (article.analysisNote.isNotEmpty) ...[
                      _sectionTitle('Analysis'),
                      const SizedBox(height: 8),
                      GlassCard(
                        gradient: AppTheme.heroGradient,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.analytics_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Text(article.analysisNote, style: GoogleFonts.inter(fontSize: 13, color: Colors.white, height: 1.6))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Mnemonic
                    if (article.mnemonic.isNotEmpty) ...[
                      _sectionTitle('Memory Aid'),
                      const SizedBox(height: 8),
                      GlassCard(
                        color: AppTheme.pastelMint.withValues(alpha: 0.5),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Image.asset('assets/flaticon_pngs/brain.png', width: 24, height: 24),
                            const SizedBox(width: 12),
                            Expanded(child: Text(article.mnemonic, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryDark, height: 1.5))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Related Topics
                    if (article.relatedTopics.isNotEmpty) ...[
                      _sectionTitle('Related Topics'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: article.relatedTopics.map((t) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.pastelLavender.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(t, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.accentViolet)),
                        )).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Related Articles
                    if (relatedArticles.isNotEmpty) ...[
                      _sectionTitle('Related Articles'),
                      const SizedBox(height: 8),
                      ...relatedArticles.take(3).map((a) => GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pushNamed(context, '/article-detail', arguments: a);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                // Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 56, height: 56,
                                    child: CachedNetworkImage(
                                      imageUrl: a.imageUrl.isNotEmpty
                                          ? a.imageUrl
                                          : AppImages.categoryImage(a.categoryTags.isNotEmpty ? a.categoryTags.first : null),
                                      fit: BoxFit.cover,
                                      placeholder: (_, __) => Container(color: Colors.grey.shade200),
                                      errorWidget: (_, __, ___) => Container(
                                        color: _categoryColor(a.categoryTags.isNotEmpty ? a.categoryTags.first : 'General').withValues(alpha: 0.1),
                                        child: Icon(Icons.article_rounded, size: 18, color: _categoryColor(a.categoryTags.isNotEmpty ? a.categoryTags.first : 'General')),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (a.categoryTags.isNotEmpty)
                                        Text(
                                          a.categoryTags.first,
                                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _categoryColor(a.categoryTags.first)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: 2),
                                      Text(a.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textP(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.textT(context)),
                              ],
                            ),
                          ),
                        ),
                      )),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassBackBtn(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pop(context);
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassActionBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _imageTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
      ),
      child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _infoBar(Article article, bool dark) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (article.upscPaper.isNotEmpty) ...[
            Icon(Icons.school_rounded, size: 16, color: AppTheme.primaryColor),
            const SizedBox(width: 6),
            Flexible(child: Text(article.upscPaper, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 16),
          ],
          if (article.examRelevance.isNotEmpty) ...[
            Icon(Icons.star_rounded, size: 16, color: AppTheme.accentViolet),
            const SizedBox(width: 6),
            Flexible(child: Text(article.examRelevance, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accentViolet), overflow: TextOverflow.ellipsis)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textP(context)), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _flowchartStep(BuildContext context, int index, String text, bool isLast) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text('${index + 1}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
            ),
            if (!isLast) Container(width: 2, height: 30, color: AppTheme.primaryColor.withValues(alpha: 0.2)),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GlassCard(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 4),
            child: Text(text, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.5)),
          ),
        ),
      ],
    );
  }

  Color _categoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'polity': return AppTheme.accentViolet;
      case 'economy': return AppTheme.primaryColor;
      case 'environment': return AppTheme.successGreen;
      case 'science': return const Color(0xFF448AFF);
      case 'international': return const Color(0xFFFF6B6B);
      default: return AppTheme.accentViolet;
    }
  }
}
