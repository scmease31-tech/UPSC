import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// AnswerWritingScreen — Timed answer writing practice for UPSC Mains.
/// Provides topics, word limit, timer, and structure guidance.
/// ──────────────────────────────────────────────────────────────────────────────
class AnswerWritingScreen extends StatefulWidget {
  const AnswerWritingScreen({super.key});

  @override
  State<AnswerWritingScreen> createState() => _AnswerWritingScreenState();
}

class _AnswerWritingScreenState extends State<AnswerWritingScreen> {
  final ScrollController _scrollController = ScrollController();
  int _selectedTopicIndex = 0;
  bool _isWriting = false;
  bool _showGuide = false;
  Timer? _timer;
  int _secondsLeft = 0;
  int _wordCount = 0;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateWordCount);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _timer?.cancel();
    _controller.removeListener(_updateWordCount);
    _controller.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    final text = _controller.text.trim();
    setState(() {
      _wordCount = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
    });
  }

  void _startWriting() {
    HapticFeedback.mediumImpact();
    final topic = _topics[_selectedTopicIndex];
    final minutes = topic['minutes'] as int;
    setState(() {
      _isWriting = true;
      _secondsLeft = minutes * 60;
      _controller.clear();
      _wordCount = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _timer?.cancel();
        setState(() => _secondsLeft = 0);
        _showTimeUpDialog();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _stopWriting() {
    _timer?.cancel();
    setState(() => _isWriting = false);
  }

  void _showTimeUpDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.timer_off_rounded, color: AppTheme.warningOrange),
          const SizedBox(width: 8),
          Text('Time\'s Up!', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You wrote $_wordCount words.', style: GoogleFonts.inter(fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              _getWordCountFeedback(),
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _stopWriting();
            },
            child: Text('Done', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  String _getWordCountFeedback() {
    final topic = _topics[_selectedTopicIndex];
    final targetWords = topic['wordLimit'] as int;
    if (_wordCount >= targetWords * 0.9 && _wordCount <= targetWords * 1.1) {
      return 'Excellent! Word count is within the ideal range.';
    } else if (_wordCount < targetWords * 0.7) {
      return 'Try to write more — aim for $targetWords words to cover the topic adequately.';
    } else if (_wordCount > targetWords * 1.2) {
      return 'A bit lengthy. Practice concise writing to fit within $targetWords words.';
    }
    return 'Good attempt! Target around $targetWords words for this type of question.';
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_isWriting) return _buildWritingView(context);
    return _buildTopicSelection(context);
  }

  Widget _buildTopicSelection(BuildContext context) {
    return GradientScaffold(
      title: 'Answer Writing Practice',
      extendBodyBehindAppBar: false,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        physics: const BouncingScrollPhysics(),
        children: [
          // Info card
          GlassCard(
            padding: const EdgeInsets.all(16),
            gradient: LinearGradient(colors: [
              AppTheme.primaryColor.withValues(alpha: 0.08),
              AppTheme.accentViolet.withValues(alpha: 0.04),
            ]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.edit_note_rounded, size: 20, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  Text('Why Practice Answer Writing?', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'UPSC Mains is an answer-writing exam. Practice structuring answers with introduction, body, and conclusion within time limits.',
                  style: GoogleFonts.inter(fontSize: 12, height: 1.5, color: AppTheme.textS(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text('Select a Topic', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
          const SizedBox(height: 10),

          ..._topics.asMap().entries.map((entry) {
            final i = entry.key;
            final topic = entry.value;
            final sel = i == _selectedTopicIndex;
            final marksColor = (topic['marks'] as int) >= 15
                ? AppTheme.errorRed
                : AppTheme.warningOrange;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedTopicIndex = i);
                },
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  borderColor: sel ? AppTheme.primaryColor : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentViolet.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(topic['paper'] as String, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.accentViolet)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: marksColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('${topic['marks']} marks', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: marksColor)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('${topic['minutes']} min', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                                ),
                              ],
                            ),
                          ),
                          if (sel) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle_rounded, color: AppTheme.primaryColor, size: 20),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(topic['question'] as String, style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: AppTheme.textP(context), height: 1.5,
                      )),
                      const SizedBox(height: 6),
                      Text('Word limit: ${topic['wordLimit']} words', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textT(context))),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _startWriting,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.edit_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text('Start Writing', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWritingView(BuildContext context) {
    final topic = _topics[_selectedTopicIndex];
    final timeProgress = topic['minutes'] as int;
    final fraction = _secondsLeft / (timeProgress * 60);
    final targetWords = topic['wordLimit'] as int;
    final wordProgress = (_wordCount / targetWords).clamp(0.0, 1.0);

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Column(
          children: [
            // Top bar with timer
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: Text('Stop Writing?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                          content: Text('Your progress won\'t be saved.', style: GoogleFonts.inter()),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textS(context)))),
                            TextButton(
                              onPressed: () { Navigator.pop(context); _stopWriting(); },
                              child: Text('Stop', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.errorRed)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(_formatTime(_secondsLeft), style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          color: fraction > 0.3 ? AppTheme.textP(context) : AppTheme.errorRed,
                        )),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: 1 - fraction,
                            minHeight: 4,
                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation(
                              fraction > 0.3 ? AppTheme.primaryColor : AppTheme.errorRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Word count
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentViolet.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$_wordCount words', style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accentViolet,
                    )),
                  ),
                ],
              ),
            ),

            // Word progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: wordProgress,
                        minHeight: 3,
                        backgroundColor: AppTheme.accentViolet.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation(AppTheme.accentViolet),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$targetWords target', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textT(context))),
                ],
              ),
            ),

            // Question
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: GlassCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(topic['question'] as String, style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.4,
                      )),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _showGuide = !_showGuide),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.warningOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _showGuide ? Icons.close_rounded : Icons.tips_and_updates_rounded,
                          size: 18, color: AppTheme.warningOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Structure guide
            if (_showGuide)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: GlassCard(
                  padding: const EdgeInsets.all(12),
                  gradient: LinearGradient(colors: [
                    AppTheme.warningOrange.withValues(alpha: 0.06),
                    AppTheme.primaryColor.withValues(alpha: 0.04),
                  ]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Answer Structure Guide', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.warningOrange)),
                      const SizedBox(height: 6),
                      _guideItem('Introduction', 'Define key terms, set context (2-3 lines)'),
                      _guideItem('Body', 'Multiple dimensions — social, economic, political, environmental'),
                      _guideItem('Examples', 'Use specific data, schemes, committee reports'),
                      _guideItem('Conclusion', 'Way forward with constructive suggestions'),
                    ],
                  ),
                ),
              ),

            // Writing area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: GlassCard(
                  padding: const EdgeInsets.all(4),
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: GoogleFonts.inter(fontSize: 14, height: 1.7, color: AppTheme.textP(context)),
                    decoration: InputDecoration(
                      hintText: 'Start writing your answer here...\n\nIntroduction:\n\n\nBody:\n\n\nConclusion:',
                      hintStyle: GoogleFonts.inter(fontSize: 14, color: AppTheme.textT(context)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right_rounded, size: 16, color: AppTheme.primaryColor),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$title: ', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                TextSpan(text: desc, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textS(context))),
              ]),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static const _topics = <Map<String, dynamic>>[
    {
      'paper': 'GS-II',
      'marks': 15,
      'minutes': 12,
      'wordLimit': 250,
      'question': 'Discuss the role of the judiciary in protecting fundamental rights in India. How has judicial activism contributed to the expansion of right to life under Article 21?',
    },
    {
      'paper': 'GS-III',
      'marks': 15,
      'minutes': 12,
      'wordLimit': 250,
      'question': 'Critically examine the impact of India\'s digital payment revolution on financial inclusion. What are the challenges that still need to be addressed?',
    },
    {
      'paper': 'GS-I',
      'marks': 10,
      'minutes': 8,
      'wordLimit': 150,
      'question': '"The process of urbanization in India has led to both opportunities and challenges." Discuss with examples.',
    },
    {
      'paper': 'GS-IV',
      'marks': 10,
      'minutes': 8,
      'wordLimit': 150,
      'question': 'What do you understand by "public interest"? How should a civil servant balance public interest with organizational loyalty?',
    },
    {
      'paper': 'GS-II',
      'marks': 15,
      'minutes': 12,
      'wordLimit': 250,
      'question': 'Evaluate the effectiveness of India\'s foreign policy in the Indo-Pacific region. How has the Quad partnership enhanced India\'s strategic interests?',
    },
    {
      'paper': 'GS-III',
      'marks': 10,
      'minutes': 8,
      'wordLimit': 150,
      'question': 'Explain the concept of green hydrogen and its potential role in India\'s energy transition towards net-zero emissions by 2070.',
    },
    {
      'paper': 'Essay',
      'marks': 125,
      'minutes': 45,
      'wordLimit': 1200,
      'question': '"Science without conscience is the soul\'s perdition." Discuss in the context of emerging technologies like AI and gene editing.',
    },
    {
      'paper': 'GS-I',
      'marks': 15,
      'minutes': 12,
      'wordLimit': 250,
      'question': 'Analyze the contribution of the Bhakti and Sufi movements in bridging social divides in medieval India.',
    },
  ];
}
