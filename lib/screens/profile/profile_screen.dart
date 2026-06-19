import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/section_header.dart';
import '../../widgets/network_image_widget.dart';
import '../../services/notification_service.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// ProfileScreen — User stats, settings, theme toggle, and account management.
/// ──────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    final progress = context.watch<DailyProgressProvider>();
    final user = auth.userProfile;
    final dark = theme.isDark;

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text('Profile', style: GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
            ),
          ),

          // Profile card
          SliverToBoxAdapter(child: _buildProfileCard(context, auth, user)),

          // Stats
          SliverToBoxAdapter(child: _buildStatsRow(context, auth, progress)),

          // Settings
          SliverToBoxAdapter(
            child: SectionHeader(title: 'Settings', padding: const EdgeInsets.fromLTRB(20, 10, 20, 6)),
          ),
          SliverToBoxAdapter(child: _buildSettings(context, theme, dark)),

          // Actions
          SliverToBoxAdapter(
            child: SectionHeader(title: 'Quick Links', padding: const EdgeInsets.fromLTRB(20, 10, 20, 6)),
          ),
          SliverToBoxAdapter(child: _buildActions(context)),

          // Sign out
          if (auth.isLoggedIn)
            SliverToBoxAdapter(child: _buildSignOut(context, auth)),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),

    );
  }

  Widget _buildProfileCard(BuildContext context, AuthProvider auth, dynamic user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: GlassCard(
        gradient: AppTheme.heroGradient,
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            AvatarImage(
              imageUrl: user?.photoUrl != null && user!.photoUrl.isNotEmpty ? user.photoUrl : null,
              name: auth.isLoggedIn ? (user?.name ?? 'User') : 'Guest',
              radius: 36,
              borderWidth: 3,
              borderGradient: const LinearGradient(
                colors: [Colors.white, Color(0xFFE0E0E0)],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.isLoggedIn ? (user?.name ?? 'User') : 'Guest User',
                    style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (auth.isLoggedIn && user?.email != null) ...[
                    const SizedBox(height: 2),
                    Text(user!.email, style: GoogleFonts.inter(fontSize: 12, color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  if (!auth.isLoggedIn) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/login'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.login_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            Text('Sign In', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, AuthProvider auth, DailyProgressProvider progress) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Column(
        children: [
          Row(
            children: [
              _statCard(context, '${progress.currentStreak}', 'Streak', Icons.local_fire_department_rounded, AppTheme.errorRed),
              const SizedBox(width: 6),
              _statCard(context, '${auth.totalQuizzesTaken}', 'Quizzes', Icons.quiz_rounded, AppTheme.accentViolet),
              const SizedBox(width: 6),
              _statCard(context, '${(auth.averageAccuracy * 100).round()}%', 'Accuracy', Icons.analytics_rounded, AppTheme.primaryColor),
              const SizedBox(width: 6),
              _statCard(context, '${progress.articlesReadThisWeek}', 'Articles', Icons.article_rounded, AppTheme.warningOrange),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _statCard(context, '${progress.longestStreak}', 'Best Streak', Icons.emoji_events_rounded, AppTheme.warmYellow),
              const SizedBox(width: 6),
              _statCard(context, '${progress.dailyChallengeTotalXp}', 'Total XP', Icons.stars_rounded, AppTheme.primaryColor),
              const SizedBox(width: 6),
              _statCard(context, '${progress.studyMinutesThisWeek}m', 'Study Time', Icons.timer_rounded, AppTheme.successGreen),
              const SizedBox(width: 6),
              _statCard(context, '${progress.masteredFlashcards.length}', 'Mastered', Icons.check_circle_rounded, AppTheme.accentViolet),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(BuildContext context, String value, String label, IconData icon, Color color) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 6),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textP(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w500, color: AppTheme.textS(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings(BuildContext context, ThemeProvider theme, bool dark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _settingTile(
              context,
              icon: Icons.dark_mode_rounded,
              color: AppTheme.accentViolet,
              title: 'Dark Mode',
              trailing: Switch.adaptive(
                value: dark,
                onChanged: (_) => theme.toggleTheme(),
                activeTrackColor: AppTheme.primaryColor,
              ),
            ),
            _divider(),
            _settingTile(
              context,
              icon: Icons.notifications_rounded,
              color: AppTheme.warningOrange,
              title: 'Notifications',
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () => _showNotificationSettings(context),
            ),
            _divider(),
            _settingTile(
              context,
              icon: Icons.info_rounded,
              color: AppTheme.primaryColor,
              title: 'About App',
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () => _showAboutDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            _settingTile(context, icon: Icons.emoji_events_rounded, color: AppTheme.warningOrange, title: 'Weekly Progress',
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () => Navigator.pushNamed(context, '/weekly-progress'),
            ),
            _divider(),
            _settingTile(context, icon: Icons.track_changes_rounded, color: AppTheme.primaryColor, title: 'Content Tracker',
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () => Navigator.pushNamed(context, '/content-tracker'),
            ),
            _divider(),
            _settingTile(context, icon: Icons.explore_rounded, color: AppTheme.accentViolet, title: 'Explore',
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              onTap: () => Navigator.pushNamed(context, '/explore'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignOut(BuildContext context, AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: () async {
            HapticFeedback.mediumImpact();
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text('Sign Out?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                content: Text('Your local data will be preserved.', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textS(context))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600))),
                  TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Sign Out', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.errorRed))),
                ],
              ),
            );
            if (confirmed == true) {
              await auth.signOut();
              if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
            }
          },
          icon: Icon(Icons.logout_rounded, color: AppTheme.errorRed),
          label: Text('Sign Out', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: AppTheme.errorRed)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppTheme.errorRed.withValues(alpha: 0.3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    );
  }

  Widget _settingTile(BuildContext context, {required IconData icon, required Color color, required String title, required Widget trailing, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textP(context))),
      trailing: trailing,
    );
  }

  Widget _divider() => Divider(height: 1, indent: 64, color: Colors.grey.withValues(alpha: 0.1));

  void _showNotificationSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 5,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Notification Settings',
                  style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textP(ctx))),
              const SizedBox(height: 4),
              Text('Manage your daily reminders', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(ctx))),
              const SizedBox(height: 20),
              _notifItem(ctx, Icons.article_rounded, 'Daily Current Affairs', '8:00 AM', AppTheme.primaryColor),
              _notifItem(ctx, Icons.style_rounded, 'Flashcard Reminder', '7:30 AM', AppTheme.accentViolet),
              _notifItem(ctx, Icons.quiz_rounded, 'Quiz Reminder', '6:00 PM', AppTheme.warningOrange),
              _notifItem(ctx, Icons.menu_book_rounded, 'Study Reminder', '9:00 PM', const Color(0xFFFF6B6B)),
              _notifItem(ctx, Icons.local_fire_department_rounded, 'Streak Reminder', '8:00 PM', AppTheme.errorRed),
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
                            const SnackBar(content: Text('All notifications turned off')),
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
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _notifItem(BuildContext context, IconData icon, String title, String time, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textP(context))),
            ),
            Text(time, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text('UPSC Daily Edge', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
            const SizedBox(height: 12),
            Text(
              'Your daily companion for UPSC preparation. Get curated current affairs, practice quizzes, flashcards, and track your progress — all in one app.',
              style: GoogleFonts.inter(fontSize: 13, height: 1.6, color: AppTheme.textS(context)),
            ),
            const SizedBox(height: 16),
            Text('Features:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textP(context))),
            const SizedBox(height: 8),
            _aboutFeature('Daily current affairs analysis'),
            _aboutFeature('Topic-wise quiz practice'),
            _aboutFeature('Smart flashcards with spaced revision'),
            _aboutFeature('Progress tracking & streaks'),
            _aboutFeature('UPSC-focused study materials'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _aboutFeature(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.successGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey))),
        ],
      ),
    );
  }
}
