import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// OnboardingScreen — 4-page premium intro with hero illustrations,
/// glassmorphic content cards, smooth page transitions, and animated dots.
/// ──────────────────────────────────────────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  final _ctrl = PageController();
  int _page = 0;
  late AnimationController _btnCtrl;
  late Animation<double> _btnScale;
  late AnimationController _iconCtrl;
  late Animation<double> _iconBounce;

  static const _pages = [
    _OnboardPage(
      icon: Icons.newspaper_rounded,
      svgAsset: 'assets/icons/onboard_news.svg',
      title: 'Daily Current Affairs',
      subtitle: 'AI-curated news analysis from The Hindu & Indian Express, tailored for UPSC aspirants.',
      gradient: [Color(0xFFD6F0F7), Color(0xFFE8D5F5)],
      accentColor: Color(0xFF00BFA6),
    ),
    _OnboardPage(
      icon: Icons.psychology_rounded,
      svgAsset: 'assets/icons/onboard_brain.svg',
      title: 'Smart Quizzes',
      subtitle: 'Test your knowledge with topic-wise and daily challenge quizzes. Track accuracy and XP.',
      gradient: [Color(0xFFE8D5F5), Color(0xFFF5C6E0)],
      accentColor: Color(0xFF7C4DFF),
    ),
    _OnboardPage(
      icon: Icons.style_rounded,
      svgAsset: 'assets/icons/onboard_flash.svg',
      title: 'Flash Revision',
      subtitle: 'Daily rotating flashcards, mnemonics, and short notes for quick memorization.',
      gradient: [Color(0xFFF5C6E0), Color(0xFFEFF9F0)],
      accentColor: Color(0xFFFF6B6B),
    ),
    _OnboardPage(
      icon: Icons.track_changes_rounded,
      svgAsset: 'assets/icons/onboard_target.svg',
      title: 'Track & Achieve',
      subtitle: 'Streaks, weekly progress, and exam countdown — everything to keep you on top.',
      gradient: [Color(0xFFEFF9F0), Color(0xFFD6F0F7)],
      accentColor: Color(0xFFFF9800),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _btnScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _btnCtrl, curve: Curves.easeInOut),
    );
    _iconCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _iconBounce = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut),
    );
    _iconCtrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _btnCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Web: Landing page layout ──
    if (kIsWeb) return _buildWebLanding(context);

    // ── Mobile: Swipeable onboarding pages ──
    return _buildMobileOnboarding(context);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // WEB LANDING PAGE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildWebLanding(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final isWide = screenW > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Top Nav Bar ──
            _buildWebNavBar(context),
            // ── Hero Section ──
            _buildWebHero(context, isWide),
            // ── Features Grid ──
            _buildWebFeatures(context, isWide),
            // ── Stats Banner ──
            _buildWebStats(context, isWide),
            // ── CTA Section ──
            _buildWebCTA(context),
            // ── Footer ──
            _buildWebFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildWebNavBar(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00BFA6), Color(0xFF00E5CC)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('U', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'UPSC Daily Edge',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          // Nav links
          _webNavLink('Features', () {}),
          const SizedBox(width: 32),
          _webNavLink('About', () {}),
          const SizedBox(width: 32),
          // Login button
          OutlinedButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            child: Text(
              'Log In',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
            ),
          ),
          const SizedBox(width: 12),
          // Get Started button
          ElevatedButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              elevation: 0,
            ),
            child: Text(
              'Get Started',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _webNavLink(String label, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildWebHero(BuildContext context, bool isWide) {
    final contentWidth = isWide ? 1200.0 : double.infinity;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF0FDF9), Color(0xFFEDE9FE), Color(0xFFFCE7F3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: contentWidth),
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 64 : 32,
            vertical: isWide ? 80 : 48,
          ),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left: Text content
                    Expanded(
                      flex: 5,
                      child: _buildHeroText(context),
                    ),
                    const SizedBox(width: 64),
                    // Right: Feature cards stack
                    Expanded(
                      flex: 4,
                      child: _buildHeroVisual(context),
                    ),
                  ],
                )
              : Column(
                  children: [
                    _buildHeroText(context),
                    const SizedBox(height: 48),
                    _buildHeroVisual(context),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeroText(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.rocket_launch_rounded, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text(
                '#1 UPSC Preparation Platform',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        // Headline
        Text(
          'Your AI-Powered\nUPSC Companion',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 52,
            fontWeight: FontWeight.w900,
            color: AppTheme.textPrimary,
            height: 1.1,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 20),
        // Subtext
        Text(
          'Master Current Affairs, practice smart quizzes, track your progress, and ace the UPSC exam with AI-curated study material.',
          style: GoogleFonts.inter(
            fontSize: 18,
            color: AppTheme.textSecondary,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 36),
        // CTA buttons
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
                elevation: 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Start Free', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
              ),
              child: Text(
                'I have an account',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroVisual(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stacked feature preview cards
        _heroCard(
          Icons.newspaper_rounded,
          'Daily Current Affairs',
          'AI-curated news from The Hindu & Indian Express',
          const Color(0xFF00BFA6),
          const [Color(0xFFD1FAE5), Color(0xFFE0F7F4)],
        ),
        const SizedBox(height: 16),
        _heroCard(
          Icons.psychology_rounded,
          'Smart Quizzes',
          'Topic-wise & daily challenges with XP tracking',
          const Color(0xFF7C4DFF),
          const [Color(0xFFEDE9FE), Color(0xFFE8D5F5)],
        ),
        const SizedBox(height: 16),
        _heroCard(
          Icons.track_changes_rounded,
          'Progress Tracking',
          'Streaks, weekly reports & exam countdown',
          const Color(0xFFFF6B6B),
          const [Color(0xFFFEE2E2), Color(0xFFFCE7F3)],
        ),
      ],
    );
  }

  Widget _heroCard(IconData icon, String title, String subtitle, Color accent, List<Color> bgGradient) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: bgGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebFeatures(BuildContext context, bool isWide) {
    final features = [
      _WebFeature(Icons.newspaper_rounded, 'Current Affairs', 'Daily AI-curated analysis from top newspapers, tailored for UPSC preparation.', AppTheme.primaryColor),
      _WebFeature(Icons.psychology_rounded, 'Smart Quizzes', 'Topic-wise practice with AI-generated questions. Track accuracy and earn XP.', AppTheme.accentViolet),
      _WebFeature(Icons.style_rounded, 'Flashcards', 'Quick revision with daily rotating cards, mnemonics, and short notes.', const Color(0xFFFF6B6B)),
      _WebFeature(Icons.track_changes_rounded, 'Progress Tracker', 'Streaks, weekly reports, exam countdown — stay motivated daily.', const Color(0xFFFF9800)),
      _WebFeature(Icons.auto_awesome_rounded, 'AI Search', 'Ask anything about UPSC topics and get instant, detailed answers.', const Color(0xFF448AFF)),
      _WebFeature(Icons.menu_book_rounded, 'Study Hub', 'Organized subjects, PYQs, answer writing practice, and syllabus tracking.', const Color(0xFF8D6E63)),
    ];

    final cols = isWide ? 3 : (MediaQuery.of(context).size.width > 600 ? 2 : 1);

    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 64 : 24,
            vertical: 72,
          ),
          child: Column(
            children: [
              Text(
                'Everything You Need to Crack UPSC',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: isWide ? 36 : 28,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Comprehensive tools and content designed specifically for UPSC aspirants.',
                style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textSecondary, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  childAspectRatio: isWide ? 2.0 : 2.2,
                ),
                itemCount: features.length,
                itemBuilder: (context, i) {
                  final f = features[i];
                  return _WebFeatureCard(feature: f);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebStats(BuildContext context, bool isWide) {
    final stats = [
      _WebStat('10K+', 'Active Learners'),
      _WebStat('5000+', 'Quiz Questions'),
      _WebStat('500+', 'Articles Daily'),
      _WebStat('95%', 'User Satisfaction'),
    ];

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1B2838)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 64 : 24,
            vertical: 56,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: stats.map((s) => Column(
              children: [
                Text(
                  s.value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: isWide ? 40 : 28,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Colors.white60,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildWebCTA(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF7F8FC),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          padding: const EdgeInsets.symmetric(vertical: 72, horizontal: 32),
          child: Column(
            children: [
              Text(
                'Ready to Start Your UPSC Journey?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Join thousands of aspirants who are preparing smarter with UPSC Daily Edge.',
                style: GoogleFonts.inter(fontSize: 16, color: AppTheme.textSecondary, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                  elevation: 0,
                ),
                child: Text(
                  'Create Free Account →',
                  style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
      ),
      child: Center(
        child: Text(
          '© 2024 UPSC Daily Edge. Built for aspirants, by aspirants.',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textTertiary),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MOBILE ONBOARDING (existing)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMobileOnboarding(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: _pages.length,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _page = i);
              _iconCtrl.reset();
              _iconCtrl.forward();
            },
            itemBuilder: (context, i) => _buildPage(context, _pages[i], i),
          ),
          // Bottom controls
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(32, 20, 32, MediaQuery.of(context).padding.bottom + 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _pages[_page].gradient[1].withValues(alpha: 0),
                    _pages[_page].gradient[1],
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _page == i ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        gradient: _page == i
                            ? LinearGradient(colors: [_pages[_page].accentColor, _pages[_page].accentColor.withValues(alpha: 0.6)])
                            : null,
                        color: _page == i ? null : Colors.black.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: _page == i
                            ? [BoxShadow(color: _pages[_page].accentColor.withValues(alpha: 0.3), blurRadius: 6)]
                            : null,
                      ),
                    )),
                  ),
                  const SizedBox(height: 28),
                  // CTA button
                  ScaleTransition(
                    scale: _btnScale,
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          _btnCtrl.forward().then((_) => _btnCtrl.reverse());
                          if (isLast) {
                            Navigator.pushReplacementNamed(context, '/login');
                          } else {
                            _ctrl.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pages[_page].accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isLast ? 'Get Started' : 'Continue',
                              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!isLast)
                    TextButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                      child: Text('Skip', style: GoogleFonts.inter(fontSize: 14, color: Colors.black45)),
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(BuildContext context, _OnboardPage p, int index) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: p.gradient,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            children: [
              const Spacer(flex: 3),
              // SVG icon badge
              CustomAnimatedBuilder(
                animation: _iconBounce,
                builder: (context, _) {
                  return Transform.scale(
                    scale: _iconBounce.value,
                    child: Container(
                      width: 140, height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [p.accentColor, p.accentColor.withValues(alpha: 0.65)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(color: p.accentColor.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 14)),
                          BoxShadow(color: p.accentColor.withValues(alpha: 0.1), blurRadius: 80, spreadRadius: 10),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Background decorative ring
                          Container(
                            width: 120, height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(34),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
                            ),
                          ),
                          // SVG icon
                          SvgPicture.asset(
                            p.svgAsset,
                            width: 56, height: 56,
                            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 44),
              // Content card with subtle glass effect
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        // Page number badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: p.accentColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: p.accentColor.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            'Step ${index + 1} of ${_pages.length}',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: p.accentColor),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Title
                        Text(
                          p.title,
                          style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, height: 1.2, letterSpacing: -0.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        // Subtitle
                        Text(
                          p.subtitle,
                          style: GoogleFonts.inter(fontSize: 15, color: AppTheme.textSecondary, height: 1.65, letterSpacing: 0.1),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 5),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardPage {
  final IconData icon;
  final String svgAsset;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final Color accentColor;
  const _OnboardPage({required this.icon, required this.svgAsset, required this.title, required this.subtitle, required this.gradient, required this.accentColor});
}

class _WebFeature {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  const _WebFeature(this.icon, this.title, this.description, this.color);
}

class _WebFeatureCard extends StatefulWidget {
  final _WebFeature feature;
  const _WebFeatureCard({required this.feature});
  @override
  State<_WebFeatureCard> createState() => _WebFeatureCardState();
}

class _WebFeatureCardState extends State<_WebFeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.feature;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(24),
        transform: _hovered ? (Matrix4.identity()..translate(0.0, -4.0)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hovered ? f.color.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered ? f.color.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.03),
              blurRadius: _hovered ? 24 : 8,
              offset: Offset(0, _hovered ? 8 : 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: f.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(f.icon, color: f.color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    f.title,
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    f.description,
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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

class _WebStat {
  final String value;
  final String label;
  const _WebStat(this.value, this.label);
}
