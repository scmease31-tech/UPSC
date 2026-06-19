import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/articles_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/section_header.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// ExploreScreen — Rebuilt: clean, professional, no emojis.
/// ──────────────────────────────────────────────────────────────────────────────
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final articles = context.watch<ArticlesProvider>();
    final progress = context.watch<DailyProgressProvider>();
    final dark = AppTheme.isDark(context);

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(child: _buildHeader(context)),

              // Exam countdown cards
              SliverToBoxAdapter(child: _buildCountdownRow(context, progress, dark)),

              // Quick tools
              SliverToBoxAdapter(
                child: SectionHeader(title: 'Quick Tools', padding: const EdgeInsets.fromLTRB(20, 20, 20, 10)),
              ),
              SliverToBoxAdapter(child: _buildToolGrid(context, dark)),

              // Browse by date
              SliverToBoxAdapter(
                child: SectionHeader(title: 'Browse by Date', padding: const EdgeInsets.fromLTRB(20, 20, 20, 10)),
              ),
              SliverToBoxAdapter(child: _buildDateStrip(context, articles, dark)),

              // Syllabus overview
              SliverToBoxAdapter(
                child: SectionHeader(title: 'Syllabus Overview', padding: const EdgeInsets.fromLTRB(20, 20, 20, 10)),
              ),
              SliverToBoxAdapter(child: _buildSyllabus(context, dark)),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HEADER ────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
          ),
          Text(
            'Explore',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textP(context),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36, height: 36,
            child: Icon(Icons.explore_rounded, color: AppTheme.primaryColor, size: 28),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              DateFormat('d MMM').format(DateTime.now()),
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  // ─── EXAM COUNTDOWN ───────────────────────────────────────────────────────

  Widget _buildCountdownRow(BuildContext context, DailyProgressProvider p, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(
        children: [
          Expanded(child: _countdownCard(
            context, dark,
            label: 'Prelims ${p.prelimsExamYear}',
            days: p.daysToPrelimsExam,
            gradient: [AppTheme.primaryColor, const Color(0xFF00E5FF)],
            icon: Icons.event_available_rounded,
          )),
          const SizedBox(width: 12),
          Expanded(child: _countdownCard(
            context, dark,
            label: 'Mains ${p.mainsExamYear}',
            days: p.daysToMainsExam,
            gradient: [AppTheme.accentViolet, const Color(0xFFE040FB)],
            icon: Icons.edit_calendar_rounded,
          )),
        ],
      ),
    );
  }

  Widget _countdownCard(
    BuildContext context, bool dark, {
    required String label,
    required int days,
    required List<Color> gradient,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: gradient.map((c) => c.withValues(alpha: dark ? 0.25 : 0.12)).toList(),
        ),
        border: Border.all(color: gradient[0].withValues(alpha: dark ? 0.2 : 0.15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: gradient[0]),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textS(context))),
            ],
          ),
          const SizedBox(height: 8),
          ShaderMask(
            shaderCallback: (b) => LinearGradient(colors: gradient).createShader(b),
            child: Text(
              '$days',
              style: GoogleFonts.plusJakartaSans(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          Text('days remaining', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
        ],
      ),
    );
  }

  // ─── QUICK TOOLS ──────────────────────────────────────────────────────────

  Widget _buildToolGrid(BuildContext context, bool dark) {
    final tools = [
      _Tool('Daily Practice', Icons.edit_note_rounded, AppTheme.primaryColor, '/daily-practice'),
      _Tool('Daily Challenge', Icons.flash_on_rounded, AppTheme.warningOrange, '/daily-challenge'),
      _Tool('Revision Hub', Icons.replay_circle_filled_rounded, AppTheme.accentViolet, '/revision'),
      _Tool('Must Know', Icons.star_rounded, const Color(0xFFFF6B6B), '/upsc-must-know'),
      _Tool('Flashcards', Icons.style_rounded, const Color(0xFF448AFF), '/flashcards'),
      _Tool('Magazine', Icons.auto_stories_rounded, AppTheme.primaryDark, '/magazine'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.88,
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
                    color: t.color.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          t.color.withValues(alpha: 0.18),
                          t.color.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(t.icon, color: t.color, size: 24),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      t.label,
                      style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: AppTheme.textP(context), height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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

  // ─── BROWSE BY DATE ───────────────────────────────────────────────────────

  Widget _buildDateStrip(BuildContext context, ArticlesProvider articles, bool dark) {
    final dates = articles.availableDates.take(7).toList();
    if (dates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('No dates available yet', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
          ),
        ),
      );
    }
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final d = dates[i];
          // Try to parse the date string for a nicer display
          DateTime? parsed;
          try { parsed = DateFormat('dd MMM yyyy').parse(d); } catch (_) {}
          final dayNum = parsed != null ? DateFormat('dd').format(parsed) : d;
          final month = parsed != null ? DateFormat('MMM').format(parsed) : '';
          final weekDay = parsed != null ? DateFormat('EEE').format(parsed) : '';

          return GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              articles.setDate(d);
              Navigator.pop(context);
            },
            child: Container(
              width: 64,
              decoration: BoxDecoration(
                color: dark
                    ? AppTheme.primaryColor.withValues(alpha: 0.08)
                    : AppTheme.primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
              ),
              child: parsed != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(weekDay, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textS(context))),
                        const SizedBox(height: 2),
                        Text(dayNum, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
                        Text(month, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textS(context))),
                      ],
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(d, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textP(context)),
                            textAlign: TextAlign.center),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  // ─── SYLLABUS OVERVIEW ────────────────────────────────────────────────────

  Widget _buildSyllabus(BuildContext context, bool dark) {
    final items = [
      _SyllabusItem('GS-I', 'Heritage, History, Geography, Society', Icons.account_balance_rounded, AppTheme.primaryColor),
      _SyllabusItem('GS-II', 'Governance, Polity, International Relations', Icons.gavel_rounded, AppTheme.accentViolet),
      _SyllabusItem('GS-III', 'Technology, Economy, Environment, Security', Icons.science_rounded, AppTheme.warningOrange),
      _SyllabusItem('GS-IV', 'Ethics, Integrity and Aptitude', Icons.psychology_rounded, const Color(0xFF448AFF)),
      _SyllabusItem('Essay', 'Philosophical, Social, Political Topics', Icons.edit_rounded, const Color(0xFFFF6B6B)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: dark ? AppTheme.darkCardBg : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: item.color.withValues(alpha: 0.12)),
                boxShadow: [
                  BoxShadow(
                    color: item.color.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: dark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.color, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.tag, style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w700, color: item.color,
                        )),
                        const SizedBox(height: 2),
                        Text(item.desc, style: GoogleFonts.inter(
                          fontSize: 12, color: AppTheme.textS(context), height: 1.3,
                        )),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppTheme.textS(context), size: 20),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── DATA CLASSES ─────────────────────────────────────────────────────────────

class _Tool {
  final String label;
  final IconData icon;
  final Color color;
  final String route;
  const _Tool(this.label, this.icon, this.color, this.route);
}

class _SyllabusItem {
  final String tag;
  final String desc;
  final IconData icon;
  final Color color;
  const _SyllabusItem(this.tag, this.desc, this.icon, this.color);
}
