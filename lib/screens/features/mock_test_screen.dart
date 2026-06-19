import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import '../../config/theme.dart';
import '../../services/firestore_content_service.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// MockTestScreen — Sectional mock tests for UPSC Prelims.
/// Simulates real exam conditions with timer, marking scheme, and analysis.
/// ──────────────────────────────────────────────────────────────────────────────
class MockTestScreen extends StatefulWidget {
  const MockTestScreen({super.key});

  @override
  State<MockTestScreen> createState() => _MockTestScreenState();
}

class _MockTestScreenState extends State<MockTestScreen> {
  final ScrollController _scrollController = ScrollController();
  _TestMode _mode = _TestMode.selection;
  int _selectedTestIndex = -1;
  List<Map<String, dynamic>> _tests = [];
  bool _loading = true;

  // Test state
  int _currentQ = 0;
  Map<int, int> _answers = {}; // questionIndex -> selectedOptionIndex
  Set<int> _markedForReview = {};
  Timer? _timer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
    final data = await FirestoreContentService.getMockTests();
    if (mounted) setState(() { _tests = data; _loading = false; });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTest(int testIndex) {
    final test = _tests[testIndex];
    final duration = test['durationMinutes'] as int? ?? 12;
    setState(() {
      _selectedTestIndex = testIndex;
      _mode = _TestMode.active;
      _currentQ = 0;
      _answers = {};
      _markedForReview = {};
      _remainingSeconds = duration * 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_remainingSeconds <= 0) {
        t.cancel();
        _submitTest();
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  void _submitTest() {
    _timer?.cancel();
    setState(() {
      _mode = _TestMode.result;
    });
  }

  void _resetToSelection() {
    setState(() {
      _mode = _TestMode.selection;
      _selectedTestIndex = -1;
    });
  }

  List<Map<String, dynamic>> get _currentQuestions {
    final qs = _tests[_selectedTestIndex]['questions'] as List<dynamic>? ?? [];
    return qs.cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return GradientScaffold(
        extendBodyBehindAppBar: false,
        title: 'Mock Tests',
        child: Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120)),
      );
    }
    return GradientScaffold(
      extendBodyBehindAppBar: false,
      title: _mode == _TestMode.selection ? 'Mock Tests' : _mode == _TestMode.active ? 'Test In Progress' : 'Test Results',
      leading: _mode != _TestMode.selection
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                if (_mode == _TestMode.active) {
                  _showExitDialog();
                } else {
                  _resetToSelection();
                }
              },
            )
          : null,
      child: _mode == _TestMode.selection
          ? _buildTestSelection()
          : _mode == _TestMode.active
              ? _buildActiveTest()
              : _buildResults(),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // TEST SELECTION
  // ═════════════════════════════════════════════════════════════════

