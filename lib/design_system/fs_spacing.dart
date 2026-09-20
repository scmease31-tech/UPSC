import 'package:flutter/widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Frosted Scholar · Spacing, Radii & Layout tokens
/// ──────────────────────────────────────────────────────────────────────────
/// Compact premium rhythm. The design target is a *balanced 12–16px* content
/// gutter — tight enough to feel dense/premium, loose enough to preserve
/// 48px touch targets and comfortable reading measure. Prefer these named
/// tokens over raw magic numbers so whitespace stays consistent app-wide.
///
/// Usage:
/// ```dart
/// Padding(padding: FsSpacing.cardPadding, child: ...)   // EdgeInsets
/// const SizedBox(height: FsSpace.md)                     // 12
/// BorderRadius.circular(FsRadii.card)                    // 16
/// ```
class FsSpace {
  FsSpace._();

  /// Micro gap — inline icon↔label, chip internal. 4px.
  static const double xxs = 4;

  /// Tight gap — dense list rows, badge stacks. 8px.
  static const double xs = 8;

  /// Default in-card gap between related elements. 12px.
  /// This is the low end of the balanced 12–16 band.
  static const double md = 12;

  /// Standard content gutter / screen edge padding. 16px.
  /// This is the high end of the balanced band and the app default.
  static const double lg = 16;

  /// Section separation — between distinct card groups. 20px.
  static const double xl = 20;

  /// Major section / above a screen title. 24px.
  static const double xxl = 24;

  /// Hero / empty-state vertical breathing room. 32px.
  static const double huge = 32;
}

/// Corner radii. Compact glass reads best with medium-soft corners; avoid
/// over-rounding small controls (looks toy-like) or under-rounding cards
/// (breaks the frosted feel).
class FsRadii {
  FsRadii._();

  /// Chips, tags, small inline controls. 10px.
  static const double sm = 10;

  /// Inputs, buttons, inset rows. 12px.
  static const double control = 12;

  /// Primary content cards. 16px.
  static const double card = 16;

  /// Modals, sheets, large surfaces. 22px.
  static const double lg = 22;

  /// Fully rounded (pills, avatars). 100px.
  static const double pill = 100;
}

/// Prebuilt [EdgeInsets] so screens don't re-derive the same paddings. Every
/// value is drawn from [FsSpace] to keep the compact rhythm coherent.
class FsSpacing {
  FsSpacing._();

  /// Screen horizontal gutter. 16px sides.
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: FsSpace.lg);

  /// Screen padding all-round. 16px.
  static const EdgeInsets screen = EdgeInsets.all(FsSpace.lg);

  /// Interior padding of a standard card. 14px — the visual midpoint of the
  /// 12–16 band; feels compact without cramping text.
  static const EdgeInsets cardPadding = EdgeInsets.all(14);

  /// Compact card padding for dense rows. 12px.
  static const EdgeInsets cardPaddingTight = EdgeInsets.all(FsSpace.md);

  /// List item vertical rhythm. 12px vertical, 16px horizontal.
  static const EdgeInsets listItem =
      EdgeInsets.symmetric(horizontal: FsSpace.lg, vertical: FsSpace.md);

  /// Button hit padding. 20×12 keeps the visual compact while the [FsButton]
  /// primitive enforces a 48px minimum tap height around it.
  static const EdgeInsets button =
      EdgeInsets.symmetric(horizontal: FsSpace.xl, vertical: FsSpace.md);

  /// Chip padding. 12×6.
  static const EdgeInsets chip =
      EdgeInsets.symmetric(horizontal: FsSpace.md, vertical: 6);

  /// Input content padding. 14×12.
  static const EdgeInsets input =
      EdgeInsets.symmetric(horizontal: 14, vertical: FsSpace.md);
}

/// Accessibility floors. Do not shrink whitespace past these — reducing
/// gutter padding never justifies a sub-minimum touch target.
class FsA11y {
  FsA11y._();

  /// Minimum interactive target (WCAG 2.5.5 / Material). Applied by [FsButton],
  /// icon buttons and list tiles even when their visual box is smaller.
  static const double minTouchTarget = 48;

  /// Minimum body line-height multiplier for readable measure.
  static const double minBodyLineHeight = 1.4;
}
