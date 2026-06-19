import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// WebShell — Desktop/web layout with collapsible sidebar navigation,
/// top bar, and wide content area. Completely different UX from mobile.
/// ──────────────────────────────────────────────────────────────────────────────
class WebShell extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final IndexedWidgetBuilder screenBuilder;

  const WebShell({
    super.key,
    required this.currentIndex,
    required this.onIndexChanged,
    required this.screenBuilder,
  });

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> with SingleTickerProviderStateMixin {
  bool _sidebarExpanded = true;
  int _hoveredIndex = -1;

  static const _navItems = [
    _WebNavItem(Icons.space_dashboard_rounded, 'Dashboard', 'Overview & progress'),
    _WebNavItem(Icons.feed_rounded, 'News Feed', 'Current affairs'),
    _WebNavItem(Icons.psychology_rounded, 'Quizzes', 'Test knowledge'),
    _WebNavItem(Icons.auto_stories_rounded, 'Study Hub', 'Subjects & tools'),
    _WebNavItem(Icons.account_circle_rounded, 'Profile', 'Account & settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    final auth = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 900;

    // Auto-collapse sidebar on smaller screens
    if (isCompact && _sidebarExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _sidebarExpanded = false);
      });
    }

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B0F19) : const Color(0xFFF7F8FC),
      body: Row(
        children: [
          // ── Sidebar ──
          _buildSidebar(context, dark, auth, themeProvider),
          // ── Vertical divider ──
          Container(
            width: 1,
            color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.06),
          ),
          // ── Main content area ──
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, dark, auth),
                Expanded(
                  child: widget.screenBuilder(context, widget.currentIndex),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SIDEBAR
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSidebar(BuildContext context, bool dark, AuthProvider auth, ThemeProvider themeProvider) {
    final expanded = _sidebarExpanded;
    final sidebarWidth = expanded ? 260.0 : 76.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0D1117) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.04),
            blurRadius: 24,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // ── Logo ──
          _buildLogo(dark, expanded),
          const SizedBox(height: 32),
          // ── Nav Items ──
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 10),
              children: [
                ...List.generate(_navItems.length, (i) => _buildNavItem(i, _navItems[i], dark, expanded)),
                if (expanded) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Divider(
                      color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildQuickLink(context, Icons.flash_on_rounded, 'Daily Challenge', '/daily-challenge', dark),
                  _buildQuickLink(context, Icons.auto_awesome_rounded, 'AI Search', '/ai-search', dark),
                  _buildQuickLink(context, Icons.style_rounded, 'Flashcards', '/flashcards', dark),
                  _buildQuickLink(context, Icons.explore_rounded, 'Explore', '/explore', dark),
                ],
              ],
            ),
          ),
          // ── Theme toggle ──
          _buildThemeToggle(context, dark, themeProvider, expanded),
          const SizedBox(height: 8),
          // ── Collapse toggle ──
          _buildCollapseToggle(dark, expanded),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLogo(bool dark, bool expanded) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 20 : 10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00BFA6), Color(0xFF00E5CC)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00BFA6).withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text('U', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UPSC Daily Edge',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: dark ? Colors.white : AppTheme.textPrimary,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Exam Preparation',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, _WebNavItem item, bool dark, bool expanded) {
    final isActive = widget.currentIndex == index;
    final isHovered = _hoveredIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoveredIndex = index),
        onExit: (_) => setState(() => _hoveredIndex = -1),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => widget.onIndexChanged(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 0,
              vertical: expanded ? 12 : 14,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? (dark ? AppTheme.primaryColor.withValues(alpha: 0.12) : AppTheme.primaryColor.withValues(alpha: 0.08))
                  : isHovered
                      ? (dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03))
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2))
                  : null,
            ),
            child: Row(
              mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  size: 22,
                  color: isActive
                      ? AppTheme.primaryColor
                      : (dark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
                ),
                if (expanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive
                                ? AppTheme.primaryColor
                                : (dark ? AppTheme.darkTextPrimary : AppTheme.textPrimary),
                          ),
                          maxLines: 1,
                        ),
                        Text(
                          item.subtitle,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickLink(BuildContext context, IconData icon, String label, String route, bool dark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, route),
          borderRadius: BorderRadius.circular(10),
          hoverColor: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: dark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeToggle(BuildContext context, bool dark, ThemeProvider themeProvider, bool expanded) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 20 : 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => themeProvider.toggleTheme(),
          borderRadius: BorderRadius.circular(12),
          hoverColor: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  size: 20,
                  color: dark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                ),
                if (expanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      dark ? 'Light Mode' : 'Dark Mode',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: dark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapseToggle(bool dark, bool expanded) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 20 : 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
          borderRadius: BorderRadius.circular(12),
          hoverColor: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? 14 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(
                  expanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                  size: 20,
                  color: dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary,
                ),
                if (expanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Collapse',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // TOP BAR
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildTopBar(BuildContext context, bool dark, AuthProvider auth) {
    final name = auth.userProfile?.name ?? 'Scholar';
    final photoUrl = auth.userProfile?.photoUrl;
    final pageTitle = _navItems[widget.currentIndex].label;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0D1117) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: dark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          // Page title
          Text(
            pageTitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : AppTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          // Search bar
          Container(
            width: 280,
            height: 40,
            decoration: BoxDecoration(
              color: dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F3F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pushNamed(context, '/ai-search'),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 18, color: dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary),
                      const SizedBox(width: 10),
                      Text(
                        'Search topics, articles...',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Notification bell
          _WebIconButton(
            icon: Icons.notifications_outlined,
            dark: dark,
            onTap: () {},
          ),
          const SizedBox(width: 8),
          // User avatar
          _WebUserChip(name: name, photoUrl: photoUrl, dark: dark),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER CLASSES
// ═══════════════════════════════════════════════════════════════════════

class _WebNavItem {
  final IconData icon;
  final String label;
  final String subtitle;
  const _WebNavItem(this.icon, this.label, this.subtitle);
}

class _WebIconButton extends StatefulWidget {
  final IconData icon;
  final bool dark;
  final VoidCallback onTap;
  const _WebIconButton({required this.icon, required this.dark, required this.onTap});
  @override
  State<_WebIconButton> createState() => _WebIconButtonState();
}

class _WebIconButtonState extends State<_WebIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.dark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F3F9))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: widget.dark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _WebUserChip extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final bool dark;
  const _WebUserChip({required this.name, this.photoUrl, required this.dark});

  @override
  Widget build(BuildContext context) {
    final firstName = name.split(' ').first;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F3F9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
            backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
            child: (photoUrl == null || photoUrl!.isEmpty)
                ? Text(
                    firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            firstName,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: dark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
