import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// QuizOptionTile — Answer option with gradient state transitions,
/// letter badge (A/B/C/D), and glassmorphic styling.
/// ──────────────────────────────────────────────────────────────────────────────
class QuizOptionTile extends StatelessWidget {
  final String text;
  final int index;
  final bool isSelected;
  final bool isCorrect;
  final bool isAnswered;
  final VoidCallback? onTap;

  const QuizOptionTile({
    super.key,
    required this.text,
    required this.index,
    this.isSelected = false,
    this.isCorrect = false,
    this.isAnswered = false,
    this.onTap,
  });

  String get _label => String.fromCharCode(65 + index); // A, B, C, D

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);

    Color bgColor;
    Color borderCol;
    Color labelBg;
    Color labelText;
    Color textCol;

    if (isAnswered && isSelected && isCorrect) {
      bgColor = AppTheme.successGreen.withValues(alpha: 0.12);
      borderCol = AppTheme.successGreen;
      labelBg = AppTheme.successGreen;
      labelText = Colors.white;
      textCol = AppTheme.successGreen;
    } else if (isAnswered && isSelected && !isCorrect) {
      bgColor = AppTheme.errorRed.withValues(alpha: 0.12);
      borderCol = AppTheme.errorRed;
      labelBg = AppTheme.errorRed;
      labelText = Colors.white;
      textCol = AppTheme.errorRed;
    } else if (isAnswered && isCorrect) {
      bgColor = AppTheme.successGreen.withValues(alpha: 0.08);
      borderCol = AppTheme.successGreen.withValues(alpha: 0.5);
      labelBg = AppTheme.successGreen.withValues(alpha: 0.15);
      labelText = AppTheme.successGreen;
      textCol = AppTheme.textP(context);
    } else if (isSelected) {
      bgColor = AppTheme.primaryColor.withValues(alpha: 0.1);
      borderCol = AppTheme.primaryColor;
      labelBg = AppTheme.primaryColor;
      labelText = Colors.white;
      textCol = AppTheme.primaryColor;
    } else {
      bgColor = dark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.92);
      borderCol = dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08);
      labelBg = dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
      labelText = AppTheme.textS(context);
      textCol = AppTheme.textP(context);
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderCol, width: 1.5),
          boxShadow: isSelected ? [
            BoxShadow(
              color: borderCol.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ] : null,
        ),
        child: Row(
          children: [
            // Letter badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: labelBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  _label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: labelText,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: textCol,
                  height: 1.4,
                ),
              ),
            ),
            if (isAnswered && isSelected)
              Icon(
                isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: isCorrect ? AppTheme.successGreen : AppTheme.errorRed,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
