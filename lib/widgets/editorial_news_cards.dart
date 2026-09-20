import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_fonts.dart';
import '../config/category_style.dart';
import '../config/theme.dart';
import '../models/article.dart';
import 'article_thumbnail.dart';

class EditorialLeadStory extends StatelessWidget {
  final Article article;

  const EditorialLeadStory({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    final category = CategoryStyle.fromTags(article.categoryTags);
    final source = article.newspaper.isNotEmpty ? article.newspaper : 'Daily briefing';

    return Semantics(
      button: true,
      label: 'Open top story: ${article.title}',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pushNamed(context, '/article-detail', arguments: article);
        },
        child: Container(
          height: 272,
          decoration: AppTheme.premiumCard(context),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ArticleThumbnail(
                imageUrl: article.imageUrl,
                title: article.title,
                category: category.label,
                footnote: source,
                height: 272,
                width: double.infinity,
                scrim: true,
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Pill(
                          icon: category.icon,
                          label: category.label,
                          background: Colors.white.withValues(alpha: 0.92),
                          foreground: category.color,
                        ),
                        const Spacer(),
                        _Pill(
                          icon: Icons.auto_awesome_rounded,
                          label: 'Top story',
                          background: Colors.black.withValues(alpha: 0.48),
                          foreground: Colors.white,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      source.toUpperCase(),
                      style: AppFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.plusJakartaSans(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                        color: Colors.white,
                      ),
                    ),
                    if (article.summary.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        article.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.inter(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.86),
                        ),
                      ),
                    ],
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 13, color: Colors.white70),
                        const SizedBox(width: 5),
                        Text(
                          '${editorialReadMinutes(article)} min read',
                          style: AppFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white70),
                        ),
                        if (article.upscPaper.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.school_rounded, size: 13, color: Colors.white70),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              article.upscPaper,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white70),
                            ),
                          ),
                        ],
                        const Spacer(),
                        const Icon(Icons.arrow_forward_rounded, size: 19, color: Colors.white),
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
}

class EditorialStoryCard extends StatelessWidget {
  final Article article;

  const EditorialStoryCard({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    final category = CategoryStyle.fromTags(article.categoryTags);
    final source = article.newspaper.isNotEmpty ? article.newspaper : 'Current affairs';

    return Semantics(
      button: true,
      label: 'Open article: ${article.title}',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.pushNamed(context, '/article-detail', arguments: article);
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 11),
          decoration: AppTheme.premiumCard(context),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ArticleThumbnail(
                  imageUrl: article.imageUrl,
                  title: article.title,
                  category: category.label,
                  footnote: source,
                  width: 108,
                  height: 148,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                source.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.55,
                                  color: category.onSoft(context),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.schedule_rounded, size: 11, color: AppTheme.textT(context)),
                            const SizedBox(width: 3),
                            Text(
                              '${editorialReadMinutes(article)}m',
                              style: AppFonts.inter(fontSize: 9.5, color: AppTheme.textT(context)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          article.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.plusJakartaSans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.28,
                            color: AppTheme.textP(context),
                          ),
                        ),
                        if (article.summary.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            article.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppFonts.inter(
                              fontSize: 10.5,
                              height: 1.3,
                              color: AppTheme.textS(context),
                            ),
                          ),
                        ],
                        const Spacer(),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Flexible(
                              child: _Pill(
                                icon: category.icon,
                                label: category.label,
                                background: category.soft(context),
                                foreground: category.onSoft(context),
                              ),
                            ),
                            if (article.upscPaper.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: _Pill(
                                  icon: Icons.school_rounded,
                                  label: article.upscPaper,
                                  background: AppTheme.primaryColor.withValues(alpha: 0.09),
                                  foreground: AppTheme.primaryColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

int editorialReadMinutes(Article article) {
  final text = article.content.isNotEmpty ? article.content : article.summary;
  final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
  return (words / 220).ceil().clamp(1, 15);
}
