import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../config/app_images.dart';
import '../../providers/quiz_provider.dart';
import '../../widgets/glass_widgets.dart';
import '../../providers/auth_provider.dart';
import '../../providers/daily_progress_provider.dart';
import '../../models/user_profile.dart';
import 'package:upsc_daily_edge/design_system/frosted_scholar.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// QuizResultScreen — Score gauge, breakdown list, animated confetti feel.
/// ──────────────────────────────────────────────────────────────────────────────
class QuizResultScreen extends StatefulWidget {
  const QuizResultScreen({super.key});

  @override
  State<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends State<QuizResultScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  late AnimationController _ctrl;
  late CurvedAnimation _elasticCurve;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
    _elasticCurve = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _saveScore();
  }

  Future<void> _saveScore() async {
    if (_saved) return;
    _saved = true;
    final quiz = context.read<QuizProvider>();
    final auth = context.read<AuthProvider>();
    final progress = context.read<DailyProgressProvider>();

    final score = QuizScore(
      date: DateTime.now(),
      score: quiz.score,
      totalQuestions: quiz.totalQuestions,
      category: quiz.currentQuestion?.category ?? 'General',
    );

    await auth.saveQuizScore(score);
    progress.recordActivity();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _elasticCurve.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quiz = context.watch<QuizProvider>();
    final pct = quiz.totalQuestions > 0 ? quiz.score / quiz.totalQuestions : 0.0;
    final grade = pct >= 0.9 ? 'Excellent!' : (pct >= 0.7 ? 'Great Job!' : (pct >= 0.5 ? 'Good Effort' : 'Keep Practising'));
    final iconPath = pct >= 0.9 ? 'assets/flaticon_pngs/trophy.png' : (pct >= 0.7 ? 'assets/flaticon_pngs/star.png' : (pct >= 0.5 ? 'assets/flaticon_pngs/thumbs_up.png' : 'assets/flaticon_pngs/muscle.png'));

    return GradientScaffold(
      showAppBar: false,
      child: Stack(
        children: [
        SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: FsSpace.lg),
          child: Column(
            children: [
              // Back bar
              Padding(
                padding: const EdgeInsets.only(top: FsSpace.xs, bottom: FsSpace.xxs),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        quiz.resetQuiz();
                        Navigator.popUntil(context, (r) => r.isFirst);
                        Navigator.pushReplacementNamed(context, '/main');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(FsSpace.xs),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(FsRadii.sm),
                        ),
                        child: Icon(Icons.arrow_back_ios_rounded, size: 18, color: AppTheme.textP(context)),
                      ),
                    ),
                    const SizedBox(width: FsSpace.md),
                    Text('Quiz Results', style: FsType.display(context)),
                  ],
                ),
              ),
              const SizedBox(height: FsSpace.xs),
              // Hero result banner
              ClipRRect(
                borderRadius: BorderRadius.circular(FsRadii.lg),
                child: Stack(
                  children: [
                    SizedBox(
                      width: double.infinity, height: 160,
                      child: CachedNetworkImage(
                        imageUrl: pct >= 0.7 ? AppImages.quizCelebration : AppImages.quizHero,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Shimmer.fromColors(
                          baseColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                          highlightColor: AppTheme.primaryColor.withValues(alpha: 0.04),
                          child: Container(color: Colors.white),
                        ),
                        errorWidget: (_, __, ___) => Container(color: AppTheme.accentViolet.withValues(alpha: 0.1)),
                      ),
                    ),
                    Container(
                      width: double.infinity, height: 160,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, _scoreColor(pct).withValues(alpha: 0.7)],
                        ),
                      ),
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(bottom: FsSpace.md),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(iconPath, width: 36, height: 36),
                          const SizedBox(height: FsSpace.xxs),
                          Text(grade, style: AppFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FsSpace.xl),

              // Score ring
              CustomAnimatedBuilder(
                animation: _elasticCurve,
                builder: (_, __) {
                  final animPct = pct * _ctrl.value;
                  final w = MediaQuery.of(context).size.width;
                  final ringSize = w < 360 ? 130.0 : 160.0;
                  return CircularProgressWidget(
                    progress: animPct,
                    size: ringSize,
                    strokeWidth: w < 360 ? 11 : 14,
                    progressColor: _scoreColor(pct),
                    trackColor: _scoreColor(pct).withValues(alpha: 0.1),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${(animPct * 100).round()}%',
                            style: AppFonts.plusJakartaSans(fontSize: w < 360 ? 28 : 36, fontWeight: FontWeight.w800, color: AppTheme.textP(context))),
                        Text('${quiz.score}/${quiz.totalQuestions}',
                            style: AppFonts.inter(fontSize: 14, color: AppTheme.textS(context))),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: FsSpace.xl),

              // Stats row
              Row(
                children: [
                  _stat('Correct', '${quiz.score}', AppTheme.successGreen),
                  const SizedBox(width: FsSpace.xs),
                  _stat('Wrong', '${quiz.totalQuestions - quiz.score}', AppTheme.errorRed),
                  const SizedBox(width: FsSpace.xs),
                  _stat('XP', '+${50 + quiz.score * 10}', AppTheme.warningOrange),
                  const SizedBox(width: FsSpace.xs),
                  _stat('Total', '${quiz.totalQuestions}', AppTheme.accentViolet),
                ],
              ),

              const SizedBox(height: FsSpace.xl),

              // Question breakdown
              GlassCard(
                padding: FsSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Question Breakdown', style: AppFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                    const SizedBox(height: FsSpace.md),
                    ...List.generate(quiz.totalQuestions, (i) {
                      final q = quiz.questions[i];
                      final userAns = i < quiz.userAnswers.length ? quiz.userAnswers[i] : null;
                      final correct = userAns == q.correctAnswerIndex;
                      return Container(
                        margin: const EdgeInsets.only(bottom: FsSpace.xs),
                        padding: const EdgeInsets.all(FsSpace.md),
                        decoration: BoxDecoration(
                          color: (correct ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(FsRadii.control),
                          border: Border.all(color: (correct ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                    color: correct ? AppTheme.successGreen : AppTheme.errorRed, size: 20),
                                const SizedBox(width: FsSpace.xs),
                                Expanded(
                                  child: Text('Q${i + 1}: ${q.question}',
                                      maxLines: 2, overflow: TextOverflow.ellipsis,
                                      style: AppFonts.inter(fontSize: 12, color: AppTheme.textP(context))),
                                ),
                              ],
                            ),
                            // Show enriched metadata if available
                            if (q.difficulty.isNotEmpty || q.syllabusArea.isNotEmpty || q.pyqYear.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6, left: 30),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: FsSpace.xxs,
                                  children: [
                                    if (q.difficulty.isNotEmpty)
                                      _metaChip(q.difficulty, _difficultyColor(q.difficulty)),
                                    if (q.syllabusArea.isNotEmpty)
                                      _metaChip(q.syllabusArea, AppTheme.accentViolet),
                                    if (q.pyqYear.isNotEmpty)
                                      _metaChip(q.pyqYear, AppTheme.warningOrange),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: FsSpace.xl),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          await quiz.loadQuiz();
                          if (context.mounted) {
                            Navigator.pushReplacementNamed(context, '/quiz-play');
                          }
                        },
                        icon: const Icon(Icons.replay_rounded),
                        label: Text('Retry', style: AppFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: const BorderSide(color: AppTheme.primaryColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.card)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: FsSpace.md),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          quiz.resetQuiz();
                          Navigator.popUntil(context, (r) => r.isFirst);
                          Navigator.pushReplacementNamed(context, '/main');
                        },
                        icon: const Icon(Icons.home_rounded),
                        label: Text('Home', style: AppFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.card)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: FsSpace.huge),
            ],
          ),
        ),
      ),
      // Lottie confetti overlay for high scores
      if (pct >= 0.7)
        Positioned.fill(
          child: IgnorePointer(
            child: Lottie.asset(
              pct >= 0.9
                  ? 'assets/animations/confetti.json'
                  : 'assets/animations/success_check.json',
              repeat: false,
              fit: BoxFit.cover,
            ),
          ),
        ),
      // Trophy animation for 90%+ scores
      if (pct >= 0.9)
        Positioned(
          top: 60,
          right: 16,
          child: IgnorePointer(
            child: Lottie.asset(
              'assets/animations/success_check.json',
              width: 80,
              height: 80,
              repeat: false,
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: FsSpace.lg),
        child: Column(
          children: [
            Text(value, style: AppFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: FsSpace.xxs),
            Text(label, style: FsType.label(context)),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(double pct) {
    if (pct >= 0.7) return AppTheme.successGreen;
    if (pct >= 0.4) return AppTheme.warningOrange;
    return AppTheme.errorRed;
  }

  Widget _metaChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FsSpace.xs, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy': return AppTheme.successGreen;
      case 'hard': return AppTheme.errorRed;
      default: return AppTheme.warningOrange;
    }
  }
}
