import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_fonts.dart';
import '../../config/theme.dart';
import '../../models/government_scheme.dart';
import '../../services/firestore_content_service.dart';

typedef SchemeUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchSchemeUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Information-dense, legacy-safe details for a government scheme.
///
/// The widget accepts a map because callers may still hold pre-schema Firestore
/// rows. It immediately normalizes that map through [GovernmentScheme], so
/// malformed optional fields never reach presentation code.
class SchemeDetailSheet extends StatelessWidget {
  const SchemeDetailSheet({
    super.key,
    required this.scheme,
    this.scrollController,
    this.urlLauncher,
  });

  final Map<String, dynamic> scheme;
  final ScrollController? scrollController;

  /// Injectable so widget tests never invoke a platform browser channel.
  final SchemeUrlLauncher? urlLauncher;

  /// The best available summary. Older rows only have `description`.
  static String bodyText(Map<String, dynamic> scheme) =>
      GovernmentScheme.fromMap(scheme).body;

  /// A sparse record has no substantive study notes beyond identity/glance
  /// metadata. Linked citations and the search affordance do not pretend to be
  /// missing scheme content.
  static bool isSparse(Map<String, dynamic> scheme) {
    final normalized = GovernmentScheme.fromMap(scheme);
    return normalized.body.isEmpty &&
        normalized.objective.isEmpty &&
        normalized.beneficiaries.isEmpty &&
        normalized.eligibility.isEmpty &&
        normalized.benefits.isEmpty &&
        normalized.funding.isEmpty &&
        normalized.implementation.isEmpty &&
        normalized.keyFeatures.isEmpty &&
        normalized.upscRelevance.isEmpty;
  }

  /// Splits "GS-II — Issues relating to…" into an exam-paper badge and prose.
  static ({String? paper, String rest}) splitRelevance(String relevance) {
    final match = RegExp(
      r'^\s*(GS-[IV]+(?:\s*/\s*GS-[IV]+)*)\s*[—–-]\s*(.*)$',
      dotAll: true,
    ).firstMatch(relevance);
    if (match == null) return (paper: null, rest: relevance.trim());
    return (paper: match.group(1)!.trim(), rest: match.group(2)!.trim());
  }

  /// Builds a browser-only discovery query. This URI is never stored as a
  /// citation and is created without making a network request.
  static Uri buildOfficialSearchUri(String schemeName) {
    final query = '"${schemeName.trim()}" '
        '(site:myscheme.gov.in OR site:pib.gov.in OR site:gov.in OR site:nic.in)';
    return Uri.https('www.google.com', '/search', <String, String>{'q': query});
  }

