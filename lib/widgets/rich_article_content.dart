import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/theme.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// RichArticleContent — renders scraped article bodies as a real reading layout.
///
/// The ingest pipeline emits lightly-marked plain text:
///
///   "## "  section heading
///   "### " sub-heading
///   "• "   bullet
///   "◦ "   nested bullet
///
/// Anything else is a paragraph. Text stored by older runs has no markers at
/// all, so bare paragraphs must stay readable — they simply render as prose.
/// ──────────────────────────────────────────────────────────────────────────────
class RichArticleContent extends StatelessWidget {
  final String content;

  /// Reader font scale (1.0 = default). Driven by the A- / A+ control.
  final double scale;

  const RichArticleContent({super.key, required this.content, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(content);
    if (blocks.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final isFirst = i == 0;
      switch (b.kind) {
        case _Kind.heading:
          children.add(Padding(
            padding: EdgeInsets.only(top: isFirst ? 0 : 22, bottom: 10),
            child: _Heading(text: b.text, scale: scale),
          ));
          break;
        case _Kind.subheading:
          children.add(Padding(
            padding: EdgeInsets.only(top: isFirst ? 0 : 16, bottom: 8),
            child: Text(
              b.text,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15 * scale,
                fontWeight: FontWeight.w700,
                color: AppTheme.textP(context),
                height: 1.35,
              ),
            ),
          ));
          break;
        case _Kind.bullet:
          children.add(Padding(
            padding: EdgeInsets.only(left: b.depth * 16.0, bottom: 8),
            child: _Bullet(text: b.text, depth: b.depth, scale: scale),
          ));
          break;
        case _Kind.paragraph:
          children.add(Padding(
            padding: EdgeInsets.only(bottom: 12, top: isFirst ? 0 : 2),
            child: Text(
              b.text,
              style: GoogleFonts.inter(
                fontSize: 15 * scale,
                color: AppTheme.textP(context),
                height: 1.72,
                letterSpacing: 0.05,
              ),
            ),
          ));
          break;
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  static List<_Block> _parse(String raw) {
    final blocks = <_Block>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;

      if (t.startsWith('### ')) {
        blocks.add(_Block(_Kind.subheading, t.substring(4).trim(), 0));
      } else if (t.startsWith('## ')) {
        blocks.add(_Block(_Kind.heading, t.substring(3).trim(), 0));
      } else if (t.startsWith('# ')) {
        blocks.add(_Block(_Kind.heading, t.substring(2).trim(), 0));
      } else if (t.startsWith('◦ ') || t.startsWith('◦')) {
        blocks.add(_Block(_Kind.bullet, t.replaceFirst(RegExp(r'^◦\s*'), ''), 1));
      } else if (t.startsWith('• ') || t.startsWith('•')) {
        blocks.add(_Block(_Kind.bullet, t.replaceFirst(RegExp(r'^•\s*'), ''), 0));
      } else if (RegExp(r'^[-*]\s+\S').hasMatch(t)) {
        blocks.add(_Block(_Kind.bullet, t.replaceFirst(RegExp(r'^[-*]\s+'), ''), 0));
      } else if (RegExp(r'^---+\s*(.*?)\s*---+$').hasMatch(t)) {
        // "--- Additional Analysis (Source) ---" separators from merged articles.
        final m = RegExp(r'^---+\s*(.*?)\s*---+$').firstMatch(t)!;
        blocks.add(_Block(_Kind.heading, m.group(1)!.trim(), 0));
      } else {
        blocks.add(_Block(_Kind.paragraph, t, 0));
      }
    }
    // Drop a trailing heading with nothing under it.
    if (blocks.isNotEmpty && blocks.last.kind == _Kind.heading) blocks.removeLast();
    return blocks;
  }
}

enum _Kind { heading, subheading, bullet, paragraph }

class _Block {
  final _Kind kind;
  final String text;
  final int depth;
  const _Block(this.kind, this.text, this.depth);
}

class _Heading extends StatelessWidget {
  final String text;
  final double scale;
  const _Heading({required this.text, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          height: 18 * scale,
          margin: const EdgeInsets.only(top: 3, right: 10),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17.5 * scale,
              fontWeight: FontWeight.w800,
              color: AppTheme.textP(context),
              height: 1.3,
              letterSpacing: -0.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  final int depth;
  final double scale;
  const _Bullet({required this.text, required this.depth, required this.scale});

  @override
  Widget build(BuildContext context) {
    final color = depth == 0 ? AppTheme.primaryColor : AppTheme.accentViolet;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: depth == 0 ? 6 : 5,
          height: depth == 0 ? 6 : 5,
          margin: EdgeInsets.only(top: 8 * scale, right: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: depth == 0 ? 0.85 : 0.55),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: (depth == 0 ? 14.5 : 14) * scale,
              color: depth == 0 ? AppTheme.textP(context) : AppTheme.textS(context),
              height: 1.62,
            ),
          ),
        ),
      ],
    );
  }
}
