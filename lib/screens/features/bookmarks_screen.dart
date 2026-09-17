import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_fonts.dart';
import '../../config/theme.dart';
import '../../providers/bookmarks_provider.dart';
import '../../widgets/article_card.dart';
import '../../widgets/glass_widgets.dart';

/// Displays articles saved by the signed-in user.
class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bookmarks = context.watch<BookmarksProvider>();
    final articles = bookmarks.getBookmarkedArticles();

    return GradientScaffold(
      title: 'Bookmarks',
      extendBodyBehindAppBar: false,
      child: articles.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bookmark_border_rounded,
                      size: 60,
                      color: AppTheme.textT(context),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No saved articles yet',
                      style: AppFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textP(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Open an article and tap the bookmark icon to keep it here.',
                      textAlign: TextAlign.center,
                      style: AppFonts.inter(
                        fontSize: 13,
                        height: 1.5,
                        color: AppTheme.textS(context),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: articles.length,
              itemBuilder: (context, index) => ArticleCard(
                article: articles[index],
                compact: true,
              ),
            ),
    );
  }
}
