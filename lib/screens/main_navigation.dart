import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';
import 'home/home_screen.dart';
import 'news/news_screen.dart';
import 'quiz/quiz_screen.dart';
import 'study/study_screen.dart';
import 'profile/profile_screen.dart';
import 'web/web_shell.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// MainNavigation — Adaptive layout:
///   • Web: Sidebar navigation with wide content area (WebShell)
///   • Mobile: Bottom tab bar with glassmorphic floating nav
/// ──────────────────────────────────────────────────────────────────────────────
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  /// Navigate to a specific tab from child screens.
  static void switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_MainNavigationState>();
    state?._switchTo(index);
  }

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _navAnimCtrl;

  void _switchTo(int index) {
    if (index >= 0 && index < 5 && index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  // Lazy-load screens: only build when first visited to avoid "Skipped frames" on startup.
  final Map<int, Widget> _builtScreens = {};

  Widget _getScreen(int index) {
    return _builtScreens.putIfAbsent(index, () {
      switch (index) {
        case 0: return const HomeScreen();
        case 1: return const NewsScreen();
        case 2: return const QuizScreen();
        case 3: return const StudyScreen();
        case 4: return const ProfileScreen();
        default: return const HomeScreen();
      }
    });
  }

  final List<_NavItem> _navItems = const [
    _NavItem(asset: 'assets/icons/home.png', label: 'Home'),
    _NavItem(asset: 'assets/icons/news.png', label: 'News'),
    _NavItem(asset: 'assets/icons/quiz.png', label: 'Quiz'),
    _NavItem(asset: 'assets/icons/table.png', label: 'Study'),
    _NavItem(asset: 'assets/icons/user.png', label: 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _navAnimCtrl = AnimationController(
      vsync: this,
      duration: AppTheme.durationMedium,
    );
  }

  @override
  void dispose() {
    _navAnimCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Web: Sidebar navigation layout ──
    if (kIsWeb) {
      return WebShell(
        currentIndex: _currentIndex,
        onIndexChanged: (i) => setState(() => _currentIndex = i),
        screenBuilder: (context, index) {
          if (_builtScreens.containsKey(index) || index == _currentIndex) {
            return _getScreen(index);
          }
          return const SizedBox.shrink();
        },
      );
    }

    // ── Mobile: Bottom nav bar layout ──
    final dark = AppTheme.isDark(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGradient(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _currentIndex,
          children: List.generate(5, (i) {
            // Only build screens that have been visited
            if (_builtScreens.containsKey(i) || i == _currentIndex) {
              return _getScreen(i);
            }
            return const SizedBox.shrink();
          }),
        ),
        extendBody: true,
        bottomNavigationBar: RepaintBoundary(
          child: Container(
            margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding > 0 ? bottomPadding : 12),
            height: 72,
            decoration: BoxDecoration(
              color: dark
                  ? const Color(0xF0111111)
                  : const Color(0xF5FFFFFF),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.6),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_navItems.length, (i) {
                final isActive = i == _currentIndex;
                final item = _navItems[i];
                return _buildNavItem(
                  pngAsset: item.asset,
                  label: item.label,
                  isActive: isActive,
                  onTap: () {
                    if (i != _currentIndex) {
                      HapticFeedback.lightImpact();
                      setState(() => _currentIndex = i);
                    }
                  },
                  dark: dark,
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required String pngAsset,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required bool dark,
  }) {
    return Expanded(
      child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
          duration: AppTheme.durationMedium,
          curve: AppTheme.curveDefault,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primaryColor.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isActive ? 1.05 : 1.0,
                duration: AppTheme.durationMedium,
                curve: AppTheme.curveDefault,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isActive ? 1.0 : 0.4,
                  child: Image.asset(
                    pngAsset,
                    width: 24,
                    height: 24,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.inter(
                  fontSize: isActive ? 10 : 9.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppTheme.primaryColor
                      : (dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary),
                  letterSpacing: isActive ? 0.2 : 0,
                ),
                child: Text(label, textAlign: TextAlign.center, maxLines: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String asset;
  final String label;

  const _NavItem({
    required this.asset,
    required this.label,
  });
}
