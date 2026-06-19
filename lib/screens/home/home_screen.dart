import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/auth_provider.dart';
import '../../providers/articles_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/article_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/network_image_widget.dart';
import '../../services/notification_service.dart';
import '../main_navigation.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// HomeScreen — Premium dashboard with glassmorphic cards, circular progress,
/// quick action grid, activity timeline, and trending topics.
/// Inspired by activity tracker + smart home UI references.
/// ──────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Responsive helpers ──
  double _hPad(double w) => w < 340 ? 12 : (w < 400 ? 16 : 20);
  double _sf(double w, double base) {
    if (w < 340) return base - 2;
    if (w < 380) return base - 1;
    return base;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final auth = context.watch<AuthProvider>();
    final articles = context.watch<ArticlesProvider>();
    final progress = context.watch<DailyProgressProvider>();
    final dark = AppTheme.isDark(context);
    final now = DateTime.now();
    final greeting = _getGreeting(now);
    final name = auth.userProfile?.name ?? 'Scholar';
    final firstName = name.split(' ').first;

    return SafeArea(
      bottom: false,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(child: _buildHeader(context, greeting, firstName, now, dark)),

            // ── Progress Hero Card ──
            SliverToBoxAdapter(child: _buildProgressHero(context, progress, dark)),

            // ── Stats Row ──
            SliverToBoxAdapter(child: RepaintBoundary(child: _buildStatsRow(context, progress, articles))),

            // ── Streak Motivation ──
            if (progress.currentStreak > 0)
              SliverToBoxAdapter(child: _buildStreakMotivation(context, progress)),

            // ── Quick Actions ──
            SliverToBoxAdapter(child: RepaintBoundary(child: _buildQuickActions(context))),

            // ── Daily Insight Card ──
            SliverToBoxAdapter(child: RepaintBoundary(child: _buildDailyInsight(context))),

            // ── Today's Activity ──
            SliverToBoxAdapter(child: RepaintBoundary(child: _buildTodayActivity(context, progress))),

            // ── Trending Topics ──
            SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Trending Topics',
                actionLabel: 'View All',
                onAction: () => _navigateToTab(1),
              ),
            ),
            SliverToBoxAdapter(child: _buildTrendingTopics(context, articles)),

            // ── Study Tools ──
            SliverToBoxAdapter(child: RepaintBoundary(child: _buildStudyTools(context))),

            // ── Weekly Progress ──
            SliverToBoxAdapter(child: RepaintBoundary(child: _buildWeeklyProgress(context, progress))),

            // ── Exam Countdown ──
            SliverToBoxAdapter(child: _buildExamCountdown(context, progress)),

            // Bottom padding for nav bar
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // HEADER
  // ═════════════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, String greeting, String name, DateTime now, bool dark) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final auth = context.watch<AuthProvider>();
    final photoUrl = auth.userProfile?.photoUrl;
    final hour = now.hour;
    final emoji = hour < 12 ? 'AM' : (hour < 17 ? 'PM' : 'EVE');
    final tagline = hour < 12
        ? 'Rise and conquer your goals today!'
        : (hour < 17 ? 'Stay focused, keep pushing!' : 'Wind down with a study session');

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 16, hp, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryColor.withValues(alpha: 0.10),
                            AppTheme.accentViolet.withValues(alpha: 0.08),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('EEEE, d MMM').format(now),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                    '$greeting, $name!',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: _sf(w, 24),
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  tagline,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textS(context),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Notification bell
          GlassCard(
            padding: const EdgeInsets.all(10),
            radius: 50,
            child: Icon(Icons.notifications_outlined, color: AppTheme.textP(context), size: 22),
            onTap: () => _showNotificationsSheet(context),
          ),
          const SizedBox(width: 8),
          // Profile avatar
          GestureDetector(
            onTap: () => _navigateToTab(4),
            child: AvatarImage(
              imageUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
              name: name,
              radius: 20,
              borderWidth: 2,
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // PROGRESS HERO CARD
  // ═════════════════════════════════════════════════════════════════

  Widget _buildProgressHero(BuildContext context, DailyProgressProvider p, bool dark) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final completion = _dailyCompletion(p);
    final completionPct = (completion * 100).round();
    final heroH = w < 340 ? 150.0 : (w < 400 ? 165.0 : 180.0);
    final circleSize = w < 340 ? 68.0 : (w < 400 ? 78.0 : 90.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 6),
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
                height: heroH,
                width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: AppImages.homeBannerStudy,
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  placeholder: (_, __) => Shimmer.fromColors(
                    baseColor: Colors.grey.shade200,
                    highlightColor: Colors.grey.shade100,
                    child: Container(color: Colors.white),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
                  ),
                ),
              ),
              // Gradient overlay
              Container(
                height: heroH,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0D1B2A).withValues(alpha: 0.85),
                      AppTheme.primaryDark.withValues(alpha: 0.70),
                    ],
                  ),
                ),
              ),
              // Content
              SizedBox(
                height: heroH,
                child: Padding(
                  padding: EdgeInsets.all(w < 360 ? 14 : 20),
                  child: Row(
                    children: [
                      // Left text
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.rocket_launch_rounded, size: 13, color: Colors.white),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Today\'s Mission',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '${p.articlesReadToday} of 5 Completed',
                              style: GoogleFonts.plusJakartaSans(fontSize: _sf(w, 15), color: Colors.white, fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              completionPct >= 100 ? 'All done! Great job!' : 'Keep going, you\'re doing great!',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: completion,
                                minHeight: 6,
                                backgroundColor: Colors.white.withValues(alpha: 0.12),
                                valueColor: AlwaysStoppedAnimation(
                                  completion >= 1.0 ? AppTheme.successGreen : AppTheme.primaryLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Circular progress with glow
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryLight.withValues(alpha: 0.25),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CircularProgressWidget(
                          progress: completion,
                          size: circleSize,
                          strokeWidth: w < 380 ? 6 : 8,
                          progressColor: AppTheme.primaryLight,
                          trackColor: Colors.white.withValues(alpha: 0.12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$completionPct%',
                                style: GoogleFonts.plusJakartaSans(fontSize: _sf(w, 24), fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                            ],
                          ),
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

  // ═════════════════════════════════════════════════════════════════
   // STATS ROW
  // ═════════════════════════════════════════════════════════════════

  Widget _buildStatsRow(BuildContext context, DailyProgressProvider p, ArticlesProvider articles) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final stats = [
      _StatInfo(Icons.local_fire_department_rounded, '${p.currentStreak}', 'Streak', [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)]),
      _StatInfo(Icons.emoji_events_rounded, '${p.quizzesThisWeek}', 'Quizzes/wk', [const Color(0xFFFBBF24), const Color(0xFFF59E0B)]),
      _StatInfo(Icons.timer_rounded, '${p.studyMinutesThisWeek}m', 'Study/wk', [AppTheme.primaryColor, AppTheme.primaryLight]),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 6),
      child: Row(
        children: stats.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i > 0 ? 8 : 0),
              child: _miniStatEnhanced(context, s),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStreakMotivation(BuildContext context, DailyProgressProvider p) {
    final streak = p.currentStreak;
    final message = streak >= 30
        ? 'Incredible! $streak-day streak — you are unstoppable!'
        : streak >= 14
            ? 'Amazing $streak-day streak! Consistency is your superpower!'
            : streak >= 7
                ? '$streak days strong! Keep the momentum going!'
                : streak >= 3
                    ? '$streak-day streak! Great start — don\'t break it!'
                    : '$streak-day streak started! Build the habit!';

    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 6),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.errorRed, AppTheme.warningOrange],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 18),
                ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: GoogleFonts.inter(fontSize: _sf(w, 13), fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStatEnhanced(BuildContext context, _StatInfo s) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: s.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: s.gradientColors[0].withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(s.icon, color: Colors.white, size: 19),
          ),
          const SizedBox(height: 8),
          Text(s.value, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
          const SizedBox(height: 2),
          Text(s.label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context), fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // QUICK ACTIONS
  // ═════════════════════════════════════════════════════════════════

  Widget _buildQuickActions(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final dark = AppTheme.isDark(context);
    final actions = [
      _QAction(Icons.flash_on_rounded, 'Daily\nChallenge', AppTheme.primaryColor, '/daily-challenge'),
      _QAction(Icons.auto_awesome_rounded, 'AI\nSearch', const Color(0xFF7C4DFF), '/ai-search'),
      _QAction(Icons.view_carousel_rounded, 'Flash\nCards', const Color(0xFFFF6B6B), '/flashcards'),
      _QAction(Icons.explore_rounded, 'Explore\nMore', AppTheme.warmYellow, '/explore'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Quick Actions', padding: EdgeInsets.zero),
          const SizedBox(height: 14),
          Row(
            children: List.generate(actions.length, (i) {
              final a = actions[i];
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i > 0 ? 10 : 0),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pushNamed(context, a.route);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: w < 360 ? 48 : 60,
                          height: w < 360 ? 48 : 60,
                          decoration: BoxDecoration(
                            color: dark
                                ? a.color.withValues(alpha: 0.12)
                                : a.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(w < 360 ? 16 : 20),
                            border: Border.all(color: a.color.withValues(alpha: 0.15)),
                          ),
                          child: Icon(a.icon, color: a.color, size: w < 360 ? 22 : 26),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          a.label,
                          style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: AppTheme.textP(context), height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // DAILY INSIGHT CARD
  // ═════════════════════════════════════════════════════════════════

  Widget _buildDailyInsight(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final insights = [
      '"The secret of getting ahead is getting started." — Mark Twain',
      '"Education is the most powerful weapon." — Nelson Mandela',
      '"Success is the sum of small efforts repeated daily."',
      '"An investment in knowledge pays the best interest." — Benjamin Franklin',
      '"Discipline is the bridge between goals and accomplishment."',
      '"The only way to do great work is to love what you do." — Steve Jobs',
      '"Believe you can and you\'re halfway there." — Theodore Roosevelt',
    ];
    final todayInsight = insights[DateTime.now().day % insights.length];

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF667EEA).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 22),
                  ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Insight',
                      style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      todayInsight,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white, height: 1.4),
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

  // ═════════════════════════════════════════════════════════════════
  // TODAY ACTIVITY TIMELINE
  // ═════════════════════════════════════════════════════════════════

  Widget _buildTodayActivity(BuildContext context, DailyProgressProvider p) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final activities = [
      _Activity('Articles Read', '${p.articlesReadToday} articles today', Icons.article_rounded, AppTheme.primaryColor, '${p.articlesReadToday}/5'),
      _Activity('Quiz Practice', '${p.quizzesToday} quizzes completed', Icons.quiz_rounded, AppTheme.accentViolet, '${p.quizzesToday}'),
      _Activity('Study Session', '${p.studyMinutesToday} min today', Icons.timer_rounded, const Color(0xFFFF6B6B), '${p.studyMinutesToday}m'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Today\'s Activity', padding: EdgeInsets.zero),
          const SizedBox(height: 12),
          ...activities.map((a) => _activityRow(context, a)),
        ],
      ),
    );
  }

  Widget _activityRow(BuildContext context, _Activity a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: a.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(a.icon, color: a.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textP(context))),
                  const SizedBox(height: 2),
                  Text(a.subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: a.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(a.time, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: a.color)),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // TRENDING TOPICS
  // ═════════════════════════════════════════════════════════════════

  Widget _buildTrendingTopics(BuildContext context, ArticlesProvider articles) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final topArticles = articles.articles.take(5).toList();
    if (topArticles.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: hp),
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                SizedBox(
                  width: 80, height: 80,
                  child: Icon(Icons.article_outlined, size: 40, color: AppTheme.textT(context)),
                ),
                const SizedBox(height: 8),
                Text('No articles yet', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textS(context))),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Featured first article with image
        if (topArticles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ArticleCard(article: topArticles.first, featured: true),
          ),
        // Horizontal scroll of remaining articles
        if (topArticles.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 310,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: hp),
              itemCount: topArticles.length - 1,
              itemBuilder: (context, i) {
                final article = topArticles[i + 1];
                final cardW = (w * 0.72).clamp(240.0, 320.0);
                return Container(
                  width: cardW,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: ArticleCard(article: article),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // STUDY TOOLS
  // ═════════════════════════════════════════════════════════════════

  Widget _buildStudyTools(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final dark = AppTheme.isDark(context);
    final cols = w < 340 ? 2 : 3;
    final aspect = w < 340 ? 0.95 : (w < 400 ? 0.92 : 0.88);
    final tools = [
      _StudyTool('UPSC Must Know', 'Facts & data', Icons.lightbulb_rounded, AppTheme.primaryColor, '/upsc-must-know'),
      _StudyTool('Previous Year Qs', 'PYQ practice', Icons.history_edu_rounded, const Color(0xFFE91E63), '/pyq'),
      _StudyTool('Study Timer', 'Pomodoro focus', Icons.timer_rounded, const Color(0xFFFF6B6B), '/study-timer'),
      _StudyTool('Quick Revision', 'Short notes', Icons.note_alt_rounded, const Color(0xFF8D6E63), '/quick-revision'),
      _StudyTool('Answer Writing', 'Mains practice', Icons.edit_note_rounded, const Color(0xFF448AFF), '/answer-writing'),
      _StudyTool('Content Tracker', 'Track progress', Icons.track_changes_rounded, AppTheme.accentViolet, '/content-tracker'),
      _StudyTool('Current Affairs', 'Compilations', Icons.newspaper_rounded, const Color(0xFF00897B), '/current-affairs'),
      _StudyTool('Syllabus Tracker', 'Preparation', Icons.checklist_rounded, const Color(0xFFEF6C00), '/syllabus-tracker'),
      _StudyTool('Vocabulary', 'Word power', Icons.abc_rounded, const Color(0xFF5C6BC0), '/vocabulary'),
      _StudyTool('Mock Tests', 'Prelims tests', Icons.quiz_rounded, const Color(0xFFD32F2F), '/mock-test'),
      _StudyTool('Govt Schemes', 'Schemes DB', Icons.account_balance_rounded, const Color(0xFF388E3C), '/govt-schemes'),
      _StudyTool('Bookmarks', 'Saved items', Icons.bookmark_rounded, const Color(0xFF0288D1), '/bookmarks'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: 'Study Tools', padding: EdgeInsets.zero),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: aspect,
            ),
            itemCount: tools.length,
            itemBuilder: (context, i) {
              final t = tools[i];
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.pushNamed(context, t.route);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: dark ? AppTheme.darkCardBg : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: t.color.withValues(alpha: 0.12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? 0.08 : 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: w < 360 ? 38 : 44,
                        height: w < 360 ? 38 : 44,
                        decoration: BoxDecoration(
                          color: dark
                              ? t.color.withValues(alpha: 0.15)
                              : t.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(t.icon, color: t.color, size: 24),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          t.title,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textP(context),
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textS(context),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // WEEKLY PROGRESS
  // ═════════════════════════════════════════════════════════════════

  Widget _buildWeeklyProgress(BuildContext context, DailyProgressProvider p) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final streakHistory = p.streakHistory;
    final todayIndex = DateTime.now().weekday - 1;
    final doneCount = streakHistory.where((s) => s == 'done').length;
    final pct = (doneCount / 7 * 100).round();
    final circleSize = w < 340 ? 28.0 : (w < 400 ? 32.0 : 36.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Weekly Progress',
            actionLabel: 'Details',
            onAction: () => Navigator.pushNamed(context, '/weekly-progress'),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Summary row with progress bar
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$doneCount/7 days active',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$pct%',
                      style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primaryColor),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Linear progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: doneCount / 7,
                    minHeight: 6,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(
                      pct >= 100 ? AppTheme.successGreen : AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Day circles
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (i) {
                    final isToday = i == todayIndex;
                    final isActive = i < streakHistory.length && streakHistory[i] == 'done';
                    final isFuture = i > todayIndex;

                    return Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                          width: circleSize,
                          height: circleSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isActive
                                ? LinearGradient(
                                    colors: [AppTheme.primaryColor, AppTheme.primaryLight],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: isActive
                                ? null
                                : isFuture
                                    ? AppTheme.textT(context).withValues(alpha: 0.06)
                                    : AppTheme.textT(context).withValues(alpha: 0.10),
                            border: isToday && !isActive
                                ? Border.all(color: AppTheme.primaryColor, width: 2)
                                : null,
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: isActive
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                                : isToday
                                    ? Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppTheme.primaryColor,
                                        ),
                                      )
                                    : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          days[i],
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                            color: isToday
                                ? AppTheme.primaryColor
                                : isActive
                                    ? AppTheme.textP(context)
                                    : AppTheme.textT(context),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // EXAM COUNTDOWN
  // ═════════════════════════════════════════════════════════════════

  Widget _buildExamCountdown(BuildContext context, DailyProgressProvider p) {
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);
    final cardH = w < 340 ? 110.0 : (w < 400 ? 120.0 : 130.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 10, hp, 12),
      child: Container(
        height: cardH,
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
                imageUrl: AppImages.homeBannerUpsc,
                fit: BoxFit.cover,
                memCacheWidth: 600,
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
                      Colors.black.withValues(alpha: 0.65),
                      AppTheme.primaryDark.withValues(alpha: 0.75),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Image.asset('assets/flaticon_pngs/target_mixed.png', width: 20, height: 20),
                              const SizedBox(width: 6),
                              Flexible(child: Text('Prelims ${DateTime.now().year}', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Keep pushing — every day counts!', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${p.daysToPrelimsExam}', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
                          Text('days left', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
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

  // ═════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════

  String _getGreeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  double _dailyCompletion(DailyProgressProvider p) {
    int done = 0;
    if (p.articlesReadToday > 0) done++;
    if (p.quizzesToday > 0) done++;
    if (p.studyMinutesToday > 0) done++;
    if (p.currentStreak > 0) done++;
    if (p.dailyChallengeScore > 0) done++;
    return (done / 5).clamp(0.0, 1.0);
  }

  void _navigateToTab(int index) {
    MainNavigation.switchTab(context, index);
  }

  void _showNotificationsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Notification Settings',
                          style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textP(ctx))),
                      const SizedBox(height: 4),
                      Text('Manage your daily reminders',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(ctx))),
                      const SizedBox(height: 20),
                      _notifOption(ctx, Icons.article_rounded, 'Current Affairs', '8:00 AM', AppTheme.primaryColor),
                      _notifOption(ctx, Icons.style_rounded, 'Flashcard Reminder', '7:30 AM', AppTheme.accentViolet),
                      _notifOption(ctx, Icons.quiz_rounded, 'Quiz Reminder', '6:00 PM', AppTheme.warningOrange),
                      _notifOption(ctx, Icons.menu_book_rounded, 'Study Reminder', '9:00 PM', const Color(0xFFFF6B6B)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                await NotificationService.cancelAll();
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('All notifications cancelled')),
                                  );
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppTheme.errorRed.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text('Turn Off All', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.errorRed)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                await NotificationService.scheduleAllDailyNotifications();
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('All notifications scheduled!')),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text('Enable All', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _notifOption(BuildContext context, IconData icon, String title, String time, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textP(context))),
                  Text(time, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
                ],
              ),
            ),
            Icon(Icons.notifications_active_rounded, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═════════════════════════════════════════════════════════════════

class _QAction {
  final IconData icon;
  final String label;
  final Color color;
  final String route;
  const _QAction(this.icon, this.label, this.color, this.route);
}

class _Activity {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String time;
  const _Activity(this.title, this.subtitle, this.icon, this.color, this.time);
}

class _StudyTool {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String route;
  const _StudyTool(this.title, this.subtitle, this.icon, this.color, this.route);
}

class _StatInfo {
  final IconData icon;
  final String value;
  final String label;
  final List<Color> gradientColors;
  const _StatInfo(this.icon, this.value, this.label, this.gradientColors);
}
