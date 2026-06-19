import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import '../../config/theme.dart';
import '../../widgets/glass_widgets.dart';
import '../../widgets/quiz_option_tile.dart';
import '../../services/daily_content_manager.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// DailyPracticeScreen — PYQ-style practice questions (daily rotation).
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
      return GradientScaffold(
        showAppBar: false,
        child: SafeArea(child: Center(child: Text('No questions available', style: GoogleFonts.inter(color: AppTheme.textS(context))))),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Text(q['q'] ?? '',
                          style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.5)),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(options.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
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
                      const SizedBox(height: 8),
                      GlassCard(
                        gradient: LinearGradient(colors: [
                          AppTheme.successGreen.withValues(alpha: 0.06),
                          AppTheme.primaryColor.withValues(alpha: 0.04),
                        ]),
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
                            Text(q['explain'], style: GoogleFonts.inter(fontSize: 13, height: 1.6, color: AppTheme.textP(context))),
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
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }),
          Expanded(
            child: Text('Daily Practice', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textP(context)), textAlign: TextAlign.center),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppTheme.primaryColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text('$_score/${_questions.length}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          value: (_current + 1) / _questions.length,
          minHeight: 5,
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
          valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
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
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: Text(isLast ? 'Finish' : 'Next', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(grade, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_score / ${_questions.length}',
              style: GoogleFonts.plusJakartaSans(fontSize: 36, fontWeight: FontWeight.w800, color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 8),
            Text('questions correct', style: GoogleFonts.inter(color: AppTheme.textS(context))),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
