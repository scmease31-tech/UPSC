import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../config/theme.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// NetworkImageWidget — CachedNetworkImage wrapper with shimmer placeholder,
/// error fallback, and consistent styling used across the entire app.
/// ──────────────────────────────────────────────────────────────────────────────
class NetworkImageWidget extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;
  final Widget? errorWidget;
  final Color? shimmerBaseColor;
  final Color? shimmerHighlightColor;
  final bool showOverlay;
  final Gradient? overlayGradient;

  const NetworkImageWidget({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 0,
    this.fit = BoxFit.cover,
    this.errorWidget,
    this.shimmerBaseColor,
    this.shimmerHighlightColor,
    this.showOverlay = false,
    this.overlayGradient,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: fit,
              memCacheWidth: (width ?? 400).toInt(),
              placeholder: (_, __) => _shimmerPlaceholder(dark),
              errorWidget: (_, __, ___) => errorWidget ?? _errorFallback(dark),
              fadeInDuration: const Duration(milliseconds: 300),
              fadeInCurve: Curves.easeOut,
            ),
            if (showOverlay)
              Container(
                decoration: BoxDecoration(
                  gradient: overlayGradient ?? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.5),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerPlaceholder(bool dark) {
    return Shimmer.fromColors(
      baseColor: shimmerBaseColor ?? (dark ? Colors.grey.shade800 : Colors.grey.shade200),
      highlightColor: shimmerHighlightColor ?? (dark ? Colors.grey.shade700 : Colors.grey.shade100),
      child: Container(color: Colors.white),
    );
  }

  Widget _errorFallback(bool dark) {
    return Container(
      color: dark ? Colors.grey.shade800 : Colors.grey.shade200,
      child: Center(
        child: Icon(
          Icons.image_not_supported_rounded,
          color: dark ? Colors.grey.shade600 : Colors.grey.shade400,
          size: 32,
        ),
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// AvatarImage — Circular network avatar with gradient border ring,
/// shimmer loading, and initials fallback.
/// ──────────────────────────────────────────────────────────────────────────────
class AvatarImage extends StatelessWidget {
  final String? imageUrl;
  final String? name;
  final double radius;
  final double borderWidth;
  final Gradient? borderGradient;
  final Color? backgroundColor;

  const AvatarImage({
    super.key,
    this.imageUrl,
    this.name,
    this.radius = 32,
    this.borderWidth = 3,
    this.borderGradient,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    final initials = _getInitials(name ?? '');

    return Container(
      width: (radius + borderWidth) * 2,
      height: (radius + borderWidth) * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: borderGradient ?? const LinearGradient(
          colors: [AppTheme.primaryColor, AppTheme.accentViolet, AppTheme.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(borderWidth),
        child: ClipOval(
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _initialsWidget(initials, dark),
                  errorWidget: (_, __, ___) => _initialsWidget(initials, dark),
                )
              : _initialsWidget(initials, dark),
        ),
      ),
    );
  }

  Widget _initialsWidget(String initials, bool dark) {
    return Container(
      color: dark ? AppTheme.darkCardBg : AppTheme.pastelLavender,
      child: Center(
        child: initials.isNotEmpty
            ? Text(
                initials,
                style: TextStyle(
                  fontSize: radius * 0.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentViolet,
                ),
              )
            : Icon(Icons.person_rounded, size: radius * 0.7, color: AppTheme.accentViolet),
      ),
    );
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// ImageBanner — Full-width banner with image, gradient overlay, and text.
/// Used for promotional cards and hero sections.
/// ──────────────────────────────────────────────────────────────────────────────
class ImageBanner extends StatelessWidget {
  final String imageUrl;
  final String? title;
  final String? subtitle;
  final double height;
  final double borderRadius;
  final VoidCallback? onTap;
  final Gradient? overlayGradient;
  final Widget? child;

  const ImageBanner({
    super.key,
    required this.imageUrl,
    this.title,
    this.subtitle,
    this.height = 160,
    this.borderRadius = 20,
    this.onTap,
    this.overlayGradient,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: AppTheme.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: Colors.grey.shade200,
                  highlightColor: Colors.grey.shade100,
                  child: Container(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => Container(
                  decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
                  child: const Center(child: Icon(Icons.image_rounded, color: Colors.white54, size: 48)),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: overlayGradient ??
                      LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.6),
                        ],
                        stops: const [0.3, 1.0],
                      ),
                ),
              ),
              if (child != null)
                child!
              else
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ──────────────────────────────────────────────────────────────────────────────
/// CategoryImageCard — Small card with background image and category label.
/// ──────────────────────────────────────────────────────────────────────────────
class CategoryImageCard extends StatelessWidget {
  final String imageUrl;
  final String label;
  final Color? labelColor;
  final double width;
  final double height;
  final double borderRadius;
  final VoidCallback? onTap;

  const CategoryImageCard({
    super.key,
    required this.imageUrl,
    required this.label,
    this.labelColor,
    this.width = 100,
    this.height = 70,
    this.borderRadius = 14,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: AppTheme.softShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey.shade200),
                errorWidget: (_, __, ___) => Container(color: Colors.grey.shade300),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: labelColor ?? Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
