import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/daily_progress_provider.dart';
import '../../providers/bookmarks_provider.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// RevisionScreen — 3-tab revision hub (Bookmarks, Incorrect Qs, Saved Facts).
/// ──────────────────────────────────────────────────────────────────────────────
class RevisionScreen extends StatelessWidget {
  const RevisionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      showAppBar: false,
      child: DefaultTabController(
        length: 3,
        child: SafeArea(
          child: Column(
            children: [
              _backBar(context),
              _buildTabs(context),
              Expanded(
                child: TabBarView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _BookmarksTab(),
                    _IncorrectTab(),
                    _SavedFactsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backBar(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              }),
              Text('Revision Hub', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                SizedBox(
                  height: 96, width: double.infinity,
                  child: CachedNetworkImage(
                    imageUrl: AppImages.revisionHero,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppTheme.accentViolet.withValues(alpha: 0.08)),
                    errorWidget: (_, __, ___) => Container(color: AppTheme.accentViolet.withValues(alpha: 0.08)),
                  ),
                ),
                Container(
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppTheme.accentViolet.withValues(alpha: 0.8),
                      AppTheme.primaryColor.withValues(alpha: 0.7),
                    ]),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.replay_circle_filled_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Review & Revise', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                            Text('Bookmarks, wrong answers & saved facts', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TabBar(
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.textS(context),
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
          dividerHeight: 0,
          tabs: const [
            Tab(text: 'Bookmarks'),
            Tab(text: 'Wrong Qs'),
            Tab(text: 'Facts'),
          ],
        ),
      ),
    );
  }
}

class _BookmarksTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bookmarks = context.watch<BookmarksProvider>();
    final articles = bookmarks.getBookmarkedArticles();

    if (articles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_rounded, color: AppTheme.primaryColor.withValues(alpha: 0.3), size: 56),
            const SizedBox(height: 14),
            Text('No bookmarks yet', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textP(context))),
            const SizedBox(height: 4),
            Text('Bookmark articles to review later', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: articles.length,
      itemBuilder: (context, i) {
        final a = articles[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AnimatedGlassCard(
            onTap: () => Navigator.pushNamed(context, '/article-detail', arguments: a),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.article_rounded, color: AppTheme.primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textP(context))),
                      Text(a.categoryTags.join(', '), style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.bookmark_remove_rounded, color: AppTheme.errorRed, size: 20),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    bookmarks.toggleBookmark(a.id);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _IncorrectTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final progress = context.watch<DailyProgressProvider>();
    final questions = progress.incorrectQuestions;

    if (questions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.successGreen.withValues(alpha: 0.3), size: 56),
            const SizedBox(height: 14),
            Text('No incorrect questions!', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textP(context))),
            const SizedBox(height: 4),
            Text('All answers correct — great job!', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: questions.length,
      itemBuilder: (context, i) {
        final q = questions[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: AppTheme.errorRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text('Wrong', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.errorRed)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => progress.removeIncorrectQuestion(i),
                      child: Icon(Icons.close_rounded, color: AppTheme.textS(context), size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(q['question'] ?? '', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textP(context), height: 1.4)),
                if (q['explanation'] != null) ...[
                  const SizedBox(height: 8),
                  Text(q['explanation'], style: GoogleFonts.inter(fontSize: 12, color: AppTheme.successGreen, height: 1.4)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SavedFactsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final progress = context.watch<DailyProgressProvider>();
    final facts = progress.savedFactIds;

    if (facts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/flaticon_pngs/lightbulb.png', width: 48, height: 48,
              color: AppTheme.textT(context).withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text('No saved facts yet', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textP(context))),
            const SizedBox(height: 4),
            Text('Save interesting facts as you learn', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      itemCount: facts.length,
      itemBuilder: (context, i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.push_pin_rounded, color: AppTheme.warningOrange, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Text(facts[i], style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context)))),
                GestureDetector(
                  onTap: () => progress.toggleSavedFact(facts[i]),
                  child: Icon(Icons.delete_outline_rounded, color: AppTheme.errorRed, size: 18),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
