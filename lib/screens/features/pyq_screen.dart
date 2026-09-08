import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_fonts.dart';

import '../../config/category_style.dart';
import '../../config/theme.dart';
import '../../models/pyq_question.dart';
import '../../services/pyq_service.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// PYQScreen — Previous Year Questions, organised by paper → year → subject.
///
/// Prelims questions are attemptable (tap an option, get immediate feedback and
/// the explanation); Mains questions expand to a model answer structure.
/// Questions come from the offline seed bank merged with the live `pyqs`
/// collection harvested by the daily scraper.
/// ──────────────────────────────────────────────────────────────────────────────
class PYQScreen extends StatefulWidget {
  const PYQScreen({super.key});

  @override
  State<PYQScreen> createState() => _PYQScreenState();
}

class _PYQScreenState extends State<PYQScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late final TextEditingController _searchCtrl;

  List<PyqQuestion> _all = const [];
  PyqProgress _progress = const PyqProgress();
  bool _loading = true;

  int? _year; // null = all years
  String? _subject; // null = all subjects
  String _query = '';
  bool _onlyBookmarked = false;
  bool _onlyUnattempted = false;

  /// Chosen option index per question id (Prelims).
  final Map<String, int> _chosen = {};

  /// Question ids whose answer/approach panel is open.
  final Set<String> _revealed = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final questions = await PyqService.load(forceRefresh: force);
    final progress = await PyqService.loadProgress();
    if (!mounted) return;
    setState(() {
      _all = questions;
      _progress = progress;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  PyqType get _activeType => _tabCtrl.index == 0 ? PyqType.prelims : PyqType.mains;

  /// Everything of the active type, before the year/subject facets — used to
  /// build the facet lists so a chip is never shown with a zero count.
  List<PyqQuestion> get _scoped {
    return _all.where((q) {
      if (q.type != _activeType) return false;
      if (_query.isNotEmpty && !q.searchText.contains(_query)) return false;
      if (_onlyBookmarked && !_progress.bookmarked.contains(q.id)) return false;
      if (_onlyUnattempted && _progress.attempted.contains(q.id)) return false;
      return true;
    }).toList();
  }

  List<PyqQuestion> get _visible {
    return _scoped.where((q) {
      if (_year != null && q.year != _year) return false;
      if (_subject != null && q.subject != _subject) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: 'Previous Year Questions',
      extendBodyBehindAppBar: false,
      actions: [
        IconButton(
          tooltip: _onlyBookmarked ? 'Showing saved' : 'Show saved only',
          icon: Icon(
            _onlyBookmarked ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
            color: _onlyBookmarked ? AppTheme.primaryColor : null,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() => _onlyBookmarked = !_onlyBookmarked);
          },
        ),
        IconButton(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: _showOptions,
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.primaryColor,
          indicatorWeight: 3,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textS(context),
          labelStyle: AppFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle: AppFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: const [Tab(text: 'Prelims'), Tab(text: 'Mains')],
        ),
      ),
      child: _loading ? _skeleton() : _body(),
    );
  }

  // ── BODY ───────────────────────────────────────────────────────────────────
  Widget _body() {
    final visible = _visible;

    return RefreshIndicator(
      color: AppTheme.primaryColor,
      onRefresh: () => _load(force: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(child: _statsBar()),
          SliverToBoxAdapter(child: _searchField()),
          SliverToBoxAdapter(child: _yearRow()),
          SliverToBoxAdapter(child: _subjectRow()),
          SliverToBoxAdapter(child: _resultCount(visible.length)),
          if (visible.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _empty())
          else
            SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, i == visible.length - 1 ? 110 : 12),
                child: _activeType == PyqType.prelims
                    ? _prelimsCard(visible[i], i + 1)
                    : _mainsCard(visible[i], i + 1),
              ),
            ),
        ],
      ),
    );
  }

  // ── STATS ──────────────────────────────────────────────────────────────────
  Widget _statsBar() {
    final ofType = _all.where((q) => q.type == _activeType).toList();
    final years = ofType.map((q) => q.year).toSet().toList()..sort();
    final span = years.isEmpty ? '—' : (years.length == 1 ? '${years.first}' : '${years.first}–${years.last}');
    final accuracy = _progress.attempted.isEmpty ? null : (_progress.accuracy * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: AppTheme.premiumCard(context, radius: 18),
        child: Row(
          children: [
            _stat('${ofType.length}', 'Questions', AppTheme.primaryColor),
            _divider(),
            _stat(span, 'Years', AppTheme.accentViolet),
            _divider(),
            _stat('${_progress.answered}', 'Attempted', AppTheme.warningOrange),
            _divider(),
            _stat(accuracy == null ? '—' : '$accuracy%', 'Accuracy', AppTheme.successGreen),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label, Color color) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              child: Text(
                value,
                style: AppFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppFonts.inter(fontSize: 10.5, color: AppTheme.textT(context), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );

  Widget _divider() => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: AppTheme.divider(context),
      );

  // ── FILTERS ────────────────────────────────────────────────────────────────
  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        style: AppFonts.inter(fontSize: 14, color: AppTheme.textP(context)),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search questions, topics, keywords…',
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: AppTheme.textT(context)),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _yearRow() {
    final years = _all.where((q) => q.type == _activeType).map((q) => q.year).toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    return SizedBox(
      height: 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        itemCount: years.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return _pill(
              label: 'All years',
              selected: _year == null,
              color: AppTheme.primaryColor,
              onTap: () => setState(() => _year = null),
            );
          }
          final y = years[i - 1];
          return _pill(
            label: '$y',
            selected: _year == y,
            color: AppTheme.primaryColor,
            onTap: () => setState(() => _year = _year == y ? null : y),
          );
        },
      ),
    );
  }

  Widget _subjectRow() {
    // Counts respect the active year so the chips describe what is actually there.
    final pool = _scoped.where((q) => _year == null || q.year == _year);
    final counts = <String, int>{};
    for (final q in pool) {
      counts[q.subject] = (counts[q.subject] ?? 0) + 1;
    }
    final subjects = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    if (subjects.isEmpty) return const SizedBox(height: 8);

    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        itemCount: subjects.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return _pill(
              label: 'All subjects',
              selected: _subject == null,
              color: AppTheme.accentViolet,
              dense: true,
              onTap: () => setState(() => _subject = null),
            );
          }
          final s = subjects[i - 1];
          return _pill(
            label: '$s  ${counts[s]}',
            selected: _subject == s,
            color: CategoryStyle.of(s).color,
            dense: true,
            onTap: () => setState(() => _subject = _subject == s ? null : s),
          );
        },
      ),
    );
  }

  Widget _pill({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
    bool dense = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14, vertical: dense ? 7 : 8),
          decoration: BoxDecoration(
            color: selected ? color : color.withValues(alpha: AppTheme.isDark(context) ? 0.12 : 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.18),
            ),
          ),
          child: Text(
            label,
            style: AppFonts.inter(
              fontSize: dense ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : (AppTheme.isDark(context) ? Colors.white70 : color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultCount(int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          Text(
            n == 1 ? '1 question' : '$n questions',
            style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textS(context)),
          ),
          const Spacer(),
          if (_year != null || _subject != null || _query.isNotEmpty || _onlyBookmarked || _onlyUnattempted)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() {
                  _year = null;
                  _subject = null;
                  _query = '';
                  _onlyBookmarked = false;
                  _onlyUnattempted = false;
                });
              },
              child: Row(
                children: [
                  const Icon(Icons.refresh_rounded, size: 14, color: AppTheme.primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    'Clear filters',
                    style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── PRELIMS CARD ───────────────────────────────────────────────────────────
  Widget _prelimsCard(PyqQuestion q, int index) {
    final style = CategoryStyle.of(q.subject);
    final chosen = _chosen[q.id];
    final revealed = _revealed.contains(q.id) || chosen != null;

    return Container(
      decoration: AppTheme.premiumCard(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(q, style, index),
          const SizedBox(height: 12),
          Text(
            q.question,
            style: AppFonts.plusJakartaSans(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textP(context),
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),

          if (q.isAnswerable)
            ...List.generate(q.options.length, (i) => _option(q, i, chosen, revealed))
          else if (q.hasUnkeyedOptions) ...[
            // Straight from an official UPSC paper: the question and its options
            // are authentic, but UPSC publishes papers without answer keys.
            ...List.generate(q.options.length, (i) => _option(q, i, null, false, locked: true)),
            const SizedBox(height: 2),
            _note(
              Icons.verified_outlined,
              'Official UPSC paper. UPSC does not publish an answer key, so this one is not scored.',
              AppTheme.accentViolet,
            ),
          ] else
            _note(
              Icons.info_outline_rounded,
              'Reference question — options were not published with this extract.',
              AppTheme.warningOrange,
            ),

          if (q.explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (!revealed)
              _linkButton(
                icon: Icons.visibility_rounded,
                label: 'Show explanation',
                onTap: () => setState(() => _revealed.add(q.id)),
              )
            else
              _explanationBox(q.explanation),
          ],
        ],
      ),
    );
  }

  Widget _note(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.insetSurface(context, accent: color),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppFonts.inter(fontSize: 11.5, color: AppTheme.textS(context), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(PyqQuestion q, int i, int? chosen, bool revealed, {bool locked = false}) {
    final isCorrect = i == q.answer;
    final isChosen = chosen == i;

    Color bg = AppTheme.isDark(context)
        ? Colors.white.withValues(alpha: 0.04)
        : const Color(0xFF0F172A).withValues(alpha: 0.03);
    Color? border;
    Color textColor = AppTheme.textP(context);
    IconData? trailing;
    Color? trailingColor;

    if (revealed) {
      if (isCorrect) {
        bg = AppTheme.successGreen.withValues(alpha: 0.12);
        border = AppTheme.successGreen;
        trailing = Icons.check_circle_rounded;
        trailingColor = AppTheme.successGreen;
      } else if (isChosen) {
        bg = AppTheme.errorRed.withValues(alpha: 0.10);
        border = AppTheme.errorRed;
        trailing = Icons.cancel_rounded;
        trailingColor = AppTheme.errorRed;
      } else {
        textColor = AppTheme.textS(context);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: (locked || chosen != null)
            ? null
            : () async {
                HapticFeedback.selectionClick();
                setState(() {
                  _chosen[q.id] = i;
                  _revealed.add(q.id);
                });
                await PyqService.recordAttempt(q.id, isCorrect);
                final updated = await PyqService.loadProgress();
                if (mounted) setState(() => _progress = updated);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: border ?? (AppTheme.isDark(context)
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFF0F172A).withValues(alpha: 0.06)),
              width: border != null ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (border ?? AppTheme.textT(context)).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  String.fromCharCode(97 + i),
                  style: AppFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: border ?? AppTheme.textS(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  q.options[i],
                  style: AppFonts.inter(fontSize: 13, color: textColor, height: 1.45),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Icon(trailing, size: 18, color: trailingColor),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _explanationBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: AppTheme.insetSurface(context, accent: AppTheme.successGreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_rounded, size: 14, color: AppTheme.successGreen),
              const SizedBox(width: 6),
              Text(
                'Explanation',
                style: AppFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.successGreen),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            text,
            style: AppFonts.inter(fontSize: 12.5, height: 1.6, color: AppTheme.textP(context)),
          ),
        ],
      ),
    );
  }

  // ── MAINS CARD ─────────────────────────────────────────────────────────────
  Widget _mainsCard(PyqQuestion q, int index) {
    final style = CategoryStyle.of(q.subject);
    final open = _revealed.contains(q.id);

    return Container(
      decoration: AppTheme.premiumCard(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(q, style, index),
          const SizedBox(height: 12),
          Text(
            q.question,
            style: AppFonts.plusJakartaSans(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textP(context),
              height: 1.55,
            ),
          ),
          if (q.approach.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (!open)
              _linkButton(
                icon: Icons.tips_and_updates_rounded,
                label: 'Show model approach',
                onTap: () => setState(() => _revealed.add(q.id)),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: AppTheme.insetSurface(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tips_and_updates_rounded, size: 14, color: AppTheme.primaryColor),
                        const SizedBox(width: 6),
                        Text(
                          'Model approach',
                          style: AppFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      q.approach,
                      style: AppFonts.inter(fontSize: 12.5, height: 1.7, color: AppTheme.textP(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _linkButton(
                icon: Icons.visibility_off_rounded,
                label: 'Hide approach',
                onTap: () => setState(() => _revealed.remove(q.id)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── SHARED PIECES ──────────────────────────────────────────────────────────
  Widget _cardHeader(PyqQuestion q, CategoryStyle style, int index) {
    final saved = _progress.bookmarked.contains(q.id);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: style.soft(context),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 11, color: style.onSoft(context)),
              const SizedBox(width: 5),
              Text(
                q.subject,
                style: AppFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: style.onSoft(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _badge('${q.year}', AppTheme.textS(context)),
        if (q.type == PyqType.mains) ...[
          const SizedBox(width: 6),
          if (q.paper.isNotEmpty) _badge(q.paper, AppTheme.accentViolet),
          if (q.marks > 0) ...[
            const SizedBox(width: 6),
            _badge('${q.marks}m', AppTheme.warningOrange),
          ],
        ],
        const Spacer(),
        if (q.source != 'UPSC')
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: q.source == 'UPSC Pattern'
                  ? 'Written to this year\'s syllabus emphasis — practice, not a record of the paper'
                  : 'Harvested from ${q.source}',
              child: Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.textT(context)),
            ),
          ),
        Text('Q$index', style: AppFonts.inter(fontSize: 10.5, color: AppTheme.textT(context))),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () async {
            HapticFeedback.selectionClick();
            final marks = await PyqService.toggleBookmark(q.id);
            if (!mounted) return;
            setState(() {
              _progress = PyqProgress(
                attempted: _progress.attempted,
                correct: _progress.correct,
                bookmarked: marks,
              );
            });
          },
          child: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            size: 18,
            color: saved ? AppTheme.primaryColor : AppTheme.textT(context),
          ),
        ),
      ],
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: AppFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: color),
        ),
      );

  Widget _linkButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.primaryColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor),
          ),
        ],
      ),
    );
  }

  // ── STATES ─────────────────────────────────────────────────────────────────
  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded, size: 32, color: AppTheme.primaryColor.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 16),
            Text(
              'No questions match these filters',
              style: AppFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textP(context),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different year or subject, or clear the filters.',
              style: AppFonts.inter(fontSize: 12.5, color: AppTheme.textS(context), height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: 5,
      itemBuilder: (_, i) => Container(
        height: i == 0 ? 74 : 150,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: AppTheme.shimmerBox(context, radius: 18),
      ),
    );
  }

  void _showOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // A bare Column in a default sheet is capped near half the screen height;
      // with large system font scaling the two ListTiles overflow it. Scroll
      // instead of clipping.
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: AppTheme.card(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.divider(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SwitchListTile(
              value: _onlyUnattempted,
              activeThumbColor: AppTheme.primaryColor,
              title: Text('Unattempted only', style: AppFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('Hide questions you have already answered',
                  style: AppFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
              onChanged: (v) {
                setState(() => _onlyUnattempted = v);
                Navigator.pop(sheetContext);
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded, color: AppTheme.errorRed),
              title: Text('Reset my attempts', style: AppFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text('Clears answered/accuracy, keeps saved questions',
                  style: AppFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
              onTap: () async {
                Navigator.pop(sheetContext);
                await PyqService.resetProgress();
                final updated = await PyqService.loadProgress();
                if (!mounted) return;
                setState(() {
                  _progress = updated;
                  _chosen.clear();
                  _revealed.clear();
                });
              },
            ),
          ],
        ),
        ),
      ),
    );
  }
}
