import 'package:flutter/material.dart';
import 'fs_buttons.dart';
import 'fs_colors.dart';
import 'fs_spacing.dart';
import 'fs_typography.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Frosted Scholar · State primitives
/// ──────────────────────────────────────────────────────────────────────────
/// Consistent loading / empty / error states so every screen speaks the same
/// language. All three are centered, compact, and readable in both modes;
/// error and empty use accessible messaging (a heading + explanation) and a
/// clear recovery action.

/// A single shimmering skeleton block. Compose several to preview a card's
/// layout while data loads. Animation is a slow, restrained opacity pulse — no
/// sweeping gradients.
class FsSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const FsSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = FsRadii.sm,
  });

  @override
  State<FsSkeleton> createState() => _FsSkeletonState();
}

class _FsSkeletonState extends State<FsSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = FsColors.divider(context);
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 0.9).animate(
        CurvedAnimation(parent: _c, curve: FsMotion.curve),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A centered accent spinner for indeterminate short waits.
class FsLoading extends StatelessWidget {
  final String? message;
  const FsLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: FsColors.accent(context),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: FsSpace.md),
            Text(message!,
                style: FsType.caption(context), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Empty state — a muted icon, a heading, a supporting line, and an optional
/// primary action. Generous vertical breathing room ([FsSpace.huge]) since it
/// occupies an otherwise empty screen.
class FsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FsEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FsSpace.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: FsColors.textTertiary(context)),
            const SizedBox(height: FsSpace.lg),
            Text(title,
                style: FsType.title(context), textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: FsSpace.xs),
              Text(message!,
                  style: FsType.caption(context), textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: FsSpace.xl),
              FsButton.tonal(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state — a danger-tinted icon, a clear heading, the (optional) detail,
/// and a Retry action. Detail text stays secondary so the recovery action is
/// the focal point.
class FsErrorState extends StatelessWidget {
  final String title;
  final String? detail;
  final VoidCallback? onRetry;
  final String retryLabel;

  const FsErrorState({
    super.key,
    this.title = 'Something went wrong',
    this.detail,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FsSpace.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(FsSpace.md),
              decoration: BoxDecoration(
                color: FsColors.dangerSurface(context),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline,
                  size: 30, color: FsColors.danger),
            ),
            const SizedBox(height: FsSpace.lg),
            Text(title,
                style: FsType.title(context), textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: FsSpace.xs),
              Text(detail!,
                  style: FsType.caption(context), textAlign: TextAlign.center),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: FsSpace.xl),
              FsButton(
                label: retryLabel,
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
