import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';
import '../config/app_images.dart';
import '../models/article.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// ArticleCard — Glassmorphic article card with hero image, category badge,
/// newspaper source, UPSC paper tag, and smooth tap animation.
/// Now features a 16:9 CachedNetworkImage with shimmer loading.
/// ──────────────────────────────────────────────────────────────────────────────
class ArticleCard extends StatefulWidget {
  final Article article;
  final bool compact;
  final bool featured;

  const ArticleCard({
    super.key,
    required this.article,
    this.compact = false,
    this.featured = false,
  });

  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard> {
  bool _pressed = false;

  Article get article => widget.article;
  bool get compact => widget.compact;
  bool get featured => widget.featured;

  Color _categoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'polity': return AppTheme.accentViolet;
      case 'economy': return AppTheme.primaryColor;
      case 'environment': return AppTheme.successGreen;
      case 'science': return const Color(0xFF448AFF);
      case 'international': return const Color(0xFFFF6B6B);
      case 'social': return const Color(0xFFFF9800);
      case 'geography': return AppTheme.primaryDark;
      case 'history': return const Color(0xFF8D6E63);
      default: return AppTheme.accentViolet;
    }
  }

  Color _categoryBg(String? category) {
    switch (category?.toLowerCase()) {
      case 'polity': return AppTheme.pastelLavender;
      case 'economy': return AppTheme.pastelMint;
      case 'environment': return const Color(0xFFD1FAE5);
      case 'science': return AppTheme.pastelBlue;
      case 'international': return const Color(0xFFFFE4E4);
      case 'social': return AppTheme.pastelYellow;
      case 'geography': return const Color(0xFFCCFBF1);
      case 'history': return const Color(0xFFFFE4D6);
      default: return AppTheme.pastelLavender;
    }
  }

  String _resolveImageUrl() {
    if (article.imageUrl.isNotEmpty) return article.imageUrl;
    final cat = article.categoryTags.isNotEmpty ? article.categoryTags.first : null;
    return AppImages.categoryImage(cat);
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    final cat = article.categoryTags.isNotEmpty ? article.categoryTags.first : 'General';
    final catColor = _categoryColor(cat);
    final catBg = _categoryBg(cat);
    final imageUrl = _resolveImageUrl();

    if (featured) return _buildFeaturedCard(context, dark, cat, catColor, imageUrl);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () => Navigator.pushNamed(context, '/article-detail', arguments: article),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: dark ? AppTheme.darkCardBg.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.5),
          ),
          boxShadow: dark ? AppTheme.darkCardShadow : AppTheme.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Hero Image ──
                if (!compact)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        child: SizedBox(
                          height: 140,
                          width: double.infinity,
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,                            memCacheWidth: 400,                            placeholder: (_, __) => Shimmer.fromColors(
                              baseColor: dark ? Colors.grey.shade800 : Colors.grey.shade200,
                              highlightColor: dark ? Colors.grey.shade700 : Colors.grey.shade100,
                              child: Container(color: Colors.white),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [catColor.withValues(alpha: 0.3), catColor.withValues(alpha: 0.1)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Center(
                                child: Icon(Icons.article_rounded, size: 40, color: catColor.withValues(alpha: 0.3)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Gradient overlay on image
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                (dark ? AppTheme.darkCardBg : Colors.white).withValues(alpha: 0.9),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Category badge on image
                      Positioned(
                        top: 10, left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: (dark ? Colors.black : Colors.white).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
                            ],
                          ),
                          child: Text(
                            cat,
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: catColor),
                          ),
                        ),
                      ),
                      // Newspaper source badge
                      if (article.newspaper.isNotEmpty)
                        Positioned(
                          top: 10, right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.newspaper_rounded, size: 10, color: Colors.white.withValues(alpha: 0.9)),
                                const SizedBox(width: 4),
                                Text(
                                  article.newspaper,
                                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                // ── Text Content ──
                Padding(
                  padding: EdgeInsets.all(compact ? 12 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Compact mode: category row
                      if (compact) ...[
                        Row(
                          children: [
                            Container(
                              width: 4, height: 16,
                              decoration: BoxDecoration(color: catColor, borderRadius: BorderRadius.circular(2)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: dark ? catColor.withValues(alpha: 0.2) : catBg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(cat, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: catColor)),
                            ),
                            const Spacer(),
                            if (article.newspaper.isNotEmpty)
                              Flexible(
                                child: Text(article.newspaper, style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textT(context), fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Title
                      Text(
                        article.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: compact ? 14 : 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textP(context),
                          height: 1.3,
                        ),
                        maxLines: compact ? 2 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!compact && article.summary.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          article.summary,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textS(context),
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      SizedBox(height: compact ? 8 : 10),

                      // Bottom row
                      Row(
                        children: [
                          if (article.upscPaper.isNotEmpty) ...[
                            Flexible(
                              child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.school_rounded, size: 10, color: AppTheme.primaryColor),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                    article.upscPaper,
                                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  )),
                                ],
                              ),
                            )),
                            const SizedBox(width: 6),
                          ],
                          if (article.examRelevance.isNotEmpty)
                            Flexible(
                              child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.accentViolet.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.accentViolet.withValues(alpha: 0.15)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star_rounded, size: 10, color: AppTheme.accentViolet),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                    article.examRelevance,
                                    style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.accentViolet),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  )),
                                ],
                              ),
                            )),
                          const Spacer(),
                          // Time ago
                          Text(
                            _timeAgo(article.publishedDate),
                            style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textT(context)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: catColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.arrow_forward_rounded, size: 14, color: catColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Featured / large variant with image background and overlay text
  Widget _buildFeaturedCard(BuildContext context, bool dark, String cat, Color catColor, String imageUrl) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/article-detail', arguments: article),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppTheme.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                memCacheWidth: 600,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: Colors.grey.shade200,
                  highlightColor: Colors.grey.shade100,
                  child: Container(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: AppTheme.heroGradient),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    stops: const [0.3, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category + newspaper
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(cat, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: catColor)),
                        ),
                        const SizedBox(width: 8),
                        if (article.newspaper.isNotEmpty)
                          Flexible(
                            child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(article.newspaper, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                          )),
                      ],
                    ),
                    const Spacer(),
                    // Title
                    Text(
                      article.title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18, fontWeight: FontWeight.w800,
                        color: Colors.white, height: 1.25,
                      ),
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Tags
                    Row(
                      children: [
                        if (article.upscPaper.isNotEmpty)
                          Flexible(
                            child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                            ),
                            child: Text(article.upscPaper, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                          )),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
