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

          // Empty values used to render as blank pills and a bare "Year: ".
          if (sector.isNotEmpty || year.isNotEmpty || ministry.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (sector.isNotEmpty) _badge(sector, color),
                if (year.isNotEmpty) _badge('Year: $year', AppTheme.textTertiary),
                if (ministry.isNotEmpty) _badge(ministry, AppTheme.accentViolet),
              ],
            ),
          ],

          if (body.isNotEmpty) ...[
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            Text(
              'Key Features',
              style: AppFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 10),
            ...keyFeatures.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f,
                        style: AppFonts.inter(
                          fontSize: 13,
                          height: 1.5,
                          color: AppTheme.textP(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (upscRelevance.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.school_rounded,
                        size: 16, color: AppTheme.primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      'UPSC Relevance',
                      style: AppFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    upscRelevance,
                    style: AppFonts.inter(
                      fontSize: 13,
                      height: 1.5,
                      color: AppTheme.textP(context),
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: AppFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
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
