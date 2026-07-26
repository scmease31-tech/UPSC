import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/category_style.dart';
import '../config/theme.dart';
import '../models/article.dart';
import 'article_thumbnail.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// ArticleCard — the app's primary content surface, in three variants:
///
///   • standard  — 16:9 cover, headline, deck, syllabus tags
///   • compact   — horizontal row with a square thumbnail (feeds, related lists)
///   • featured  — full-bleed hero used at the top of the news tab
///
/// All three share [ArticleThumbnail], so an article without artwork still gets
/// a designed cover rather than an empty grey box.
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

  void _open() => Navigator.pushNamed(context, '/article-detail', arguments: article);

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.fromTags(article.categoryTags);

    final Widget card = widget.featured
        ? _featured(context, style)
        : widget.compact
            ? _compact(context, style)
            : _standard(context, style);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: _open,
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: card,
      ),
    );
  }

  // ── STANDARD ───────────────────────────────────────────────────────────────
  Widget _standard(BuildContext context, CategoryStyle style) {
    final dark = AppTheme.isDark(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: AppTheme.premiumCard(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Cover ──
          Stack(
            children: [
              ArticleThumbnail(
                imageUrl: article.imageUrl,
                title: article.title,
                category: style.label,
                footnote: article.newspaper,
                height: 152,
                width: double.infinity,
              ),
              Positioned(
                top: 10,
                left: 10,
                child: _chip(
                  style.label,
                  bg: (dark ? Colors.black : Colors.white).withValues(alpha: 0.88),
                  fg: style.color,
                  icon: style.icon,
                ),
              ),
              if (article.newspaper.isNotEmpty)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _chip(
                    article.newspaper,
                    bg: Colors.black.withValues(alpha: 0.52),
                    fg: Colors.white,
                    icon: Icons.newspaper_rounded,
                  ),
                ),
            ],
          ),

          // ── Text ──
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  article.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textP(context),
                    height: 1.28,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (article.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    article.summary,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: AppTheme.textS(context),
                      height: 1.45,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                _metaRow(context, style),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── COMPACT ────────────────────────────────────────────────────────────────
  Widget _compact(BuildContext context, CategoryStyle style) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      decoration: AppTheme.premiumCard(context, radius: 18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ArticleThumbnail(
              imageUrl: article.imageUrl,
              title: article.title,
              category: style.label,
              width: 86,
              height: 86,
              borderRadius: BorderRadius.circular(13),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: style.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          style.label,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: style.onSoft(context),
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(article.publishedDate),
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textT(context)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    article.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textP(context),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      if (article.upscPaper.isNotEmpty) ...[
                        _tinyTag(context, article.upscPaper, AppTheme.primaryColor),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          article.newspaper,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textT(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── FEATURED ───────────────────────────────────────────────────────────────
  Widget _featured(BuildContext context, CategoryStyle style) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      height: 232,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.cardSh(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ArticleThumbnail(
            imageUrl: article.imageUrl,
            title: article.title,
            category: style.label,
            footnote: article.newspaper,
            scrim: true,
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _chip(style.label, bg: Colors.white.withValues(alpha: 0.92), fg: style.color, icon: style.icon),
                    const SizedBox(width: 8),
                    if (article.newspaper.isNotEmpty)
                      Flexible(
                        child: _chip(
                          article.newspaper,
                          bg: Colors.black.withValues(alpha: 0.42),
                          fg: Colors.white,
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  article.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.24,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (article.upscPaper.isNotEmpty) ...[
                      _chip(
                        article.upscPaper,
                        bg: Colors.white.withValues(alpha: 0.22),
                        fg: Colors.white,
                        icon: Icons.school_rounded,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _timeAgo(article.publishedDate),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
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
    );
  }

  // ── PIECES ─────────────────────────────────────────────────────────────────
  Widget _metaRow(BuildContext context, CategoryStyle style) {
    return Row(
      children: [
        // The tag group takes whatever space is left after the timestamp and
        // the chevron, and each tag inside it may shrink — cards are rendered
        // as narrow as ~280 px in the home screen's trending rail.
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (article.upscPaper.isNotEmpty)
                Flexible(
                  child: _tinyTag(context, article.upscPaper, AppTheme.primaryColor, icon: Icons.school_rounded),
                ),
              if (article.upscPaper.isNotEmpty && article.examRelevance.isNotEmpty)
                const SizedBox(width: 6),
              if (article.examRelevance.isNotEmpty)
                Flexible(
                  child: _tinyTag(context, article.examRelevance, AppTheme.accentViolet, icon: Icons.star_rounded),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _timeAgo(article.publishedDate),
          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textT(context)),
        ),
        const SizedBox(width: 8),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: style.soft(context),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(Icons.arrow_forward_rounded, size: 14, color: style.onSoft(context)),
        ),
      ],
    );
  }

  Widget _chip(String label, {required Color bg, required Color fg, IconData? icon}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon != null ? 9 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tinyTag(BuildContext context, String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: AppTheme.isDark(context) ? 0.18 : 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
