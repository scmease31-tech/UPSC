import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_fonts.dart';
import '../../config/theme.dart';
import '../../data/vocabulary_data.dart';
import '../../models/vocabulary_entry.dart';
import '../../services/firestore_content_service.dart';
import '../../widgets/glass_widgets.dart';

typedef VocabularyDataLoader = Future<List<Map<String, dynamic>>> Function();
typedef VocabularyErrorReader = Object? Function();
typedef VocabularySourceOpener = Future<bool> Function(Uri uri);

enum VocabularyLibraryMode {
  full,
  latestNews,
}

enum _VocabularyLoadStatus {
  library,
  savedLibrary,
  savedEssentials,
}

Future<bool> _openVocabularySource(Uri uri) async {
  if (!await canLaunchUrl(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A complete, searchable vocabulary library for UPSC answer writing.
class VocabularyBuilderScreen extends StatefulWidget {
  const VocabularyBuilderScreen({
    super.key,
    this.loadVocabulary,
    this.refreshVocabulary,
    this.lastErrorReader,
    this.openSource,
    this.loadTimeout = const Duration(seconds: 20),
  });

  /// Injection seams keep widget tests independent of Firebase and platform URL
  /// channels. Production callers continue to use the service defaults.
  final VocabularyDataLoader? loadVocabulary;
  final VocabularyDataLoader? refreshVocabulary;
  final VocabularyErrorReader? lastErrorReader;
  final VocabularySourceOpener? openSource;
  final Duration loadTimeout;

  @override
  State<VocabularyBuilderScreen> createState() =>
      _VocabularyBuilderScreenState();
}

class _VocabularyBuilderScreenState extends State<VocabularyBuilderScreen> {
  static const _learnedPreferenceKey = 'vocab_learned';
  static const _bookmarkedPreferenceKey = 'vocab_bookmarked';

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<VocabularyEntry> _entries = const <VocabularyEntry>[];
  Set<String> _learnedIds = <String>{};
  Set<String> _bookmarkedIds = <String>{};
  String _selectedCategory = 'All';
  String _searchQuery = '';
  VocabularyLibraryMode _mode = VocabularyLibraryMode.full;
  _VocabularyLoadStatus _loadStatus = _VocabularyLoadStatus.savedEssentials;
  int _libraryRecordCount = 0;
  bool _showLearnedOnly = false;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _bounded(
    VocabularyDataLoader loader,
  ) =>
      loader().timeout(
        widget.loadTimeout,
        onTimeout: () => throw TimeoutException(
          'Vocabulary loading exceeded ${widget.loadTimeout.inSeconds} seconds',
        ),
      );

  Future<void> _loadAll() async {
    await _loadProgress();
    try {
      final loader =
          widget.loadVocabulary ?? FirestoreContentService.getVocabulary;
      final raw = await _bounded(loader);
      if (!mounted) return;
      _applySnapshot(
        _VocabularySnapshot.fromLibrary(raw),
        sourceError: _readLastError(isRefresh: false),
      );
    } catch (error) {
      debugPrint('Failed to load vocabulary: $error');
      if (!mounted) return;
      _applySnapshot(
        _VocabularySnapshot.fromLibrary(const <Map<String, dynamic>>[]),
        sourceError: error,
      );
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final loader = widget.refreshVocabulary ??
          () => FirestoreContentService.refresh('vocabulary');
      final raw = await _bounded(loader);
      if (!mounted) return;
      final sourceError = _readLastError(isRefresh: true);
      final snapshot = _VocabularySnapshot.fromLibrary(raw);

      // If a failed refresh has no stale cache of its own, retain the library
      // already on screen and label it saved rather than collapsing to 50.
      if (sourceError != null &&
          snapshot.libraryRecordCount == 0 &&
          _libraryRecordCount > 0) {
        setState(() => _loadStatus = _VocabularyLoadStatus.savedLibrary);
      } else {
        _applySnapshot(snapshot, sourceError: sourceError);
      }
    } catch (error) {
      debugPrint('Failed to refresh vocabulary: $error');
      if (!mounted) return;
      if (_entries.isEmpty) {
        _applySnapshot(
          _VocabularySnapshot.fromLibrary(const <Map<String, dynamic>>[]),
          sourceError: error,
        );
      } else {
        setState(() {
          _loadStatus = _libraryRecordCount > 0
              ? _VocabularyLoadStatus.savedLibrary
              : _VocabularyLoadStatus.savedEssentials;
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Object? _readLastError({required bool isRefresh}) {
    final reader = widget.lastErrorReader;
    if (reader != null) {
      try {
        return reader();
      } catch (error) {
        return error;
      }
    }
    final usesService = isRefresh
        ? widget.refreshVocabulary == null
        : widget.loadVocabulary == null;
    return usesService
        ? FirestoreContentService.lastErrorFor('vocabulary')
        : null;
  }

  void _applySnapshot(
    _VocabularySnapshot snapshot, {
    required Object? sourceError,
  }) {
    final progressChanged = _migrateProgress(_learnedIds, snapshot.entries) |
        _migrateProgress(_bookmarkedIds, snapshot.entries);
    setState(() {
      _entries = snapshot.entries;
      _libraryRecordCount = snapshot.libraryRecordCount;
      _loadStatus = snapshot.libraryRecordCount == 0
          ? _VocabularyLoadStatus.savedEssentials
          : (sourceError == null
              ? _VocabularyLoadStatus.library
              : _VocabularyLoadStatus.savedLibrary);
      _loading = false;
      final categories = VocabularyEntry.categoryCounts(_modeEntries).keys;
      if (_selectedCategory != 'All' &&
          !categories.contains(_selectedCategory)) {
        _selectedCategory = 'All';
      }
    });
    if (progressChanged) unawaited(_saveProgress());
  }

  Future<void> _loadProgress() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _learnedIds = _decodeProgress(
        preferences.get(_learnedPreferenceKey),
      );
      _bookmarkedIds = _decodeProgress(
        preferences.get(_bookmarkedPreferenceKey),
      );
    } catch (error) {
      debugPrint('Could not read vocabulary progress: $error');
      _learnedIds = <String>{};
      _bookmarkedIds = <String>{};
    }
  }

  static Set<String> _decodeProgress(Object? stored) {
    Object? value = stored;
    if (stored is String) {
      try {
        value = jsonDecode(stored);
      } catch (_) {
        return <String>{};
      }
    }
    if (value is! List) return <String>{};
    return value
        .where((item) => item is String || item is num)
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet();
  }

  static bool _migrateProgress(
    Set<String> storedIds,
    Iterable<VocabularyEntry> entries,
  ) {
    var changed = false;
    for (final entry in entries) {
      if (entry.isTrackedBy(storedIds) && storedIds.add(entry.stableId)) {
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _saveProgress() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final learned = _learnedIds.toList()..sort();
      final bookmarked = _bookmarkedIds.toList()..sort();
      await Future.wait(<Future<bool>>[
        preferences.setString(_learnedPreferenceKey, jsonEncode(learned)),
        preferences.setString(
          _bookmarkedPreferenceKey,
          jsonEncode(bookmarked),
        ),
      ]);
    } catch (error) {
      debugPrint('Could not save vocabulary progress: $error');
    }
  }

  bool _isLearned(VocabularyEntry entry) => entry.isTrackedBy(_learnedIds);

  bool _isBookmarked(VocabularyEntry entry) =>
      entry.isTrackedBy(_bookmarkedIds);

  int _trackedCount(Set<String> storedIds) =>
      _entries.where((entry) => entry.isTrackedBy(storedIds)).length;

  void _toggleLearned(VocabularyEntry entry) {
    _toggleProgress(entry, _learnedIds);
    HapticFeedback.lightImpact();
  }

  void _toggleBookmark(VocabularyEntry entry) {
    _toggleProgress(entry, _bookmarkedIds);
    HapticFeedback.selectionClick();
  }

  void _toggleProgress(VocabularyEntry entry, Set<String> storedIds) {
    setState(() {
      if (entry.isTrackedBy(storedIds)) {
        storedIds.removeWhere(entry.progressAliases.contains);
      } else {
        storedIds.add(entry.stableId);
      }
    });
    unawaited(_saveProgress());
  }

  List<VocabularyEntry> get _latestEntries =>
      VocabularyEntry.latestNews(_entries);

  List<VocabularyEntry> get _modeEntries =>
      _mode == VocabularyLibraryMode.full ? _entries : _latestEntries;

  Map<String, int> get _categoryCounts =>
      VocabularyEntry.categoryCounts(_modeEntries);

  List<String> get _categories {
    final categories = _categoryCounts.keys.toList()
      ..sort((a, b) {
        if (a == 'General') return 1;
        if (b == 'General') return -1;
        return a.compareTo(b);
      });
    return <String>['All', ...categories];
  }

  List<VocabularyEntry> get _filteredEntries {
    return _modeEntries.where((entry) {
      if (_selectedCategory != 'All' && entry.category != _selectedCategory) {
        return false;
      }
      if (_showLearnedOnly && !_isLearned(entry)) return false;
      return entry.matchesQuery(_searchQuery);
    }).toList(growable: false);
  }

  void _selectMode(VocabularyLibraryMode mode) {
    setState(() {
      _mode = mode;
      _selectedCategory = 'All';
    });
    _scrollToTop();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedCategory = 'All';
      _showLearnedOnly = false;
      _mode = VocabularyLibraryMode.full;
    });
    _scrollToTop();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();

    final filtered = _filteredEntries;
    return GradientScaffold(
      title: 'Vocabulary Builder',
      extendBodyBehindAppBar: false,
      actions: <Widget>[
        IconButton(
          key: const Key('vocabulary-learned-filter'),
          icon: Icon(
            _showLearnedOnly ? Icons.check_circle : Icons.check_circle_outline,
            color: _showLearnedOnly
                ? AppTheme.primaryColor
                : AppTheme.textS(context),
          ),
          onPressed: () {
            setState(() => _showLearnedOnly = !_showLearnedOnly);
            _scrollToTop();
          },
          tooltip: 'Show learned only',
        ),
      ],
      child: Column(
        children: <Widget>[
          _buildSourceBanner(),
          _buildModeSelector(),
          _buildSearch(),
          _buildCategoryFilters(),
          _buildCountAndRefresh(filtered.length),
          Expanded(child: _buildList(filtered)),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return GradientScaffold(
      title: 'Vocabulary Builder',
      extendBodyBehindAppBar: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 14),
            Text(
              'Loading complete vocabulary library…',
              key: const Key('vocabulary-loading-label'),
              style: AppFonts.inter(color: AppTheme.textS(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceBanner() {
    late final Color color;
    late final IconData icon;
    late final String title;
    late final String detail;

    switch (_loadStatus) {
      case _VocabularyLoadStatus.library:
        color = AppTheme.primaryColor;
        icon = Icons.cloud_done_rounded;
        title = 'Live library + saved essentials';
        detail =
            '$_libraryRecordCount library records merged with ${VocabularyData.words.length} curated essentials.';
      case _VocabularyLoadStatus.savedLibrary:
        color = AppTheme.warningOrange;
        icon = Icons.cloud_off_rounded;
        title = 'Showing saved library + essentials';
        detail =
            'The update failed. ${_entries.length} saved words remain available; pull down or tap refresh to retry.';
      case _VocabularyLoadStatus.savedEssentials:
        color = AppTheme.warningOrange;
        icon = Icons.inventory_2_outlined;
        title = 'Showing saved essentials';
        detail =
            '${VocabularyData.words.length} curated words are available offline. Pull down or tap refresh for the full library.';
    }

    return Semantics(
      container: true,
      label: '$title. $detail',
      child: Container(
        key: const Key('vocabulary-source-banner'),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: AppFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: AppFonts.inter(
                      fontSize: 10,
                      height: 1.35,
                      color: AppTheme.textS(context),
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

  Widget _buildModeSelector() {
    final latest = _latestEntries;
    return SizedBox(
      height: 43,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        children: <Widget>[
          ChoiceChip(
            key: const Key('vocabulary-mode-full'),
            label: Text('Full library (${_entries.length})'),
            selected: _mode == VocabularyLibraryMode.full,
            onSelected: (_) => _selectMode(VocabularyLibraryMode.full),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const Key('vocabulary-mode-latest'),
            label: Text('Latest news (${latest.length})'),
            selected: _mode == VocabularyLibraryMode.latestNews,
            onSelected: (_) => _selectMode(VocabularyLibraryMode.latestNews),
          ),
          if (latest.isNotEmpty) ...<Widget>[
            const SizedBox(width: 9),
            Center(
              child: Text(
                'Latest available: ${latest.first.publishedDateLabel}',
                style: AppFonts.inter(
                  fontSize: 10,
                  color: AppTheme.textT(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.isDark(context)
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: TextField(
          key: const Key('vocabulary-search'),
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          style: AppFonts.inter(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search meaning, usage, source…',
            hintStyle: AppFonts.inter(
              fontSize: 14,
              color: AppTheme.textT(context),
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: AppTheme.textT(context),
              size: 20,
            ),
            suffixIcon: _searchQuery.trim().isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            fillColor: Colors.transparent,
            filled: true,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    final counts = _categoryCounts;
    final modeTotal = _modeEntries.length;
    return SizedBox(
      height: 42,
      child: ListView.builder(
        key: const Key('vocabulary-category-list'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = category == _selectedCategory;
          final count = category == 'All' ? modeTotal : counts[category] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              key: ValueKey<String>('vocabulary-category-$category'),
              label: Text('$category ($count)'),
              selected: selected,
              onSelected: (_) {
                setState(() => _selectedCategory = category);
                _scrollToTop();
              },
              backgroundColor: AppTheme.isDark(context)
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.white.withValues(alpha: 0.7),
              selectedColor: AppTheme.primaryColor.withValues(alpha: 0.15),
              labelStyle: AppFonts.inter(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:
                    selected ? AppTheme.primaryColor : AppTheme.textS(context),
              ),
              side: BorderSide(
                color: selected ? AppTheme.primaryColor : Colors.transparent,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCountAndRefresh(int visibleCount) {
    final modeCount = _modeEntries.length;
    final learnedCount = _trackedCount(_learnedIds);
    final bookmarkedCount = _trackedCount(_bookmarkedIds);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 10, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_entries.length} words loaded',
                  key: const Key('vocabulary-loaded-total'),
                  style: AppFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textP(context),
                  ),
                ),
                Text(
                  '$visibleCount of $modeCount showing • $learnedCount learned • $bookmarkedCount saved',
                  key: const Key('vocabulary-visible-total'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.inter(
                    fontSize: 10,
                    color: AppTheme.textS(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('vocabulary-refresh'),
            onPressed: _refreshing ? null : _refresh,
            tooltip: 'Refresh vocabulary',
            visualDensity: VisualDensity.compact,
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 21),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<VocabularyEntry> filtered) {
    if (filtered.isEmpty) {
      final latestUnavailable =
          _mode == VocabularyLibraryMode.latestNews && _modeEntries.isEmpty;
      return RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.primaryColor,
        child: ListView(
          key: const Key('vocabulary-empty-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          children: <Widget>[
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.10),
            Icon(
              latestUnavailable
                  ? Icons.newspaper_outlined
                  : Icons.search_off_rounded,
              size: 46,
              color: AppTheme.textT(context),
            ),
            const SizedBox(height: 12),
            Text(
              latestUnavailable
                  ? 'No dated news vocabulary yet'
                  : 'No words match',
              textAlign: TextAlign.center,
              style: AppFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textP(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              latestUnavailable
                  ? 'Latest uses the newest available publication date. The full saved library is still available.'
                  : 'Clear search, category, and learned filters to browse every loaded word.',
              textAlign: TextAlign.center,
              style: AppFonts.inter(
                fontSize: 12,
                height: 1.45,
                color: AppTheme.textS(context),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: Text(
                  latestUnavailable ? 'View full library' : 'Clear filters',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.primaryColor,
      child: ListView.builder(
        key: const Key('vocabulary-list'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          100 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _buildWordCard(filtered[index]),
      ),
    );
  }

  Widget _buildWordCard(VocabularyEntry entry) {
    final learned = _isLearned(entry);
    final bookmarked = _isBookmarked(entry);
    final categoryColor = _categoryColor(entry.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedGlassCard(
        key: ValueKey<String>('vocabulary-card-${entry.stableId}'),
        onTap: () => _showWordDetail(entry),
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.word,
                        style: AppFonts.plusJakartaSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textP(context),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: <Widget>[
                          if (entry.partOfSpeech.isNotEmpty)
                            _metadataBadge(
                              entry.partOfSpeech,
                              AppTheme.textS(context),
                            ),
                          _metadataBadge(entry.category, categoryColor),
                          _metadataBadge(
                            entry.provenanceLabel,
                            entry.hasLibraryProvenance
                                ? AppTheme.primaryColor
                                : AppTheme.warningOrange,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  constraints:
                      const BoxConstraints.tightFor(width: 36, height: 36),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark word',
                  onPressed: () => _toggleBookmark(entry),
                  icon: Icon(
                    bookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_outline_rounded,
                    size: 21,
                    color: bookmarked
                        ? AppTheme.accentViolet
                        : AppTheme.textT(context),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  constraints:
                      const BoxConstraints.tightFor(width: 36, height: 36),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: learned ? 'Mark unlearned' : 'Mark learned',
                  onPressed: () => _toggleLearned(entry),
                  icon: Icon(
                    learned
                        ? Icons.check_circle_rounded
                        : Icons.check_circle_outline_rounded,
                    size: 21,
                    color: learned
                        ? AppTheme.primaryColor
                        : AppTheme.textT(context),
                  ),
                ),
              ],
            ),
            if (entry.meaning.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                entry.meaning,
                style: AppFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textS(context),
                  height: 1.4,
                ),
              ),
            ],
            if (entry.example.isNotEmpty) ...<Widget>[
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.format_quote_rounded,
                    size: 15,
                    color: AppTheme.textT(context),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      entry.example,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.inter(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.textT(context),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (entry.synonyms.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              _wordChips('Synonyms', entry.synonyms, AppTheme.primaryColor),
            ],
            if (entry.antonyms.isNotEmpty) ...<Widget>[
              const SizedBox(height: 7),
              _wordChips('Antonyms', entry.antonyms, AppTheme.warningOrange),
            ],
            if (entry.upscPaper.isNotEmpty ||
                entry.upscUsage.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              _upscNote(entry),
            ],
            if (entry.sourceAttribution.isNotEmpty ||
                entry.articleRef.isNotEmpty) ...<Widget>[
              const SizedBox(height: 9),
              _sourceAttribution(entry),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metadataBadge(String label, Color color) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: AppFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _wordChips(String label, List<String> words, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: AppFonts.inter(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.textT(context),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: words
              .map(
                (word) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.16)),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Text(
                      word,
                      style: AppFonts.inter(fontSize: 9, color: color),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _upscNote(VocabularyEntry entry) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.accentViolet.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.school_outlined,
              size: 15,
              color: AppTheme.accentViolet,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (entry.upscPaper.isNotEmpty)
                    Text(
                      entry.upscPaper,
                      style: AppFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accentViolet,
                      ),
                    ),
                  if (entry.upscUsage.isNotEmpty)
                    Text(
                      entry.upscUsage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.inter(
                        fontSize: 10,
                        height: 1.35,
                        color: AppTheme.textS(context),
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

  Widget _sourceAttribution(VocabularyEntry entry) {
    final attribution = entry.sourceAttribution.isNotEmpty
        ? entry.sourceAttribution
        : entry.articleRef;
    final uri = entry.sourceUri;
    return Row(
      children: <Widget>[
        Icon(
          Icons.newspaper_outlined,
          size: 15,
          color: AppTheme.textT(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            attribution,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppFonts.inter(
              fontSize: 10,
              color: AppTheme.textS(context),
            ),
          ),
        ),
        if (uri != null)
          TextButton.icon(
            key: ValueKey<String>('vocabulary-source-${entry.stableId}'),
            onPressed: () => _launchSource(entry),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 30),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 13),
            label: const Text('Open source'),
          ),
      ],
    );
  }

  Future<void> _launchSource(VocabularyEntry entry) async {
    final uri = entry.sourceUri;
    if (uri == null) return;
    var opened = false;
    try {
      opened = await (widget.openSource ?? _openVocabularySource)(uri);
    } catch (error) {
      debugPrint('Could not open vocabulary source: $error');
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this source link.')),
      );
    }
  }

  void _showWordDetail(VocabularyEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  entry.word,
                  style: AppFonts.plusJakartaSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textP(sheetContext),
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: <Widget>[
                    if (entry.partOfSpeech.isNotEmpty)
                      _metadataBadge(
                        entry.partOfSpeech,
                        AppTheme.textS(sheetContext),
                      ),
                    _metadataBadge(
                      entry.category,
                      _categoryColor(entry.category),
                    ),
                    _metadataBadge(
                      entry.provenanceLabel,
                      entry.hasLibraryProvenance
                          ? AppTheme.primaryColor
                          : AppTheme.warningOrange,
                    ),
                  ],
                ),
                if (entry.meaning.isNotEmpty)
                  _detailText(
                    sheetContext,
                    'Meaning',
                    entry.meaning,
                    Icons.lightbulb_outline_rounded,
                  ),
                if (entry.example.isNotEmpty)
                  _detailText(
                    sheetContext,
                    'Example in context',
                    entry.example,
                    Icons.format_quote_rounded,
                  ),
                if (entry.synonyms.isNotEmpty)
                  _detailWords(
                    sheetContext,
                    'Synonyms',
                    entry.synonyms,
                    AppTheme.primaryColor,
                  ),
                if (entry.antonyms.isNotEmpty)
                  _detailWords(
                    sheetContext,
                    'Antonyms',
                    entry.antonyms,
                    AppTheme.warningOrange,
                  ),
                if (entry.upscPaper.isNotEmpty)
                  _detailText(
                    sheetContext,
                    'UPSC paper',
                    entry.upscPaper,
                    Icons.assignment_outlined,
                  ),
                if (entry.upscUsage.isNotEmpty)
                  _detailText(
                    sheetContext,
                    'UPSC usage',
                    entry.upscUsage,
                    Icons.school_outlined,
                  ),
                if (entry.sourceAttribution.isNotEmpty)
                  _detailText(
                    sheetContext,
                    'Source',
                    entry.sourceAttribution,
                    Icons.newspaper_outlined,
                  ),
                if (entry.articleRef.isNotEmpty &&
                    entry.articleRef != entry.sourceName)
                  _detailText(
                    sheetContext,
                    'Article reference',
                    entry.articleRef,
                    Icons.link_rounded,
                  ),
                const SizedBox(height: 8),
                if (entry.sourceUri != null) ...<Widget>[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _launchSource(entry),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open original HTTPS source'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _toggleBookmark(entry);
                          Navigator.pop(sheetContext);
                        },
                        icon: Icon(
                          _isBookmarked(entry)
                              ? Icons.bookmark_remove_rounded
                              : Icons.bookmark_add_outlined,
                        ),
                        label: Text(
                          _isBookmarked(entry) ? 'Unsave' : 'Save',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _toggleLearned(entry);
                          Navigator.pop(sheetContext);
                        },
                        icon: Icon(
                          _isLearned(entry)
                              ? Icons.undo_rounded
                              : Icons.check_rounded,
                        ),
                        label: Text(
                          _isLearned(entry) ? 'Unlearn' : 'Mark learned',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailText(
    BuildContext sheetContext,
    String label,
    String value,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: AppFonts.inter(
                    fontSize: 13,
                    height: 1.5,
                    color: AppTheme.textP(sheetContext),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailWords(
    BuildContext sheetContext,
    String label,
    List<String> words,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: AppFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: words
                .map(
                  (word) => Chip(
                    label: Text(word),
                    visualDensity: VisualDensity.compact,
                    labelStyle: AppFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textP(sheetContext),
                    ),
                    backgroundColor: color.withValues(alpha: 0.08),
                    side: BorderSide(color: color.withValues(alpha: 0.18)),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'Governance':
        return AppTheme.accentViolet;
      case 'Economy':
        return AppTheme.warningOrange;
      case 'Diplomacy':
        return const Color(0xFF448AFF);
      case 'Environment':
        return const Color(0xFF4CAF50);
      case 'Ethics':
        return const Color(0xFF8D6E63);
      case 'Social':
        return const Color(0xFFE91E63);
      case 'Legal':
        return const Color(0xFF607D8B);
      case 'Science & Technology':
        return const Color(0xFF00897B);
      default:
        return AppTheme.primaryColor;
    }
  }
}

class _VocabularySnapshot {
  const _VocabularySnapshot({
    required this.entries,
    required this.libraryRecordCount,
  });

  factory _VocabularySnapshot.fromLibrary(
    List<Map<String, dynamic>> library,
  ) {
    final entries = VocabularyEntry.combine(library, VocabularyData.words);
    return _VocabularySnapshot(
      entries: entries,
      libraryRecordCount:
          entries.where((entry) => entry.hasLibraryProvenance).length,
    );
  }

  final List<VocabularyEntry> entries;
  final int libraryRecordCount;
}
