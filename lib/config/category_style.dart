import 'package:flutter/material.dart';
import 'theme.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// CategoryStyle — one source of truth for how a syllabus subject looks.
///
/// Every surface that shows a subject (article cards, news chips, PYQ badges,
/// article detail, generated thumbnails) resolves through here, so a topic has
/// the same colour, gradient and glyph everywhere in the app.
/// ──────────────────────────────────────────────────────────────────────────────
class CategoryStyle {
  final String label;
  final Color color;
  final IconData icon;
  final List<Color> gradient;

  const CategoryStyle._({
    required this.label,
    required this.color,
    required this.icon,
    required this.gradient,
  });

  /// Tinted background for chips/badges, adapted to the current brightness.
  Color soft(BuildContext context) => AppTheme.isDark(context)
      ? color.withValues(alpha: 0.20)
      : color.withValues(alpha: 0.10);

  /// Readable foreground on a [soft] background.
  Color onSoft(BuildContext context) =>
      AppTheme.isDark(context) ? _lighten(color, 0.28) : color;

  static Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  // ── Palette ──────────────────────────────────────────────────────────────
  static const _polity = CategoryStyle._(
    label: 'Polity',
    color: Color(0xFF7C4DFF),
    icon: Icons.account_balance_rounded,
    gradient: [Color(0xFF6A3DE8), Color(0xFFB388FF)],
  );
  static const _governance = CategoryStyle._(
    label: 'Governance',
    color: Color(0xFF5C6BC0),
    icon: Icons.gavel_rounded,
    gradient: [Color(0xFF3F51B5), Color(0xFF7986CB)],
  );
  static const _economy = CategoryStyle._(
    label: 'Economy',
    color: Color(0xFF00897B),
    icon: Icons.trending_up_rounded,
    gradient: [Color(0xFF00897B), Color(0xFF4DD0C4)],
  );
  static const _environment = CategoryStyle._(
    label: 'Environment',
    color: Color(0xFF2E9E5B),
    icon: Icons.eco_rounded,
    gradient: [Color(0xFF1B7F45), Color(0xFF66D48A)],
  );
  static const _science = CategoryStyle._(
    label: 'Science & Technology',
    color: Color(0xFF2979FF),
    icon: Icons.science_rounded,
    gradient: [Color(0xFF1E5FE0), Color(0xFF64B5F6)],
  );
  static const _ir = CategoryStyle._(
    label: 'International Relations',
    color: Color(0xFFE5533D),
    icon: Icons.public_rounded,
    gradient: [Color(0xFFD1442F), Color(0xFFFF8A65)],
  );
  static const _history = CategoryStyle._(
    label: 'History',
    color: Color(0xFF8D6E63),
    icon: Icons.museum_rounded,
    gradient: [Color(0xFF6D4C41), Color(0xFFBCAAA4)],
  );
  static const _geography = CategoryStyle._(
    label: 'Geography',
    color: Color(0xFF0E9AA7),
    icon: Icons.terrain_rounded,
    gradient: [Color(0xFF067A85), Color(0xFF4DD0E1)],
  );
  static const _social = CategoryStyle._(
    label: 'Social Issues',
    color: Color(0xFFF08C00),
    icon: Icons.groups_rounded,
    gradient: [Color(0xFFD97706), Color(0xFFFBBF24)],
  );
  static const _security = CategoryStyle._(
    label: 'Security',
    color: Color(0xFF455A64),
    icon: Icons.shield_rounded,
    gradient: [Color(0xFF37474F), Color(0xFF78909C)],
  );
  static const _ethics = CategoryStyle._(
    label: 'Ethics',
    color: Color(0xFFAD1457),
    icon: Icons.balance_rounded,
    gradient: [Color(0xFF880E4F), Color(0xFFF06292)],
  );
  static const _general = CategoryStyle._(
    label: 'Current Affairs',
    color: Color(0xFF00BFA6),
    icon: Icons.newspaper_rounded,
    gradient: [Color(0xFF00897B), Color(0xFF5DF2D6)],
  );

  /// All canonical subjects, in the order used by filter rows.
  static const List<CategoryStyle> all = [
    _polity, _governance, _economy, _environment, _science,
    _ir, _history, _geography, _social, _security, _ethics, _general,
  ];

  /// Resolve any raw tag ("GS Paper - 2", "biotechnology", "Polity") to a style.
  static CategoryStyle of(String? raw) {
    final k = (raw ?? '').toLowerCase().trim();
    if (k.isEmpty) return _general;

    if (k.contains('polity') || k.contains('constitution') || k.contains('parliament') ||
        k.contains('judiciary') || k.contains('election')) return _polity;
    if (k.contains('governance') || k.contains('government polic') || k.contains('scheme') ||
        k.contains('statutory') || k.contains('welfare')) return _governance;
    if (k.contains('econom') || k.contains('bank') || k.contains('fiscal') ||
        k.contains('monetary') || k.contains('gdp') || k.contains('inflation') ||
        k.contains('trade') || k.contains('agricultur') || k.contains('industry') ||
        k.contains('infrastructure')) return _economy;
    if (k.contains('environment') || k.contains('climate') || k.contains('biodiversity') ||
        k.contains('ecolog') || k.contains('pollution') || k.contains('wildlife') ||
        k.contains('conservation')) return _environment;
    if (k.contains('science') || k.contains('tech') || k.contains('space') ||
        k.contains('biotech') || k.contains('digital') || k.contains('health') ||
        k.contains('vaccine') || k.contains('ai')) return _science;
    if (k.contains('international') || k.contains('foreign') || k.contains('bilateral') ||
        k.contains('diplomacy') || k.contains('global') || k.contains('summit') ||
        k.contains('treaty')) return _ir;
    if (k.contains('history') || k.contains('culture') || k.contains('heritage') ||
        k.contains('freedom struggle') || k.contains('ancient') || k.contains('medieval') ||
        k.contains('modern india')) return _history;
    if (k.contains('geograph') || k.contains('monsoon') || k.contains('river') ||
        k.contains('mapping') || k.contains('resource') || k.contains('mineral') ||
        k.contains('disaster')) return _geography;
    if (k.contains('social') || k.contains('society') || k.contains('education') ||
        k.contains('women') || k.contains('poverty') || k.contains('minorit') ||
        k.contains('tribal') || k.contains('population')) return _social;
    if (k.contains('security') || k.contains('defence') || k.contains('defense') ||
        k.contains('terror') || k.contains('army') || k.contains('cyber')) return _security;
    if (k.contains('ethic') || k.contains('integrity') || k.contains('aptitude') ||
        k.contains('moral')) return _ethics;
    if (k.contains('essay')) return _ethics;

    return _general;
  }

  /// Resolve from a list of tags, preferring the first meaningful one.
  static CategoryStyle fromTags(List<String> tags) {
    for (final t in tags) {
      if (t.trim().isEmpty) continue;
      if (t.toLowerCase().startsWith('gs paper')) continue;
      final s = of(t);
      if (s.label != _general.label) return s;
    }
    return tags.isEmpty ? _general : of(tags.first);
  }
}
