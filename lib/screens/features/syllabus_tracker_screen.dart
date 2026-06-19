import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../config/theme.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// SyllabusTrackerScreen — Track preparation progress across all UPSC papers.
/// ──────────────────────────────────────────────────────────────────────────────
class SyllabusTrackerScreen extends StatefulWidget {
  const SyllabusTrackerScreen({super.key});

  @override
  State<SyllabusTrackerScreen> createState() => _SyllabusTrackerScreenState();
}

class _SyllabusTrackerScreenState extends State<SyllabusTrackerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map<String, bool> _completedTopics = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _papers.length, vsync: this);
    _loadProgress();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('syllabus_progress');
    if (data != null) {
      setState(() {
        _completedTopics = Map<String, bool>.from(json.decode(data));
      });
    }
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('syllabus_progress', json.encode(_completedTopics));
  }

  void _toggleTopic(String key) {
    setState(() {
      _completedTopics[key] = !(_completedTopics[key] ?? false);
    });
    _saveProgress();
    HapticFeedback.lightImpact();
  }

  int _paperCompleted(int paperIndex) {
    final paper = _papers[paperIndex];
    int count = 0;
    for (final section in paper.sections) {
      for (final topic in section.topics) {
        final key = '${paper.name}|${section.name}|$topic';
        if (_completedTopics[key] == true) count++;
      }
    }
    return count;
  }

  int _paperTotal(int paperIndex) {
    int count = 0;
    for (final section in _papers[paperIndex].sections) {
      count += section.topics.length;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final totalDone = _completedTopics.values.where((v) => v).length;
    final totalAll = _papers.fold<int>(0, (s, p) => s + p.sections.fold<int>(0, (s2, sec) => s2 + sec.topics.length));

    return GradientScaffold(
      title: 'Syllabus Tracker',
      extendBodyBehindAppBar: false,
      bottom: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        indicatorColor: AppTheme.primaryColor,
        indicatorWeight: 3,
        labelColor: AppTheme.primaryColor,
        unselectedLabelColor: AppTheme.textS(context),
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
        tabAlignment: TabAlignment.start,
        tabs: List.generate(_papers.length, (i) => Tab(text: _papers[i].shortName)),
      ),
      child: Column(
        children: [
          // Overall progress bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressWidget(
                    progress: totalAll > 0 ? totalDone / totalAll : 0,
                    size: 56,
                    strokeWidth: 6,
                    child: Text('${(totalAll > 0 ? totalDone / totalAll * 100 : 0).round()}%',
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primaryColor)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Overall Progress', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                        const SizedBox(height: 4),
                        Text('$totalDone / $totalAll topics covered', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textS(context))),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: totalAll > 0 ? totalDone / totalAll : 0,
                            minHeight: 5,
                            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: List.generate(_papers.length, (i) => _buildPaperView(i)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperView(int paperIndex) {
    final paper = _papers[paperIndex];
    final done = _paperCompleted(paperIndex);
    final total = _paperTotal(paperIndex);

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        // Paper progress summary
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: paper.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$done / $total', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: paper.color)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total > 0 ? done / total : 0,
                    minHeight: 6,
                    backgroundColor: paper.color.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(paper.color),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Sections
        ...paper.sections.map((section) => _buildSection(paper, section)),
      ],
    );
  }

  Widget _buildSection(_Paper paper, _Section section) {
    int sectionDone = 0;
    for (final topic in section.topics) {
      final key = '${paper.name}|${section.name}|$topic';
      if (_completedTopics[key] == true) sectionDone++;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: paper.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(section.icon, color: paper.color, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(section.name,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textP(context))),
                ),
                Text('$sectionDone/${section.topics.length}',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: paper.color)),
              ],
            ),
            const SizedBox(height: 10),
            ...section.topics.map((topic) {
              final key = '${paper.name}|${section.name}|$topic';
              final done = _completedTopics[key] == true;
              return InkWell(
                onTap: () => _toggleTopic(key),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: done ? paper.color : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: done ? paper.color : AppTheme.textT(context),
                            width: 1.5,
                          ),
                        ),
                        child: done
                            ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          topic,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: done ? AppTheme.textT(context) : AppTheme.textP(context),
                            decoration: done ? TextDecoration.lineThrough : null,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
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

  // ── All UPSC Papers & Syllabus ──
  static final _papers = <_Paper>[
    _Paper('GS-I', 'GS-I', AppTheme.accentViolet, [
      _Section('Indian Heritage & Culture', Icons.temple_hindu_rounded, [
        'Salient aspects of Art Forms, Literature, Architecture',
        'Ancient Indian History — Indus Valley to Gupta Period',
        'Medieval Indian History — Sultanate, Mughal, Bhakti & Sufi',
        'Modern Indian History — British rule, Freedom struggle',
        'Post-independence consolidation and reorganization',
      ]),
      _Section('World History', Icons.public_rounded, [
        'Industrial Revolution and its impact',
        'World Wars — causes, consequences',
        'Colonization and Decolonization',
        'Political philosophies — Communism, Capitalism, Socialism',
        'Redrawing of national boundaries',
      ]),
      _Section('Indian Society', Icons.people_rounded, [
        'Salient features of Indian Society — Diversity',
        'Role of Women and Women\'s organizations',
        'Population and associated issues',
        'Poverty and developmental issues',
        'Urbanization — problems and remedies',
        'Communalism, Regionalism, Secularism',
        'Effects of Globalization on Indian society',
        'Social Empowerment',
      ]),
      _Section('Physical Geography', Icons.landscape_rounded, [
        'Geophysical phenomena — Earthquakes, Tsunami, Volcanoes',
        'Geographical features — Mountains, Plateaus, Plains',
        'Distribution of key natural resources',
        'Critical geographical features — Water bodies, Ice-caps',
        'Oceanography and ocean currents',
        'Climate and weather patterns',
      ]),
    ]),
    _Paper('GS-II', 'GS-II', const Color(0xFF448AFF), [
      _Section('Indian Constitution & Polity', Icons.account_balance_rounded, [
        'Constitution — historical underpinnings, evolution, features',
        'Fundamental Rights and Duties',
        'Directive Principles of State Policy',
        'Parliament and State Legislatures — structure, functioning',
        'Executive and Judiciary — structure, organization',
        'Separation of Powers and dispute redressal',
        'Constitutional amendments and their significance',
        'Federal structure and its challenges',
        'Panchayati Raj and Municipalities',
        'Representation of People\'s Act',
        'Statutory, Regulatory and Quasi-judicial bodies',
      ]),
      _Section('Governance & Social Justice', Icons.gavel_rounded, [
        'Government policies and interventions in various sectors',
        'Welfare schemes for vulnerable sections',
        'Performance of welfare schemes — SHGs, education, health',
        'Issues relating to development and management of social sector',
        'Important aspects of Governance',
        'E-governance applications, models, successes, limitations',
        'Role of Civil Services in a democracy',
        'Transparency and Accountability — RTI, Citizens\' Charters',
      ]),
      _Section('International Relations', Icons.language_rounded, [
        'India and its neighbors — relations',
        'Bilateral, regional and global groupings',
        'Effect of other countries\' policies on India',
        'Indian Diaspora',
        'Important International institutions, agencies — structure, mandate',
      ]),
    ]),
    _Paper('GS-III', 'GS-III', const Color(0xFFFF6B6B), [
      _Section('Indian Economy', Icons.trending_up_rounded, [
        'Indian Economy — Planning, Mobilization of resources, Growth',
        'Inclusive growth and issues arising from it',
        'Government Budgeting — Fiscal policy, Taxation',
        'Major crops, irrigation systems, issues of MSP',
        'Food processing, Land reforms, Liberalization',
        'Cropping patterns in various parts of the country',
        'Effects of liberalization on the Economy',
        'Infrastructure — Energy, Ports, Roads, Airports, Railways',
        'Investment models and their significance',
      ]),
      _Section('Science & Technology', Icons.science_rounded, [
        'Developments in S&T and applications in daily life',
        'Achievements of Indians in S&T — Indigenization',
        'Awareness in IT, Space, Computers, Robotics, Nano-technology',
        'Bio-technology and issues relating to IPR',
      ]),
      _Section('Environment & Ecology', Icons.eco_rounded, [
        'Conservation, Environmental pollution and degradation',
        'Environmental Impact Assessment',
        'Disaster Management — types, mitigation strategies',
        'Climate Change and its impact',
        'Biodiversity and its conservation',
        'Environmental laws and policies',
      ]),
      _Section('Internal Security', Icons.security_rounded, [
        'Security challenges — Linkages of organized crime with terrorism',
        'Role of external state and non-state actors',
        'Challenges to internal security in border areas',
        'Cyber security — threats and responses',
        'Money laundering, Black money — challenges and prevention',
        'Role of media and social networking sites in internal security',
      ]),
    ]),
    _Paper('GS-IV (Ethics)', 'GS-IV', const Color(0xFF8D6E63), [
      _Section('Ethics and Human Interface', Icons.balance_rounded, [
        'Ethics — essence, determinants and consequences of Ethics',
        'Dimensions of Ethics — private and public relationships',
        'Human Values — role of family, society and education',
        'Attitude — content, structure, function, influence',
        'Aptitude and foundational values for Civil Service',
        'Emotional Intelligence — concepts and utility',
        'Contributions of moral thinkers — India and World',
        'Public/Civil Service values and Ethics in public administration',
      ]),
      _Section('Integrity & Probity', Icons.verified_rounded, [
        'Probity in Governance — concept and philosophical basis',
        'Information sharing and transparency in government',
        'RTI, Codes of Ethics, Codes of Conduct, Citizens\' Charters',
        'Challenges of corruption — institutional measures',
        'Work culture, quality of service delivery, utilization of public funds',
        'Ethical concerns and dilemmas in government institutions',
        'Laws, Rules, Regulations and Conscience as source of ethical guidance',
        'Accountability and ethical governance',
      ]),
    ]),
    _Paper('Essay', 'Essay', const Color(0xFF9C27B0), [
      _Section('Essay Practice Topics', Icons.edit_note_rounded, [
        'Philosophical/Abstract topics — Freedom, Democracy, Justice',
        'Social issues — Gender, Caste, Education, Health',
        'Economic topics — Development, Poverty, Globalization',
        'Science & Technology — AI, Space, Innovation',
        'Environmental topics — Climate, Conservation, Sustainability',
        'Governance & Polity — Federalism, Decentralization',
        'International Relations — India\'s role, Globalization',
        'Culture & Society — Diversity, Unity, Heritage',
      ]),
    ]),
    _Paper('CSAT', 'CSAT', const Color(0xFF607D8B), [
      _Section('Comprehension', Icons.menu_book_rounded, [
        'Reading Comprehension — passages and inference',
        'Interpersonal skills including communication',
        'Logical reasoning and analytical ability',
        'Decision making and problem solving',
      ]),
      _Section('Quantitative Aptitude', Icons.calculate_rounded, [
        'Basic numeracy — numbers and their relations, orders of magnitude',
        'Data interpretation — charts, graphs, tables',
        'Ratio/Proportion, Percentages, Simple & Compound Interest',
        'Time & Work, Speed & Distance, Profit & Loss',
        'Probability, Permutation & Combination',
      ]),
    ]),
  ];
}

class _Paper {
  final String name;
  final String shortName;
  final Color color;
  final List<_Section> sections;
  const _Paper(this.name, this.shortName, this.color, this.sections);
}

class _Section {
  final String name;
  final IconData icon;
  final List<String> topics;
  const _Section(this.name, this.icon, this.topics);
}
