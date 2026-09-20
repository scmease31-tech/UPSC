import 'package:flutter/material.dart';
import 'fs_colors.dart';
import 'fs_spacing.dart';
import 'fs_typography.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Frosted Scholar · Input primitives
/// ──────────────────────────────────────────────────────────────────────────
/// Frosted text fields with a compact 14×12 content padding, a hairline border
/// that thickens to a 1.5px teal focus ring, and a visible label + error slot
/// so screen readers and sighted users both get state. Fields keep a 48px
/// minimum height for touch.

class FsTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  const FsTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = FsColors.accent(context);
    final hasError = errorText != null && errorText!.isNotEmpty;

    OutlineInputBorder borderOf(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(FsRadii.control),
          borderSide: BorderSide(color: c, width: w),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: FsType.caption(context)),
          const SizedBox(height: FsSpace.xxs),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FsA11y.minTouchTarget),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            maxLines: obscure ? 1 : maxLines,
            enabled: enabled,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: FsType.body(context),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: FsType.caption(context)
                  .copyWith(color: FsColors.textTertiary(context)),
              prefixIcon: prefixIcon != null
                  ? Icon(prefixIcon, size: 18, color: FsColors.textSecondary(context))
                  : null,
              suffixIcon: suffix,
              filled: true,
              fillColor: FsColors.scaffold(context) == Colors.transparent
                  ? null
                  : FsColors.divider(context).withValues(alpha: 0.15),
              isDense: true,
              contentPadding: FsSpacing.input,
              enabledBorder:
                  borderOf(FsColors.divider(context).withValues(alpha: 0.6), 1),
              focusedBorder: borderOf(accent, 1.5),
              errorBorder: borderOf(FsColors.danger, 1),
              focusedErrorBorder: borderOf(FsColors.danger, 1.5),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: FsSpace.xxs),
          Text(errorText!,
              style: FsType.caption(context).copyWith(color: FsColors.danger)),
        ],
      ],
    );
  }
}

/// A rounded frosted search field — the pill variant of [FsTextField].
class FsSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  const FsSearchField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FsA11y.minTouchTarget),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        style: FsType.body(context),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: FsType.caption(context)
              .copyWith(color: FsColors.textTertiary(context)),
          prefixIcon:
              Icon(Icons.search, size: 20, color: FsColors.textSecondary(context)),
          suffixIcon: onClear != null
              ? IconButton(
                  icon: Icon(Icons.close,
                      size: 18, color: FsColors.textSecondary(context)),
                  onPressed: onClear,
                  tooltip: 'Clear',
                )
              : null,
          filled: true,
          fillColor: FsColors.divider(context).withValues(alpha: 0.15),
          isDense: true,
          contentPadding: FsSpacing.input,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FsRadii.pill),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FsRadii.pill),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FsRadii.pill),
            borderSide: BorderSide(color: FsColors.accent(context), width: 1.5),
          ),
        ),
      ),
    );
  }
}
