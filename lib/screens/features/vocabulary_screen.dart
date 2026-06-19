import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../config/theme.dart';
import '../../data/vocabulary_data.dart';
import '../../services/firestore_content_service.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// VocabularyBuilderScreen — Learn important English words with meanings,
/// usage, and synonyms — essential for Essay and Answer Writing.
/// ──────────────────────────────────────────────────────────────────────────────
class VocabularyBuilderScreen extends StatefulWidget {
  const VocabularyBuilderScreen({super.key});

  @override
  State<VocabularyBuilderScreen> createState() => _VocabularyBuilderScreenState();
}

class _VocabularyBuilderScreenState extends State<VocabularyBuilderScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedCategory = 'All';
  Set<String> _learnedWords = {};
  Set<String> _bookmarkedWords = {};
  bool _showLearnedOnly = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _words = [];
  bool _loading = true;
  bool _hasError = false;

  static const _wordCategories = [
    'All', 'Governance', 'Economy', 'Diplomacy', 'Environment',
    'Ethics', 'Social', 'Legal', 'General',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final learned = prefs.getString('vocab_learned');
      final bookmarked = prefs.getString('vocab_bookmarked');
      if (learned != null) _learnedWords = Set<String>.from(json.decode(learned));
      if (bookmarked != null) _bookmarkedWords = Set<String>.from(json.decode(bookmarked));
      var words = await FirestoreContentService.getVocabulary();
      // If Firestore returned nothing, use embedded fallback data
      if (words.isEmpty) {
        words = VocabularyData.words.map((w) => Map<String, dynamic>.from(w)).toList();
      }
      if (mounted) {
        final validIds = words.map((w) => w['id'] as String? ?? w['word'] as String? ?? '').toSet();
        _learnedWords.retainWhere(validIds.contains);
        _bookmarkedWords.retainWhere(validIds.contains);
        setState(() { _words = words; _loading = false; _hasError = false; });
      }
    } catch (e) {
      if (mounted) {
        // Fall back to embedded data on error
        final words = VocabularyData.words.map((w) => Map<String, dynamic>.from(w)).toList();
        setState(() { _words = words; _loading = false; _hasError = false; });
      }
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vocab_learned', json.encode(_learnedWords.toList()));
    await prefs.setString('vocab_bookmarked', json.encode(_bookmarkedWords.toList()));
  }

  String _wordId(int index) => _words[index]['id'] as String? ?? _words[index]['word'] as String? ?? '$index';

  void _toggleLearned(int index) {
    final id = _wordId(index);
    setState(() {
      if (_learnedWords.contains(id)) { _learnedWords.remove(id); } else { _learnedWords.add(id); }
    });
    _saveState();
    HapticFeedback.lightImpact();
  }

  void _toggleBookmark(int index) {
    final id = _wordId(index);
    setState(() {
      if (_bookmarkedWords.contains(id)) { _bookmarkedWords.remove(id); } else { _bookmarkedWords.add(id); }
    });
    _saveState();
    HapticFeedback.selectionClick();
  }

  List<int> _getFilteredIndices() {
    final indices = <int>[];
    for (int i = 0; i < _words.length; i++) {
      final w = _words[i];
      final cat = w['category'] as String? ?? '';
      if (_selectedCategory != 'All' && cat != _selectedCategory) continue;
      if (_showLearnedOnly && !_learnedWords.contains(_wordId(i))) continue;
      if (_searchQuery.isNotEmpty) {
        final word = (w['word'] as String? ?? '').toLowerCase();
        final meaning = (w['meaning'] as String? ?? '').toLowerCase();
        if (!word.contains(_searchQuery) && !meaning.contains(_searchQuery)) continue;
      }
      indices.add(i);
    }
    return indices;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return GradientScaffold(
        title: 'Vocabulary Builder',
        extendBodyBehindAppBar: false,
        child: Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120)),
      );
    }
    final filtered = _getFilteredIndices();

    return GradientScaffold(
      title: 'Vocabulary Builder',
      extendBodyBehindAppBar: false,
      actions: [
        IconButton(
          icon: Icon(
            _showLearnedOnly ? Icons.check_circle : Icons.check_circle_outline,
            color: _showLearnedOnly ? AppTheme.primaryColor : AppTheme.textS(context),
          ),
          onPressed: () => setState(() => _showLearnedOnly = !_showLearnedOnly),
          tooltip: 'Show learned only',
        ),
      ],
      child: Column(
        children: [
          // Stats bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                _statBadge('${_learnedWords.length}', 'Learned', AppTheme.primaryColor),
                const SizedBox(width: 8),
                _statBadge('${(_words.length - _learnedWords.length).clamp(0, _words.length)}', 'Remaining', AppTheme.warningOrange),
                const SizedBox(width: 8),
                _statBadge('${_bookmarkedWords.length}', 'Saved', AppTheme.accentViolet),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
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
                  hintText: 'Search words...',
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
          // Category chips
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _wordCategories.length,
              itemBuilder: (context, i) {
                final cat = _wordCategories[i];
                final selected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedCategory = cat),
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
          const SizedBox(height: 8),
          // Word list
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text('No words found', style: GoogleFonts.inter(color: AppTheme.textS(context))))
                : ListView.builder(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _buildWordCard(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statBadge(String value, String label, Color color) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textS(context)),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordCard(int index) {
    final w = _words[index];
    final id = _wordId(index);
    final learned = _learnedWords.contains(id);
    final bookmarked = _bookmarkedWords.contains(id);
    final word = w['word'] as String? ?? '';
    final category = w['category'] as String? ?? '';
    final meaning = w['meaning'] as String? ?? '';
    final example = w['example'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedGlassCard(
        onTap: () => _showWordDetail(index),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(word, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textP(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _categoryColor(category).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(category, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: _categoryColor(category))),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _toggleBookmark(index),
                  child: Icon(
                    bookmarked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                    size: 20,
                    color: bookmarked ? AppTheme.accentViolet : AppTheme.textT(context),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _toggleLearned(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: learned ? AppTheme.primaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: learned ? AppTheme.primaryColor : AppTheme.textT(context),
                        width: 1.5,
                      ),
                    ),
                    child: learned ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(meaning, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textS(context), height: 1.4)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.format_quote_rounded, size: 14, color: AppTheme.textT(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(example, style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: AppTheme.textT(context))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showWordDetail(int index) {
    final w = _words[index];
    final id = _wordId(index);
    final word = w['word'] as String? ?? '';
    final partOfSpeech = w['partOfSpeech'] as String? ?? '';
    final meaning = w['meaning'] as String? ?? '';
    final example = w['example'] as String? ?? '';
    final synonyms = (w['synonyms'] as List<dynamic>?)?.cast<String>() ?? [];
    final antonyms = (w['antonyms'] as List<dynamic>?)?.cast<String>() ?? [];
    final upscUsage = w['upscUsage'] as String? ?? '';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text(word, style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('($partOfSpeech)', style: GoogleFonts.inter(fontSize: 13, fontStyle: FontStyle.italic, color: AppTheme.textS(ctx))),
                const SizedBox(height: 12),
                _detailRow('Meaning', meaning, Icons.lightbulb_outline_rounded),
                _detailRow('Example', example, Icons.format_quote_rounded),
                _detailRow('Synonyms', synonyms.join(', '), Icons.swap_horiz_rounded),
                if (antonyms.isNotEmpty)
                  _detailRow('Antonyms', antonyms.join(', '), Icons.compare_arrows_rounded),
                _detailRow('UPSC Usage', upscUsage, Icons.school_rounded),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _toggleLearned(index);
                          Navigator.pop(ctx);
                        },
                        icon: Icon(_learnedWords.contains(id) ? Icons.undo_rounded : Icons.check_rounded),
                        label: Text(_learnedWords.contains(id) ? 'Unlearn' : 'Mark Learned'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
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

  Widget _detailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.inter(fontSize: 13, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'Governance': return AppTheme.accentViolet;
      case 'Economy': return AppTheme.warningOrange;
      case 'Diplomacy': return const Color(0xFF448AFF);
      case 'Environment': return const Color(0xFF4CAF50);
      case 'Ethics': return const Color(0xFF8D6E63);
      case 'Social': return const Color(0xFFE91E63);
      case 'Legal': return const Color(0xFF607D8B);
      default: return AppTheme.primaryColor;
    }
  }

}
