import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/quiz_option_tile.dart';
import '../../services/daily_content_manager.dart';
import 'package:upsc_daily_edge/design_system/frosted_scholar.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// DailyPracticeScreen — PYQ-style practice questions (daily rotation).
/// Migrated to the Frosted Scholar design system (tokens + primitives).
/// ──────────────────────────────────────────────────────────────────────────────
class DailyPracticeScreen extends StatefulWidget {
  const DailyPracticeScreen({super.key});

  @override
  State<DailyPracticeScreen> createState() => _DailyPracticeScreenState();
}

class _DailyPracticeScreenState extends State<DailyPracticeScreen> {
  List<Map<String, dynamic>> _questions = [];
  int _current = 0;
  int? _selected;
  bool _answered = false;
  int _score = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    // Try Firestore quiz questions first, fall back to local challenge questions
    await DailyContentManager.fetchFlashcardsFromFirestore(); // warm up Firestore
    final localQs = DailyContentManager.getTodaysChallengeQuestions();
    if (!mounted) return;
    setState(() {
      _questions = localQs;
      _loading = false;
    });
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
      return const GradientScaffold(
        showAppBar: false,
        child: SafeArea(
          child: FsEmptyState(
            icon: Icons.quiz_outlined,
            title: 'No questions available',
            message: 'Daily practice questions will appear here once published.',
          ),
        ),
      );
    }

    final q = _questions[_current];
    final options = (q['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final correctIdx = int.tryParse(q['answer']?.toString() ?? '') ?? 0;

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            _buildProgress(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                    FsSpace.lg, FsSpace.lg, FsSpace.lg, FsSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassCard(
                      padding: FsSpacing.cardPadding,
                      child: Text(q['q'] ?? '',
                          style: FsType.subtitle(context).copyWith(fontSize: 16, height: 1.5)),
                    ),
                    const SizedBox(height: FsSpace.lg),
                    ...List.generate(options.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: FsSpace.xs),
                        child: QuizOptionTile(
                          index: i,
                          text: options[i],
                          isSelected: _selected == i,
                          isCorrect: i == correctIdx,
                          isAnswered: _answered,
                          onTap: () => _selectOption(i, correctIdx),
                        ),
                      );
                    }),
                    if (_answered && q['explain'] != null) ...[
                      const SizedBox(height: FsSpace.xs),
                      GlassCard(
                        gradient: LinearGradient(colors: [
                          FsColors.success.withValues(alpha: 0.06),
                          FsColors.accent(context).withValues(alpha: 0.04),
                        ]),
                        padding: FsSpacing.cardPadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.lightbulb_rounded, color: FsColors.success, size: 18),
                                const SizedBox(width: FsSpace.xs),
                                Text('Explanation', style: FsType.subtitle(context).copyWith(
                                    fontSize: 14, fontWeight: FontWeight.w700, color: FsColors.success)),
                              ],
                            ),
                            const SizedBox(height: FsSpace.xs),
                            Text(q['explain'], style: FsType.caption(context).copyWith(
                                height: 1.6, color: FsColors.textPrimary(context))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_answered) _buildNextButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xs, FsSpace.xs, FsSpace.lg, 0),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }),
          Expanded(
            child: Text('Daily Practice', style: FsType.title(context), textAlign: TextAlign.center),
          ),
          Container(
            padding: FsSpacing.chip,
            decoration: BoxDecoration(
                color: FsColors.accent(context).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(FsRadii.pill)),
            child: Text('$_score/${_questions.length}',
                style: FsType.button(FsColors.accent(context)).copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.lg, FsSpace.md, FsSpace.lg, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FsRadii.sm),
        child: LinearProgressIndicator(
          value: (_current + 1) / _questions.length,
          minHeight: 5,
          backgroundColor: FsColors.accent(context).withValues(alpha: 0.08),
          valueColor: AlwaysStoppedAnimation(FsColors.accent(context)),
        ),
      ),
    );
  }

  void _selectOption(int i, int correct) {
    if (_answered) return;
    setState(() {
      _selected = i;
      _answered = true;
      if (i == correct) _score++;
    });
  }

  Widget _buildNextButton(BuildContext context) {
    final isLast = _current >= _questions.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.lg, FsSpace.xs, FsSpace.lg, FsSpace.lg),
      child: FsButton(
        label: isLast ? 'Finish' : 'Next',
        expand: true,
        onPressed: () {
          if (isLast) {
            _showCompletionDialog(context);
          } else {
            setState(() {
              _current++;
              _selected = null;
              _answered = false;
            });
          }
        },
      ),
    );
  }

  void _showCompletionDialog(BuildContext context) {
    final pct = _questions.isNotEmpty ? _score / _questions.length : 0.0;
    final grade = pct >= 0.8 ? 'Excellent!' : (pct >= 0.6 ? 'Great Job!' : (pct >= 0.4 ? 'Good Effort' : 'Keep Practising'));

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FsRadii.lg)),
        title: Text(grade, style: FsType.display(context), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_score / ${_questions.length}',
              style: FsType.display(context).copyWith(fontSize: 36, color: FsColors.accent(context)),
            ),
            const SizedBox(height: FsSpace.xs),
            Text('questions correct', style: FsType.caption(context)),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FsButton(
              label: 'Done',
              expand: true,
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}
