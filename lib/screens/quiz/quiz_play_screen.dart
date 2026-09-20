import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/quiz_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../widgets/glass_widgets.dart';
import 'package:lottie/lottie.dart';
import '../../widgets/quiz_option_tile.dart';
import '../../utils/constants.dart';
import 'package:upsc_daily_edge/design_system/frosted_scholar.dart';

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
      duration: const Duration(seconds: AppConstants.quizTimerSeconds),
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
                const SizedBox(height: FsSpace.lg),
                Text('Loading questions...', style: FsType.body(context).copyWith(color: FsColors.textSecondary(context))),
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
                const SizedBox(height: FsSpace.lg),
                Text('No questions available', style: FsType.title(context)),
                const SizedBox(height: FsSpace.xs),
                Text('Try again later or select a different topic', style: FsType.caption(context)),
                const SizedBox(height: FsSpace.xxl),
                SizedBox(
                  height: FsA11y.minTouchTarget,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: Text('Go Back', style: AppFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.control)),
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
            const SizedBox(height: FsSpace.md),
            // Timer ring + question
            Expanded(
              child: FadeTransition(
                opacity: _cardFade,
                child: SlideTransition(
                  position: _cardSlide,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: FsSpace.lg),
                    child: Column(
                      children: [
                        _buildTimerRing(context),
                        const SizedBox(height: FsSpace.lg),
                        _buildQuestionCard(context, q, quiz),
                        const SizedBox(height: FsSpace.lg),
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
                          const SizedBox(height: FsSpace.xs),
                          _buildExplanation(context, q),
                        ],
                        const SizedBox(height: FsSpace.xl),
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
      padding: const EdgeInsets.fromLTRB(FsSpace.xs, FsSpace.xs, FsSpace.lg, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close_rounded, color: AppTheme.textP(context)),
            onPressed: () => _showExitDialog(context),
          ),
          Expanded(
            child: Text(
              'Question ${quiz.currentIndex + 1} of ${quiz.totalQuestions}',
              style: AppFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textP(context)),
              textAlign: TextAlign.center,
            ),
          ),
          Container(
            padding: FsSpacing.chip,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(FsRadii.pill),
            ),
            child: Text('${quiz.score} pts',
                style: AppFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context, QuizProvider quiz, double progress) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.lg, FsSpace.md, FsSpace.lg, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FsRadii.sm),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 6,
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
          valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
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
              style: AppFonts.plusJakartaSans(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(BuildContext context, dynamic q, QuizProvider quiz) {
    final dark = AppTheme.isDark(context);
    return GlassCard(
      color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.95),
      padding: FsSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: FsSpace.xs,
            runSpacing: 6,
            children: [
              FsTag(
                label: q.category.isNotEmpty ? q.category : 'General',
                color: FsColors.accentSecondary(context),
              ),
              FsTag(
                label: q.difficulty,
                color: _difficultyColor(q.difficulty),
              ),
            ],
          ),
          const SizedBox(height: FsSpace.md),
          Text(q.question,
              style: AppFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.5)),
          // Show enriched metadata if available
          if (q.syllabusArea.isNotEmpty || q.pyqYear.isNotEmpty) ...[
            const SizedBox(height: FsSpace.xs),
            Wrap(
              spacing: 6,
              runSpacing: FsSpace.xxs,
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
      padding: const EdgeInsets.symmetric(horizontal: FsSpace.xs, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FsRadii.sm),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: FsSpace.xxs),
          Flexible(
            child: Text(
              label,
              style: AppFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color),
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
      padding: FsSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_rounded, color: AppTheme.successGreen, size: 18),
              const SizedBox(width: FsSpace.xs),
              Text('Explanation', style: AppFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.successGreen)),
            ],
          ),
          const SizedBox(height: FsSpace.xs),
          Text(q.explanation, style: AppFonts.inter(fontSize: 13, height: 1.6, color: AppTheme.textP(context))),
        ],
      ),
    );
  }

  Widget _buildNextButton(BuildContext context, QuizProvider quiz) {
    final isLast = quiz.currentIndex >= quiz.totalQuestions - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.lg, FsSpace.xs, FsSpace.lg, FsSpace.lg),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.card)),
            elevation: 0,
          ),
          child: Text(isLast ? 'View Results' : 'Next Question',
              style: AppFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.lg)),
        title: Text('Exit Quiz?', style: AppFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Your progress will be lost.', style: AppFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              context.read<QuizProvider>().resetQuiz();
            },
            child: const Text('Exit', style: TextStyle(color: AppTheme.errorRed)),
          ),
        ],
      ),
    );
  }
}
