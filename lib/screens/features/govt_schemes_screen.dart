import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import '../../config/theme.dart';
import '../../services/firestore_content_service.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// GovtSchemesScreen — Searchable database of important government schemes
/// organized by ministry/sector for UPSC preparation.
/// ──────────────────────────────────────────────────────────────────────────────
class GovtSchemesScreen extends StatefulWidget {
  const GovtSchemesScreen({super.key});

  @override
  State<GovtSchemesScreen> createState() => _GovtSchemesScreenState();
}

class _GovtSchemesScreenState extends State<GovtSchemesScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedSector = 'All';
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _schemes = [];
  bool _loading = true;

  bool _hasError = false;

  static const _sectors = [
    'All', 'Agriculture', 'Education', 'Health', 'Employment',
    'Financial Inclusion', 'Infrastructure', 'Social Welfare', 'Environment',
  ];

  @override
  void initState() {
    super.initState();
    _loadSchemes();
  }

  Future<void> _loadSchemes() async {
    try {
      final data = await FirestoreContentService.getGovtSchemes();
      if (mounted) setState(() { _schemes = data; _loading = false; });
    } catch (e) {
      debugPrint('Failed to load schemes: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    return _schemes.where((s) {
      final sector = s['sector'] as String? ?? '';
      final name = (s['name'] as String? ?? '').toLowerCase();
      final fullForm = (s['fullForm'] as String? ?? '').toLowerCase();
      final desc = (s['description'] as String? ?? '').toLowerCase();
      if (_selectedSector != 'All' && sector != _selectedSector) return false;
      if (_searchQuery.isNotEmpty && !name.contains(_searchQuery) && !fullForm.contains(_searchQuery) && !desc.contains(_searchQuery)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return GradientScaffold(
        title: 'Govt Schemes',
        extendBodyBehindAppBar: false,
        child: Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120)),
      );
    }
    if (_hasError) {
      return GradientScaffold(
        title: 'Govt Schemes',
        extendBodyBehindAppBar: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppTheme.textT(context)),
              const SizedBox(height: 12),
              Text('Failed to load schemes', style: GoogleFonts.inter(color: AppTheme.textS(context))),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() { _loading = true; _hasError = false; });
                  _loadSchemes();
                },
                child: const Text('Retry'),
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
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.isDark(context)
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                style: GoogleFonts.inter(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search schemes...',
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: AppTheme.textT(context)),
                  prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textT(context), size: 20),
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
                    backgroundColor: AppTheme.isDark(context) ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.7),
                    selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
                    labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppTheme.primaryColor : AppTheme.textS(context)),
                    side: BorderSide(color: selected ? AppTheme.primaryColor : Colors.transparent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
            ),
          ),
          // Count
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Row(
              children: [
                Text('${schemes.length} schemes', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
              ],
            ),
          ),
          // Scheme list
          Expanded(
            child: schemes.isEmpty
                ? Center(child: Text('No schemes found', style: GoogleFonts.inter(color: AppTheme.textS(context))))
                : ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: schemes.length,
                    itemBuilder: (context, i) => _buildSchemeCard(schemes[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSchemeCard(Map<String, dynamic> s) {
    final name = s['name'] as String? ?? '';
    final fullForm = s['fullForm'] as String? ?? '';
    final description = s['description'] as String? ?? '';
    final sector = s['sector'] as String? ?? '';
    final year = s['year'] as String? ?? '';
    final icon = FirestoreContentService.getIcon(s['iconName'] as String? ?? '');
    final color = FirestoreContentService.parseColor(s['colorHex'] as String? ?? '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedGlassCard(
        onTap: () {
          HapticFeedback.lightImpact();
          _showSchemeDetail(s);
        },
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40, height: 40,
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
                      Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                      if (fullForm.isNotEmpty && fullForm != name)
                        Text(fullForm, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textT(context))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context), height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                _schemeBadge(sector, color),
                const SizedBox(width: 8),
                _schemeBadge('Launched: $year', AppTheme.textTertiary),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.textT(context)),
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
      child: Text(text, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  void _showSchemeDetail(Map<String, dynamic> s) {
    final name = s['name'] as String? ?? '';
    final fullForm = s['fullForm'] as String? ?? '';
    final sector = s['sector'] as String? ?? '';
    final year = s['year'] as String? ?? '';
    final ministry = s['ministry'] as String? ?? '';
    final detailedDescription = s['detailedDescription'] as String? ?? '';
    final keyFeatures = (s['keyFeatures'] as List<dynamic>?)?.cast<String>() ?? [];
    final upscRelevance = s['upscRelevance'] as String? ?? '';
    final icon = FirestoreContentService.getIcon(s['iconName'] as String? ?? '');
    final color = FirestoreContentService.parseColor(s['colorHex'] as String? ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => SingleChildScrollView(
          controller: scroll,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.6)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800)),
                        if (fullForm.isNotEmpty && fullForm != name)
                          Text(fullForm, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(ctx))),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _schemeBadge(sector, color),
                  _schemeBadge('Year: $year', AppTheme.textTertiary),
                  _schemeBadge(ministry, AppTheme.accentViolet),
                ],
              ),
              const SizedBox(height: 16),
              Text(detailedDescription, style: GoogleFonts.inter(fontSize: 14, height: 1.7)),
              const SizedBox(height: 16),
              Text('Key Features', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
              const SizedBox(height: 10),
              ...keyFeatures.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(margin: const EdgeInsets.only(top: 6), width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(f, style: GoogleFonts.inter(fontSize: 13, height: 1.5))),
                  ],
                ),
              )),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.school_rounded, size: 16, color: AppTheme.primaryColor),
                      const SizedBox(width: 6),
                      Text('UPSC Relevance', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                    ]),
                    const SizedBox(height: 8),
                    Text(upscRelevance, style: GoogleFonts.inter(fontSize: 13, height: 1.5)),
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
