import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import '../../config/theme.dart';
import '../../services/firestore_content_service.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// QuickRevisionScreen — Condensed topic-wise notes for rapid revision.
/// Organized by UPSC GS Papers with expandable sections.
/// ──────────────────────────────────────────────────────────────────────────────
class QuickRevisionScreen extends StatefulWidget {
  const QuickRevisionScreen({super.key});

  @override
  State<QuickRevisionScreen> createState() => _QuickRevisionScreenState();
}

class _QuickRevisionScreenState extends State<QuickRevisionScreen> {
  final ScrollController _scrollController = ScrollController();
  String _selectedPaper = 'GS-I';
  int? _expandedTopic;
  Map<String, List<Map<String, dynamic>>> _topicsByPaper = {};
  bool _loading = true;
  bool _hasError = false;

  static const _papers = ['GS-I', 'GS-II', 'GS-III', 'GS-IV', 'CSAT'];

  static const _paperDescriptions = {
    'GS-I': 'History, Geography, Society',
    'GS-II': 'Polity, Governance, IR',
    'GS-III': 'Economy, Environment, S&T',
    'GS-IV': 'Ethics, Integrity, Aptitude',
    'CSAT': 'Comprehension, Reasoning, Math',
  };

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    try {
      final all = await FirestoreContentService.getRevisionNotes();
      final grouped = FirestoreContentService.groupByPaper(all);
      if (mounted) setState(() { _topicsByPaper = grouped; _loading = false; });
    } catch (e) {
      debugPrint('Quick revision load error: $e');
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return GradientScaffold(
        title: 'Quick Revision',
        extendBodyBehindAppBar: false,
        child: Center(child: Lottie.asset('assets/animations/loading.json', width: 120, height: 120)),
      );
    }
    if (_hasError) {
      return GradientScaffold(
        title: 'Quick Revision',
        extendBodyBehindAppBar: false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.textT(context)),
              const SizedBox(height: 12),
              Text('Failed to load notes', style: GoogleFonts.inter(color: AppTheme.textS(context))),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () { setState(() { _loading = true; _hasError = false; }); _loadNotes(); },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final topics = _topicsByPaper[_selectedPaper] ?? [];

    return GradientScaffold(
      title: 'Quick Revision',
      extendBodyBehindAppBar: false,
      child: Column(
        children: [
          // Paper selector
          SizedBox(
            height: 82,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _papers.length,
              itemBuilder: (_, i) {
                final paper = _papers[i];
                final sel = paper == _selectedPaper;
                final colors = [
                  AppTheme.primaryColor, AppTheme.accentViolet,
                  AppTheme.warningOrange, AppTheme.successGreen,
                  const Color(0xFF448AFF),
                ];
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _selectedPaper = paper;
                        _expandedTopic = null;
                      });
                    },
                    child: Container(
                      width: 110,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? colors[i] : colors[i].withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: sel ? null : Border.all(color: colors[i].withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(paper, style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w800,
                            color: sel ? Colors.white : colors[i],
                          )),
                          const SizedBox(height: 2),
                          Text(_paperDescriptions[paper] ?? '', style: GoogleFonts.inter(
                            fontSize: 9, color: sel ? Colors.white70 : AppTheme.textT(context),
                          ), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Topics list
          Expanded(
            child: topics.isEmpty
                ? Center(
                    child: Text('No notes available for this paper',
                        style: GoogleFonts.inter(color: AppTheme.textS(context))),
                  )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              physics: const BouncingScrollPhysics(),
              itemCount: topics.length,
              itemBuilder: (_, i) {
                final topic = topics[i];
                final expanded = _expandedTopic == i;
                final points = List<String>.from(topic['points'] ?? []);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        // Topic header
                        InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _expandedTopic = expanded ? null : i);
                          },
                          borderRadius: BorderRadius.circular(22),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _getTopicIcon(topic['icon'] as String? ?? 'book'),
                                    color: AppTheme.primaryColor, size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(topic['title'] ?? '', style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context),
                                      )),
                                      Text('${points.length} key points', style: GoogleFonts.inter(
                                        fontSize: 11, color: AppTheme.textT(context),
                                      )),
                                    ],
                                  ),
                                ),
                                AnimatedRotation(
                                  turns: expanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textT(context)),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Expanded content
                        AnimatedCrossFade(
                          firstChild: const SizedBox(width: double.infinity),
                          secondChild: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              children: [
                                const Divider(height: 1),
                                const SizedBox(height: 12),
                                ...points.map((p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        width: 6, height: 6,
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(p, style: GoogleFonts.inter(
                                          fontSize: 13, height: 1.5, color: AppTheme.textP(context),
                                        )),
                                      ),
                                    ],
                                  ),
                                )),
                                if (topic['mnemonic'] != null) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.warningOrange.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: AppTheme.warningOrange.withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.lightbulb_rounded, size: 16, color: AppTheme.warningOrange),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text('Mnemonic: ${topic['mnemonic']}', style: GoogleFonts.inter(
                                            fontSize: 12, fontWeight: FontWeight.w600,
                                            color: AppTheme.warningOrange,
                                          )),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 200),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTopicIcon(String name) {
    return FirestoreContentService.getRevisionIcon(name);
  }
}
