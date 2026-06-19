import 'dart:ui';
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
