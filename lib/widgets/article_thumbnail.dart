import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

import '../config/category_style.dart';
import '../config/theme.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// ArticleThumbnail — the single image surface used by every article card.
///
/// Many sources (Drishti "Rapid Fire" pieces, newspaper PDF ingests) genuinely
/// ship without artwork. Instead of a grey "broken image" box — or a random
/// stock photo that has nothing to do with the story — those articles get a
/// generated cover: a deterministic gradient derived from the headline plus the
/// subject's glyph. Same article always renders the same cover, and it works
/// offline.
/// ──────────────────────────────────────────────────────────────────────────────
class ArticleThumbnail extends StatelessWidget {
  final String imageUrl;
  final String title;
  final String category;

  /// Optional label drawn on the generated cover (usually the source name).
  final String? footnote;

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  /// Scrim drawn over real photos so overlaid text stays readable.
  final bool scrim;

  const ArticleThumbnail({
    super.key,
    required this.imageUrl,
    required this.title,
    this.category = '',
    this.footnote,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.scrim = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category.isNotEmpty ? category : title);
    final cover = _GeneratedCover(title: title, style: style, footnote: footnote);

    Widget image;
    if (imageUrl.trim().isEmpty) {
      image = cover;
    } else {
      image = CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        width: width,
        height: height,
        memCacheWidth: width != null && width!.isFinite ? (width! * 2).round() : 720,
        fadeInDuration: const Duration(milliseconds: 250),
        placeholder: (_, __) => _Skeleton(dark: AppTheme.isDark(context)),
        // A dead link should still look designed, never broken.
        errorWidget: (_, __, ___) => cover,
      );
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: scrim
            ? Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.62),
                        ],
                        stops: const [0.35, 1.0],
                      ),
                    ),
                  ),
                ],
              )
            : image,
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final bool dark;
  const _Skeleton({required this.dark});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: dark ? const Color(0xFF1C2333) : const Color(0xFFEDEFF3),
      highlightColor: dark ? const Color(0xFF2A3348) : const Color(0xFFF8FAFC),
      child: Container(color: Colors.white),
    );
  }
}

/// Deterministic, subject-aware cover art for articles with no image.
class _GeneratedCover extends StatelessWidget {
  final String title;
  final CategoryStyle style;
  final String? footnote;

  const _GeneratedCover({required this.title, required this.style, this.footnote});

  /// Stable hash so the same headline always yields the same artwork.
  int get _seed {
    var h = 0;
    for (final c in title.codeUnits) {
      h = 0x1fffffff & (h + c);
      h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
      h ^= h >> 6;
    }
    return h == 0 ? 7 : h;
  }

  @override
  Widget build(BuildContext context) {
    final seed = _seed;
    // Rotate the gradient slightly per-article so a list of image-less cards
    // does not look like the same tile repeated.
    final tilt = ((seed % 5) - 2) * 0.18;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 140.0;
        final compact = h < 96;

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: style.gradient,
              begin: Alignment(-1, -1 + tilt),
              end: Alignment(1, 1 - tilt),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _CoverPainter(seed: seed)),
              Align(
                alignment: compact ? Alignment.center : const Alignment(0.62, -0.05),
                child: Icon(
                  style.icon,
                  size: compact ? h * 0.42 : h * 0.52,
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
              if (!compact)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 26,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        style.label.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (footnote != null && footnote!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          footnote!,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.72),
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
        );
      },
    );
  }
}

/// Soft geometric texture: a few translucent discs plus fine diagonal rules.
class _CoverPainter extends CustomPainter {
  final int seed;
  const _CoverPainter({required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);

    // Diagonal hairlines.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    final step = size.height / 5;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }

    // Translucent discs.
    for (var i = 0; i < 3; i++) {
      final r = size.height * (0.28 + rnd.nextDouble() * 0.45);
      final cx = rnd.nextDouble() * size.width;
      final cy = rnd.nextDouble() * size.height;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = Colors.white.withValues(alpha: i == 0 ? 0.10 : 0.055),
      );
    }

    // Bottom vignette keeps overlaid badges legible.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.22)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _CoverPainter old) => old.seed != seed;
}
