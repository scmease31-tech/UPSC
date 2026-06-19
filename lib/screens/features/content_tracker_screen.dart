import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/daily_progress_provider.dart';
import '../../services/daily_content_manager.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/section_header.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// ContentTrackerScreen — Daily tasks, weekly stats, update history.
/// ──────────────────────────────────────────────────────────────────────────────
class ContentTrackerScreen extends StatefulWidget {
  const ContentTrackerScreen({super.key});

  @override
  State<ContentTrackerScreen> createState() => _ContentTrackerScreenState();
}

class _ContentTrackerScreenState extends State<ContentTrackerScreen> {
  final ScrollController _scrollController = ScrollController();
  List<String> _updateLog = [];
  bool _quizUpdated = false;
  bool _flashcardsUpdated = false;

  @override
  void initState() {
    super.initState();
    _loadTrackerData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTrackerData() async {
    final log = await DailyContentManager.getContentUpdateLog();
    final quizUp = await DailyContentManager.isQuizUpdatedToday();
    final flashUp = await DailyContentManager.isFlashcardUpdatedToday();
    if (mounted) {
      setState(() {
        _updateLog = log;
        _quizUpdated = quizUp;
        _flashcardsUpdated = flashUp;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<DailyProgressProvider>();

    final tasks = [
      _Task(Icons.quiz_rounded, 'Daily Quiz', 'New questions rotate every day', _quizUpdated, AppTheme.primaryColor),
      _Task(Icons.style_rounded, 'Flashcard Review', '15 fresh cards daily', _flashcardsUpdated, const Color(0xFF0EA5E9)),
      _Task(Icons.bolt_rounded, 'Daily Challenge', '5 questions · +50 XP', progress.dailyChallengeCompleted, AppTheme.warningOrange),
      _Task(Icons.menu_book_rounded, 'Read Articles', '${progress.articlesReadThisWeek} read this week', progress.articlesReadThisWeek > 0, AppTheme.successGreen),
    ];

    final doneCount = tasks.where((t) => t.done).length;
    final pct = tasks.isNotEmpty ? doneCount / tasks.length : 0.0;

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _backBar(context)),
            SliverToBoxAdapter(child: _heroCard(context, progress, doneCount, tasks.length, pct)),
            SliverToBoxAdapter(child: SectionHeader(title: 'Daily Tasks', padding: const EdgeInsets.fromLTRB(20, 16, 20, 8))),
            SliverList(delegate: SliverChildBuilderDelegate((_, i) => _taskTile(context, tasks[i]), childCount: tasks.length)),
            SliverToBoxAdapter(child: SectionHeader(title: 'Weekly Stats', padding: const EdgeInsets.fromLTRB(20, 20, 20, 8))),
            SliverToBoxAdapter(child: _weeklyStats(context, progress)),
            SliverToBoxAdapter(child: _countdownRow(context, progress)),
            SliverToBoxAdapter(child: SectionHeader(title: 'Recent Updates', padding: const EdgeInsets.fromLTRB(20, 20, 20, 8))),
            SliverToBoxAdapter(child: _updateHistory(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ── appbar ──
  Widget _backBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }),
          Text('Content Tracker', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
        ],
      ),
    );
  }

  // ── hero card ──
  Widget _heroCard(BuildContext context, DailyProgressProvider p, int done, int total, double pct) {
    final w = MediaQuery.of(context).size.width;
    final hp = w < 340 ? 12.0 : (w < 400 ? 16.0 : 20.0);
    final heroH = w < 360 ? 130.0 : 140.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 8, hp, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            SizedBox(
              height: heroH, width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: AppImages.trackerHero,
                fit: BoxFit.cover,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                  highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
                  child: Container(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: BoxDecoration(gradient: AppTheme.heroGradient),
                ),
              ),
            ),
            Container(
              height: heroH,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                  colors: [
                    AppTheme.primaryDark.withValues(alpha: 0.85),
                    AppTheme.primaryColor.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
            Container(
              height: heroH,
              padding: EdgeInsets.all(w < 360 ? 16 : 22),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Today's Progress", style: GoogleFonts.plusJakartaSans(fontSize: w < 360 ? 16 : 18, fontWeight: FontWeight.w800, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('$done of $total tasks done', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _pill(Icons.local_fire_department_rounded, '${p.currentStreak} day streak'),
                            _pill(Icons.emoji_events_rounded, 'Best: ${p.longestStreak}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  CircularProgressWidget(
                    progress: pct,
                    size: 68,
                    strokeWidth: 7,
                    progressColor: Colors.white,
                    trackColor: Colors.white24,
                    child: Text('${(pct * 100).round()}%', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  // ── task tile ──
  Widget _taskTile(BuildContext context, _Task t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: t.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(t.icon, color: t.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                  const SizedBox(height: 2),
                  Text(t.subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
                ],
              ),
            ),
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: t.done ? AppTheme.successGreen : AppTheme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(t.done ? Icons.check_rounded : Icons.remove_rounded, size: 16, color: t.done ? Colors.white : AppTheme.textS(context)),
            ),
          ],
        ),
      ),
    );
  }

