import 'package:flutter/material.dart';

import '../../config/app_fonts.dart';
import '../../config/theme.dart';
import '../../services/firestore_content_service.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// SchemeDetailSheet — the body of the Govt Schemes detail sheet.
///
/// Scheme documents arrive in two very different shapes and this has to read
/// both:
///
///   • The embedded OfflineContent set is hand-written and complete: it carries
///     ministry, detailedDescription, keyFeatures and upscRelevance.
///   • The scraper-derived `govtSchemes` documents — which WIN over the embedded
///     set whenever Firestore returns anything — are built by
///     generators.js:generateSchemes and contain only
///     id, name, fullForm, description, sector, year, iconName, colorHex.
///
/// The earlier version read detailedDescription, keyFeatures and upscRelevance
/// and nothing else, all unguarded. Against a scraper document that produced a
/// title, an empty badge, a "Key Features" heading with no features under it and
/// an empty "UPSC Relevance" box — a sheet that looked blank, even though the
/// card behind it looked complete because the card guards every optional field
/// and falls back to `description`.
///
/// So: fall back to the fields that do exist, and never render the heading for a
/// section that has no content.
/// ──────────────────────────────────────────────────────────────────────────────
class SchemeDetailSheet extends StatelessWidget {
  const SchemeDetailSheet({super.key, required this.scheme, this.scrollController});

  final Map<String, dynamic> scheme;
  final ScrollController? scrollController;

  static String _str(Map<String, dynamic> m, String key) =>
      (m[key] as String? ?? '').trim();

  static List<String> _list(Map<String, dynamic> m, String key) =>
      (m[key] as List<dynamic>?)
          ?.map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList() ??
      const <String>[];

  /// The best available prose for the scheme. Scraper documents only have
  /// `description`, so preferring `detailedDescription` but falling back is what
  /// keeps the sheet from being empty.
  static String bodyText(Map<String, dynamic> scheme) {
    final detailed = _str(scheme, 'detailedDescription');
    return detailed.isNotEmpty ? detailed : _str(scheme, 'description');
  }

  /// True when there is nothing beyond the header worth showing. Callers can use
  /// this to explain the gap instead of presenting an empty sheet.
  static bool isSparse(Map<String, dynamic> scheme) =>
      bodyText(scheme).isEmpty &&
      _list(scheme, 'keyFeatures').isEmpty &&
      _str(scheme, 'upscRelevance').isEmpty;

  /// Splits "GS-II — Issues relating to…" into its paper label and the rest, so
  /// the paper can be shown as a badge instead of buried in a paragraph. Returns
  /// a null label when the text does not start with a recognisable paper.
  static ({String? paper, String rest}) splitRelevance(String relevance) {
    final match = RegExp(
      r'^\s*(GS-[IV]+(?:\s*/\s*GS-[IV]+)*)\s*[—–-]\s*(.*)$',
      dotAll: true,
    ).firstMatch(relevance);
    if (match == null) return (paper: null, rest: relevance.trim());
    return (paper: match.group(1)!.trim(), rest: match.group(2)!.trim());
  }