  Future<void> _openUri(BuildContext context, Uri uri) async {
    var opened = false;
    try {
      opened = await (urlLauncher ?? _launchSchemeUrl)(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Could not open this link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = GovernmentScheme.fromMap(scheme);
    final icon = FirestoreContentService.getIcon(data.iconName);
    final color = FirestoreContentService.parseColor(data.colorHex);
    final glanceRows = <({IconData icon, String label, String value})>[
      if (data.ministry.isNotEmpty)
        (
          icon: Icons.account_balance_rounded,
          label: 'Administered by',
          value: data.ministry,
        ),
      if (data.sector.isNotEmpty &&
          !(data.sector == 'Other' && data.sourceSector.isEmpty))
        (
          icon: Icons.category_rounded,
          label: 'Sector',
          value: data.sector,
        ),
      if (data.coverageYear.isNotEmpty)
        (
          icon: Icons.library_books_rounded,
          label: 'Coverage year',
          value: data.coverageYear,
        ),
      if (data.launchYear.isNotEmpty)
        (
          icon: Icons.rocket_launch_rounded,
          label: 'Launch year',
          value: data.launchYear,
        ),
    ];
    final hasAtAGlance = data.body.isNotEmpty || glanceRows.isNotEmpty;
    final hasSources = data.officialUrl.isNotEmpty || data.sources.isNotEmpty;

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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      data.name,
                      style: AppFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textP(context),
                      ),
                    ),
                    if (data.fullForm.isNotEmpty && data.fullForm != data.name)
                      Text(
                        data.fullForm,
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
          if (hasAtAGlance) ...[
            const SizedBox(height: 20),
            _SectionLabel(text: 'At a Glance', color: color),
            if (data.body.isNotEmpty) ...[
              const SizedBox(height: 9),
              Text(
                data.body,
                style: AppFonts.inter(
                  fontSize: 14,
                  height: 1.65,
                  color: AppTheme.textP(context),
                ),
              ),
            ],
            if (glanceRows.isNotEmpty) ...[
              const SizedBox(height: 12),
              _GlanceGrid(rows: glanceRows, color: color),
            ],
          ],
          if (data.objective.isNotEmpty)
            _TextSection(
              title: 'Objective',
              text: data.objective,
              color: color,
              icon: Icons.track_changes_rounded,
            ),
          if (data.beneficiaries.isNotEmpty)
            _PointSection(
              title: 'Intended Beneficiaries',
              points: data.beneficiaries,
              color: color,
              icon: Icons.groups_2_rounded,
            ),
          if (data.eligibility.isNotEmpty)
            _PointSection(
              title: 'Eligibility',
              points: data.eligibility,
              color: color,
              icon: Icons.fact_check_rounded,
            ),
          if (data.benefits.isNotEmpty)
            _PointSection(
              title: 'Benefits',
              points: data.benefits,
              color: color,
              icon: Icons.redeem_rounded,
            ),
          if (data.funding.isNotEmpty)
            _TextSection(
              title: 'Funding/Outlay',
              text: data.funding,
              color: color,
              icon: Icons.currency_rupee_rounded,
            ),
          if (data.implementation.isNotEmpty)
            _TextSection(
              title: 'Implementation',
              text: data.implementation,
              color: color,
              icon: Icons.account_tree_rounded,
            ),
          if (data.keyFeatures.isNotEmpty)
            _PointSection(
              title: 'Key Facts',
              points: data.keyFeatures,
              color: color,
              icon: Icons.lightbulb_rounded,
              numbered: true,
            ),
          if (data.upscRelevance.isNotEmpty) ...[
            const SizedBox(height: 22),
            _RelevanceCard(relevance: data.upscRelevance),
          ],
          if (hasSources) ...[
            const SizedBox(height: 22),
            _SectionLabel(
              text: 'Sources',
              color: color,
              trailing:
                  '${data.sources.length + (data.officialUrl.isNotEmpty ? 1 : 0)}',
            ),
            const SizedBox(height: 10),
            _SourcesSection(
              officialUrl: data.officialUrl,
              sources: data.sources,
              color: color,
              onOpen: (uri) => _openUri(context, uri),
            ),
          ],
          if (isSparse(scheme)) ...[
            const SizedBox(height: 18),
            _SparseNote(
              color: color,
              canSearch: data.name.isNotEmpty,
            ),
          ],
          if (data.name.isNotEmpty) ...[
            const SizedBox(height: 18),
            _OfficialSearchAction(
              onTap: () => _openUri(
                context,
                buildOfficialSearchUri(data.name),
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

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
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: AppFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppTheme.textP(context),
            ),
          ),
        ),
        if (trailing != null)
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
    );
  }
}

class _TextSection extends StatelessWidget {
  const _TextSection({
    required this.title,
    required this.text,
    required this.color,
    required this.icon,
  });

  final String title;
  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(text: title, color: color),
          const SizedBox(height: 9),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color.withValues(alpha: 0.14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 17, color: color),
                const SizedBox(width: 10),
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
        ],
      ),
    );
  }
}

class _PointSection extends StatelessWidget {
  const _PointSection({
    required this.title,
    required this.points,
    required this.color,
    required this.icon,
    this.numbered = false,
  });