  Widget _buildTestSelection() {
    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      itemCount: _tests.length,
      itemBuilder: (context, i) {
        final test = _tests[i];
        final title = test['title'] as String? ?? '';
        final subtitle = test['subtitle'] as String? ?? '';
        final icon = FirestoreContentService.getIcon(test['iconName'] as String? ?? '');
        final color = FirestoreContentService.parseColor(test['colorHex'] as String? ?? '');
        final questions = (test['questions'] as List<dynamic>?) ?? [];
        final duration = test['durationMinutes'] as int? ?? 12;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AnimatedGlassCard(
            onTap: () => _startTest(i),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.6)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                          const SizedBox(height: 2),
                          Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
                        ],
                      ),
                    ),
                    Icon(Icons.play_circle_fill_rounded, color: color, size: 32),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _testInfoBadge(Icons.quiz_rounded, '${questions.length} Qs', color),
                    _testInfoBadge(Icons.timer_rounded, '$duration min', color),
                    _testInfoBadge(Icons.star_rounded, '+${questions.length * 2} marks', color),
                    _testInfoBadge(Icons.remove_circle_outline_rounded, '-0.66', AppTheme.errorRed),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _testInfoBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // ACTIVE TEST
  // ═════════════════════════════════════════════════════════════════

  Widget _buildActiveTest() {
    final qMap = _currentQuestions[_currentQ];
    final question = qMap['question'] as String? ?? '';
    final options = (qMap['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final mins = _remainingSeconds ~/ 60;
    final secs = _remainingSeconds % 60;

    return Column(
      children: [
        // Timer & progress bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.timer_rounded, size: 18, color: _remainingSeconds < 60 ? AppTheme.errorRed : AppTheme.primaryColor),
                const SizedBox(width: 6),
                Text(
                  '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w800,
                    color: _remainingSeconds < 60 ? AppTheme.errorRed : AppTheme.primaryColor,
                  ),
                ),
                const Spacer(),
                Text('Q ${_currentQ + 1}/${_currentQuestions.length}',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textS(context))),
                const SizedBox(width: 12),
                if (_markedForReview.contains(_currentQ))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppTheme.warningOrange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text('Marked', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.warningOrange)),
                  ),
              ],
            ),
          ),
        ),
        // Progress
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (_currentQ + 1) / _currentQuestions.length,
              minHeight: 3,
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
            ),
          ),
        ),
        // Question
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(question, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.5)),
                const SizedBox(height: 16),
                ...List.generate(options.length, (oi) {
                  final selected = _answers[_currentQ] == oi;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _answers[_currentQ] = oi);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primaryColor.withValues(alpha: 0.1)
                              : (AppTheme.isDark(context)
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.white.withValues(alpha: 0.7)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? AppTheme.primaryColor : Colors.white.withValues(alpha: 0.3),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: selected ? AppTheme.primaryColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected ? AppTheme.primaryColor : AppTheme.textT(context),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  String.fromCharCode(65 + oi),
                                  style: GoogleFonts.inter(
                                    fontSize: 13, fontWeight: FontWeight.w700,
                                    color: selected ? Colors.white : AppTheme.textS(context),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(options[oi], style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.4)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        // Navigation bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                if (_currentQ > 0)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _currentQ--),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Previous'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: AppTheme.primaryColor),
                      ),
                    ),
                  ),
                if (_currentQ > 0) const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      if (_markedForReview.contains(_currentQ)) {
                        _markedForReview.remove(_currentQ);
                      } else {
                        _markedForReview.add(_currentQ);
                      }
                    });
                  },
                  icon: Icon(
                    _markedForReview.contains(_currentQ) ? Icons.flag_rounded : Icons.flag_outlined,
                    color: AppTheme.warningOrange,
                  ),
                  tooltip: 'Mark for Review',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_currentQ < _currentQuestions.length - 1) {
                        setState(() => _currentQ++);
                      } else {
                        _showSubmitDialog();
                      }
                    },
                    icon: Icon(_currentQ < _currentQuestions.length - 1 ? Icons.arrow_forward_rounded : Icons.check_rounded, size: 18),
                    label: Text(_currentQ < _currentQuestions.length - 1 ? 'Next' : 'Submit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // RESULTS
  // ═════════════════════════════════════════════════════════════════

  Widget _buildResults() {
    final questions = _currentQuestions;
    int correct = 0, wrong = 0, unattempted = 0;
    for (int i = 0; i < questions.length; i++) {
      final ci = questions[i]['correctIndex'] as int? ?? 0;
      if (!_answers.containsKey(i)) {
        unattempted++;
      } else if (_answers[i] == ci) {
        correct++;
      } else {
        wrong++;
      }
    }
    final marks = (correct * 2) - (wrong * 0.66);
    final totalMarks = questions.length * 2;
    final percentage = (marks / totalMarks * 100).clamp(0, 100);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        // Score card
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              CircularProgressWidget(
                progress: percentage / 100,
                size: 100,
                strokeWidth: 10,
                progressColor: percentage >= 60 ? AppTheme.successGreen : percentage >= 33 ? AppTheme.warningOrange : AppTheme.errorRed,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${percentage.round()}%', style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w800)),
                    Text('Score', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textS(context))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('${marks.toStringAsFixed(1)} / $totalMarks marks',
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _resultStat('$correct', 'Correct', AppTheme.successGreen),
                  const SizedBox(width: 8),
                  _resultStat('$wrong', 'Wrong', AppTheme.errorRed),
                  const SizedBox(width: 8),
                  _resultStat('$unattempted', 'Skipped', AppTheme.textTertiary),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Question Analysis', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
        const SizedBox(height: 10),
        // Question-wise review
        ...List.generate(questions.length, (i) {
          final q = questions[i];
          final qText = q['question'] as String? ?? '';
          final qOptions = (q['options'] as List<dynamic>?)?.cast<String>() ?? [];
          final correctIdx = q['correctIndex'] as int? ?? 0;
          final explanation = q['explanation'] as String? ?? '';
          final answered = _answers.containsKey(i);
          final isCorrect = answered && _answers[i] == correctIdx;
          final statusColor = !answered ? AppTheme.textTertiary : isCorrect ? AppTheme.successGreen : AppTheme.errorRed;
          final statusIcon = !answered ? Icons.remove_circle_outline_rounded : isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 20),
                      const SizedBox(width: 8),
                      Text('Q${i + 1}', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: statusColor)),
                      const Spacer(),
                      Text(
                        !answered ? 'Unattempted' : isCorrect ? '+2.00' : '-0.66',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: statusColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(qText, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  if (answered && !isCorrect && _answers[i]! < qOptions.length)
                    Text('Your answer: ${qOptions[_answers[i]!]}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.errorRed)),
                  if (correctIdx < qOptions.length)
                    Text('Correct: ${qOptions[correctIdx]}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.successGreen, fontWeight: FontWeight.w600)),
                  if (explanation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(explanation, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context), height: 1.4)),
                  ],
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _resetToSelection,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to Tests'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _resultStat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: GoogleFonts.inter(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // DIALOGS
  // ═════════════════════════════════════════════════════════════════

  void _showSubmitDialog() {
    final unanswered = _currentQuestions.length - _answers.length;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Submit Test?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Answered: ${_answers.length}/${_currentQuestions.length}', style: GoogleFonts.inter(fontSize: 14)),
            if (unanswered > 0) Text('Unanswered: $unanswered', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.errorRed)),
            if (_markedForReview.isNotEmpty) Text('Marked for review: ${_markedForReview.length}', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.warningOrange)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _submitTest();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Exit Test?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Your progress will be lost.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Continue')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _timer?.cancel();
              _resetToSelection();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed, foregroundColor: Colors.white),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

}

enum _TestMode { selection, active, result }
