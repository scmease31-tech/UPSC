import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/theme.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// CategoryChip — Animated selection chip with teal/mint accent
/// ──────────────────────────────────────────────────────────────────────────────
class CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final String? iconPath;

  const CategoryChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.iconPath,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor
              : (dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? AppTheme.primaryColor
                : (dark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06)),
            width: 1,
          ),
          boxShadow: isSelected ? AppTheme.glowShadow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconPath != null) ...[
              Image.asset(iconPath!, width: 16, height: 16,
                color: isSelected ? Colors.white : null,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (dark ? AppTheme.darkTextSecondary : AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
