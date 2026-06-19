import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/quiz_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import 'package:lottie/lottie.dart';
import '../../widgets/quiz_option_tile.dart';
import '../../utils/constants.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// QuizPlayScreen — Active quiz with timer ring, question card, and option tiles.
/// ──────────────────────────────────────────────────────────────────────────────
class QuizPlayScreen extends StatefulWidget {
  const QuizPlayScreen({super.key});

  @override
  State<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends State<QuizPlayScreen>
    with TickerProviderStateMixin {
  late AnimationController _timerCtrl;
  late AnimationController _cardCtrl;
  late Animation<double> _cardFade;
  late Animation<Offset> _cardSlide;
  Timer? _timer;
  int _secondsLeft = AppConstants.quizTimerSeconds;

  @override
  void initState() {
    super.initState();
    _timerCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: AppConstants.quizTimerSeconds),
    )..forward();

    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _cardFade = CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut));

    _startTimer();
  }

  void _startTimer() {
    _secondsLeft = AppConstants.quizTimerSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        // Auto-select nothing → mark as answered with no selection
        final quiz = context.read<QuizProvider>();
        if (!quiz.answered) quiz.selectOption(-1);
      }
    });
  }

  void _resetForNext() {
    _timerCtrl.reset();
    _timerCtrl.forward();
    _cardCtrl.reset();
    _cardCtrl.forward();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quiz = context.watch<QuizProvider>();
    final q = quiz.currentQuestion;

    if (quiz.isLoading) {
      return GradientScaffold(
        showAppBar: false,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Lottie.asset('assets/animations/loading.json', width: 120, height: 120),
                const SizedBox(height: 16),
                Text('Loading questions...', style: GoogleFonts.inter(color: AppTheme.textS(context))),
              ],
            ),
          ),
        ),
      );
    }

    if (q == null) {
      return GradientScaffold(
        showAppBar: false,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.quiz_rounded, size: 56, color: AppTheme.textT(context)),
                const SizedBox(height: 16),
                Text('No questions available', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                const SizedBox(height: 8),
                Text('Try again later or select a different topic', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context))),
                const SizedBox(height: 24),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text('Go Back', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final progress = (quiz.currentIndex + 1) / quiz.totalQuestions;

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar
            _buildTopBar(context, quiz),
            // Progress
            _buildProgress(context, quiz, progress),
            const SizedBox(height: 12),
            // Timer ring + question
            Expanded(
              child: FadeTransition(
                opacity: _cardFade,
                child: SlideTransition(
                  position: _cardSlide,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _buildTimerRing(context),
                        const SizedBox(height: 16),
                        _buildQuestionCard(context, q, quiz),
                        const SizedBox(height: 16),
                        ...List.generate(q.options.length, (i) {
                          return QuizOptionTile(
                              index: i,
                              text: q.options[i],
                              isSelected: quiz.selectedOptionIndex == i,
                              isCorrect: i == q.correctAnswerIndex,
                              isAnswered: quiz.answered,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                quiz.selectOption(i);
                                // Save incorrect answer for revision
                                if (i != q.correctAnswerIndex) {
                                  context.read<DailyProgressProvider>().addIncorrectQuestion({
                                    'question': q.question,
                                    'options': q.options,
                                    'correctIndex': q.correctAnswerIndex,
                                    'selectedIndex': i,
                                    'explanation': q.explanation,
                                    'category': q.category,
                                  });
                                }
                              },
                          );
                        }),
                        if (quiz.answered) ...[
                          const SizedBox(height: 8),
                          _buildExplanation(context, q),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Bottom button
            if (quiz.answered) _buildNextButton(context, quiz),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, QuizProvider quiz) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close_rounded, color: AppTheme.textP(context)),
            onPressed: () => _showExitDialog(context),
          ),
          Expanded(
            child: Text(
              'Question ${quiz.currentIndex + 1} of ${quiz.totalQuestions}',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textP(context)),
              textAlign: TextAlign.center,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${quiz.score} pts',
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context, QuizProvider quiz, double progress) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
          valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
        ),
      ),
    );
  }

  Widget _buildTimerRing(BuildContext context) {
    final fraction = _secondsLeft / AppConstants.quizTimerSeconds;
    final color = fraction > 0.5
        ? AppTheme.primaryColor
        : (fraction > 0.2 ? AppTheme.warningOrange : AppTheme.errorRed);

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: CircularProgressIndicator(
              value: fraction,
              strokeWidth: 5,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text('$_secondsLeft',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(BuildContext context, dynamic q, QuizProvider quiz) {
    final dark = AppTheme.isDark(context);
    return GlassCard(
      color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.95),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentViolet.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(q.category.isNotEmpty ? q.category : 'General',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.accentViolet)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _difficultyColor(q.difficulty).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(q.difficulty,
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: _difficultyColor(q.difficulty))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(q.question,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.5)),
          // Show enriched metadata if available
          if (q.syllabusArea.isNotEmpty || q.pyqYear.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (q.syllabusArea.isNotEmpty)
                  _metaChip(q.syllabusArea, AppTheme.accentViolet, Icons.menu_book_rounded),
                if (q.pyqYear.isNotEmpty)
                  _metaChip(q.pyqYear, AppTheme.warningOrange, Icons.history_edu_rounded),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _metaChip(String label, Color color, IconData icon) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Color _difficultyColor(String d) {
    switch (d.toLowerCase()) {
      case 'easy':
        return AppTheme.successGreen;
      case 'hard':
        return AppTheme.errorRed;
      default:
        return AppTheme.warningOrange;
    }
  }

  Widget _buildExplanation(BuildContext context, dynamic q) {
    return GlassCard(
      gradient: LinearGradient(
        colors: [AppTheme.successGreen.withValues(alpha: 0.06), AppTheme.primaryColor.withValues(alpha: 0.04)],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_rounded, color: AppTheme.successGreen, size: 18),
              const SizedBox(width: 8),
              Text('Explanation', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.successGreen)),
            ],
          ),
          const SizedBox(height: 8),
          Text(q.explanation, style: GoogleFonts.inter(fontSize: 13, height: 1.6, color: AppTheme.textP(context))),
        ],
      ),
    );
  }

  Widget _buildNextButton(BuildContext context, QuizProvider quiz) {
    final isLast = quiz.currentIndex >= quiz.totalQuestions - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            if (isLast) {
              Navigator.pushReplacementNamed(context, '/quiz-result');
            } else {
              quiz.nextQuestion();
              _resetForNext();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: Text(isLast ? 'View Results' : 'Next Question',
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Exit Quiz?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Your progress will be lost.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              context.read<QuizProvider>().resetQuiz();
            },
            child: Text('Exit', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
  }
}
