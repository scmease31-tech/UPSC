import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// StudyTimerScreen — Pomodoro-style study timer with session logging.
/// 25-min focus blocks with 5-min breaks. Integrates with study time tracking.
/// ──────────────────────────────────────────────────────────────────────────────
class StudyTimerScreen extends StatefulWidget {
  const StudyTimerScreen({super.key});

  @override
  State<StudyTimerScreen> createState() => _StudyTimerScreenState();
}

class _StudyTimerScreenState extends State<StudyTimerScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  int _totalSeconds = 25 * 60; // 25 min default
  int _secondsLeft = 25 * 60;
  bool _isRunning = false;
  bool _isBreak = false;
  int _completedSessions = 0;
  int _totalStudyMinutes = 0;
  String _selectedSubject = 'General';

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  static const _focusDuration = 25 * 60;
  static const _shortBreak = 5 * 60;
  static const _longBreak = 15 * 60;

  static const _subjects = [
    'General', 'Polity', 'Economy', 'History', 'Geography',
    'Science & Tech', 'Environment', 'International Relations',
    'Ethics', 'CSAT', 'Essay', 'Current Affairs',
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulse = Tween(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _timer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    HapticFeedback.mediumImpact();
    setState(() => _isRunning = true);
    _pulseCtrl.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _secondsLeft--;
        if (!_isBreak) {
          _totalStudyMinutes = ((_totalSeconds - _secondsLeft) / 60).ceil() +
              (_completedSessions * (_focusDuration ~/ 60));
        }
      });
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        _onSessionComplete();
      }
    });
  }

  void _pauseTimer() {
    HapticFeedback.lightImpact();
    _timer?.cancel();
    _pulseCtrl.stop();
    setState(() => _isRunning = false);
  }

  void _resetTimer() {
    HapticFeedback.mediumImpact();
    _timer?.cancel();
    _pulseCtrl.stop();
    _pulseCtrl.reset();
    setState(() {
      _isRunning = false;
      _isBreak = false;
      _secondsLeft = _focusDuration;
      _totalSeconds = _focusDuration;
    });
  }

  void _onSessionComplete() {
    HapticFeedback.heavyImpact();
    _pulseCtrl.stop();
    _pulseCtrl.reset();

    if (!_isBreak) {
      // Focus session completed — log it
      final minutesStudied = _totalSeconds ~/ 60;
      _completedSessions++;
      context.read<DailyProgressProvider>().addStudyMinutes(minutesStudied);

      setState(() {
        _isBreak = true;
        final breakDuration = _completedSessions % 4 == 0 ? _longBreak : _shortBreak;
        _totalSeconds = breakDuration;
        _secondsLeft = breakDuration;
        _isRunning = false;
      });

      _showCompletionSnackbar('Focus session complete! Take a break.');
    } else {
      // Break completed
      setState(() {
        _isBreak = false;
        _totalSeconds = _focusDuration;
        _secondsLeft = _focusDuration;
        _isRunning = false;
      });

      _showCompletionSnackbar('Break over! Ready for next session?');
    }
  }

  void _showCompletionSnackbar(String msg) {
    if (!mounted) return;
    final isBreakMsg = msg.contains('break') || msg.contains('Break');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: isBreakMsg ? AppTheme.accentViolet : AppTheme.primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _totalSeconds > 0 ? (1 - _secondsLeft / _totalSeconds) : 0.0;

    return GradientScaffold(
      title: 'Study Timer',
      extendBodyBehindAppBar: false,
      child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          child: Column(
            children: [
              // Status label
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: (_isBreak ? AppTheme.successGreen : AppTheme.primaryColor).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _isBreak ? 'Break Time' : 'Focus Mode',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: _isBreak ? AppTheme.successGreen : AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Timer circle
              ScaleTransition(
                scale: _isRunning ? _pulse : const AlwaysStoppedAnimation(1.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = MediaQuery.of(context).size.width;
                    final timerSize = (w * 0.58).clamp(180.0, 260.0);
                    final fontSize = (timerSize * 0.22).clamp(32.0, 52.0);
                    return SizedBox(
                      width: timerSize, height: timerSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: timerSize, height: timerSize,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: timerSize < 200 ? 8 : 10,
                              strokeCap: StrokeCap.round,
                              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                              valueColor: AlwaysStoppedAnimation(
                                _isBreak ? AppTheme.successGreen : AppTheme.primaryColor,
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatTime(_secondsLeft),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: fontSize, fontWeight: FontWeight.w800,
                                  color: AppTheme.textP(context),
                                  letterSpacing: 2,
                                ),
                              ),
                              Text(
                                _isBreak ? 'Relax' : 'Stay focused',
                                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textS(context)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _controlBtn(Icons.refresh_rounded, 'Reset', AppTheme.textS(context), _resetTimer),
                  const SizedBox(width: 20),
                  // Main play/pause button
                  GestureDetector(
                    onTap: _isRunning ? _pauseTimer : _startTimer,
                    child: Builder(
                      builder: (context) {
                        final btnSize = MediaQuery.of(context).size.width < 360 ? 60.0 : 72.0;
                        return Container(
                          width: btnSize, height: btnSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isBreak
                              ? [AppTheme.successGreen, AppTheme.successGreen.withValues(alpha: 0.7)]
                              : [AppTheme.primaryColor, AppTheme.accentViolet],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isBreak ? AppTheme.successGreen : AppTheme.primaryColor).withValues(alpha: 0.3),
                            blurRadius: 16, offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white, size: 36,
                      ),
                    );
                      },
                    ),
                  ),
                  const SizedBox(width: 20),
                  _controlBtn(Icons.skip_next_rounded, 'Skip', AppTheme.textS(context), () {
                    _timer?.cancel();
                    _onSessionComplete();
                  }),
                ],
              ),
              const SizedBox(height: 28),

              // Subject selector
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Studying', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _subjects.map((s) {
                        final sel = s == _selectedSubject;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedSubject = s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel ? AppTheme.primaryColor : AppTheme.primaryColor.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(s, style: GoogleFonts.inter(
                              fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              color: sel ? Colors.white : AppTheme.textS(context),
                            )),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Session stats
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today\'s Progress', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statItem(Icons.local_fire_department_rounded, '$_completedSessions', 'Sessions', AppTheme.errorRed),
                        _statItem(Icons.timer_rounded, '$_totalStudyMinutes', 'Minutes', AppTheme.primaryColor),
                        _statItem(Icons.emoji_events_rounded, '${(_completedSessions * 50)}', 'XP Earned', AppTheme.warningOrange),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Pomodoro tips
              GlassCard(
                padding: const EdgeInsets.all(16),
                gradient: LinearGradient(colors: [
                  AppTheme.accentViolet.withValues(alpha: 0.06),
                  AppTheme.primaryColor.withValues(alpha: 0.04),
                ]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.tips_and_updates_rounded, size: 16, color: AppTheme.accentViolet),
                      const SizedBox(width: 6),
                      Text('Pomodoro Tips', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.accentViolet)),
                    ]),
                    const SizedBox(height: 8),
                    _tipRow('25 min focused study → 5 min break'),
                    _tipRow('After 4 sessions → 15 min long break'),
                    _tipRow('No phone during focus sessions'),
                    _tipRow('Review notes during breaks'),
                  ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Widget _controlBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.1),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
        ],
      ),
    );
  }

  Widget _tipRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.successGreen),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12, height: 1.4, color: AppTheme.textP(context)))),
        ],
      ),
    );
  }
}
