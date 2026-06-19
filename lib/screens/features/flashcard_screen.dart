import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/daily_progress_provider.dart';
import '../../services/daily_content_manager.dart';
import '../../widgets/glass_widgets.dart';

/// Flashcard revision mode — swipe through UPSC facts with mastered tracking.
class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageCtrl;
  late AnimationController _flipCtrl;
  int _currentIndex = 0;
  bool _showAnswer = false;
  bool _loading = true;

  // Flashcards are loaded from Firestore or local content manager
  List<Map<String, String>> _flashcards = [];

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _loadFlashcards();
  }

  Future<void> _loadFlashcards() async {
    // Fetch from Firestore first
    await DailyContentManager.fetchFlashcardsFromFirestore();
    final cards = DailyContentManager.getTodaysFlashcards();

    if (!mounted) return;
    final progress = context.read<DailyProgressProvider>();
    setState(() {
      _flashcards = cards;
      _currentIndex = _flashcards.isEmpty ? 0 : progress.flashcardIndex.clamp(0, _flashcards.length - 1);
      _pageCtrl = PageController(initialPage: _currentIndex, viewportFraction: 0.85);
      _loading = false;
    });
  }

  @override
  void dispose() {
    if (!_loading) _pageCtrl.dispose();
    _flipCtrl.dispose();
    super.dispose();
  }

  void _toggleCard() {
    HapticFeedback.lightImpact();
    if (_showAnswer) {
      _flipCtrl.reverse().then((_) {
        if (mounted) setState(() => _showAnswer = false);
      });
    } else {
      setState(() => _showAnswer = true);
      _flipCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return GradientScaffold(
        showAppBar: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () => Navigator.pop(context)),
                    Text('Flashcards', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                  ],
                ),
              ),
              Expanded(child: Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120))),
            ],
          ),
        ),
      );
    }

    if (_flashcards.isEmpty) {
      return GradientScaffold(
        showAppBar: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () => Navigator.pop(context)),
                    Text('Flashcards', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Lottie.asset('assets/animations/empty_box.json', width: 160, height: 160, repeat: true),
                      const SizedBox(height: 12),
                      Text('No flashcards available', style: GoogleFonts.inter(fontSize: 15, color: AppTheme.textS(context))),
                      const SizedBox(height: 4),
                      Text('Check back later for new content', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textT(context))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final dark = AppTheme.isDark(context);
    final progress = context.watch<DailyProgressProvider>();
    final mastered = progress.masteredFlashcards;

    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: Column(
          children: [
            // Custom app bar with mastered badge
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back_ios_rounded), onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  }),
                  Text('Flashcards', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.successGreen),
                        const SizedBox(width: 4),
                        Text(
                          '${mastered.length}/${_flashcards.length}',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.successGreen),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: mastered.length / _flashcards.length,
                backgroundColor: AppTheme.divider(context),
                valueColor: const AlwaysStoppedAnimation(AppTheme.successGreen),
                minHeight: 6,
              ),
            ),
          ),

          // Card number
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${_currentIndex + 1} of ${_flashcards.length}',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textS(context)),
            ),
          ),

          // Flashcard carousel
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _flashcards.length,
              onPageChanged: (i) {
                _flipCtrl.reset();
                setState(() {
                  _currentIndex = i;
                  _showAnswer = false;
                });
                progress.setFlashcardIndex(i);
              },
              itemBuilder: (ctx, i) {
                final card = _flashcards[i];
                final isMastered = mastered.contains(i);

                final isActive = i == _currentIndex;

                return GestureDetector(
                  onTap: () { if (isActive) _toggleCard(); },
                  child: AnimatedBuilder(
                    animation: _flipCtrl,
                    builder: (_, child) {
                      final angle = isActive ? _flipCtrl.value * math.pi : 0.0;
                      final isFront = angle < math.pi / 2;

                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(angle),
                        child: isFront
                            ? _buildCardFace(
                                card: card,
                                isBack: false,
                                isMastered: isMastered,
                                dark: dark,
                              )
                            : Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()..rotateY(math.pi),
                                child: _buildCardFace(
                                  card: card,
                                  isBack: true,
                                  isMastered: isMastered,
                                  dark: dark,
                                ),
                              ),
                      );
                    },
                  ),
                );
              },
            ),
          ),

          // Bottom actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Previous',
                  color: AppTheme.textS(context),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (_currentIndex > 0) {
                      _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                    }
                  },
                ),
                _ActionButton(
                  icon: mastered.contains(_currentIndex) ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                  label: mastered.contains(_currentIndex) ? 'Mastered' : 'Mark Mastered',
                  color: AppTheme.successGreen,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    progress.markFlashcardMastered(_currentIndex);
                  },
                ),
                _ActionButton(
                  icon: Icons.arrow_forward_rounded,
                  label: 'Next',
                  color: AppTheme.primaryColor,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (_currentIndex < _flashcards.length - 1) {
                      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildCardFace({
    required Map<String, String> card,
    required bool isBack,
    required bool isMastered,
    required bool dark,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
      decoration: isBack
          ? BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTheme.primaryColor, AppTheme.primaryColor.withValues(alpha: 0.85)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isMastered
                    ? AppTheme.successGreen.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.2),
                width: isMastered ? 2 : 1,
              ),
            )
          : AppTheme.cleanCard(context, radius: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isBack ? Colors.white : AppTheme.primaryColor).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        card['category']!,
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: isBack ? Colors.white : AppTheme.primaryColor,
                        ),
                      ),
                    ),
                    if (isMastered) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.successGreen),
                            SizedBox(width: 3),
                            Text('Mastered', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.successGreen)),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      isBack ? Icons.visibility_rounded : Icons.touch_app_rounded,
                      size: 18,
                      color: (isBack ? Colors.white : AppTheme.textT(context)).withValues(alpha: 0.5),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  isBack ? 'Answer' : 'Question',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: (isBack ? Colors.white : AppTheme.textT(context)).withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isBack ? card['back']! : card['front']!,
                  style: TextStyle(
                    fontSize: isBack ? 15 : 20,
                    fontWeight: FontWeight.w700,
                    color: isBack ? Colors.white : AppTheme.textP(context),
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.flip_rounded, size: 14,
                        color: (isBack ? Colors.white : AppTheme.textT(context)).withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isBack ? 'Tap to flip back' : 'Tap to reveal answer',
                        style: TextStyle(
                          fontSize: 12,
                          color: (isBack ? Colors.white : AppTheme.textT(context)).withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final btnSize = w < 360 ? 42.0 : 50.0;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: btnSize, height: btnSize,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: btnSize * 0.48),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: w < 360 ? 60 : 80,
            child: Text(label, style: GoogleFonts.inter(fontSize: w < 360 ? 9 : 10, fontWeight: FontWeight.w600, color: color), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