  @override
  Widget build(BuildContext context) {
    final name = _str(scheme, 'name');
    final fullForm = _str(scheme, 'fullForm');
    final sector = _str(scheme, 'sector');
    final year = _str(scheme, 'year');
    final ministry = _str(scheme, 'ministry');
    final body = bodyText(scheme);
    final keyFeatures = _list(scheme, 'keyFeatures');
    final upscRelevance = _str(scheme, 'upscRelevance');
    final icon = FirestoreContentService.getIcon(_str(scheme, 'iconName'));
    final color = FirestoreContentService.parseColor(_str(scheme, 'colorHex'));

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textT(context).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.6)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textP(context),
                      ),
                    ),
                    if (fullForm.isNotEmpty && fullForm != name)
                      Text(
                        fullForm,
                        style: AppFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textS(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // At a glance: the three facts most often asked about a scheme, each
          // labelled so they read as answers rather than loose pills. Empty
          // values are skipped — they used to render as blank pills and a bare
          // "Year: ".
          if (sector.isNotEmpty || year.isNotEmpty || ministry.isNotEmpty) ...[
            const SizedBox(height: 18),
            _GlanceGrid(
              color: color,
              rows: [
                if (ministry.isNotEmpty)
                  (
                    icon: Icons.account_balance_rounded,
                    label: 'Administered by',
                    value: ministry
                  ),
                if (sector.isNotEmpty)
                  (icon: Icons.category_rounded, label: 'Sector', value: sector),
                if (year.isNotEmpty)
                  (
                    icon: Icons.event_rounded,
                    label: 'In coverage from',
                    value: year
                  ),
              ],
            ),
          ],

          if (body.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionLabel(text: 'Overview', color: color),
            const SizedBox(height: 8),
            Text(
              body,
              style: AppFonts.inter(
                fontSize: 14,
                height: 1.7,
                color: AppTheme.textP(context),
              ),
            ),
          ],

          if (keyFeatures.isNotEmpty) ...[
            const SizedBox(height: 22),
            _SectionLabel(
              text: 'Key Features',
              color: color,
              trailing: '${keyFeatures.length}',
            ),
            const SizedBox(height: 12),
            // Numbered cards rather than bare bullets: these are revision points,
            // and a number gives them a handle ("the third feature").
            ...keyFeatures.asMap().entries.map(
                  (e) => _FeatureCard(
                    index: e.key + 1,
                    text: e.value,
                    color: color,
                  ),
                ),
          ],

          if (upscRelevance.isNotEmpty) ...[
            const SizedBox(height: 22),
            _RelevanceCard(relevance: upscRelevance),
          ],

          // A scraper-derived scheme can legitimately have nothing but a name
          // and a sector. Say so rather than showing an empty sheet.
          if (isSparse(scheme)) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: AppTheme.textT(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only a brief record exists for this scheme so far. Fuller '
                    'notes appear once it is covered in more detail.',
                    style: AppFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: AppTheme.textT(context),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

}

/// A small capitalised section heading with an accent rule, so the sheet reads as
/// distinct sections instead of one continuous column of text.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color, this.trailing});

  final String text;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: AppFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: AppTheme.textP(context),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              trailing!,
              style: AppFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Label/value rows for the facts a scheme is most often examined on.
class _GlanceGrid extends StatelessWidget {
  const _GlanceGrid({required this.rows, required this.color});

  final List<({IconData icon, String label, String value})> rows;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.textT(context).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: AppTheme.textT(context).withValues(alpha: 0.12),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(rows[i].icon, size: 16, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].label,
                          style: AppFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            color: AppTheme.textT(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rows[i].value,
                          style: AppFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: AppTheme.textP(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One numbered revision point.
class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.index,
    required this.text,
    required this.color,
  });

  final int index;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '$index',
                style: AppFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                text,
                style: AppFonts.inter(
                  fontSize: 13,
                  height: 1.55,
                  color: AppTheme.textP(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// UPSC relevance, with the GS paper lifted out of the prose into a badge.
class _RelevanceCard extends StatelessWidget {
  const _RelevanceCard({required this.relevance});

  final String relevance;

  @override
  Widget build(BuildContext context) {
    final split = SchemeDetailSheet.splitRelevance(relevance);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school_rounded,
                  size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 6),
              Text(
                'UPSC Relevance',
                style: AppFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  color: AppTheme.primaryColor,
                ),
              ),
              if (split.paper != null) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    split.paper!,
                    style: AppFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Text(
            split.rest,
            style: AppFonts.inter(
              fontSize: 13,
              height: 1.55,
              color: AppTheme.textP(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens [SchemeDetailSheet] as a draggable modal sheet.
Future<void> showSchemeDetailSheet(
  BuildContext context,
  Map<String, dynamic> scheme,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => SchemeDetailSheet(
        scheme: scheme,
        scrollController: scroll,
      ),
    ),
  );
}
