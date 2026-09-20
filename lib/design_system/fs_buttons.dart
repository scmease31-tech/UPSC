import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fs_colors.dart';
import 'fs_spacing.dart';
import 'fs_typography.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Frosted Scholar · Button primitives
/// ──────────────────────────────────────────────────────────────────────────
/// One button widget, three variants. Visuals are compact (20×12 padding) but
/// every button enforces a 48px minimum tap height so shrinking whitespace
/// never shrinks the touch target. Teal by default; pass [color] for violet or
/// semantic buttons.

enum FsButtonVariant {
  /// Solid accent fill, white label — primary action.
  filled,

  /// Low-alpha accent fill, accent label — secondary action.
  tonal,

  /// Hairline accent border, accent label — tertiary action.
  outline,
}

class FsButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final FsButtonVariant variant;
  final Color? color;
  final bool expand;
  final bool loading;

  const FsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = FsButtonVariant.filled,
    this.color,
    this.expand = false,
    this.loading = false,
  });

  const FsButton.tonal({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.expand = false,
    this.loading = false,
  }) : variant = FsButtonVariant.tonal;

  const FsButton.outline({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.expand = false,
    this.loading = false,
  }) : variant = FsButtonVariant.outline;

  @override
  State<FsButton> createState() => _FsButtonState();
}

class _FsButtonState extends State<FsButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.color ?? FsColors.accent(context);
    final disabled = widget.onPressed == null || widget.loading;

    late final Color bg;
    late final Color fg;
    late final BoxBorder? border;
    switch (widget.variant) {
      case FsButtonVariant.filled:
        bg = accent;
        fg = FsColors.onAccent;
        border = null;
        break;
      case FsButtonVariant.tonal:
        bg = accent.withValues(alpha: 0.14);
        fg = accent;
        border = null;
        break;
      case FsButtonVariant.outline:
        bg = Colors.transparent;
        fg = accent;
        border = Border.all(color: accent.withValues(alpha: 0.45));
        break;
    }

    final Widget label = widget.loading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        : Row(
            mainAxisSize:
                widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: fg),
                const SizedBox(width: FsSpace.xs),
              ],
              Flexible(
                child: Text(widget.label,
                    style: FsType.button(fg),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: Opacity(
        opacity: disabled && !widget.loading ? 0.5 : 1.0,
        child: GestureDetector(
          onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
          onTapUp: disabled
              ? null
              : (_) {
                  setState(() => _pressed = false);
                  HapticFeedback.selectionClick();
                  widget.onPressed!();
                },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? FsMotion.pressScale : 1.0,
            duration: FsMotion.fast,
            curve: FsMotion.curve,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: FsA11y.minTouchTarget),
              child: Container(
                width: widget.expand ? double.infinity : null,
                alignment: Alignment.center,
                padding: FsSpacing.button,
                decoration: BoxDecoration(
                  color: bg,
                  border: border,
                  borderRadius: BorderRadius.circular(FsRadii.control),
                ),
                child: label,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact circular icon button with an enforced 48px tap target regardless of
/// its visual [size].
class FsIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final String? tooltip;

  const FsIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.size = 40,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? FsColors.accent(context);
    final button = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: FsA11y.minTouchTarget,
        minHeight: FsA11y.minTouchTarget,
      ),
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: size * 0.5, color: accent),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip ?? '',
      child: InkResponse(
        onTap: onPressed,
        radius: FsA11y.minTouchTarget / 2,
        child: tooltip != null
            ? Tooltip(message: tooltip!, child: button)
            : button,
      ),
    );
  }
}
