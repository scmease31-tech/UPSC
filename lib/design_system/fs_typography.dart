import 'package:flutter/material.dart';
import '../config/app_fonts.dart';
import 'fs_colors.dart';
import 'fs_spacing.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Frosted Scholar · Type & Motion tokens
/// ──────────────────────────────────────────────────────────────────────────
/// A compact type ramp (Plus Jakarta Sans for display/titles, Inter for body)
/// with line-heights that never drop below the readable floor
/// ([FsA11y.minBodyLineHeight]). Motion is *restrained*: short, eased, no
/// bounce — premium, not playful.
///
/// Usage:
/// ```dart
/// Text('Title', style: FsType.title(context))
/// Text('Body',  style: FsType.body(context))
/// AnimatedContainer(duration: FsMotion.base, curve: FsMotion.curve, ...)
/// ```
class FsType {
  FsType._();

  /// Screen / hero title. 22 / w800.
  static TextStyle display(BuildContext c) => AppFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: FsColors.textPrimary(c),
        letterSpacing: -0.4,
        height: 1.25,
      );

  /// Section / card title. 18 / w700.
  static TextStyle title(BuildContext c) => AppFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: FsColors.textPrimary(c),
        letterSpacing: -0.2,
        height: 1.3,
      );

  /// Sub-title / list heading. 15 / w600.
  static TextStyle subtitle(BuildContext c) => AppFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: FsColors.textPrimary(c),
        height: 1.35,
      );

  /// Primary reading text. 15 / 1.5 line-height for comfortable measure.
  static TextStyle body(BuildContext c) => AppFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: FsColors.textPrimary(c),
        height: 1.5,
      );

  /// Secondary/supporting text. 13 / muted.
  static TextStyle caption(BuildContext c) => AppFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: FsColors.textSecondary(c),
        height: FsA11y.minBodyLineHeight,
      );

  /// Micro label — tags, timestamps. 11 / w600 / tertiary.
  static TextStyle label(BuildContext c) => AppFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: FsColors.textTertiary(c),
        letterSpacing: 0.2,
      );

  /// Button label. 14 / w600.
  static TextStyle button(Color color) => AppFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.1,
      );
}

/// Restrained motion. One base duration for most transitions; a slightly
/// longer one for entering surfaces. No elastic/bounce curves — a single
/// decelerating ease keeps the whole app feeling calm and premium.
class FsMotion {
  FsMotion._();

  /// Taps, toggles, micro-feedback. 120ms.
  static const Duration fast = Duration(milliseconds: 120);

  /// Standard state transition. 220ms.
  static const Duration base = Duration(milliseconds: 220);

  /// Surface enter (sheets, dialogs). 300ms.
  static const Duration enter = Duration(milliseconds: 300);

  /// The single approved easing curve. Decelerating, no overshoot.
  static const Curve curve = Curves.easeOutCubic;

  /// Press-scale for tappable cards — a subtle 0.97, never a dramatic squish.
  static const double pressScale = 0.97;
}
