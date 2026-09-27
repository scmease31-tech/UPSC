import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_fonts.dart';
import '../../config/theme.dart';
import '../../data/offline_content.dart';
import '../../models/government_scheme.dart';
import '../../services/firestore_content_service.dart';
import '../../widgets/glass_widgets.dart';
import 'scheme_detail_sheet.dart';

typedef SchemeDataLoader = Future<List<Map<String, dynamic>>> Function();

/// ──────────────────────────────────────────────────────────────────────────────
/// GovtSchemesScreen — Searchable database of important government schemes
/// organized by ministry/sector for UPSC preparation.
/// ──────────────────────────────────────────────────────────────────────────────
class GovtSchemesScreen extends StatefulWidget {
  const GovtSchemesScreen({
    super.key,
    this.loadSchemes,
    this.refreshSchemes,
  });

  /// Injection points keep the complete loading/filter/rendering path testable
  /// without a Firebase process. Production callers use the service defaults.
  final SchemeDataLoader? loadSchemes;
  final SchemeDataLoader? refreshSchemes;

  @override
  State<GovtSchemesScreen> createState() => _GovtSchemesScreenState();
}

class _GovtSchemesScreenState extends State<GovtSchemesScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedSector = 'All';
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<GovernmentScheme> _schemes = const <GovernmentScheme>[];
  bool _loading = true;
  bool _refreshing = false;
  bool _hasError = false;

  static const _preferredSectors = <String>[
    'Agriculture',
    'Education',
    'Health',
    'Employment',
    'Financial Inclusion',
    'Infrastructure',
    'Social Welfare',
    'Environment',
    'Governance',
    'Other',
  ];

  List<String> get _sectors {
    final present = _schemes.map((scheme) => scheme.sector).toSet();
    final ordered = _preferredSectors.where(present.contains).toList();
    final extra = present
        .where((sector) => !_preferredSectors.contains(sector))
        .toList()
      ..sort();
    return <String>['All', ...ordered, ...extra];
  }

  @override
  void initState() {
    super.initState();
    _loadSchemes();
  }

  List<GovernmentScheme> _normalize(List<Map<String, dynamic>> remote) =>
      GovernmentScheme.combine(remote, OfflineContent.govtSchemes);

  Future<void> _loadSchemes() async {
    try {
      final loader =
          widget.loadSchemes ?? FirestoreContentService.getGovtSchemes;
      final data = await loader();
      if (!mounted) return;
      setState(() {
        _schemes = _normalize(data);
        _loading = false;
        _hasError = widget.loadSchemes == null &&
            FirestoreContentService.lastErrorFor('govtSchemes') != null;
      });
    } catch (error) {
      debugPrint('Failed to load schemes: $error');
      if (!mounted) return;
      // A backend problem must not hide the feature. The curated essentials are
      // shipped in the APK specifically for this path.
      setState(() {
        _schemes = _normalize(const <Map<String, dynamic>>[]);
        _loading = false;
        _hasError = true;
      });
    }
  }

  /// Pull-to-refresh drops BOTH the process and project/schema-scoped disk cache.
  Future<void> _refreshSchemes() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final loader = widget.refreshSchemes ??
          () => FirestoreContentService.refresh('govtSchemes');
      final data = await loader();
      if (!mounted) return;
      setState(() {
        _schemes = _normalize(data);
        _hasError = widget.refreshSchemes == null &&
            FirestoreContentService.lastErrorFor('govtSchemes') != null;
      });
    } catch (error) {
      debugPrint('Failed to refresh schemes: $error');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<GovernmentScheme> get _filtered {
    final queryWords = _searchQuery
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    return _schemes.where((scheme) {
      if (_selectedSector != 'All' && scheme.sector != _selectedSector) {
        return false;
      }
      return queryWords.every(scheme.searchableText.contains);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return GradientScaffold(
        title: 'Govt Schemes',
        extendBodyBehindAppBar: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 14),
              Text(
                'Loading schemes…',
                style: AppFonts.inter(color: AppTheme.textS(context)),
              ),
            ],
          ),
        ),
      );
    }
    final schemes = _filtered;

    return GradientScaffold(
      title: 'Govt Schemes',
      extendBodyBehindAppBar: false,
      child: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.isDark(context)
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
                style: AppFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search schemes...',
                  hintStyle: AppFonts.inter(
                      fontSize: 14, color: AppTheme.textT(context)),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: AppTheme.textT(context), size: 20),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  fillColor: Colors.transparent,
                  filled: true,
                ),
              ),
            ),
          ),
          // Sector chips
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              itemCount: _sectors.length,
              itemBuilder: (context, i) {
                final sec = _sectors[i];
                final selected = sec == _selectedSector;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(sec),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedSector = sec),
                    backgroundColor: AppTheme.isDark(context)
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.7),
                    selectedColor:
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                    labelStyle: AppFonts.inter(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? AppTheme.primaryColor
                            : AppTheme.textS(context)),
                    side: BorderSide(
                        color: selected
                            ? AppTheme.primaryColor
                            : Colors.transparent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
            ),
          ),
          if (_hasError)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppTheme.warningOrange.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.warningOrange.withValues(alpha: 0.24),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 17, color: AppTheme.warningOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing saved essentials. Pull down or tap refresh to retry live data.',
                      style: AppFonts.inter(
                        fontSize: 11,
                        height: 1.35,
                        color: AppTheme.textS(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Count and an explicit refresh affordance. Pull-to-refresh alone is
          // easy to miss when the list is short or empty.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
            child: Row(
              children: [
                Text(
                  schemes.length == _schemes.length
                      ? '${_schemes.length} schemes'
                      : '${schemes.length} of ${_schemes.length} schemes',
                  style: AppFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textS(context),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _refreshing ? null : _refreshSchemes,
                  tooltip: 'Refresh schemes',
                  visualDensity: VisualDensity.compact,
                  icon: _refreshing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                ),
              ],
            ),
          ),
          // Scheme list. Wrapped in a RefreshIndicator even when empty, so a
          // user looking at "No schemes found" can still pull to retry.
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshSchemes,
              color: AppTheme.primaryColor,
              child: schemes.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      children: [
                        SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.18),
                        Icon(Icons.search_off_rounded,
                            size: 46, color: AppTheme.textT(context)),
                        const SizedBox(height: 12),
                        Text(
                          'No schemes match',
                          textAlign: TextAlign.center,
                          style: AppFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textP(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _searchQuery.trim().isNotEmpty ||
                                  _selectedSector != 'All'
                              ? 'Clear the search and category to see all available schemes.'
                              : 'Pull down to fetch the latest scheme library.',
                          textAlign: TextAlign.center,
                          style: AppFonts.inter(
                            fontSize: 12,
                            height: 1.45,
                            color: AppTheme.textS(context),
                          ),
                        ),
                        if (_searchQuery.trim().isNotEmpty ||
                            _selectedSector != 'All') ...[
                          const SizedBox(height: 14),
                          Center(
                            child: TextButton.icon(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _selectedSector = 'All';
                                });
                              },
                              icon: const Icon(Icons.filter_alt_off_rounded,
                                  size: 18),
                              label: const Text('Clear filters'),
                            ),
                          ),
                        ],
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: schemes.length,
                      itemBuilder: (context, i) => _buildSchemeCard(schemes[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemeCard(GovernmentScheme scheme) {
    final icon = FirestoreContentService.getIcon(scheme.iconName);
    final color = FirestoreContentService.parseColor(scheme.colorHex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedGlassCard(
        onTap: () {
          HapticFeedback.lightImpact();
          _showSchemeDetail(scheme);
        },
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scheme.name,
                        style: AppFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textP(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (scheme.fullForm.isNotEmpty &&
                          scheme.fullForm != scheme.name)
                        Text(
                          scheme.fullForm,
                          style: AppFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textT(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppTheme.textT(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              scheme.description.isNotEmpty
                  ? scheme.description
                  : (scheme.body.isNotEmpty
                      ? scheme.body
                      : 'Open for available scheme notes.'),
              style: AppFonts.inter(
                fontSize: 12,
                color: AppTheme.textS(context),
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // Ministry is both a useful scan cue and common exam material.
            if (scheme.ministry.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.account_balance_rounded,
                    size: 13,
                    color: AppTheme.textT(context),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      scheme.ministry,
                      style: AppFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textT(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _schemeBadge(scheme.sector, color),
                // Legacy `year` is coverage metadata. Only the explicit
                // launchYear field may ever receive a launch label.
                if (scheme.coverageYear.isNotEmpty)
                  _schemeBadge(
                    'Coverage: ${scheme.coverageYear}',
                    AppTheme.textTertiary,
                  ),
                if (scheme.launchYear.isNotEmpty)
                  _schemeBadge(
                    'Launch: ${scheme.launchYear}',
                    AppTheme.primaryColor,
                  ),
                if (scheme.beneficiaries.isNotEmpty)
                  _schemeBadge(
                    '${scheme.beneficiaries.length} beneficiary ${scheme.beneficiaries.length == 1 ? 'group' : 'groups'}',
                    color,
                  ),
                if (scheme.hasVerifiedOfficialSource)
                  _schemeBadge('Verified source', AppTheme.successGreen)
                else if (scheme.structuredDetailCount > 0)
                  _schemeBadge(
                    '${scheme.structuredDetailCount}/8 detail areas',
                    AppTheme.primaryColor,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _schemeBadge(String text, Color color) {
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

  void _showSchemeDetail(GovernmentScheme scheme) =>
      showSchemeDetailSheet(context, scheme.toMap());
}
