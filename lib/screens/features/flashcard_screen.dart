import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_fonts.dart';
import '../../config/theme.dart';
import '../../services/daily_content_manager.dart';
import '../../widgets/glass_widgets.dart';

typedef FlashcardLibraryLoader = Future<StudyContentResult<StudyFlashcard>>
    Function({bool forceRefresh});
typedef FlashcardMasteryLoader = Future<Set<String>> Function();
typedef FlashcardMasterySaver = Future<void> Function(Set<String> ids);

/// Searchable daily and full-library flashcard revision with stable mastery IDs.
class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({
    super.key,
    this.loadLibrary,
    this.loadMastery,
    this.saveMastery,
    this.now,
  });

  final FlashcardLibraryLoader? loadLibrary;
  final FlashcardMasteryLoader? loadMastery;
  final FlashcardMasterySaver? saveMastery;
  final DateTime Function()? now;

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen>
    with SingleTickerProviderStateMixin {
  static const _masteryKey = 'flashcard_mastered_ids_v2';

  final _searchController = TextEditingController();
  PageController? _pageController;
  late final AnimationController _flipController;

  StudyContentResult<StudyFlashcard>? _result;
  List<StudyFlashcard> _library = const [];
  List<StudyFlashcard> _modeCards = const [];
  List<StudyFlashcard> _visibleCards = const [];
  Set<String> _masteredIds = <String>{};
  StudyLibraryMode _mode = StudyLibraryMode.daily;
  String? _selectedCategory;
  String _query = '';
  int _currentIndex = 0;
  int _loadGeneration = 0;
  bool _showAnswer = false;
  bool _loading = true;
  bool _refreshing = false;
  bool _masteryLoaded = false;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  StudyFlashcard? get _currentCard =>
      _visibleCards.isEmpty ? null : _visibleCards[_currentIndex];

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _loadFlashcards();
  }

  @override
  void dispose() {
    _loadGeneration++;
    _pageController?.dispose();
    _flipController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFlashcards({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        if (_result == null) {
          _loading = true;
        } else {
          _refreshing = true;
        }
      });
    }

    final resultFuture = widget.loadLibrary != null
        ? widget.loadLibrary!(forceRefresh: forceRefresh)
        : DailyContentManager.loadFlashcardLibrary(
            forceRefresh: forceRefresh,
          );
    final masteryFuture = _masteryLoaded
        ? Future<Set<String>>.value(_masteredIds)
        : (widget.loadMastery?.call() ?? _loadSavedMastery());

    late StudyContentResult<StudyFlashcard> result;
    Set<String> mastery;
    try {
      result = await resultFuture;
      try {
        mastery = await masteryFuture;
      } catch (_) {
        mastery = <String>{};
      }
    } catch (error) {
      result = StudyContentResult<StudyFlashcard>(
        items: const [],
        state: StudyContentLoadState.fallback,
        source: StudyContentCollectionSource.foundation,
        loadedAt: _now,
        error: error,
      );
      mastery = await masteryFuture.catchError((_) => <String>{});
    }

    if (!mounted || generation != _loadGeneration) return;
    final preferredId = _currentCard?.id;
    _library = result.items;
    _result = result;
    _masteredIds = Set<String>.from(mastery);
    _masteryLoaded = true;
    _loading = false;
    _refreshing = false;
    _rebuildDeck(preferredId: preferredId);
  }

  Future<Set<String>> _loadSavedMastery() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_masteryKey) ?? const <String>[]).toSet();
  }

  Future<void> _saveMastery(Set<String> ids) async {
    if (widget.saveMastery != null) {
      await widget.saveMastery!(Set<String>.unmodifiable(ids));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final sorted = ids.toList()..sort();
    await prefs.setStringList(_masteryKey, sorted);
  }

  List<StudyFlashcard> _cardsForMode() {
    if (_mode == StudyLibraryMode.fullLibrary) {
      return StudyLibrarySelectors.sortFlashcards(_library);
    }
    return StudyLibrarySelectors.dailyFlashcards(_library, date: _now);
  }

  void _rebuildDeck({String? preferredId}) {
    final previousId = preferredId ?? _currentCard?.id;
    final nextModeCards = _cardsForMode();
    final counts = StudyLibrarySelectors.flashcardCategoryCounts(nextModeCards);
    if (_selectedCategory != null && !counts.containsKey(_selectedCategory)) {
      _selectedCategory = null;
    }
    final nextVisible = StudyLibrarySelectors.filterFlashcards(
      nextModeCards,
      category: _selectedCategory,
      query: _query,
    );
    var nextIndex = 0;
    if (previousId != null) {
      final preserved = nextVisible.indexWhere((card) => card.id == previousId);
      if (preserved >= 0) nextIndex = preserved;
    }

    final oldController = _pageController;
    final nextController = nextVisible.isEmpty
        ? null
        : PageController(initialPage: nextIndex, viewportFraction: 0.88);
    _flipController.reset();
    setState(() {
      _modeCards = nextModeCards;
      _visibleCards = nextVisible;
      _currentIndex = nextIndex;
      _showAnswer = false;
      _pageController = nextController;
    });
    oldController?.dispose();
  }

  void _changeMode(StudyLibraryMode mode) {
    if (_mode == mode) return;
    HapticFeedback.selectionClick();
    final previousId = _currentCard?.id;
    _mode = mode;
    _selectedCategory = null;
    _rebuildDeck(preferredId: previousId);
  }

  void _changeCategory(String? category) {
    HapticFeedback.selectionClick();
    final previousId = _currentCard?.id;
    _selectedCategory = category;
    _rebuildDeck(preferredId: previousId);
  }

  void _changeQuery(String query) {
    final previousId = _currentCard?.id;
    _query = query;
    _rebuildDeck(preferredId: previousId);
  }

  void _toggleCard() {
    HapticFeedback.lightImpact();
    if (_showAnswer) {
      _flipController.reverse().then((_) {
        if (mounted) setState(() => _showAnswer = false);
      });
    } else {
      setState(() => _showAnswer = true);
      _flipController.forward();
    }
  }

  void _toggleMastery() {
    final card = _currentCard;
    if (card == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      if (!_masteredIds.add(card.id)) _masteredIds.remove(card.id);
    });
    final masterySnapshot = Set<String>.from(_masteredIds);
    unawaited(_saveMastery(masterySnapshot));
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      showAppBar: false,
      child: SafeArea(
        child: _loading ? _buildLoading(context) : _buildContent(context),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return Column(
      children: [
        _buildAppBar(context),
        Expanded(
          child: Center(
            child: Lottie.asset(
              'assets/animations/loading.json',
              width: 120,
              height: 120,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final categoryCounts =
        StudyLibrarySelectors.flashcardCategoryCounts(_modeCards);
    final masteredCount = StudyLibrarySelectors.visibleMasteredCount(
      _visibleCards,
      _masteredIds,
    );

    return Column(
      children: [
        _buildAppBar(context),
        _buildModeSelector(context),
        _buildSearchBar(context),
        _buildCategoryChips(context, categoryCounts),
        if (_result?.isFallback == true)
          _statusBanner(
            context,
            icon: Icons.offline_bolt_rounded,
            text: 'Showing Foundation cards — live library unavailable.',
            color: AppTheme.warningOrange,
          ),
        if (_result?.isStale == true)
          _statusBanner(
            context,
            icon: Icons.history_rounded,
            text: 'Refresh failed — showing the saved live library.',
            color: AppTheme.warningOrange,
          ),
        if (_result?.truncated == true)
          _statusBanner(
            context,
            icon: Icons.info_outline_rounded,
            text:
                'Library reached the ${DailyContentManager.maxFlashcards}-card safety limit.',
            color: AppTheme.primaryColor,
          ),
        _buildDeckSummary(context, masteredCount),
        Expanded(
          child: _visibleCards.isEmpty
              ? _buildEmptyState(context)
              : PageView.builder(
                  key: ValueKey(
                    'flashcards-${_mode.name}-${_selectedCategory ?? 'all'}-$_query',
                  ),
                  controller: _pageController,
                  itemCount: _visibleCards.length,
                  onPageChanged: (index) {
                    _flipController.reset();
                    setState(() {
                      _currentIndex = index;
                      _showAnswer = false;
                    });
                  },
                  itemBuilder: (context, index) {
                    final card = _visibleCards[index];
                    return _buildFlipCard(
                      context,
                      card,
                      index == _currentIndex,
                      _masteredIds.contains(card.id),
                    );
                  },
                ),
        ),
        if (_visibleCards.isNotEmpty)
          _buildBottomActions(context, masteredCount),
      ],
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.maybePop(context);
            },
          ),
          Text(
            'Flashcards',
            style: AppFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textP(context),
            ),
          ),
          const Spacer(),
          IconButton(
            key: const ValueKey('refresh-flashcards'),
            tooltip: 'Refresh library',
            onPressed:
                _refreshing ? null : () => _loadFlashcards(forceRefresh: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
      child: Row(
        children: StudyLibraryMode.values.map((mode) {
          final selected = mode == _mode;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: mode == StudyLibraryMode.daily ? 6 : 0,
                left: mode == StudyLibraryMode.fullLibrary ? 6 : 0,
              ),
              child: ChoiceChip(
                key: ValueKey('flashcard-mode-${mode.name}'),
                label: SizedBox(
                  width: double.infinity,
                  child: Text(mode.label, textAlign: TextAlign.center),
                ),
                selected: selected,
                onSelected: (_) => _changeMode(mode),
                selectedColor: AppTheme.primaryColor,
                labelStyle: AppFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.textS(context),
                ),
                side: BorderSide.none,
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: TextField(
          key: const ValueKey('flashcard-search'),
          controller: _searchController,
          onChanged: _changeQuery,
          style: AppFonts.inter(fontSize: 13, color: AppTheme.textP(context)),
          decoration: InputDecoration(
            hintText: 'Search question, answer, subject or source',
            hintStyle:
                AppFonts.inter(fontSize: 12, color: AppTheme.textS(context)),
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      _changeQuery('');
                    },
                    icon: const Icon(Icons.clear_rounded, size: 18),
                  ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(
    BuildContext context,
    Map<String, int> categoryCounts,
  ) {
    final entries = <MapEntry<String?, int>>[
      MapEntry<String?, int>(null, _modeCards.length),
      ...categoryCounts.entries,
    ];
    return SizedBox(
      height: 43,
      child: ListView.builder(
        key: const ValueKey('flashcard-category-list'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final selected = entry.key == _selectedCategory;
          final label = entry.key ?? 'All';
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              key: ValueKey('flashcard-category-${entry.key ?? 'all'}'),
              selected: selected,
              onSelected: (_) => _changeCategory(entry.key),
              label: Text('$label (${entry.value})'),
              selectedColor: AppTheme.primaryColor,
              labelStyle: AppFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.textS(context),
              ),
              side: BorderSide.none,
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeckSummary(BuildContext context, int masteredCount) {
    final date = _modeCards.isEmpty
        ? ''
        : _modeCards
            .map((card) => card.publishedDateLabel)
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final libraryTotal = _library.length;
    final visible = _visibleCards.length;
    final description = _mode == StudyLibraryMode.daily
        ? (date.isEmpty ? 'Foundation daily set' : 'Publication date $date')
        : '$visible of $libraryTotal cards visible';
    final progress = visible == 0 ? 0.0 : masteredCount / visible;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  description,
                  key: const ValueKey('flashcard-visible-total'),
                  style: AppFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textS(context),
                  ),
                ),
              ),
              Text(
                '$masteredCount/$visible mastered',
                style: AppFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.successGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 5,
              backgroundColor: AppTheme.divider(context),
              valueColor: const AlwaysStoppedAnimation(AppTheme.successGreen),
            ),
          ),
          if (visible > 0)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                '${_currentIndex + 1} of $visible',
                style: AppFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textS(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final noDatedDaily = _mode == StudyLibraryMode.daily &&
        _library.isNotEmpty &&
        _modeCards.isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.style_outlined,
                size: 52, color: AppTheme.primaryColor),
            const SizedBox(height: 12),
            Text(
              noDatedDaily
                  ? 'No dated daily cards are available'
                  : 'No cards match these filters',
              textAlign: TextAlign.center,
              style: AppFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textP(context),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                if (noDatedDaily) {
                  _changeMode(StudyLibraryMode.fullLibrary);
                } else {
                  _searchController.clear();
                  _query = '';
                  _selectedCategory = null;
                  _rebuildDeck();
                }
              },
              child: Text(noDatedDaily ? 'Open Full Library' : 'Clear filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipCard(
    BuildContext context,
    StudyFlashcard card,
    bool isActive,
    bool isMastered,
  ) {
    return GestureDetector(
      key: ValueKey('flashcard-${card.id}'),
      onTap: isActive ? _toggleCard : null,
      child: AnimatedBuilder(
        animation: _flipController,
        builder: (context, child) {
          final angle = isActive ? _flipController.value * math.pi : 0.0;
          final isFront = angle < math.pi / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isFront
                ? _buildCardFace(context, card, false, isMastered)
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _buildCardFace(context, card, true, isMastered),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildCardFace(
    BuildContext context,
    StudyFlashcard card,
    bool isBack,
    bool isMastered,
  ) {
    final textColor = isBack ? Colors.white : AppTheme.textP(context);
    final secondaryColor = isBack ? Colors.white70 : AppTheme.textS(context);
    final metadata = <String>[
      if (card.publishedDateLabel.isNotEmpty) card.publishedDateLabel,
      if (card.newspaper.isNotEmpty) card.newspaper,
      if (card.upscPaper.isNotEmpty) card.upscPaper,
      if (card.kind.isNotEmpty) card.kind,
    ];
    final source = card.sourceUrl.isNotEmpty ? card.sourceUrl : card.articleRef;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      decoration: isBack
          ? BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryColor,
                  AppTheme.primaryColor.withValues(alpha: 0.84),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isMastered
                    ? AppTheme.successGreen
                    : Colors.white.withValues(alpha: 0.2),
                width: isMastered ? 2 : 1,
              ),
            )
          : AppTheme.cleanCard(context, radius: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  _cardBadge(card.category, isBack, context),
                  _cardBadge(card.origin.label, isBack, context),
                  if (isMastered)
                    _cardBadge('Mastered', isBack, context,
                        color: AppTheme.successGreen),
                ],
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBack ? 'Answer' : 'Question',
                            style: AppFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: secondaryColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isBack ? card.back : card.front,
                            style: AppFonts.plusJakartaSans(
                              fontSize: isBack ? 15 : 20,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (metadata.isNotEmpty)
                Text(
                  metadata.join(' • '),
                  key: ValueKey('flashcard-metadata-${card.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.inter(
                    fontSize: 10,
                    color: secondaryColor,
                    height: 1.35,
                  ),
                ),
              if (source.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Source: $source',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.inter(
                    fontSize: 9,
                    color: secondaryColor,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Center(
                child: Text(
                  isBack ? 'Tap to flip back' : 'Tap to reveal answer',
                  style: AppFonts.inter(fontSize: 10, color: secondaryColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardBadge(
    String label,
    bool isBack,
    BuildContext context, {
    Color? color,
  }) {
    final badgeColor = color ?? (isBack ? Colors.white : AppTheme.primaryColor);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: AppFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color ?? (isBack ? Colors.white : AppTheme.primaryColor),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context, int masteredCount) {
    final card = _currentCard!;
    final mastered = _masteredIds.contains(card.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.arrow_back_rounded,
            label: 'Previous',
            color: AppTheme.textS(context),
            onTap: _currentIndex == 0
                ? null
                : () => _pageController?.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                    ),
          ),
          _ActionButton(
            key: const ValueKey('toggle-flashcard-mastery'),
            icon: mastered
                ? Icons.check_circle_rounded
                : Icons.check_circle_outline_rounded,
            label: mastered ? 'Mastered' : 'Mark Mastered',
            color: AppTheme.successGreen,
            onTap: _toggleMastery,
          ),
          _ActionButton(
            icon: Icons.arrow_forward_rounded,
            label: 'Next',
            color: AppTheme.primaryColor,
            onTap: _currentIndex >= _visibleCards.length - 1
                ? null
                : () => _pageController?.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                    ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      key: ValueKey('flashcard-status-${icon.codePoint}'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: AppFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textP(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    final size = compact ? 42.0 : 48.0;
    final enabledColor = onTap == null ? color.withValues(alpha: 0.35) : color;
    return InkWell(
      borderRadius: BorderRadius.circular(size),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: enabledColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: enabledColor, size: size * 0.48),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: compact ? 68 : 84,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppFonts.inter(
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w600,
                  color: enabledColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
