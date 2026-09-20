import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/gemini_service.dart';
import '../../services/web_search_service.dart';
import 'package:upsc_daily_edge/design_system/frosted_scholar.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// AI Search Screen — Gemini-powered UPSC topic search engine.
/// Search any topic → Get simplified, exam-focused content with images,
/// key points, mnemonics, related PYQs, and answer frameworks.
/// ──────────────────────────────────────────────────────────────────────────────
class AiSearchScreen extends StatefulWidget {
  const AiSearchScreen({super.key});

  @override
  State<AiSearchScreen> createState() => _AiSearchScreenState();
}

class _AiSearchScreenState extends State<AiSearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocusNode = FocusNode();

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  bool _isSearching = false;
  Map<String, dynamic>? _searchResult;
  String? _selectedCategory;
  String? _selectedExamType;
  List<String> _recentSearches = [];
  bool _showApiKeySetup = false;
  bool _useAiEnhanced = false; // false = web search (free), true = AI enhanced
  String _searchStatusText = '';

  static const _categories = [
    'All',
    'Polity',
    'Economy',
    'History',
    'Geography',
    'Environment',
    'Science & Technology',
    'International Relations',
    'Ethics',
    'Governance',
    'Social Issues',
  ];

  static const _examTypes = ['Both', 'Prelims', 'Mains'];

  static const _trendingTopics = [
    'Article 370 Abrogation',
    'Union Budget 2025-26',
    'Gaganyaan Mission',
    'COP29 Climate Summit',
    'Digital India Act',
    'PM Gati Shakti',
    'Jal Jeevan Mission',
    'Green Hydrogen Mission',
    'RBI Monetary Policy',
    'One Nation One Election',
    'Biodiversity Act Amendment',
    'AFSPA & Northeast',
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _searchController.addListener(() => setState(() {}));
    _loadRecentSearches();
    _checkApiKey();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkApiKey() async {
    await GeminiService.initialize();
    if (GeminiService.keyCount < 5) {
      setState(() => _showApiKeySetup = true);
    }
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('recentSearches');
      if (saved != null && mounted) {
        setState(() => _recentSearches = saved);
      }
    } catch (_) {}
  }

  Future<void> _saveRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('recentSearches', _recentSearches);
    } catch (_) {}
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    final trimmedQuery = query.trim();
    setState(() {
      _isSearching = true;
      _searchResult = null;
      _searchStatusText = 'Searching the web...';
    });

    // Add to recent searches
    _recentSearches.remove(trimmedQuery);
    _recentSearches.insert(0, trimmedQuery);
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.sublist(0, 10);
    }
    _saveRecentSearches();

    final cat = _selectedCategory != 'All' ? _selectedCategory : null;
    final exam = _selectedExamType != 'Both' ? _selectedExamType : null;

    // Step 1: Always fetch web content first (free, no API key needed)
    final webResult = await WebSearchService.searchWeb(trimmedQuery, category: cat);

    // Step 2: If AI enhanced mode AND Gemini is configured, use Gemini to analyze web content
    if (_useAiEnhanced && GeminiService.isConfigured && webResult != null) {
      if (mounted) setState(() => _searchStatusText = 'AI is analyzing web content...');
      final webContext = WebSearchService.getWebContextForAI(webResult);
      final aiResult = await GeminiService.searchWithWebContext(
        trimmedQuery,
        webContext,
        category: cat,
        examType: exam,
      );
      // Merge web sources into AI result
      if (aiResult['error'] != true) {
        aiResult['web_sources'] = webResult['web_sources'];
        aiResult['imageUrl'] = webResult['imageUrl'];
        aiResult['source'] = 'ai+web';
        if (mounted) {
          setState(() {
            _isSearching = false;
            _searchResult = aiResult;
          });
          _scrollToResults();
          return;
        }
      }
      // If AI fails, fall through to web-only results
    } else if (_useAiEnhanced && GeminiService.isConfigured && webResult == null) {
      // No web content, try pure Gemini
      if (mounted) setState(() => _searchStatusText = 'Searching with AI...');
      final aiResult = await GeminiService.searchTopic(
        trimmedQuery,
        category: cat,
        examType: exam,
      );
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResult = aiResult;
        });
        _scrollToResults();
        return;
      }
    }

    // Step 3: Show web results directly (works without any API key)
    if (mounted) {
      setState(() {
        _isSearching = false;
        _searchResult = webResult ?? {
          'error': true,
          'message': 'No results found. Try a different search term or check your internet connection.',
        };
      });
      _scrollToResults();
    }
  }

  void _scrollToResults() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        300,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppTheme.scaffoldGradient(context)),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                // Header
                SliverToBoxAdapter(child: _buildHeader(dark)),

                // API Key Setup Banner (only show if AI mode selected and no keys)
                if (_showApiKeySetup && _useAiEnhanced)
                  SliverToBoxAdapter(child: _buildApiKeyBanner(dark)),

                // Search Bar
                SliverToBoxAdapter(child: _buildSearchBar(dark)),

                // Filters
                SliverToBoxAdapter(child: _buildFilters(dark)),

                // Search Mode Toggle
                SliverToBoxAdapter(child: _buildSearchModeToggle(dark)),

                // Content
                if (_isSearching)
                  SliverToBoxAdapter(child: _buildLoadingState(dark))
                else if (_searchResult != null)
                  ..._buildResults(dark)
                else ...[
                  // Trending Topics
                  SliverToBoxAdapter(child: _buildTrendingTopics(dark)),

                  // Recent Searches
                  if (_recentSearches.isNotEmpty)
                    SliverToBoxAdapter(child: _buildRecentSearches(dark)),

                  // Quick Categories
                  SliverToBoxAdapter(child: _buildQuickCategories(dark)),
                ],

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // HEADER
  // ═════════════════════════════════════════════════════════════════

  Widget _buildHeader(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.lg, FsSpace.xl, FsSpace.xs),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(FsSpace.xs),
              decoration: BoxDecoration(
                color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(FsRadii.control),
              ),
              child: Icon(Icons.arrow_back_rounded, color: FsColors.textPrimary(context), size: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Search Engine',
                  style: FsType.display(context).copyWith(fontSize: 24),
                ),
                const SizedBox(height: 2),
                Text(
                  _useAiEnhanced
                      ? (GeminiService.keyCount > 0
                          ? 'AI Enhanced • ${GeminiService.keyCount} key${GeminiService.keyCount > 1 ? 's' : ''} active'
                          : 'AI Enhanced • Add API key for full power')
                      : 'Web Search • No API key needed',
                  style: FsType.caption(context),
                ),
              ],
            ),
          ),
          // Settings gear for API key
          GestureDetector(
            onTap: () => _showApiKeyDialog(),
            child: Container(
              padding: const EdgeInsets.all(FsSpace.xs),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(FsRadii.control),
              ),
              child: const Icon(Icons.settings_rounded, color: AppTheme.primaryColor, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // API KEY SETUP BANNER
  // ═════════════════════════════════════════════════════════════════

  Widget _buildApiKeyBanner(bool dark) {
    final keyCount = GeminiService.keyCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: const EdgeInsets.all(FsSpace.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF7C4DFF).withValues(alpha: 0.12),
              const Color(0xFF448AFF).withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(FsRadii.lg),
          border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(FsSpace.xs),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(FsRadii.control),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C4DFF), size: 22),
                ),
                const SizedBox(width: FsSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        keyCount == 0 ? 'Enable AI Search' : 'Add More API Keys',
                        style: FsType.subtitle(context).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        keyCount == 0
                            ? 'Free • Takes 30 seconds • No credit card'
                            : '$keyCount/5 keys added • Add more for uninterrupted search',
                        style: FsType.label(context).copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (keyCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: FsSpace.xs, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(FsRadii.pill),
                    ),
                    child: Text(
                      '$keyCount/5',
                      style: FsType.button(const Color(0xFF4CAF50)).copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FsSpace.lg),
            // Step-by-step guide
            if (keyCount == 0) ...[
              _buildSetupStep(1, 'Tap the button below to open Google AI Studio', Icons.open_in_new_rounded),
              _buildSetupStep(2, 'Sign in with your Google account', Icons.account_circle_rounded),
              _buildSetupStep(3, 'Click "Create API Key" on the page', Icons.key_rounded),
              _buildSetupStep(4, 'Copy the key and paste it here', Icons.content_paste_rounded),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(FsSpace.md),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(FsRadii.control),
                  border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF4CAF50), size: 18),
                    const SizedBox(width: FsSpace.xs),
                    Expanded(
                      child: Text(
                        'Add up to 5 keys from different Google accounts. '
                        'When one key hits the rate limit, the app automatically switches to the next one — no interruptions!',
                        style: FsType.caption(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: FsSpace.lg),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _openAIStudioAndSetup(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: FsSpace.xs),
                          Text(
                            keyCount == 0 ? 'Get Free API Key' : 'Add Another Key',
                            style: FsType.button(Colors.white).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: FsSpace.xs),
                GestureDetector(
                  onTap: () => _showApiKeyDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      keyCount == 0 ? 'I have a key' : 'Manage keys',
                      style: FsType.button(FsColors.textPrimary(context)).copyWith(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupStep(int step, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FsSpace.xs),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(FsSpace.xs),
            ),
            child: Center(
              child: Text(
                '$step',
                style: FsType.button(const Color(0xFF7C4DFF)).copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: FsSpace.xs),
          Icon(icon, size: 16, color: FsColors.textSecondary(context)),
          const SizedBox(width: FsSpace.xs),
          Expanded(
            child: Text(
              text,
              style: FsType.caption(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAIStudioAndSetup() async {
    // Open Google AI Studio directly to the API key page
    final uri = Uri.parse('https://aistudio.google.com/apikey');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // If browser fails, copy the URL to clipboard
      await Clipboard.setData(const ClipboardData(text: 'https://aistudio.google.com/apikey'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Link copied! Open browser and paste: aistudio.google.com/apikey',
              style: FsType.caption(context),
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    // Show paste dialog after a short delay so user can come back with the key
    if (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _showApiKeyDialog();
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // SEARCH BAR
  // ═════════════════════════════════════════════════════════════════

  Widget _buildSearchBar(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.md, FsSpace.xl, FsSpace.xs),
      child: DecoratedBox(
        decoration: AppTheme.glassCard(context, radius: 18),
        child: Row(
          children: [
            const SizedBox(width: FsSpace.lg),
            const Icon(Icons.search_rounded, color: AppTheme.primaryColor, size: 24),
            const SizedBox(width: FsSpace.md),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: FsType.body(context),
                decoration: InputDecoration(
                  hintText: 'Search any UPSC topic...',
                  hintStyle: FsType.body(context).copyWith(color: FsColors.textTertiary(context)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: FsSpace.lg),
                  fillColor: Colors.transparent,
                  filled: true,
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: _performSearch,
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchResult = null);
                },
                child: Padding(
                  padding: const EdgeInsets.all(FsSpace.md),
                  child: Icon(Icons.close_rounded, color: FsColors.textTertiary(context), size: 20),
                ),
              ),
            // Search button
            GestureDetector(
              onTap: () => _performSearch(_searchController.text),
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.all(FsSpace.md),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(FsRadii.control),
                  boxShadow: AppTheme.glowShadow,
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // FILTERS
  // ═════════════════════════════════════════════════════════════════

  Widget _buildFilters(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Row(
        children: [
          // Category dropdown
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: FsSpace.md, vertical: FsSpace.xxs),
              decoration: BoxDecoration(
                color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(FsRadii.control),
                border: Border.all(
                  color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory ?? 'All',
                  isExpanded: true,
                  icon: Icon(Icons.expand_more_rounded, color: FsColors.textSecondary(context), size: 20),
                  style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context)),
                  dropdownColor: AppTheme.card(context),
                  items: _categories.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context))),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val),
                ),
              ),
            ),
          ),
          const SizedBox(width: FsSpace.xs),
          // Exam type chips
          ...List.generate(_examTypes.length, (i) {
            final selected = (_selectedExamType ?? 'Both') == _examTypes[i];
            return Padding(
              padding: const EdgeInsets.only(left: FsSpace.xxs),
              child: GestureDetector(
                onTap: () => setState(() => _selectedExamType = _examTypes[i]),
                child: AnimatedContainer(
                  duration: FsMotion.base,
                  padding: const EdgeInsets.symmetric(horizontal: FsSpace.md, vertical: FsSpace.xs),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primaryColor.withValues(alpha: 0.12)
                        : (dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(FsRadii.sm),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primaryColor.withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    _examTypes[i],
                    style: FsType.caption(context).copyWith(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? AppTheme.primaryColor : FsColors.textSecondary(context),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // LOADING STATE
  // ═════════════════════════════════════════════════════════════════

  Widget _buildLoadingState(bool dark) {
    return Padding(
      padding: const EdgeInsets.all(FsSpace.xl),
      child: Column(
        children: [
          const SizedBox(height: FsSpace.lg),
          Lottie.asset(
            'assets/animations/searching.json',
            width: 120,
            height: 120,
          ),
          const SizedBox(height: FsSpace.lg),
          Text(
            _searchStatusText.isNotEmpty ? _searchStatusText : 'Searching the web...',
            style: FsType.subtitle(context).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: FsSpace.xs),
          Text(
            _useAiEnhanced ? 'Fetching & analyzing with AI' : 'Fetching content from the web',
            style: FsType.caption(context),
          ),
          const SizedBox(height: FsSpace.xl),
          // Shimmer placeholders
          ...List.generate(3, (i) => Padding(
            padding: const EdgeInsets.only(bottom: FsSpace.md),
            child: Shimmer.fromColors(
              baseColor: dark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
              highlightColor: dark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.shade100,
              child: Container(
                height: 80 + (i * 20.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(FsRadii.card),
                ),
              ),
            ),
          )),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // SEARCH RESULTS
  // ═════════════════════════════════════════════════════════════════

  List<Widget> _buildResults(bool dark) {
    final result = _searchResult!;

    if (result['error'] == true) {
      return [
        SliverToBoxAdapter(child: _buildErrorCard(result['message'] ?? 'Unknown error', dark)),
      ];
    }

    return [
      // Title & Summary
      SliverToBoxAdapter(child: _buildResultHeader(result, dark)),

      // Image (from web or search terms)
      SliverToBoxAdapter(child: _buildResultImage(result, dark)),

      // Exam Relevance Card
      if (result['exam_relevance'] != null)
        SliverToBoxAdapter(child: _buildExamRelevanceCard(result, dark)),

      // Summary
      if (result['summary'] != null)
        SliverToBoxAdapter(child: _buildSummaryCard(result, dark)),

      // Web Sources (clickable links)
      if (result['web_sources'] != null && (result['web_sources'] as List).isNotEmpty)
        SliverToBoxAdapter(child: _buildWebSourcesCard(result, dark)),

      // Key Points
      if (result['key_points'] != null && (result['key_points'] as List).isNotEmpty)
        SliverToBoxAdapter(child: _buildKeyPointsCard(result, dark)),

      // Detailed Explanation (only show for AI-enhanced results, not raw web dumps)
      if (result['detailed_explanation'] != null &&
          (result['detailed_explanation'] as String).isNotEmpty &&
          (result['source'] == 'ai+web' || result['enhanced_by_ai'] == true))
        SliverToBoxAdapter(child: _buildDetailedExplanation(result, dark)),

      // Mnemonic (AI only)
      if (result['mnemonic'] != null && (result['mnemonic'] as String).isNotEmpty)
        SliverToBoxAdapter(child: _buildMnemonicCard(result, dark)),

      // Flowchart (AI only)
      if (result['flowchart'] != null && (result['flowchart'] as List).isNotEmpty)
        SliverToBoxAdapter(child: _buildFlowchartCard(result, dark)),

      // Important Terms (AI only)
      if (result['important_terms'] != null && (result['important_terms'] as Map).isNotEmpty)
        SliverToBoxAdapter(child: _buildTermsCard(result, dark)),

      // Answer Framework (AI only)
      if (result['answer_framework'] != null && (result['answer_framework'] as String).isNotEmpty)
        SliverToBoxAdapter(child: _buildAnswerFrameworkCard(result, dark)),

      // PYQ Connections (AI only)
      if (result['previous_year_questions'] != null && (result['previous_year_questions'] as List).isNotEmpty)
        SliverToBoxAdapter(child: _buildPYQCard(result, dark)),

      // Quick Revision Notes (AI only)
      if (result['quick_revision_notes'] != null && (result['quick_revision_notes'] as List).isNotEmpty)
        SliverToBoxAdapter(child: _buildQuickRevisionCard(result, dark)),

      // Related Topics
      if (result['related_topics'] != null && (result['related_topics'] as List).isNotEmpty)
        SliverToBoxAdapter(child: _buildRelatedTopics(result, dark)),

      // AI Enhancement prompt (if web-only)
      if (result['source'] == 'web' && GeminiService.isConfigured)
        SliverToBoxAdapter(child: _buildEnhanceWithAiButton(result, dark)),

      // Generate Quiz button (if AI is available)
      if (GeminiService.isConfigured)
        SliverToBoxAdapter(child: _buildGenerateQuizButton(result, dark)),
    ];
  }

  Widget _buildResultHeader(Map<String, dynamic> result, bool dark) {
    final isAiEnhanced = result['source'] == 'ai+web' || result['enhanced_by_ai'] == true;
    final sourceLabel = isAiEnhanced ? 'AI + Web Research' : 'Web Research';
    final sourceIcon = isAiEnhanced ? Icons.auto_awesome_rounded : Icons.public_rounded;
    final sourceColor = isAiEnhanced ? AppTheme.primaryColor : const Color(0xFF26A69A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.lg, FsSpace.xl, FsSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: FsSpace.md, vertical: FsSpace.xxs),
                decoration: BoxDecoration(
                  color: sourceColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(FsSpace.xs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(sourceIcon, color: sourceColor, size: 14),
                    const SizedBox(width: FsSpace.xxs),
                    Text(
                      sourceLabel,
                      style: FsType.button(AppTheme.primaryColor).copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FsSpace.md),
          Text(
            result['title'] ?? 'Search Result',
            style: FsType.display(context).copyWith(height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildResultImage(Map<String, dynamic> result, bool dark) {
    // Prefer real image from web sources (Wikipedia, DuckDuckGo)
    String? imageUrl = result['imageUrl'] as String?;

    // Fallback to picsum if no real image
    if (imageUrl == null || imageUrl.isEmpty) {
      final terms = result['image_search_terms'] as List<dynamic>?;
      if (terms != null && terms.isNotEmpty) {
        final searchTerm = terms.first.toString().replaceAll(' ', '_');
        imageUrl = 'https://picsum.photos/seed/$searchTerm/800/400';
      } else {
        return const SizedBox.shrink();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FsRadii.lg),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (_, __) => Shimmer.fromColors(
            baseColor: dark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
            highlightColor: dark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.shade100,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(FsRadii.lg),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            height: 180,
            decoration: BoxDecoration(
              gradient: AppTheme.heroGradient,
              borderRadius: BorderRadius.circular(FsRadii.lg),
            ),
            child: Center(
              child: Icon(Icons.image_rounded, color: Colors.white.withValues(alpha: 0.5), size: 48),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExamRelevanceCard(Map<String, dynamic> result, bool dark) {
    final exam = result['exam_relevance'];
    if (exam == null) return const SizedBox.shrink();

    final papers = exam is Map ? (exam['papers'] as List<dynamic>? ?? []) : [];
    final frequency = exam is Map ? (exam['frequency'] ?? 'Medium') : 'Medium';
    final syllabus = exam is Map ? (exam['syllabus_topic'] ?? '') : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: AppTheme.glassCard(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.school_rounded, color: AppTheme.accentViolet, size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Exam Relevance',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: FsSpace.md, vertical: FsSpace.xxs),
                  decoration: BoxDecoration(
                    color: _frequencyColor(frequency.toString()).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(FsSpace.xs),
                  ),
                  child: Text(
                    '$frequency Frequency',
                    style: FsType.button(_frequencyColor(frequency.toString())).copyWith(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            Wrap(
              spacing: FsSpace.xs,
              runSpacing: FsSpace.xs,
              children: papers.map<Widget>((p) => Container(
                padding: const EdgeInsets.symmetric(horizontal: FsSpace.md, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.accentViolet.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(FsRadii.sm),
                  border: Border.all(color: AppTheme.accentViolet.withValues(alpha: 0.2)),
                ),
                child: Text(
                  p.toString(),
                  style: FsType.button(AppTheme.accentViolet).copyWith(fontSize: 12),
                ),
              )).toList(),
            ),
            if (syllabus.toString().isNotEmpty) ...[
              const SizedBox(height: FsSpace.md),
              Row(
                children: [
                  Icon(Icons.bookmark_rounded, color: FsColors.textTertiary(context), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Syllabus: $syllabus',
                      style: FsType.caption(context).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> result, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryColor.withValues(alpha: 0.06),
              AppTheme.primaryColor.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(FsRadii.lg),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.summarize_rounded, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Quick Summary',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            Text(
              result['summary'] ?? '',
              style: FsType.body(context).copyWith(fontSize: 14, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyPointsCard(Map<String, dynamic> result, bool dark) {
    final points = (result['key_points'] as List<dynamic>).map((e) => e.toString()).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: AppTheme.glassCard(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rounded, color: FsColors.success, size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Key Points',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${points.length} points',
                  style: FsType.label(context),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            ...points.asMap().entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: FsSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: FsSpace.md),
                    decoration: BoxDecoration(
                      color: FsColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(FsSpace.xs),
                    ),
                    child: Center(
                      child: Text(
                        '${entry.key + 1}',
                        style: FsType.button(FsColors.success).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context), height: 1.5),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedExplanation(Map<String, dynamic> result, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: AppTheme.glassCard(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.article_rounded, color: AppTheme.accentViolet, size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Detailed Explanation',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            Text(
              result['detailed_explanation'] ?? '',
              style: FsType.body(context).copyWith(fontSize: 14, height: 1.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMnemonicCard(Map<String, dynamic> result, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.warmYellow.withValues(alpha: 0.12),
              AppTheme.warmGold.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(FsRadii.lg),
          border: Border.all(color: AppTheme.warmYellow.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(FsSpace.xs),
              decoration: BoxDecoration(
                color: AppTheme.warmYellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(FsRadii.control),
              ),
              child: const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.warmYellow, size: 22),
            ),
            const SizedBox(width: FsSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Memory Aid (Mnemonic)',
                    style: FsType.subtitle(context).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    result['mnemonic'] ?? '',
                    style: FsType.caption(context).copyWith(
                      color: FsColors.textPrimary(context),
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowchartCard(Map<String, dynamic> result, bool dark) {
    final steps = (result['flowchart'] as List<dynamic>).map((e) => e.toString()).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: AppTheme.glassCard(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_tree_rounded, color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Flowchart / Process',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.lg),
            ...steps.asMap().entries.map((entry) {
              final isLast = entry.key == steps.length - 1;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(FsSpace.xs),
                        ),
                        child: Center(
                          child: Text(
                            '${entry.key + 1}',
                            style: FsType.button(Colors.white).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 24,
                          color: AppTheme.primaryColor.withValues(alpha: 0.2),
                        ),
                    ],
                  ),
                  const SizedBox(width: FsSpace.md),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : FsSpace.lg),
                      child: Text(
                        entry.value,
                        style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context), height: 1.5),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsCard(Map<String, dynamic> result, bool dark) {
    final terms = result['important_terms'] as Map<String, dynamic>;

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: AppTheme.glassCard(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_rounded, color: AppTheme.accentRose, size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Important Terms',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            ...terms.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: FsSpace.md),
              child: Container(
                padding: const EdgeInsets.all(FsSpace.md),
                decoration: BoxDecoration(
                  color: AppTheme.accentRose.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(FsRadii.control),
                  border: Border.all(color: AppTheme.accentRose.withValues(alpha: 0.1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: FsSpace.xs, vertical: FsSpace.xxs),
                      decoration: BoxDecoration(
                        color: AppTheme.accentRose.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.key,
                        style: FsType.button(AppTheme.accentRose).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: FsSpace.md),
                    Expanded(
                      child: Text(
                        entry.value.toString(),
                        style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context), height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerFrameworkCard(Map<String, dynamic> result, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.accentViolet.withValues(alpha: 0.08),
              AppTheme.accentLavender.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(FsRadii.lg),
          border: Border.all(color: AppTheme.accentViolet.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note_rounded, color: AppTheme.accentViolet, size: 20),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Mains Answer Framework',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            Text(
              result['answer_framework'] ?? '',
              style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context), height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPYQCard(Map<String, dynamic> result, bool dark) {
    final pyqs = (result['previous_year_questions'] as List<dynamic>).map((e) => e.toString()).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: AppTheme.glassCard(context, radius: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history_edu_rounded, color: FsColors.warning, size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Previous Year Connections',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            ...pyqs.map((q) => Padding(
              padding: const EdgeInsets.only(bottom: FsSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.arrow_right_rounded, color: FsColors.warning, size: 18),
                  const SizedBox(width: FsSpace.xxs),
                  Expanded(
                    child: Text(
                      q,
                      style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context), height: 1.5),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickRevisionCard(Map<String, dynamic> result, bool dark) {
    final notes = (result['quick_revision_notes'] as List<dynamic>).map((e) => e.toString()).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.mintGreen.withValues(alpha: 0.08),
              AppTheme.primaryColor.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(FsRadii.lg),
          border: Border.all(color: AppTheme.mintGreen.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on_rounded, color: AppTheme.mintGreen, size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Quick Revision Notes',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            ...notes.map((n) => Padding(
              padding: const EdgeInsets.only(bottom: FsSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6, right: FsSpace.md),
                    decoration: BoxDecoration(
                      color: AppTheme.mintGreen,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      n,
                      style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context), height: 1.5),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedTopics(Map<String, dynamic> result, bool dark) {
    final topics = (result['related_topics'] as List<dynamic>).map((e) => e.toString()).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Related Topics',
            style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: FsSpace.md),
          Wrap(
            spacing: FsSpace.xs,
            runSpacing: FsSpace.xs,
            children: topics.map((t) => GestureDetector(
              onTap: () {
                _searchController.text = t;
                _performSearch(t);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: FsSpace.xs),
                decoration: BoxDecoration(
                  color: FsColors.accent(context).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(FsRadii.control),
                  border: Border.all(color: FsColors.accent(context).withValues(alpha: 0.2)),
                ),
                child: Text(
                  t,
                  style: FsType.button(FsColors.accent(context)).copyWith(fontSize: 12),
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateQuizButton(Map<String, dynamic> result, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.lg, FsSpace.xl, FsSpace.xs),
      child: GestureDetector(
        onTap: () => _generateQuizFromResult(result),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: FsSpace.lg),
          decoration: AppTheme.gradientButton(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.quiz_rounded, color: Colors.white, size: 20),
              const SizedBox(width: FsSpace.md),
              Text(
                'Generate Quiz on This Topic',
                style: FsType.button(Colors.white).copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message, bool dark) {
    final isRateLimit = message.toLowerCase().contains('busy') ||
        message.toLowerCase().contains('rate') ||
        message.toLowerCase().contains('limit') ||
        message.toLowerCase().contains('exhausted');

    return Padding(
      padding: const EdgeInsets.all(FsSpace.xl),
      child: Container(
        padding: const EdgeInsets.all(FsSpace.lg),
        decoration: BoxDecoration(
          color: (isRateLimit ? Colors.amber : FsColors.danger).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(FsRadii.lg),
          border: Border.all(color: (isRateLimit ? Colors.amber : FsColors.danger).withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(
              isRateLimit ? Icons.hourglass_top_rounded : Icons.error_outline_rounded,
              color: isRateLimit ? Colors.amber[700] : FsColors.danger,
              size: 40,
            ),
            const SizedBox(height: FsSpace.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: FsType.body(context).copyWith(fontSize: 14),
            ),
            const SizedBox(height: FsSpace.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    // Clear rate limits and retry the search
                    GeminiService.clearRateLimits();
                    if (_searchController.text.trim().isNotEmpty) {
                      _performSearch(_searchController.text);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: FsSpace.xxl, vertical: FsSpace.md),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF26A69A), Color(0xFF00897B)],
                      ),
                      borderRadius: BorderRadius.circular(FsRadii.control),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF26A69A).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: FsSpace.xs),
                        Text(
                          'Retry Now',
                          style: FsType.button(Colors.white).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isRateLimit && GeminiService.keyCount < 5) ...[
                  const SizedBox(width: FsSpace.xs),
                  GestureDetector(
                    onTap: () => _showApiKeyDialog(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: FsSpace.lg, vertical: FsSpace.md),
                      decoration: BoxDecoration(
                        color: dark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(FsRadii.control),
                        border: Border.all(
                          color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        '+ Add Key',
                        style: FsType.button(FsColors.textPrimary(context)).copyWith(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // TRENDING TOPICS
  // ═════════════════════════════════════════════════════════════════

  Widget _buildTrendingTopics(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.lg, FsSpace.xl, FsSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: FsSpace.xs),
              Text(
                'Trending UPSC Topics',
                style: FsType.title(context).copyWith(fontSize: 17),
              ),
            ],
          ),
          const SizedBox(height: FsSpace.md),
          Wrap(
            spacing: FsSpace.xs,
            runSpacing: FsSpace.md,
            children: _trendingTopics.map((topic) {
              final cleanTopic = topic.replaceAll(RegExp(r'[^\w\s&]'), '').trim();
              return GestureDetector(
                onTap: () {
                  _searchController.text = cleanTopic;
                  _performSearch(cleanTopic);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: FsSpace.md),
                  decoration: AppTheme.glassCard(context, radius: FsRadii.control),
                  child: Text(
                    topic,
                    style: FsType.caption(context).copyWith(
                      color: FsColors.textPrimary(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // RECENT SEARCHES
  // ═════════════════════════════════════════════════════════════════

  Widget _buildRecentSearches(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.lg, FsSpace.xl, FsSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, color: FsColors.textSecondary(context), size: 18),
              const SizedBox(width: FsSpace.xs),
              Text(
                'Recent Searches',
                style: FsType.subtitle(context),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() => _recentSearches.clear());
                  _saveRecentSearches();
                },
                child: Text(
                  'Clear',
                  style: FsType.caption(context).copyWith(color: FsColors.textTertiary(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: FsSpace.md),
          ...(_recentSearches.take(5).map((s) => GestureDetector(
            onTap: () {
              _searchController.text = s;
              _performSearch(s);
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: FsSpace.xs),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: FsColors.textTertiary(context), size: 16),
                  const SizedBox(width: FsSpace.md),
                  Text(
                    s,
                    style: FsType.body(context).copyWith(fontSize: 14, color: FsColors.textSecondary(context)),
                  ),
                ],
              ),
            ),
          ))),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // QUICK CATEGORIES
  // ═════════════════════════════════════════════════════════════════

  Widget _buildQuickCategories(bool dark) {
    final quickSearches = [
      {'icon': Icons.account_balance_rounded, 'label': 'Polity & Constitution', 'color': AppTheme.accentViolet},
      {'icon': Icons.trending_up_rounded, 'label': 'Economy & Budget', 'color': AppTheme.successGreen},
      {'icon': Icons.public_rounded, 'label': 'International Relations', 'color': AppTheme.primaryColor},
      {'icon': Icons.eco_rounded, 'label': 'Environment & Ecology', 'color': const Color(0xFF4CAF50)},
      {'icon': Icons.science_rounded, 'label': 'Science & Technology', 'color': AppTheme.accentRose},
      {'icon': Icons.history_edu_rounded, 'label': 'Modern History', 'color': AppTheme.warningOrange},
      {'icon': Icons.map_rounded, 'label': 'Indian Geography', 'color': const Color(0xFF2196F3)},
      {'icon': Icons.gavel_rounded, 'label': 'Ethics & Integrity', 'color': const Color(0xFF9C27B0)},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.lg, FsSpace.xl, FsSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explore by Subject',
            style: FsType.title(context).copyWith(fontSize: 17),
          ),
          const SizedBox(height: FsSpace.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: FsSpace.md,
              mainAxisSpacing: FsSpace.md,
              childAspectRatio: 2.5,
            ),
            itemCount: quickSearches.length,
            itemBuilder: (context, index) {
              final item = quickSearches[index];
              return GestureDetector(
                onTap: () {
                  final label = item['label'] as String;
                  _searchController.text = label;
                  _performSearch(label);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: FsSpace.md, vertical: FsSpace.md),
                  decoration: AppTheme.glassCard(context, radius: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(FsSpace.xs),
                        decoration: BoxDecoration(
                          color: (item['color'] as Color).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(FsRadii.sm),
                        ),
                        child: Icon(item['icon'] as IconData, color: item['color'] as Color, size: 18),
                      ),
                      const SizedBox(width: FsSpace.xs),
                      Expanded(
                        child: Text(
                          item['label'] as String,
                          style: FsType.caption(context).copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: FsColors.textPrimary(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // SEARCH MODE TOGGLE
  // ═════════════════════════════════════════════════════════════════

  Widget _buildSearchModeToggle(bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xxs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: const EdgeInsets.all(FsSpace.xxs),
        decoration: BoxDecoration(
          color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            // Web Search tab
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _useAiEnhanced = false),
                child: AnimatedContainer(
                  duration: FsMotion.base,
                  padding: const EdgeInsets.symmetric(vertical: FsSpace.md),
                  decoration: BoxDecoration(
                    color: !_useAiEnhanced
                        ? const Color(0xFF26A69A).withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(FsRadii.sm),
                    border: Border.all(
                      color: !_useAiEnhanced
                          ? const Color(0xFF26A69A).withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.public_rounded,
                        size: 16,
                        color: !_useAiEnhanced ? const Color(0xFF26A69A) : FsColors.textTertiary(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Web Search',
                        style: FsType.caption(context).copyWith(
                          fontWeight: !_useAiEnhanced ? FontWeight.w700 : FontWeight.w500,
                          color: !_useAiEnhanced ? const Color(0xFF26A69A) : FsColors.textSecondary(context),
                        ),
                      ),
                      if (!_useAiEnhanced) ...[
                        const SizedBox(width: FsSpace.xxs),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF26A69A).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(FsSpace.xxs),
                          ),
                          child: Text(
                            'FREE',
                            style: FsType.label(context).copyWith(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF26A69A),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: FsSpace.xxs),
            // AI Enhanced tab
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _useAiEnhanced = true),
                child: AnimatedContainer(
                  duration: FsMotion.base,
                  padding: const EdgeInsets.symmetric(vertical: FsSpace.md),
                  decoration: BoxDecoration(
                    color: _useAiEnhanced
                        ? AppTheme.primaryColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(FsRadii.sm),
                    border: Border.all(
                      color: _useAiEnhanced
                          ? AppTheme.primaryColor.withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: _useAiEnhanced ? AppTheme.primaryColor : FsColors.textTertiary(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AI Enhanced',
                        style: FsType.caption(context).copyWith(
                          fontWeight: _useAiEnhanced ? FontWeight.w700 : FontWeight.w500,
                          color: _useAiEnhanced ? AppTheme.primaryColor : FsColors.textSecondary(context),
                        ),
                      ),
                      if (!GeminiService.isConfigured && _useAiEnhanced) ...[
                        const SizedBox(width: FsSpace.xxs),
                        Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber[700]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // WEB SOURCES CARD
  // ═════════════════════════════════════════════════════════════════

  Widget _buildWebSourcesCard(Map<String, dynamic> result, bool dark) {
    final sources = result['web_sources'] as List<dynamic>;
    if (sources.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.xs, FsSpace.xl, FsSpace.xs),
      child: Container(
        padding: FsSpacing.cardPadding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF26A69A).withValues(alpha: 0.06),
              const Color(0xFF26A69A).withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(FsRadii.lg),
          border: Border.all(color: const Color(0xFF26A69A).withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded, color: Color(0xFF26A69A), size: 18),
                const SizedBox(width: FsSpace.xs),
                Text(
                  'Sources (${sources.length})',
                  style: FsType.subtitle(context).copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  'Tap to read full article',
                  style: FsType.label(context),
                ),
              ],
            ),
            const SizedBox(height: FsSpace.md),
            ...sources.take(5).map<Widget>((source) {
              final s = source as Map<String, dynamic>;
              final title = s['title'] as String? ?? 'Source';
              final url = s['url'] as String? ?? '';
              final desc = s['description'] as String? ?? '';
              final sourceName = s['source'] as String? ?? '';

              return GestureDetector(
                onTap: () => _openUrl(url),
                child: Container(
                  margin: const EdgeInsets.only(bottom: FsSpace.xs),
                  padding: const EdgeInsets.all(FsSpace.md),
                  decoration: BoxDecoration(
                    color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(FsRadii.control),
                    border: Border.all(
                      color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF26A69A).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(FsSpace.xs),
                        ),
                        child: Icon(
                          sourceName == 'Wikipedia' ? Icons.menu_book_rounded : Icons.language_rounded,
                          size: 14,
                          color: const Color(0xFF26A69A),
                        ),
                      ),
                      const SizedBox(width: FsSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: FsType.caption(context).copyWith(
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF26A69A),
                                decoration: TextDecoration.underline,
                                decorationColor: const Color(0xFF26A69A).withValues(alpha: 0.4),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                desc,
                                style: FsType.label(context).copyWith(
                                  color: FsColors.textSecondary(context),
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: FsSpace.xs),
                      Icon(Icons.open_in_new_rounded, size: 14, color: FsColors.textTertiary(context)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // ENHANCE WITH AI BUTTON
  // ═════════════════════════════════════════════════════════════════

  Widget _buildEnhanceWithAiButton(Map<String, dynamic> result, bool dark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(FsSpace.xl, FsSpace.md, FsSpace.xl, FsSpace.xxs),
      child: GestureDetector(
        onTap: () {
          setState(() => _useAiEnhanced = true);
          _performSearch(_searchController.text);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: FsSpace.xl),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
              const SizedBox(width: FsSpace.xs),
              Text(
                'Enhance with AI Analysis',
                style: FsType.button(Colors.white).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Gemini',
                  style: FsType.label(context).copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link copied! Open in browser: $url', style: FsType.label(context)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════════════════════════

  Color _frequencyColor(String frequency) {
    switch (frequency.toLowerCase()) {
      case 'high': return FsColors.danger;
      case 'medium': return FsColors.warning;
      case 'low': return FsColors.success;
      default: return FsColors.warning;
    }
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final keys = GeminiService.apiKeys;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: Row(
                children: [
                  const Icon(Icons.key_rounded, color: Color(0xFF7C4DFF), size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'API Keys (${keys.length}/5)',
                    style: FsType.title(context).copyWith(fontSize: 17),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_fix_high_rounded, color: Color(0xFF4CAF50), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Auto-rotation: When one key is rate-limited, '
                              'the app switches to the next automatically!',
                              style: FsType.label(context).copyWith(color: const Color(0xFF2E7D32), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Show existing keys
                    if (keys.isNotEmpty) ...[
                      Text(
                        'Your API Keys',
                        style: FsType.caption(context).copyWith(fontWeight: FontWeight.w600, color: FsColors.textPrimary(context)),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(keys.length, (i) {
                        final key = keys[i];
                        final masked = '${key.substring(0, 6)}...${key.substring(key.length - 4)}';
                        final status = GeminiService.keyStatus;
                        final isActive = status['activeIndex'] == i;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF7C4DFF).withValues(alpha: 0.08)
                                : Colors.grey.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFF7C4DFF).withValues(alpha: 0.3)
                                  : Colors.grey.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isActive ? Icons.check_circle_rounded : Icons.vpn_key_rounded,
                                size: 16,
                                color: isActive ? const Color(0xFF4CAF50) : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Key ${i + 1}: $masked',
                                // Platform monospace instead of a third Google
                                // font family: this single masked-key label was
                                // pulling down an entire typeface at runtime.
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontFamilyFallback: const ['Roboto Mono', 'Courier New'],
                                  fontSize: 12,
                                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                  color: FsColors.textPrimary(context),
                                ),
                              ),
                              const Spacer(),
                              if (isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Active', style: FsType.label(context).copyWith(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF4CAF50))),
                                ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () async {
                                  await GeminiService.removeApiKey(i);
                                  setDialogState(() {});
                                  if (GeminiService.keyCount == 0) {
                                    setState(() => _showApiKeySetup = true);
                                  }
                                },
                                child: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],

                    // "Don't have a key?" section
                    if (keys.length < 5) ...[
                      Text(
                        keys.isEmpty ? 'Don\'t have a key yet?' : 'Add another key (use a different Google account)',
                        style: FsType.caption(context).copyWith(fontWeight: FontWeight.w600, color: FsColors.textPrimary(context)),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () async {
                          final uri = Uri.parse('https://aistudio.google.com/apikey');
                          try {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          } catch (_) {
                            await Clipboard.setData(const ClipboardData(text: 'https://aistudio.google.com/apikey'));
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Link copied to clipboard!')),
                              );
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.open_in_new_rounded, size: 15, color: Color(0xFF7C4DFF)),
                              const SizedBox(width: 6),
                              Text(
                                'Open Google AI Studio →',
                                style: FsType.caption(context).copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF7C4DFF)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: 'Paste new API key here...',
                          hintStyle: FsType.body(context).copyWith(fontSize: 14, color: Colors.grey),
                          prefixIcon: const Icon(Icons.vpn_key_rounded, size: 19),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xFF7C4DFF), width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste_rounded, size: 19),
                            tooltip: 'Paste from clipboard',
                            onPressed: () async {
                              final data = await Clipboard.getData('text/plain');
                              if (data?.text != null && data!.text!.isNotEmpty) {
                                controller.text = data.text!;
                              }
                            },
                          ),
                        ),
                        style: FsType.body(context).copyWith(fontSize: 14),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Maximum 5 keys reached! You have excellent search capacity.',
                                style: FsType.label(context).copyWith(fontSize: 12, color: Colors.amber[800], height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Close', style: FsType.button(Colors.grey)),
                ),
                if (keys.length < 5)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C4DFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: () async {
                      final key = controller.text.trim();
                      if (key.isNotEmpty) {
                        if (GeminiService.apiKeys.contains(key)) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('This key is already added!')),
                          );
                          return;
                        }
                        await GeminiService.addApiKey(key);
                        controller.clear();
                        setDialogState(() {});
                        if (mounted) {
                          setState(() => _showApiKeySetup = GeminiService.keyCount == 0);
                        }
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Key ${GeminiService.keyCount} added! (${GeminiService.keyCount}/5)',
                                    style: FsType.button(Colors.white).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              backgroundColor: const Color(0xFF4CAF50),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                      } else {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Please paste your API key')),
                        );
                      }
                    },
                    child: Text(
                      keys.isEmpty ? 'Activate AI Search' : 'Add Key',
                      style: FsType.button(Colors.white).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _generateQuizFromResult(Map<String, dynamic> result) async {
    final topic = result['title'] ?? _searchController.text;
    if (!GeminiService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please configure your Gemini API key first')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset('assets/animations/loading.json', width: 100, height: 100),
            const SizedBox(height: 16),
            Text(
              'Generating quiz questions...',
              style: FsType.body(context).copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );

    final questions = await GeminiService.generateQuizQuestions(topic, count: 5);

    if (mounted) {
      Navigator.pop(context); // Dismiss loading dialog

      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate quiz. Try again.')),
        );
        return;
      }

      // Show quiz in a bottom sheet
      _showQuizBottomSheet(questions, topic);
    }
  }

  void _showQuizBottomSheet(List<Map<String, dynamic>> questions, String topic) {
    int currentQ = 0;
    int score = 0;
    int? selectedAnswer;
    bool answered = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (currentQ >= questions.length) {
            // Quiz complete
            return Container(
              height: MediaQuery.of(context).size.height * 0.5,
              decoration: BoxDecoration(
                color: AppTheme.card(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppTheme.successGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Quiz Complete!',
                    style: FsType.display(context),
                  ),
                  const SizedBox(height: FsSpace.xs),
                  Text(
                    'Score: $score / ${questions.length}',
                    style: FsType.subtitle(context).copyWith(fontSize: 18, color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: FsSpace.xs),
                  Text(
                    'Topic: $topic',
                    style: FsType.body(context).copyWith(fontSize: 14, color: FsColors.textSecondary(context)),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ],
              ),
            );
          }

          final q = questions[currentQ];
          final options = (q['options'] as List<dynamic>?) ?? [];
          final correctIdx = q['correctAnswerIndex'] ?? 0;

          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: BoxDecoration(
              color: AppTheme.card(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                // Handle
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.divider(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Progress
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        'Question ${currentQ + 1} / ${questions.length}',
                        style: FsType.caption(context).copyWith(fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                      ),
                      const Spacer(),
                      Text(
                        'Score: $score',
                        style: FsType.caption(context).copyWith(fontWeight: FontWeight.w600, color: FsColors.textSecondary(context)),
                      ),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: (currentQ + 1) / questions.length,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
                ),
                // Question
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          q['question'] ?? '',
                          style: FsType.title(context).copyWith(fontSize: 17, height: 1.5),
                        ),
                        const SizedBox(height: FsSpace.lg),
                        ...List.generate(options.length, (i) {
                          final isSelected = selectedAnswer == i;
                          final isCorrect = i == correctIdx;

                          Color bgColor;
                          Color borderColor;
                          if (answered) {
                            if (isCorrect) {
                              bgColor = AppTheme.successGreen.withValues(alpha: 0.1);
                              borderColor = AppTheme.successGreen;
                            } else if (isSelected && !isCorrect) {
                              bgColor = AppTheme.errorRed.withValues(alpha: 0.1);
                              borderColor = AppTheme.errorRed;
                            } else {
                              bgColor = Colors.transparent;
                              borderColor = AppTheme.divider(context);
                            }
                          } else {
                            bgColor = isSelected ? AppTheme.primaryColor.withValues(alpha: 0.08) : Colors.transparent;
                            borderColor = isSelected ? AppTheme.primaryColor : AppTheme.divider(context);
                          }

                          return GestureDetector(
                            onTap: answered ? null : () {
                              setSheetState(() {
                                selectedAnswer = i;
                                answered = true;
                                if (i == correctIdx) score++;
                              });
                            },
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor, width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: (answered && isCorrect)
                                          ? AppTheme.successGreen
                                          : (answered && isSelected && !isCorrect)
                                              ? AppTheme.errorRed
                                              : AppTheme.primaryColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        String.fromCharCode(65 + i),
                                        style: FsType.button(
                                          (answered && (isCorrect || (isSelected && !isCorrect)))
                                              ? Colors.white
                                              : AppTheme.primaryColor,
                                        ).copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      options[i].toString(),
                                      style: FsType.body(context).copyWith(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (answered && q['explanation'] != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.lightbulb_rounded, color: AppTheme.primaryColor, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    q['explanation'] ?? '',
                                    style: FsType.caption(context).copyWith(color: FsColors.textPrimary(context), height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Next button
                if (answered)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          setSheetState(() {
                            currentQ++;
                            selectedAnswer = null;
                            answered = false;
                          });
                        },
                        child: Text(currentQ < questions.length - 1 ? 'Next Question' : 'See Results'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
