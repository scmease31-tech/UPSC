import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';

/// Web-friendly centered layout for auth screens (login/signup).
/// Shows a constrained-width card on a clean background.
class WebAuthScaffold extends StatelessWidget {
  final Widget child;
  const WebAuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    final screenW = MediaQuery.of(context).size.width;
    final isWide = screenW > 800;

    final formPanel = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Back to landing
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushReplacementNamed(context, '/onboarding');
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text('Back', style: GoogleFonts.inter(fontSize: 14)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );

    if (!isWide) {
      // Narrow: just form centered, no branding panel
      return Scaffold(
        backgroundColor: dark ? const Color(0xFF0B0F19) : const Color(0xFFF7F8FC),
        body: formPanel,
      );
    }

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B0F19) : const Color(0xFFF7F8FC),
      body: Row(
        children: [
          // Left: Branding panel
          Expanded(
            flex: 5,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00BFA6), Color(0xFF00897B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Text('U', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'UPSC Daily Edge',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your AI-Powered UPSC Companion',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      // Feature highlights
                      for (final item in const [
                        ('📰', 'Daily Current Affairs from top sources'),
                        ('🧠', 'Smart Quizzes with XP tracking'),
                        ('📝', 'Flash Revision & Mnemonics'),
                        ('📊', 'Progress tracking & streaks'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(item.$1, style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 14),
                              Text(
                                item.$2,
                                style: GoogleFonts.inter(
                                  fontSize: 15,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Right: Auth form
          Expanded(
            flex: 4,
            child: formPanel,
          ),
        ],
      ),
    );
  }
}

/// Web-friendly layout for feature sub-pages.
/// Shows constrained-width content with a clean header and back button.
class WebFeatureScaffold extends StatelessWidget {
  final Widget child;
  final String title;
  const WebFeatureScaffold({super.key, required this.child, this.title = ''});

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    final screenW = MediaQuery.of(context).size.width;
    final isNarrow = screenW < 600;

    return Scaffold(
      backgroundColor: dark ? const Color(0xFF0B0F19) : const Color(0xFFF7F8FC),
      body: Column(
        children: [
          // Top header bar
          Container(
            height: 56,
            padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 32),
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
                // Back button
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushReplacementNamed(context, '/main');
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F3F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back_rounded, size: 18,
                            color: dark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
                          if (!isNarrow) ...[
                            const SizedBox(width: 8),
                            Text('Back to Dashboard', style: GoogleFonts.inter(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: dark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
                            )),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (!isNarrow) ...[
                // Logo
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF00BFA6), Color(0xFF00E5CC)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('U', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(width: 10),
                Text('UPSC Daily Edge', style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: dark ? Colors.white : AppTheme.textPrimary,
                )),
                ],
                if (title.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('/', style: GoogleFonts.inter(
                      fontSize: 16, color: dark ? AppTheme.darkTextTertiary : AppTheme.textTertiary,
                    )),
                  ),
                  Text(title, style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w600,
                    color: dark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
                  )),
                ],
              ],
            ),
          ),
          // Content area
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isNarrow ? double.infinity : 1100),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 0),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
