import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fs_colors.dart';
import 'fs_spacing.dart';
import 'fs_typography.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Frosted Scholar · Surface primitives
/// ──────────────────────────────────────────────────────────────────────────
/// Reusable frosted containers and headers. All spacing/blur/radii come from
/// tokens, so these render consistently in light and dark and keep the compact
/// premium rhythm without per-screen tuning.

/// The canonical content card. Compact 14px padding, 16px radius, controlled
/// frosted fill. Set [frost] true to add a real backdrop blur (use over
/// imagery); leave false over a flat scaffold for a cheaper translucent look.
/// When [onTap] is set the card gets a restrained press-scale and a 48px
/// minimum tap height for accessibility.
class FsCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double? radius;
  final VoidCallback? onTap;
  final bool frost;
  final Color? tint;

  const FsCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius,
    this.onTap,
    this.frost = false,
    this.tint,
  });

  @override
  State<FsCard> createState() => _FsCardState();
}

class _FsCardState extends State<FsCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.radius ?? FsRadii.card;
    var decoration = FsGlass.card(context, radius: radius);
    if (widget.tint != null) {
      decoration = decoration.copyWith(color: widget.tint);
    }

    Widget content = Padding(
      padding: widget.padding ?? FsSpacing.cardPadding,
      child: widget.child,
    );

    if (widget.frost) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: FsBlur.card, sigmaY: FsBlur.card),
          child: content,
        ),
      );
    }

    final Widget card = Container(
      margin: widget.margin,
      decoration: decoration,
      child: content,
    );

    if (widget.onTap == null) return card;

    return Semantics(
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          HapticFeedback.selectionClick();
          widget.onTap!();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FsA11y.minTouchTarget),
          child: AnimatedScale(
            scale: _pressed ? FsMotion.pressScale : 1.0,
            duration: FsMotion.fast,
            curve: FsMotion.curve,
            child: card,
          ),
        ),
      ),
    );
  }
}

/// Section header with a teal accent bar and optional trailing action pill.
/// Compact vertical rhythm (12/4) to keep sections tight.
class FsSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FsSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final accent = FsColors.accent(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FsSpace.lg, FsSpace.md, FsSpace.lg, FsSpace.xxs),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: FsSpace.xs),
          Expanded(
            child: Text(title,
                style: FsType.title(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (actionLabel != null)
            Semantics(
              button: true,
              child: GestureDetector(
                onTap: onAction,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(minHeight: FsA11y.minTouchTarget),
                  child: Container(
                    alignment: Alignment.center,
                    padding: FsSpacing.chip,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(FsRadii.pill),
                    ),
                    child: Text(actionLabel!, style: FsType.button(accent)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small semantic tag/badge. Teal by default; pass [color] for violet/danger.
class FsTag extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;

  const FsTag({super.key, required this.label, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final c = color ?? FsColors.accent(context);
    return Container(
      padding: FsSpacing.chip,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FsRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: FsSpace.xxs),
          ],
          Text(label, style: FsType.button(c).copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
