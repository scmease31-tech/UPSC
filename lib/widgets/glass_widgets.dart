import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/theme.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// GradientScaffold — Full-screen pastel gradient background with optional
/// frosted glass app bar. Replaces the old purple wave background.
/// Used as the base layout for every screen in the app.
/// ──────────────────────────────────────────────────────────────────────────────
class GradientScaffold extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool showAppBar;
  final bool centerTitle;
  final bool extendBodyBehindAppBar;
  final PreferredSizeWidget? bottom;
  final Color? appBarBgColor;

  const GradientScaffold({
    super.key,
    required this.child,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.showAppBar = true,
    this.centerTitle = false,
    this.extendBodyBehindAppBar = true,
    this.bottom,
    this.appBarBgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.scaffoldGradient(context),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        appBar: showAppBar
            ? AppBar(
                title: titleWidget ?? (title != null
                    ? Text(title!, style: Theme.of(context).textTheme.titleLarge)
                    : null),
                centerTitle: centerTitle,
                leading: leading,
                actions: actions,
                backgroundColor: appBarBgColor ?? Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                bottom: bottom,
              )
            : null,
        body: child,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// GlassCard — Frosted glassmorphic card with optional blur backdrop
/// ──────────────────────────────────────────────────────────────────────────────
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final double blur;
  final Color? color;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final Gradient? gradient;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding,
    this.margin,
    this.blur = 0,
    this.color,
    this.borderColor,
    this.boxShadow,
    this.onTap,
    this.width,
    this.height,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);

    final cardColor = color ??
        (dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.82));

    final stroke = borderColor ??
        (dark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.5));

    final content = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );

    Widget card = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: gradient != null ? null : cardColor,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: stroke, width: 1.2),
        boxShadow: boxShadow ?? (dark ? AppTheme.darkCardShadow : AppTheme.cardShadow),
      ),
      child: blur > 0
          ? RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: content,
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: content,
            ),
    );

    if (onTap != null) {
      card = GestureDetector(onTap: onTap, child: card);
    }

    return card;
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// AnimatedGlassCard — GlassCard with scale animation on tap
/// ──────────────────────────────────────────────────────────────────────────────
class AnimatedGlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final Gradient? gradient;

  const AnimatedGlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 22,
    this.padding,
    this.margin,
    this.color,
    this.gradient,
  });

  @override
  State<AnimatedGlassCard> createState() => _AnimatedGlassCardState();
}

class _AnimatedGlassCardState extends State<AnimatedGlassCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: GlassCard(
          radius: widget.radius,
          padding: widget.padding,
          margin: widget.margin,
          color: widget.color,
          gradient: widget.gradient,
          child: widget.child,
        ),
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// GradientIconButton — Circular gradient icon button
/// ──────────────────────────────────────────────────────────────────────────────
class GradientIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final List<Color>? colors;
  final Color? iconColor;

  const GradientIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 48,
    this.colors,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final btnColors = colors ?? [AppTheme.primaryColor, AppTheme.primaryLight];
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: btnColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: btnColors[0].withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor ?? Colors.white, size: size * 0.5),
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// PastelTag — Small colored tag/badge with rounded corners
/// ──────────────────────────────────────────────────────────────────────────────
class PastelTag extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final IconData? icon;

  const PastelTag({
    super.key,
    required this.label,
    required this.color,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor ?? AppTheme.textPrimary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// CircularProgress — Animated circular progress indicator
/// ──────────────────────────────────────────────────────────────────────────────
class CircularProgressWidget extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final double size;
  final double strokeWidth;
  final Color? progressColor;
  final Color? trackColor;
  final Widget? child;

  const CircularProgressWidget({
    super.key,
    required this.progress,
    this.size = 80,
    this.strokeWidth = 8,
    this.progressColor,
    this.trackColor,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: strokeWidth,
              strokeCap: StrokeCap.round,
              backgroundColor: trackColor ?? Colors.black.withValues(alpha: 0.06),
              color: progressColor ?? AppTheme.primaryColor,
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// StatCard — Small stat display card with icon + value + label
/// ──────────────────────────────────────────────────────────────────────────────
class StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.textP(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textS(context),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// QuickActionTile — Rounded icon + label tile for quick actions grid
/// ──────────────────────────────────────────────────────────────────────────────
class QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedGlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Reusable CustomAnimatedBuilder -- wraps AnimatedWidget for inline animation builders.
class CustomAnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  const CustomAnimatedBuilder({super.key, required Animation<double> animation, required this.builder})
      : super(listenable: animation);
  @override
  Widget build(BuildContext context) => builder(context, null);
}
