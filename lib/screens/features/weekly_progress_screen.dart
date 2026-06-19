import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/section_header.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// WeeklyProgressScreen — Weekly metrics dashboard with charts & stats.
/// ──────────────────────────────────────────────────────────────────────────────
class WeeklyProgressScreen extends StatefulWidget {
  const WeeklyProgressScreen({super.key});

  @override
  State<WeeklyProgressScreen> createState() => _WeeklyProgressScreenState();
}

class _WeeklyProgressScreenState extends State<WeeklyProgressScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = context.watch<DailyProgressProvider>();

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _backBar(context)),
            SliverToBoxAdapter(child: _buildStreakCard(context, progress)),
            SliverToBoxAdapter(child: _buildWeeklyStats(context, progress)),
            SliverToBoxAdapter(
              child: SectionHeader(title: 'This Week', padding: const EdgeInsets.fromLTRB(20, 16, 20, 8)),
            ),
            SliverToBoxAdapter(child: _buildWeekChart(context, progress)),
            SliverToBoxAdapter(child: _buildAccuracyCard(context, progress)),
            SliverToBoxAdapter(child: _buildExamCountdown(context, progress)),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _backBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }),
          Text('Weekly Progress', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
        ],
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context, DailyProgressProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            SizedBox(
              height: 120, width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: AppImages.progressHero,
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
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                  colors: [
                    AppTheme.primaryDark.withValues(alpha: 0.85),
                    AppTheme.primaryColor.withValues(alpha: 0.7),
                  ],
                ),
              ),
            ),
            Container(
              height: 120,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Image.asset('assets/flaticon_pngs/fire.png', width: 32, height: 32)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${p.currentStreak} Day Streak', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('Longest: ${p.longestStreak} days', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyStats(BuildContext context, DailyProgressProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          _statTile(context, '${p.articlesReadThisWeek}', 'Articles', AppTheme.primaryColor),
          const SizedBox(width: 8),
          _statTile(context, '${p.quizzesThisWeek}', 'Quizzes', AppTheme.accentViolet),
          const SizedBox(width: 8),
          _statTile(context, '${p.studyMinutesThisWeek}m', 'Study', AppTheme.warningOrange),
          const SizedBox(width: 8),
          _statTile(context, '${p.dailyChallengeTotalXp}', 'XP', AppTheme.errorRed),
        ],
      ),
    );
  }

  Widget _statTile(BuildContext context, String value, String label, Color color) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textS(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekChart(BuildContext context, DailyProgressProvider p) {
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final history = p.streakHistory;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (i) {
            final done = i < history.length && history[i] == 'done';
            return Column(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: done ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    done ? Icons.check_rounded : Icons.remove_rounded,
                    color: done ? Colors.white : AppTheme.textS(context),
                    size: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(days[i], style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textS(context))),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildAccuracyCard(BuildContext context, DailyProgressProvider p) {
    final accuracy = p.weeklyAccuracy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircularProgressWidget(
              progress: accuracy / 100,
              size: 80,
              strokeWidth: 8,
              progressColor: accuracy >= 70 ? AppTheme.successGreen : AppTheme.warningOrange,
              trackColor: AppTheme.primaryColor.withValues(alpha: 0.08),
              child: Text('${accuracy.round()}%', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quiz Accuracy', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                  const SizedBox(height: 4),
                  Text('${p.correctAnswersThisWeek}/${p.totalAnswersThisWeek} correct this week',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamCountdown(BuildContext context, DailyProgressProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            SizedBox(
              height: 90, width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: AppImages.homeBannerUpsc,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppTheme.accentViolet.withValues(alpha: 0.08)),
                errorWidget: (_, __, ___) => Container(color: AppTheme.accentViolet.withValues(alpha: 0.08)),
              ),
            ),
            Container(
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppTheme.accentViolet.withValues(alpha: 0.85),
                  AppTheme.primaryColor.withValues(alpha: 0.8),
                ]),
              ),
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Image.asset('assets/flaticon_pngs/target_mixed.png', width: 24, height: 24)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('UPSC Prelims ${p.prelimsExamYear}', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text('${p.daysToPrelimsExam} days remaining', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