  // ── weekly stats ──
  Widget _weeklyStats(BuildContext context, DailyProgressProvider p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _statRow(context, 'Articles Read', '${p.articlesReadThisWeek}', Icons.article_rounded, AppTheme.primaryColor),
            _div(),
            _statRow(context, 'Quizzes Taken', '${p.quizzesThisWeek}', Icons.quiz_rounded, const Color(0xFF0EA5E9)),
            _div(),
            _statRow(context, 'Accuracy', '${p.weeklyAccuracy.round()}%', Icons.gps_fixed_rounded, AppTheme.successGreen),
            _div(),
            _statRow(context, 'Study Time', '${p.studyMinutesThisWeek} min', Icons.timer_rounded, AppTheme.warningOrange),
            _div(),
            _statRow(context, 'Total XP', '${p.dailyChallengeTotalXp}', Icons.star_rounded, const Color(0xFFEAB308)),
          ],
        ),
      ),
    );
  }

  Widget _statRow(BuildContext context, String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context)))),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
        ],
      ),
    );
  }

  Widget _div() => Divider(height: 16, color: AppTheme.primaryColor.withValues(alpha: 0.06));

  // ── countdown ──
  Widget _countdownRow(BuildContext context, DailyProgressProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Expanded(child: _countdownTile(context, 'Prelims ${p.prelimsExamYear}', p.daysToPrelimsExam, AppTheme.primaryColor)),
          const SizedBox(width: 10),
          Expanded(child: _countdownTile(context, 'Mains ${p.mainsExamYear}', p.daysToMainsExam, AppTheme.successGreen)),
        ],
      ),
    );
  }

  Widget _countdownTile(BuildContext context, String label, int days, Color color) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text('$days', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w800, color: color)),
          Text('days left', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
        ],
      ),
    );
  }

  // ── update history ──
  Widget _updateHistory(BuildContext context) {
    if (_updateLog.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GlassCard(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('No updates yet. Complete tasks to see history.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: _updateLog.reversed.take(10).map((entry) {
            final parts = entry.split('|');
            final date = parts.isNotEmpty ? parts[0] : '';
            final type = parts.length > 1 ? parts[1] : '';
            IconData icon;
            String label;
            switch (type) {
              case 'quiz':
                icon = Icons.quiz_rounded;
                label = 'Quiz updated';
                break;
              case 'flashcards':
                icon = Icons.style_rounded;
                label = 'Flashcards refreshed';
                break;
              case 'challenge':
                icon = Icons.bolt_rounded;
                label = 'Challenge completed';
                break;
              case 'articles':
                icon = Icons.article_rounded;
                label = 'Articles synced';
                break;
              default:
                icon = Icons.update_rounded;
                label = 'Content updated';
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: AppTheme.primaryColor),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textP(context)))),
                  Text(date, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textS(context))),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _Task {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final Color color;
  const _Task(this.icon, this.title, this.subtitle, this.done, this.color);
}