  final String title;
  final List<String> points;
  final Color color;
  final IconData icon;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            text: title,
            color: color,
            trailing: '${points.length}',
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < points.length; index++)
            _PointCard(
              marker: numbered ? '${index + 1}' : null,
              icon: icon,
              text: points[index],
              color: color,
            ),
        ],
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  const _PointCard({
    required this.marker,
    required this.icon,
    required this.text,
    required this.color,
  });

  final String? marker;
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 23,
              height: 23,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(7),
              ),
              child: marker == null
                  ? Icon(icon, size: 13, color: color)
                  : Text(
                      marker!,
                      style: AppFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
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
    );
  }
}

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
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              Divider(
                height: 1,
                color: AppTheme.textT(context).withValues(alpha: 0.12),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(rows[index].icon, size: 16, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[index].label,
                          style: AppFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                            color: AppTheme.textT(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rows[index].value,
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
              const Icon(
                Icons.school_rounded,
                size: 16,
                color: AppTheme.primaryColor,
              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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

class _SourcesSection extends StatelessWidget {
  const _SourcesSection({
    required this.officialUrl,
    required this.sources,
    required this.color,
    required this.onOpen,
  });

  final String officialUrl;
  final List<GovernmentSchemeSource> sources;
  final Color color;
  final void Function(Uri uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final officialUri = GovernmentScheme.isVerifiedOfficialUrl(officialUrl)
        ? Uri.parse(officialUrl)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (officialUri != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_rounded, size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Verified government page • ${officialUri.host}',
                        style: AppFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  key: const Key('open-official-page'),
                  onPressed: () => onOpen(officialUri),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open official page'),
                ),
              ],
            ),
          ),
          if (sources.isNotEmpty) const SizedBox(height: 9),
        ],
        for (var index = 0; index < sources.length; index++)
          _SourceCard(
            index: index,
            source: sources[index],
            color: color,
            onOpen: onOpen,
          ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.index,
    required this.source,
    required this.color,
    required this.onOpen,
  });

  final int index;
  final GovernmentSchemeSource source;
  final Color color;
  final void Function(Uri uri) onOpen;

  @override
  Widget build(BuildContext context) {
    final uri = source.webUri;
    final title = source.title.isNotEmpty
        ? source.title
        : (source.publisher.isNotEmpty
            ? source.publisher
            : (source.articleId.isNotEmpty
                ? 'Article ${source.articleId}'
                : source.url));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.textT(context).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppTheme.textT(context).withValues(alpha: 0.11),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: (source.official ? color : AppTheme.textT(context))
                  .withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              source.official ? 'Verified official source' : 'Source article',
              style: AppFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: source.official ? color : AppTheme.textS(context),
              ),
            ),
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              title,
              style: AppFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.35,
                color: AppTheme.textP(context),
              ),
            ),
          ],
          if (source.publisher.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Publisher: ${source.publisher}',
              style: AppFonts.inter(
                fontSize: 10,
                color: AppTheme.textS(context),
              ),
            ),
          ],
          if (source.publishedDate.isNotEmpty)
            Text(
              'Published: ${source.publishedDate}',
              style: AppFonts.inter(
                fontSize: 10,
                color: AppTheme.textS(context),
              ),
            ),
          if (uri != null) ...[
            const SizedBox(height: 3),
            TextButton.icon(
              key: ValueKey<String>('open-scheme-source-$index'),
              onPressed: () => onOpen(uri),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('Open source'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SparseNote extends StatelessWidget {
  const _SparseNote({required this.color, required this.canSearch});

  final Color color;
  final bool canSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              canSearch
                  ? 'Only a brief record exists for this scheme so far. '
                      'Missing details are not inferred; use the official-source '
                      'search below to verify current information.'
                  : 'Only a brief record exists for this scheme so far. '
                      'Missing details are not inferred.',
              style: AppFonts.inter(
                fontSize: 12,
                height: 1.5,
                color: AppTheme.textS(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficialSearchAction extends StatelessWidget {
  const _OfficialSearchAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            key: const Key('search-official-sources'),
            onPressed: onTap,
            icon: const Icon(Icons.travel_explore_rounded, size: 18),
            label: const Text('Search official government sources'),
          ),
          const SizedBox(height: 4),
          Text(
            'Opens a site-restricted Google search in your browser. Search '
            'results are not stored or treated as evidence for this note.',
            style: AppFonts.inter(
              fontSize: 10,
              height: 1.4,
              color: AppTheme.textT(context),
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
  Map<String, dynamic> scheme, {
  SchemeUrlLauncher? urlLauncher,
}) {
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
        urlLauncher: urlLauncher,
      ),
    ),
  );
}
