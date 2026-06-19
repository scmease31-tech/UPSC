import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:lottie/lottie.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/quiz_option_tile.dart';
import '../../services/daily_content_manager.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// DailyChallengeScreen — 5-question timed daily challenge with XP rewards.
/// ──────────────────────────────────────────────────────────────────────────────
class DailyChallengeScreen extends StatefulWidget {
  const DailyChallengeScreen({super.key});

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _questions = [];
  int _current = 0;
  int? _selected;
  bool _answered = false;
  int _score = 0;
  bool _finished = false;
  bool _loading = true;
  int _secondsLeft = 20;
  Timer? _timer;
  late AnimationController _cardCtrl;
  late CurvedAnimation _cardCurve;

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..forward();
    _cardCurve = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    await DailyContentManager.fetchFlashcardsFromFirestore();
    final qs = DailyContentManager.getTodaysChallengeQuestions();
    if (!mounted) return;
    setState(() {
      _questions = qs;
      _loading = false;
    });
    if (_questions.isNotEmpty) _startTimer();
  }

  void _startTimer() {
    _secondsLeft = 20;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        if (!_answered) _selectOption(-1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cardCurve.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  void _selectOption(int i) {
    if (_answered) return;
    HapticFeedback.mediumImpact();
    _timer?.cancel();
    final correct = _questions[_current]['answer'] as int? ?? 0;
    setState(() {
      _selected = i;
      _answered = true;
      if (i == correct) _score++;
    });
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_current >= _questions.length - 1) {
      setState(() => _finished = true);
      context.read<DailyProgressProvider>().completeDailyChallenge(_score, _questions.length);
    } else {
      setState(() {
        _current++;
        _selected = null;
        _answered = false;
      });
      _cardCtrl.reset();
      _cardCtrl.forward();
      _startTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return GradientScaffold(
        showAppBar: false,
        child: SafeArea(child: Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120))),
      );
    }

    if (_questions.isEmpty) {
      return GradientScaffold(
        showAppBar: false,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flash_on_rounded, size: 56, color: AppTheme.textT(context)),
                const SizedBox(height: 16),
                Text('No challenge questions yet', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                const SizedBox(height: 8),
                Text('Check back later!', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Go Back', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_finished) return _buildResults(context);

    final q = _questions[_current];
    final options = List<String>.from(q['options'] ?? []);
    final correctIdx = q['answer'] as int? ?? 0;
    final timerFraction = _secondsLeft / 20;

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.close_rounded), onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  }),
                  Expanded(child: Text('Daily Challenge', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textP(context)), textAlign: TextAlign.center)),
                  Image.asset('assets/flaticon_pngs/lightning.png', width: 20, height: 20),
                ],
              ),
            ),

            // Progress + timer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: (_current + 1) / _questions.length,
                        minHeight: 5,
                        backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (timerFraction > 0.4 ? AppTheme.primaryColor : AppTheme.errorRed).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${_secondsLeft}s',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700,
                            color: timerFraction > 0.4 ? AppTheme.primaryColor : AppTheme.errorRed)),
                  ),
                ],
              ),
            ),

            // Question card
            Expanded(
              child: FadeTransition(
                opacity: _cardCurve,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Text(q['q'] ?? '',
                            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.5)),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(options.length, (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: QuizOptionTile(
                          index: i,
                          text: options[i],
                          isSelected: _selected == i,
                          isCorrect: i == correctIdx,
                          isAnswered: _answered,
                          onTap: () => _selectOption(i),
                        ),
                      )),
                      if (_answered && q['explain'] != null) ...[
                        const SizedBox(height: 8),
                        GlassCard(
                          gradient: LinearGradient(colors: [AppTheme.successGreen.withValues(alpha: 0.06), AppTheme.primaryColor.withValues(alpha: 0.04)]),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.lightbulb_rounded, color: AppTheme.successGreen, size: 18),
                                const SizedBox(width: 8),
                                Text('Explanation', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.successGreen)),
                              ]),
                              const SizedBox(height: 8),
                              Text(q['explain'], style: GoogleFonts.inter(fontSize: 13, height: 1.6, color: AppTheme.textP(context))),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            if (_answered)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_current >= _questions.length - 1 ? 'See Results' : 'Next',
                            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Icon(_current >= _questions.length - 1 ? Icons.emoji_events_rounded : Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final pct = _questions.isNotEmpty ? _score / _questions.length : 0.0;
    final xp = 50 + (_score * 10);
    final w = MediaQuery.of(context).size.width;
    final heroH = w < 360 ? 140.0 : 180.0;
    final circleSize = w < 360 ? 110.0 : 140.0;

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: w < 360 ? 20 : 28),
            child: Column(
              children: [
                // Trophy image
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      SizedBox(
                        width: double.infinity, height: heroH,
                        child: CachedNetworkImage(
                          imageUrl: pct >= 0.8 ? AppImages.challengeTrophy : AppImages.challengeHero,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Shimmer.fromColors(
                            baseColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                            highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
                            child: Container(color: Colors.white),
                          ),
                          errorWidget: (_, __, ___) => Container(color: AppTheme.primaryColor.withValues(alpha: 0.1)),
                        ),
                      ),
                      Container(
                        width: double.infinity, height: heroH,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.6)],
                          ),
                        ),
                        alignment: Alignment.bottomCenter,
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text('Challenge Complete!',
                            style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                CircularProgressWidget(
                  progress: pct,
                  size: circleSize,
                  strokeWidth: circleSize < 120 ? 10 : 12,
                  progressColor: pct >= 0.7 ? AppTheme.successGreen : AppTheme.warningOrange,
                  trackColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$_score/${_questions.length}', style: GoogleFonts.plusJakartaSans(fontSize: 28, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
                      Text('correct', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                GlassCard(
                  gradient: LinearGradient(colors: [AppTheme.warningOrange.withValues(alpha: 0.1), AppTheme.primaryColor.withValues(alpha: 0.06)]),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/flaticon_pngs/lightning.png', width: 24, height: 24),
                      const SizedBox(width: 8),
                      Text('+$xp XP earned!', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.warningOrange)),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.home_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text('Done', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
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
