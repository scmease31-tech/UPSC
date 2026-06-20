import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/quiz_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/section_header.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// QuizScreen — Quiz dashboard with glassmorphic score card, accuracy ring,
/// topic grid, and category stats.
/// ──────────────────────────────────────────────────────────────────────────────
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _fadeCtrl;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
    _fadeCurve = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  late CurvedAnimation _fadeCurve;

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeCurve.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final progress = context.watch<DailyProgressProvider>();
    final dark = AppTheme.isDark(context);

    const _ib = 'assets/flaticon_pngs/';
    final categories = [
      _QuizTopic('Polity', '${_ib}polity.png', AppTheme.accentViolet, 'Polity'),
      _QuizTopic('Economy', '${_ib}economy.png', AppTheme.primaryColor, 'Economy'),
      _QuizTopic('Environ', '${_ib}environment.png', AppTheme.successGreen, 'Environment'),
      _QuizTopic('Science', '${_ib}science.png', const Color(0xFF448AFF), 'Science & Tech'),
      _QuizTopic('Intl.', '${_ib}international.png', const Color(0xFFFF6B6B), 'International'),
      _QuizTopic('Geography', '${_ib}geography.png', AppTheme.primaryDark, 'Geography'),
      _QuizTopic('History', '${_ib}history.png', const Color(0xFF8D6E63), 'History'),
      _QuizTopic('Mixed', '${_ib}target_mixed.png', AppTheme.warningOrange, null),
    ];

    Widget content = FadeTransition(
        opacity: _fadeCurve,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header
            if (!kIsWeb)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Quiz Arena', style: GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
                ),
              ),

            // Score Hero Card
            SliverToBoxAdapter(child: _buildScoreCard(context, progress, dark)),

            // Stats Row
            SliverToBoxAdapter(child: _buildStatsRow(context, progress)),

            // Topic Grid
            SliverToBoxAdapter(
              child: SectionHeader(title: 'Choose Topic', padding: const EdgeInsets.fromLTRB(20, 12, 20, 6)),
            ),
            SliverToBoxAdapter(child: _buildTopicGrid(context, categories)),

            // Quick Start
            SliverToBoxAdapter(child: _buildQuickStart(context)),

            // Leaderboard teaser
            SliverToBoxAdapter(child: _buildLeaderboard(context, progress)),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      );

    return kIsWeb ? content : SafeArea(bottom: false, child: content);
  }

  Widget _buildScoreCard(BuildContext context, DailyProgressProvider p, bool dark) {
    final accuracy = p.weeklyAccuracy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppTheme.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Background image
              SizedBox(
                height: 160,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: AppImages.quizHero,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Shimmer.fromColors(
                    baseColor: Colors.grey.shade200,
                    highlightColor: Colors.grey.shade100,
                    child: Container(color: Colors.white),
                  ),
                  errorWidget: (_, __, ___) => Container(color: AppTheme.accentViolet.withValues(alpha: 0.2)),
                ),
              ),
              // Dark overlay
              Container(
                height: 160,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.75),
                      AppTheme.accentViolet.withValues(alpha: 0.5),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              // Content
              SizedBox(
                height: 160,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      CircularProgressWidget(
                        progress: accuracy / 100,
                        size: 100,
                        strokeWidth: 10,
                        progressColor: Colors.white,
                        trackColor: Colors.white.withValues(alpha: 0.15),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${accuracy.round()}%', style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                            Text('Accuracy', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Your Performance', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 10),
                            _whiteStatLine(Icons.quiz_rounded, '${p.quizzesThisWeek} quizzes taken'),
                            const SizedBox(height: 6),
                            _whiteStatLine(Icons.check_circle_outline_rounded, '${p.dailyChallengeScore} challenges done'),
                            const SizedBox(height: 6),
                            _whiteStatLine(Icons.emoji_events_rounded, '${p.dailyChallengeTotalXp} XP earned'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _whiteStatLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white70),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: Colors.white70))),
      ],
    );
  }

  Widget _buildStatsRow(BuildContext context, DailyProgressProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          Expanded(child: _statTile(context, 'Weekly', '${p.quizzesThisWeek}', Icons.format_list_numbered_rounded, AppTheme.primaryColor)),
          const SizedBox(width: 10),
          Expanded(child: _statTile(context, 'Streak', '${p.currentStreak}d', Icons.local_fire_department_rounded, AppTheme.errorRed)),
          const SizedBox(width: 10),
          Expanded(child: _statTile(context, 'XP', '${p.dailyChallengeTotalXp}', Icons.bolt_rounded, AppTheme.warningOrange)),
        ],
      ),
    );
  }

  Widget _statTile(BuildContext context, String label, String value, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textP(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context), fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildTopicGrid(BuildContext context, List<_QuizTopic> topics) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.8,
        ),
        itemCount: topics.length,
        itemBuilder: (context, i) {
          final t = topics[i];
          return GestureDetector(
            onTap: () async {
              try {
              HapticFeedback.lightImpact();
              final quiz = context.read<QuizProvider>();
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => PopScope(
                  canPop: false,
                  child: Center(
                    child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Lottie.asset('assets/animations/loading.json', width: 100, height: 100),
                        const SizedBox(height: 12),
                        Text('Loading ${t.name}...', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  ),
                ),
              );
              await quiz.loadQuiz(category: t.category);
              if (context.mounted) {
                Navigator.pop(context); // dismiss loading
                Navigator.pushNamed(context, '/quiz-play');
              }
              } catch (_) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to load quiz. Please try again.'), behavior: SnackBarBehavior.floating),
                  );
                }
              }
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    t.color.withValues(alpha: 0.85),
                    t.color.withValues(alpha: 0.55),
                  ],
                ),
                boxShadow: AppTheme.softShadow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(t.iconPath, width: 30, height: 30, color: Colors.white),
                  const SizedBox(height: 6),
                  Text(
                    t.name,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickStart(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: GestureDetector(
        onTap: () async {
          try {
          HapticFeedback.mediumImpact();
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => Center(
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Lottie.asset('assets/animations/loading.json', width: 100, height: 100),
                    const SizedBox(height: 12),
                    Text('Preparing quiz...', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          );
          await context.read<QuizProvider>().loadQuiz();
          if (context.mounted) {
            Navigator.pop(context); // dismiss loading
            Navigator.pushNamed(context, '/quiz-play');
          }
          } catch (_) {
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to load quiz. Please try again.'), behavior: SnackBarBehavior.floating),
              );
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.gradientButton(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Text('Start Quick Quiz', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboard(BuildContext context, DailyProgressProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.softShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: AppImages.quizCelebration,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.accentViolet.withValues(alpha: 0.85),
                      AppTheme.primaryColor.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Image.asset('assets/flaticon_pngs/trophy.png', width: 36, height: 36),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Keep it up!', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                          Text('Complete daily quizzes to climb the ranks', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    );
  }
}

class _QuizTopic {
  final String name;
  final String iconPath;
  final Color color;
  final String? category;
  const _QuizTopic(this.name, this.iconPath, this.color, this.category);
}
