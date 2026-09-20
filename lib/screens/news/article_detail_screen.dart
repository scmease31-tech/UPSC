import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/category_style.dart';
import '../../config/theme.dart';
import '../../design_system/frosted_scholar.dart';
import '../../models/article.dart';
import '../../providers/bookmarks_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/articles_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/article_thumbnail.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/rich_article_content.dart';

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
  double _textScale = 1.0;
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
              const Icon(Icons.article_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: FsSpace.md),
              Text('No article data', style: AppFonts.inter(color: Colors.grey)),
              const SizedBox(height: FsSpace.md),
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
                const Icon(Icons.article_outlined, size: 48, color: Colors.grey),
                const SizedBox(height: FsSpace.md),
                Text('Article not found', style: AppFonts.inter(color: Colors.grey)),
                const SizedBox(height: FsSpace.md),
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
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: FsSpace.md),
              Text('Invalid article data', style: AppFonts.inter(color: Colors.grey)),
              const SizedBox(height: FsSpace.md),
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

    return DecoratedBox(
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.control)),
                          margin: FsSpacing.screen,
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
                              const SizedBox(width: FsSpace.xs),
                              Text(isBookmarked ? 'Removed from bookmarks' : 'Saved to bookmarks'),
                            ],
                          ),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.control)),
                          margin: FsSpacing.screen,
                        ),
                      );
                    }
                  },
                  color: isBookmarked ? AppTheme.primaryColor : null,
                ),
                const SizedBox(width: FsSpace.xs),
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
                    // Hero image — falls back to generated subject artwork when
                    // the source ships no photo, so the header never looks broken.
                    ArticleThumbnail(
                      imageUrl: article.imageUrl,
                      title: article.title,
                      category: article.categoryTags.isNotEmpty ? article.categoryTags.first : '',
                      footnote: article.newspaper,
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
                            const SizedBox(height: FsSpace.md),
                            Text(
                              article.title,
                              style: AppFonts.plusJakartaSans(
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
                padding: FsSpacing.screen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // UPSC Relevance
                    if (article.upscPaper.isNotEmpty || article.examRelevance.isNotEmpty)
                      _infoBar(article, dark),

                    // Attribution for openly-licensed artwork we sourced
                    // ourselves (the publisher shipped none).
                    if (article.imageCredit.isNotEmpty) ...[
                      const SizedBox(height: FsSpace.xs),
                      GestureDetector(
                        onTap: article.imageCreditUrl.isEmpty
                            ? null
                            : () async {
                                final uri = Uri.tryParse(article.imageCreditUrl);
                                if (uri != null && await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                        child: Row(
                          children: [
                            Icon(Icons.photo_camera_outlined, size: 13, color: AppTheme.textT(context)),
                            const SizedBox(width: FsSpace.xxs),
                            Expanded(
                              child: Text(
                                'Image: ${article.imageCredit}',
                                style: AppFonts.inter(
                                  fontSize: 11,
                                  color: AppTheme.textT(context),
                                  decoration: article.imageCreditUrl.isEmpty
                                      ? null
                                      : TextDecoration.underline,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Source URL button
                    if (article.sourceUrl.isNotEmpty) ...[
                      const SizedBox(height: FsSpace.md),
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
                              const SizedBox(width: FsSpace.xs),
                              Text(
                                'Read Original on ${article.newspaper.isNotEmpty ? article.newspaper : "Source"}',
                                style: AppFonts.inter(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: AppTheme.accentTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: FsSpace.lg),

                    // Summary
                    if (article.summary.isNotEmpty) ...[
                      _sectionTitle('Summary'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        padding: FsSpacing.cardPadding,
                        child: Text(
                          article.summary,
                          style: AppFonts.inter(fontSize: 14, color: AppTheme.textP(context), height: 1.7),
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Content — rendered as a real reading layout (headings,
                    // bullets, paragraphs) instead of one undifferentiated block.
                    if (article.content.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(child: _sectionTitle('Full Analysis')),
                          _ReaderSizeControl(
                            scale: _textScale,
                            onChanged: (v) => setState(() => _textScale = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                        child: RichArticleContent(content: article.content, scale: _textScale),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Key Points
                    if (article.keyPoints.isNotEmpty) ...[
                      _sectionTitle('Key Points'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        padding: FsSpacing.cardPadding,
                        child: Column(
                          children: article.keyPoints.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: FsSpace.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24, height: 24,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(FsRadii.sm),
                                  ),
                                  child: Center(child: Text('${e.key + 1}', style: AppFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryColor))),
                                ),
                                const SizedBox(width: FsSpace.md),
                                Expanded(child: Text(e.value, style: AppFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.5))),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Short Notes
                    if (article.shortNotes.isNotEmpty) ...[
                      _sectionTitle('Quick Notes'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        padding: FsSpacing.cardPadding,
                        child: Column(
                          children: article.shortNotes.map((n) => Padding(
                            padding: const EdgeInsets.only(bottom: FsSpace.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.circle, size: 6, color: AppTheme.primaryColor),
                                const SizedBox(width: FsSpace.xs),
                                Expanded(child: Text(n, style: AppFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.5))),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Syllabus Mapping
                    if (article.syllabusMapping.isNotEmpty) ...[
                      _sectionTitle('UPSC Syllabus Mapping'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        padding: FsSpacing.cardPadding,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.accentViolet.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(FsRadii.sm),
                              ),
                              child: const Icon(Icons.account_tree_rounded, size: 18, color: AppTheme.accentViolet),
                            ),
                            const SizedBox(width: FsSpace.md),
                            Expanded(
                              child: Text(
                                article.syllabusMapping,
                                style: AppFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.accentViolet, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Previous Year Questions
                    if (article.previousYearQs.isNotEmpty) ...[
                      _sectionTitle('Previous Year Questions'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        padding: FsSpacing.cardPadding,
                        child: Column(
                          children: article.previousYearQs.map((q) => Padding(
                            padding: const EdgeInsets.only(bottom: FsSpace.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.history_edu_rounded, size: 16, color: AppTheme.warningOrange),
                                const SizedBox(width: FsSpace.xs),
                                Expanded(child: Text(q, style: AppFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.5))),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Key Terms & Definitions
                    if (article.keyTerms.isNotEmpty) ...[
                      _sectionTitle('Key Terms'),
                      const SizedBox(height: FsSpace.xs),
                      ...article.keyTerms.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: FsSpace.xs),
                        child: GlassCard(
                          padding: FsSpacing.cardPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.key, style: AppFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                              const SizedBox(height: FsSpace.xxs),
                              Text(e.value, style: AppFonts.inter(fontSize: 13, color: AppTheme.textS(context), height: 1.5)),
                            ],
                          ),
                        ),
                      )),
                      const SizedBox(height: FsSpace.md),
                    ],

                    // Constitutional/Legal Basis
                    if (article.constitutionalBasis.isNotEmpty) ...[
                      _sectionTitle('Constitutional Basis'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        color: const Color(0xFFFFF3E0),
                        padding: FsSpacing.cardPadding,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.gavel_rounded, size: 20, color: Color(0xFFE65100)),
                            const SizedBox(width: FsSpace.md),
                            Expanded(child: Text(article.constitutionalBasis, style: AppFonts.inter(fontSize: 13, color: const Color(0xFFBF360C), height: 1.6))),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Government Scheme
                    if (article.governmentScheme.isNotEmpty) ...[
                      _sectionTitle('Related Government Scheme'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        color: const Color(0xFFE8F5E9),
                        padding: FsSpacing.cardPadding,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.policy_rounded, size: 20, color: AppTheme.successGreen),
                            const SizedBox(width: FsSpace.md),
                            Expanded(child: Text(article.governmentScheme, style: AppFonts.inter(fontSize: 13, color: const Color(0xFF1B5E20), height: 1.6))),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Editorial Opinion
                    if (article.editorialOpinion.isNotEmpty) ...[
                      _sectionTitle('Editorial Perspective'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        padding: FsSpacing.cardPadding,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.edit_note_rounded, size: 20, color: AppTheme.accentViolet),
                            const SizedBox(width: FsSpace.md),
                            Expanded(child: Text(article.editorialOpinion, style: AppFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: AppTheme.textP(context), height: 1.6))),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Answer Framework
                    if (article.answerFramework.isNotEmpty) ...[
                      _sectionTitle('Mains Answer Framework'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        gradient: LinearGradient(
                          colors: [AppTheme.primaryColor.withValues(alpha: 0.05), AppTheme.accentViolet.withValues(alpha: 0.05)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        padding: FsSpacing.cardPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.draw_rounded, size: 18, color: AppTheme.primaryColor),
                                const SizedBox(width: FsSpace.xs),
                                Text('How to structure your answer', style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                              ],
                            ),
                            const SizedBox(height: FsSpace.md),
                            Text(article.answerFramework, style: AppFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.7)),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Flowchart
                    if (article.flowchartSteps.isNotEmpty) ...[
                      _sectionTitle('Flowchart'),
                      const SizedBox(height: FsSpace.xs),
                      ...article.flowchartSteps.asMap().entries.map((e) => _flowchartStep(context, e.key, e.value, e.key == article.flowchartSteps.length - 1)),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Analysis Note
                    if (article.analysisNote.isNotEmpty) ...[
                      _sectionTitle('Analysis'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        gradient: AppTheme.heroGradient,
                        padding: FsSpacing.cardPadding,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.analytics_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: FsSpace.md),
                            Expanded(child: Text(article.analysisNote, style: AppFonts.inter(fontSize: 13, color: Colors.white, height: 1.6))),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Mnemonic
                    if (article.mnemonic.isNotEmpty) ...[
                      _sectionTitle('Memory Aid'),
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        color: AppTheme.pastelMint.withValues(alpha: 0.5),
                        padding: FsSpacing.cardPadding,
                        child: Row(
                          children: [
                            Image.asset('assets/flaticon_pngs/brain.png', width: 24, height: 24),
                            const SizedBox(width: FsSpace.md),
                            Expanded(child: Text(article.mnemonic, style: AppFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryDark, height: 1.5))),
                          ],
                        ),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Related Topics
                    if (article.relatedTopics.isNotEmpty) ...[
                      _sectionTitle('Related Topics'),
                      const SizedBox(height: FsSpace.xs),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: article.relatedTopics.map((t) => Container(
                          padding: FsSpacing.chip,
                          decoration: BoxDecoration(
                            color: AppTheme.pastelLavender.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(FsRadii.sm),
                          ),
                          child: Text(t, style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.accentViolet)),
                        )).toList(),
                      ),
                      const SizedBox(height: FsSpace.lg),
                    ],

                    // Related Articles
                    if (relatedArticles.isNotEmpty) ...[
                      _sectionTitle('Related Articles'),
                      const SizedBox(height: FsSpace.xs),
                      ...relatedArticles.take(3).map((a) => GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pushNamed(context, '/article-detail', arguments: a);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: FsSpace.xs),
                          child: GlassCard(
                            padding: FsSpacing.cardPaddingTight,
                            child: Row(
                              children: [
                                // Thumbnail
                                ArticleThumbnail(
                                  imageUrl: a.imageUrl,
                                  title: a.title,
                                  category: a.categoryTags.isNotEmpty ? a.categoryTags.first : '',
                                  width: 56,
                                  height: 56,
                                  borderRadius: BorderRadius.circular(FsRadii.sm),
                                ),
                                const SizedBox(width: FsSpace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (a.categoryTags.isNotEmpty)
                                        Text(
                                          a.categoryTags.first,
                                          style: AppFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: _categoryColor(a.categoryTags.first)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      const SizedBox(height: FsSpace.xxs),
                                      Text(a.title, style: AppFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textP(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
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

                    const SizedBox(height: FsSpace.huge),
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
          borderRadius: BorderRadius.circular(FsRadii.control),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(FsRadii.control),
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
          borderRadius: BorderRadius.circular(FsRadii.control),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(FsRadii.control),
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
        borderRadius: BorderRadius.circular(FsRadii.sm),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
      ),
      child: Text(label, style: AppFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _infoBar(Article article, bool dark) {
    return GlassCard(
      padding: FsSpacing.listItem,
      child: Row(
        children: [
          if (article.upscPaper.isNotEmpty) ...[
            const Icon(Icons.school_rounded, size: 16, color: AppTheme.primaryColor),
            const SizedBox(width: FsSpace.xxs),
            Flexible(child: Text(article.upscPaper, style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 16),
          ],
          if (article.examRelevance.isNotEmpty) ...[
            const Icon(Icons.star_rounded, size: 16, color: AppTheme.accentViolet),
            const SizedBox(width: FsSpace.xxs),
            Flexible(child: Text(article.examRelevance, style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accentViolet), overflow: TextOverflow.ellipsis)),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(
      children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: FsSpace.xs),
        Expanded(child: Text(title, style: FsType.title(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
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
                borderRadius: BorderRadius.circular(FsRadii.sm),
              ),
              child: Center(child: Text('${index + 1}', style: AppFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
            ),
            if (!isLast) Container(width: 2, height: 30, color: AppTheme.primaryColor.withValues(alpha: 0.2)),
          ],
        ),
        const SizedBox(width: FsSpace.md),
        Expanded(
          child: GlassCard(
            padding: FsSpacing.cardPaddingTight,
            margin: const EdgeInsets.only(bottom: FsSpace.xxs),
            child: Text(text, style: AppFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.5)),
          ),
        ),
      ],
    );
  }

  Color _categoryColor(String? category) => CategoryStyle.of(category).color;
}

/// A− / A+ reader control for the article body.
class _ReaderSizeControl extends StatelessWidget {
  final double scale;
  final ValueChanged<double> onChanged;

  const _ReaderSizeControl({required this.scale, required this.onChanged});

  static const _steps = [0.9, 1.0, 1.15, 1.3];

  void _step(int direction) {
    var i = _steps.indexWhere((s) => (s - scale).abs() < 0.01);
    if (i < 0) i = 1;
    final next = (i + direction).clamp(0, _steps.length - 1);
    if (next != i) onChanged(_steps[next]);
  }

  @override
  Widget build(BuildContext context) {
    final atMin = (scale - _steps.first).abs() < 0.01;
    final atMax = (scale - _steps.last).abs() < 0.01;

    return Container(
      decoration: AppTheme.insetSurface(context, radius: 10),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(context, Icons.remove_rounded, atMin ? null : () => _step(-1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              'A',
              style: AppFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.textS(context),
              ),
            ),
          ),
          _btn(context, Icons.add_rounded, atMax ? null : () => _step(1)),
        ],
      ),
    );
  }

  Widget _btn(BuildContext context, IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap();
            },
      borderRadius: BorderRadius.circular(FsRadii.sm),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 16,
          color: onTap == null ? AppTheme.textT(context).withValues(alpha: 0.4) : AppTheme.primaryColor,
        ),
      ),
    );
  }
}
