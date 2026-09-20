import 'package:flutter/material.dart';
import '../config/theme.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Frosted Scholar · Color, Glass & Blur tokens
/// ──────────────────────────────────────────────────────────────────────────
/// Teal (primary) + Violet (secondary) accents on a frosted-glass surface,
/// tuned for readable LIGHT **and** DARK modes. All context-aware getters read
/// [Theme.of(context).brightness] so a single call site renders correctly in
/// both modes. Brand hues are shared with the existing [AppTheme] so this
/// system layers on top of the app palette rather than forking it.
///
/// Usage:
/// ```dart
/// color: FsColors.accentTeal
/// decoration: FsGlass.card(context)           // frosted card decoration
/// filter: ImageFilter.blur(sigmaX: FsBlur.card, sigmaY: FsBlur.card)
/// ```
class FsColors {
  FsColors._();

  // ── Accents (shared with AppTheme brand) ────────────────────────────────
  static const Color accentTeal = AppTheme.primaryColor;     // 0xFF00BFA6
  static const Color accentTealSoft = AppTheme.primaryLight; // 0xFF5DF2D6
  static const Color accentViolet = AppTheme.accentViolet;   // 0xFF7C4DFF
  static const Color accentVioletSoft = AppTheme.accentLavender; // 0xFFB388FF

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color success = AppTheme.successGreen;
  static const Color warning = AppTheme.warningOrange;
  static const Color danger = AppTheme.errorRed;

  /// A11y-safe accent on a dark surface: the soft teal has higher luminance
  /// and clears 4.5:1 on the dark card, where the base teal is borderline.
  static Color accent(BuildContext context) =>
      AppTheme.isDark(context) ? accentTealSoft : accentTeal;

  static Color accentSecondary(BuildContext context) =>
      AppTheme.isDark(context) ? accentVioletSoft : accentViolet;

  // ── Text (delegates to AppTheme's tuned pairs) ────────────────────────────
  static Color textPrimary(BuildContext c) => AppTheme.textP(c);
  static Color textSecondary(BuildContext c) => AppTheme.textS(c);
  static Color textTertiary(BuildContext c) => AppTheme.textT(c);

  /// Foreground guaranteed legible on a filled teal/violet button.
  static const Color onAccent = Colors.white;

  // ── Surfaces ──────────────────────────────────────────────────────────────
  static Color scaffold(BuildContext c) => AppTheme.scaffold(c);
  static Color divider(BuildContext c) => AppTheme.divider(c);

  /// Danger tint for error surfaces — low-alpha so it reads as a state, not a
  /// solid block, in both modes.
  static Color dangerSurface(BuildContext c) =>
      danger.withValues(alpha: AppTheme.isDark(c) ? 0.16 : 0.08);
}

/// Controlled blur sigmas. Frosted, not smeared: kept low so text behind the
/// glass never becomes unreadable mush and so the effect stays cheap on
/// mid-range devices. Higher sigmas are deliberately absent.
class FsBlur {
  FsBlur._();

  /// Chips / small overlays. 6.
  static const double subtle = 6;

  /// Standard frosted card. 10.
  static const double card = 10;

  /// Modal / sheet backdrop scrim. 16 — the ceiling; do not exceed.
  static const double modal = 16;
}

/// Frosted surface decorations. Opacity and stroke are split per-brightness so
/// glass stays crisp on the light pastel gradient and luminous on the dark
/// background without a washed-out or muddy look.
class FsGlass {
  FsGlass._();

  /// Standard frosted content card (compact radius). Pair with a
  /// [BackdropFilter] of [FsBlur.card] when placed over imagery; over a flat
  /// scaffold the translucent fill alone is enough and cheaper.
  static BoxDecoration card(BuildContext context, {double? radius}) {
    final dark = AppTheme.isDark(context);
    return BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(radius ?? 16),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.55),
      ),
      boxShadow: dark ? AppTheme.darkCardShadow : AppTheme.softShadow,
    );
  }

  /// A quieter inset surface for rows nested inside a [card].
  static BoxDecoration inset(BuildContext context,
      {double? radius, Color? accent}) {
    final dark = AppTheme.isDark(context);
    final base = accent ?? FsColors.accentTeal;
    return BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: 0.045)
          : base.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(radius ?? 12),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : base.withValues(alpha: 0.10),      ),
    );
  }
}
