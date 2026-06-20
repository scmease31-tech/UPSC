import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/study_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/section_header.dart';
import '../../models/subject.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// StudyScreen — Fully responsive Study Hub with adaptive grid,
/// scaled typography, and flexible quick-link layout.
/// ──────────────────────────────────────────────────────────────────────────────
class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _fadeCtrl;
  late CurvedAnimation _fadeCurve;
  final ScrollController _scrollController = ScrollController();

  static const _subjectIcons = <String, IconData>{
    'book': Icons.menu_book_rounded,
    'history': Icons.history_edu_rounded,
    'geography': Icons.public_rounded,
    'polity': Icons.account_balance_rounded,
    'economy': Icons.trending_up_rounded,
    'science': Icons.science_rounded,
    'environment': Icons.eco_rounded,
    'international': Icons.language_rounded,
    'ethics': Icons.balance_rounded,
  };

  static const _subjectColors = <int>[
    0xFF00BFA6, 0xFF7C4DFF, 0xFF448AFF, 0xFFFF6B6B,
    0xFF8D6E63, 0xFFFF9800, 0xFF4CAF50, 0xFFE91E63,
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..forward();
    _fadeCurve = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeCurve.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Responsive helpers ──
  double _hPad(double w) => w < 340 ? 12 : (w < 400 ? 16 : 20);
  double _scaledFont(double w, double base) {
    if (w < 340) return base - 2;
    if (w < 380) return base - 1;
    return base;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final study = context.watch<StudyProvider>();
    final progress = context.watch<DailyProgressProvider>();
    final w = MediaQuery.of(context).size.width;
    final hp = _hPad(w);

    Widget content = FadeTransition(
        opacity: _fadeCurve,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            if (!kIsWeb)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 16, hp, 4),
                  child: Text('Study Hub', style: GoogleFonts.plusJakartaSans(fontSize: _scaledFont(w, 26), fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
                ),
              ),

            // Study time card
            SliverToBoxAdapter(child: _buildStudyTime(context, progress, w)),

            // Quick links
            SliverToBoxAdapter(child: _buildQuickLinks(context, w)),

            // Subjects header
            SliverToBoxAdapter(
              child: SectionHeader(title: 'Subjects', padding: EdgeInsets.fromLTRB(hp, 16, hp, 8)),
            ),

            // Subject grid
            study.isLoading
                ? SliverToBoxAdapter(child: Center(child: Padding(padding: const EdgeInsets.all(40), child: Lottie.asset('assets/animations/loading.json', width: 100, height: 100))))
                : SliverToBoxAdapter(child: _buildSubjectGrid(context, study.subjects, w)),

            // Magazine shortcut
            SliverToBoxAdapter(child: _buildMagazineCard(context, w)),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      );

    return kIsWeb ? content : SafeArea(bottom: false, child: content);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // STUDY TIME CARD — scales height and inner elements by screen width
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildStudyTime(BuildContext context, DailyProgressProvider p, double w) {
    final hp = _hPad(w);
    final cardH = w < 340 ? 120.0 : (w < 400 ? 130.0 : 140.0);
    final circleSize = w < 340 ? 54.0 : (w < 400 ? 62.0 : 70.0);
    final circleFontSize = w < 340 ? 14.0 : (w < 400 ? 16.0 : 18.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 8, hp, 8),
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
                imageUrl: AppImages.studyHero,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(decoration: const BoxDecoration(gradient: AppTheme.heroGradient)),
                errorWidget: (_, __, ___) => Container(decoration: const BoxDecoration(gradient: AppTheme.heroGradient)),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryDark.withValues(alpha: 0.8),
                      AppTheme.primaryColor.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(w < 340 ? 14 : 20),
                child: Row(
                  children: [
                    CircularProgressWidget(
                      progress: (p.studyMinutesThisWeek / 300).clamp(0.0, 1.0),
                      size: circleSize,
                      strokeWidth: w < 380 ? 6 : 8,
                      progressColor: Colors.white,
                      trackColor: Colors.white24,
                      child: Text('${p.studyMinutesThisWeek}', style: GoogleFonts.plusJakartaSans(fontSize: circleFontSize, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    SizedBox(width: w < 340 ? 10 : 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Study Time This Week', style: GoogleFonts.plusJakartaSans(fontSize: _scaledFont(w, 15), fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Text('${p.studyMinutesThisWeek} / 300 min goal', style: GoogleFonts.inter(fontSize: _scaledFont(w, 12), color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: (p.studyMinutesThisWeek / 300).clamp(0.0, 1.0),
                              minHeight: 4,
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              valueColor: const AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
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

  // ═══════════════════════════════════════════════════════════════════════════
  // QUICK LINKS — Responsive grid that adapts columns to screen width
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQuickLinks(BuildContext context, double w) {
    final dark = AppTheme.isDark(context);
    final hp = _hPad(w);

    final allLinks = [
      _QLink('Flashcards', Icons.style_rounded, AppTheme.accentViolet, '/flashcards'),
      _QLink('Revision', Icons.replay_circle_filled_rounded, AppTheme.primaryColor, '/revision'),
      _QLink('Must Know', Icons.star_rounded, AppTheme.warningOrange, '/upsc-must-know'),
      _QLink('PYQ', Icons.history_edu_rounded, const Color(0xFFE91E63), '/pyq'),
      _QLink('Timer', Icons.timer_rounded, const Color(0xFFFF6B6B), '/study-timer'),
      _QLink('Notes', Icons.note_alt_rounded, const Color(0xFF8D6E63), '/quick-revision'),
      _QLink('Answer', Icons.edit_note_rounded, const Color(0xFF448AFF), '/answer-writing'),
      _QLink('Magazine', Icons.auto_stories_rounded, AppTheme.errorRed, '/magazine'),
      _QLink('Mock', Icons.quiz_rounded, const Color(0xFFD32F2F), '/mock-test'),
      _QLink('Affairs', Icons.newspaper_rounded, const Color(0xFF00897B), '/current-affairs'),
      _QLink('Syllabus', Icons.checklist_rounded, const Color(0xFFEF6C00), '/syllabus-tracker'),
      _QLink('Vocab', Icons.abc_rounded, const Color(0xFF5C6BC0), '/vocabulary'),
      _QLink('Schemes', Icons.account_balance_rounded, const Color(0xFF388E3C), '/govt-schemes'),
      _QLink('AI Search', Icons.auto_awesome_rounded, const Color(0xFF7C4DFF), '/ai-search'),
    ];

    // Adaptive: 4 columns on small, 5 on normal+
    final cols = w < 360 ? 4 : 5;
    final iconSize = w < 340 ? 18.0 : (w < 400 ? 20.0 : 22.0);
    final iconBoxSize = w < 340 ? 34.0 : (w < 400 ? 36.0 : 40.0);
    final labelSize = w < 340 ? 9.5 : (w < 400 ? 10.0 : 11.0);
    final spacing = w < 360 ? 6.0 : 8.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 4, hp, 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: w < 360 ? 0.72 : 0.75,
        ),
        itemCount: allLinks.length,
        itemBuilder: (context, i) {
          final l = allLinks[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushNamed(context, l.route);
            },
            child: Container(
              padding: EdgeInsets.symmetric(vertical: w < 360 ? 8 : 10),
              decoration: BoxDecoration(
                color: dark
                    ? l.color.withValues(alpha: 0.08)
                    : l.color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: l.color.withValues(alpha: dark ? 0.15 : 0.12),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: iconBoxSize,
                    height: iconBoxSize,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          l.color.withValues(alpha: 0.2),
                          l.color.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(l.icon, color: l.color, size: iconSize),
                  ),
                  SizedBox(height: w < 360 ? 4 : 6),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        l.label,
                        style: GoogleFonts.inter(fontSize: labelSize, fontWeight: FontWeight.w600, color: AppTheme.textP(context)),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SUBJECT GRID — Responsive columns + aspect ratio
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSubjectGrid(BuildContext context, List<Subject> subjects, double w) {
    final hp = _hPad(w);
    final cols = w < 340 ? 2 : (w >= 600 ? 3 : 2);
    final aspect = w < 340 ? 1.15 : (w < 400 ? 1.25 : 1.3);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: aspect,
        ),
        itemCount: subjects.length,
        itemBuilder: (context, i) {
          final s = subjects[i];
          final color = Color(_subjectColors[i % _subjectColors.length]);
          final icon = _subjectIcons[s.iconName] ?? Icons.menu_book_rounded;

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pushNamed(context, '/subject-detail', arguments: s.id);
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withValues(alpha: 0.65)],
                ),
                boxShadow: AppTheme.softShadow,
              ),
              child: Padding(
                padding: EdgeInsets.all(w < 360 ? 12 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: w < 360 ? 36 : 42,
                      height: w < 360 ? 36 : 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: w < 360 ? 18 : 22),
                    ),
                    const Spacer(),
                    Text(
                      s.name,
                      style: GoogleFonts.plusJakartaSans(fontSize: _scaledFont(w, 14), fontWeight: FontWeight.w700, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text('${s.notes.length} notes', style: GoogleFonts.inter(fontSize: _scaledFont(w, 11), color: Colors.white.withValues(alpha: 0.8))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAGAZINE CARD — flexible height instead of fixed
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMagazineCard(BuildContext context, double w) {
    final hp = _hPad(w);

    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 16, hp, 8),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/magazine'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.softShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: AppImages.magazineCover,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppTheme.pastelLavender),
                    errorWidget: (_, __, ___) => Container(color: AppTheme.pastelLavender),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.accentViolet.withValues(alpha: 0.85),
                          AppTheme.primaryColor.withValues(alpha: 0.5),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: w < 340 ? 14 : 18, vertical: w < 340 ? 14 : 18),
                  child: Row(
                    children: [
                      Container(
                        width: w < 340 ? 42 : 52,
                        height: w < 340 ? 42 : 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.auto_stories_rounded, color: Colors.white, size: w < 340 ? 22 : 28),
                      ),
                      SizedBox(width: w < 340 ? 10 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Weekly Magazine', style: GoogleFonts.plusJakartaSans(fontSize: _scaledFont(w, 15), fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('Download latest UPSC compilations', style: GoogleFonts.inter(fontSize: _scaledFont(w, 12), color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 20),
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
}

class _QLink {
  final String label;
  final IconData icon;
  final Color color;
  final String route;
  const _QLink(this.label, this.icon, this.color, this.route);
}
