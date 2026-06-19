import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// ScrollToTopFab — Glassmorphic animated scroll-to-top button.
/// Shows after scrolling past [showAfterOffset] with a bounce-in animation.
/// Features frosted glass effect, glow ring, and pulse animation.
/// ──────────────────────────────────────────────────────────────────────────────
class ScrollToTopFab extends StatefulWidget {
  final ScrollController scrollController;
  final double showAfterOffset;

  const ScrollToTopFab({
    super.key,
    required this.scrollController,
    this.showAfterOffset = 200,
  });

  @override
  State<ScrollToTopFab> createState() => _ScrollToTopFabState();
}

class _ScrollToTopFabState extends State<ScrollToTopFab>
    with SingleTickerProviderStateMixin {
  bool _show = false;
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.elasticOut,
    );
    _glowAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    );
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ScrollToTopFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    _animCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final shouldShow =
        widget.scrollController.offset > widget.showAfterOffset;
    if (shouldShow != _show) {
      setState(() => _show = shouldShow);
      if (shouldShow) {
        _animCtrl.forward(from: 0);
      } else {
        _animCtrl.reverse();
      }
    }
  }

  void _scrollToTop() {
    HapticFeedback.mediumImpact();
    widget.scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);

    return IgnorePointer(
      ignoring: !_show,
      child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, child) {
          final scale = _show ? _scaleAnim.value : (1.0 - _glowAnim.value);
          final opacity = _show ? _glowAnim.value : (1.0 - _glowAnim.value);

          return Transform.scale(
            scale: scale.clamp(0.0, 1.2),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: GestureDetector(
          onTap: _scrollToTop,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor.withValues(alpha: dark ? 0.7 : 0.85),
                  AppTheme.accentViolet.withValues(alpha: dark ? 0.5 : 0.65),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
