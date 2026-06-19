import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/theme.dart';
import '../../widgets/glass_widgets.dart';

/// ──────────────────────────────────────────────────────────────────────────────
/// PYQ Screen — Previous Year UPSC Questions organized by year & subject.
/// Includes Prelims MCQs and Mains questions with model answers.
/// ──────────────────────────────────────────────────────────────────────────────
class PYQScreen extends StatefulWidget {
  const PYQScreen({super.key});

  @override
  State<PYQScreen> createState() => _PYQScreenState();
}

class _PYQScreenState extends State<PYQScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _selectedYear = '2024';
  String _selectedSubject = 'All';
  int? _expandedIndex;

  static const _years = ['2024', '2023', '2022'];

  static const _subjects = [
    'All', 'Polity', 'Economy', 'History', 'Geography',
    'Science & Tech', 'Environment', 'International Relations',
    'Ethics', 'Essay',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() => _expandedIndex = null);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: 'Previous Year Questions',
      extendBodyBehindAppBar: false,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.primaryColor,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textS(context),
          labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [Tab(text: 'Prelims'), Tab(text: 'Mains')],
        ),
      ),
      child: Column(
        children: [
          // Year selector
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _years.length,
              itemBuilder: (_, i) {
                final yr = _years[i];
                final sel = yr == _selectedYear;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(yr, style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppTheme.textP(context),
                    )),
                    selected: sel,
                    selectedColor: AppTheme.primaryColor,
                    backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.06),
                    side: BorderSide.none,
                    onSelected: (_) => setState(() {
                      _selectedYear = yr;
                      _expandedIndex = null;
                    }),
                  ),
                );
              },
            ),
          ),

          // Subject filter
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _subjects.length,
              itemBuilder: (_, i) {
                final sub = _subjects[i];
                final sel = sub == _selectedSubject;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _selectedSubject = sub;
                      _expandedIndex = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? AppTheme.accentViolet.withValues(alpha: 0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: sel ? Border.all(color: AppTheme.accentViolet, width: 1) : null,
                      ),
                      child: Text(sub, style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? AppTheme.accentViolet : AppTheme.textS(context),
                      )),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Questions list
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildPrelimsList(context),
                _buildMainsList(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrelimsList(BuildContext context) {
    final questions = _getPrelimsQuestions();
    final filtered = _selectedSubject == 'All'
        ? questions
        : questions.where((q) => q['subject'] == _selectedSubject).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.quiz_rounded, size: 48, color: AppTheme.textT(context)),
            const SizedBox(height: 12),
            Text('No questions for this filter', style: GoogleFonts.inter(color: AppTheme.textS(context))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final q = filtered[i];
        final expanded = _expandedIndex == i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(q['subject'] ?? '', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                    ),
                    const Spacer(),
                    Text('Q${i + 1}', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textT(context))),
                  ],
                ),
                const SizedBox(height: 10),
                Text(q['question'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.5)),
                const SizedBox(height: 10),
                // Options
                ...List.generate((q['options'] as List).length, (oi) {
                  final opt = q['options'][oi];
                  final isCorrect = oi == (q['answer'] as int);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: expanded && isCorrect
                            ? AppTheme.successGreen.withValues(alpha: 0.1)
                            : AppTheme.primaryColor.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: expanded && isCorrect
                            ? Border.all(color: AppTheme.successGreen, width: 1.5)
                            : null,
                      ),
                      child: Row(
                        children: [
                          Text('${String.fromCharCode(65 + oi)}. ', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textS(context))),
                          Expanded(child: Text(opt, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textP(context), height: 1.4))),
                          if (expanded && isCorrect)
                            Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 18),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _expandedIndex = expanded ? null : i);
                  },
                  child: Row(
                    children: [
                      Icon(expanded ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 16, color: AppTheme.primaryColor),
                      const SizedBox(width: 6),
                      Text(expanded ? 'Hide Answer' : 'Show Answer', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                    ],
                  ),
                ),
                if (expanded && q['explanation'] != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.lightbulb_rounded, size: 14, color: AppTheme.successGreen),
                          const SizedBox(width: 6),
                          Text('Explanation', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.successGreen)),
                        ]),
                        const SizedBox(height: 6),
                        Text(q['explanation'], style: GoogleFonts.inter(fontSize: 12, height: 1.5, color: AppTheme.textP(context))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainsList(BuildContext context) {
    final questions = _getMainsQuestions();
    final filtered = _selectedSubject == 'All'
        ? questions
        : questions.where((q) => q['subject'] == _selectedSubject).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 48, color: AppTheme.textT(context)),
            const SizedBox(height: 12),
            Text('No Mains questions for this filter', style: GoogleFonts.inter(color: AppTheme.textS(context))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final q = filtered[i];
        final expanded = _expandedIndex == i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.accentViolet.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(q['paper'] ?? '', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.accentViolet)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.warningOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${q['marks']} marks', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.warningOrange)),
                    ),
                    const Spacer(),
                    Text(q['subject'] ?? '', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textT(context))),
                  ],
                ),
                const SizedBox(height: 12),
                Text(q['question'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textP(context), height: 1.5)),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _expandedIndex = expanded ? null : i);
                  },
                  child: Row(
                    children: [
                      Icon(expanded ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 16, color: AppTheme.primaryColor),
                      const SizedBox(width: 6),
                      Text(expanded ? 'Hide Approach' : 'Show Approach', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                    ],
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.tips_and_updates_rounded, size: 14, color: AppTheme.primaryColor),
                          const SizedBox(width: 6),
                          Text('Model Approach', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
                        ]),
                        const SizedBox(height: 8),
                        Text(q['approach'] ?? '', style: GoogleFonts.inter(fontSize: 12, height: 1.6, color: AppTheme.textP(context))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── DATA ───

  List<Map<String, dynamic>> _getPrelimsQuestions() {
    final bank = <String, List<Map<String, dynamic>>>{
      '2024': [
        {'subject': 'Polity', 'question': 'Which of the following is/are the function(s) of the Cabinet Secretariat?\n1. Preparation of agenda for Cabinet meetings\n2. Secretarial assistance to Cabinet Committees\n3. Rules of business allocation', 'options': ['1 and 2 only', '2 and 3 only', '1 and 3 only', '1, 2 and 3'], 'answer': 3, 'explanation': 'The Cabinet Secretariat functions directly under the PM and provides secretarial assistance to the Cabinet and its Committees, including preparation of agenda.'},
        {'subject': 'Economy', 'question': 'Consider the following about "Green Bonds":\n1. They are debt instruments for financing environment-friendly projects\n2. SEBI regulates green bonds in India\n3. Only government entities can issue green bonds\nWhich statements are correct?', 'options': ['1 and 2 only', '2 and 3 only', '1 and 3 only', '1, 2 and 3'], 'answer': 0, 'explanation': 'Green bonds finance eco-friendly projects and are regulated by SEBI in India. Both government and private entities can issue them.'},
        {'subject': 'Geography', 'question': 'The Western Ghats are considered a biodiversity hotspot. Which of the following states does NOT have a part of the Western Ghats?', 'options': ['Gujarat', 'Telangana', 'Goa', 'Tamil Nadu'], 'answer': 1, 'explanation': 'The Western Ghats pass through Gujarat, Maharashtra, Goa, Karnataka, Kerala, and Tamil Nadu. Telangana lies on the Deccan Plateau, not along the Western Ghats.'},
        {'subject': 'History', 'question': 'The Poona Pact (1932) was an agreement between:', 'options': ['Jawaharlal Nehru and Muhammad Ali Jinnah', 'Mahatma Gandhi and B.R. Ambedkar', 'Subhas Chandra Bose and the British Government', 'Sardar Patel and the princely states'], 'answer': 1, 'explanation': 'The Poona Pact was signed between Mahatma Gandhi and Dr. B.R. Ambedkar in 1932, replacing separate electorates for Depressed Classes with reserved seats in joint electorates.'},
        {'subject': 'Science & Tech', 'question': 'Which of the following technologies is used by ISRO\'s Gaganyaan mission for crew safety?\n1. Crew Escape System (CES)\n2. Environmental Control Life Support System (ECLSS)\n3. Reusable Launch Vehicle Technology', 'options': ['1 and 2 only', '2 and 3 only', '1 only', '1, 2 and 3'], 'answer': 0, 'explanation': 'Gaganyaan uses CES for emergency escape during launch and ECLSS for cabin atmosphere management. The mission uses an expendable launch vehicle (GSLV Mk III).'},
        {'subject': 'Environment', 'question': 'The "Miyawaki Method" is related to:', 'options': ['Organic farming techniques', 'Urban afforestation', 'Wastewater treatment', 'Soil conservation'], 'answer': 1, 'explanation': 'The Miyawaki Method, developed by Japanese botanist Akira Miyawaki, is a technique for creating dense urban forests using native species, growing trees 10x faster than conventional methods.'},
        {'subject': 'Polity', 'question': 'Article 370 of the Indian Constitution was related to:', 'options': ['Emergency provisions', 'Special status of Jammu & Kashmir', 'Fundamental Rights', 'Directive Principles of State Policy'], 'answer': 1, 'explanation': 'Article 370 granted special autonomous status to the state of Jammu & Kashmir. It was abrogated on 5 August 2019.'},
        {'subject': 'International Relations', 'question': 'The Quad (Quadrilateral Security Dialogue) consists of which four countries?', 'options': ['USA, UK, France, India', 'USA, India, Japan, Australia', 'USA, India, Japan, South Korea', 'USA, India, UK, Australia'], 'answer': 1, 'explanation': 'The Quad is a strategic security dialogue between the United States, India, Japan, and Australia, focusing on a free and open Indo-Pacific.'},
      ],
      '2023': [
        {'subject': 'Polity', 'question': 'Consider the following statements regarding the Anti-Defection Law:\n1. It is contained in the 10th Schedule\n2. The Speaker\'s decision is subject to judicial review\n3. A merger requires at least two-thirds of members\nWhich are correct?', 'options': ['1 and 2 only', '1 and 3 only', '2 and 3 only', '1, 2 and 3'], 'answer': 3, 'explanation': 'All three are correct. The Anti-Defection Law (10th Schedule, 52nd Amendment) allows judicial review of Speaker\'s decisions (Kihoto Hollohan case) and merger needs 2/3 members.'},
        {'subject': 'Economy', 'question': 'Which of the following is/are component(s) of India\'s current account?\n1. Trade in goods\n2. Foreign Direct Investment\n3. Remittances', 'options': ['1 and 3 only', '2 and 3 only', '1 only', '1, 2 and 3'], 'answer': 0, 'explanation': 'Current account includes trade in goods/services, income, and transfers (remittances). FDI falls under the capital account of Balance of Payments.'},
        {'subject': 'History', 'question': 'The Revolt of 1857 started from which regiment?', 'options': ['34th Bengal Native Infantry at Barrackpore', '19th Bengal Native Infantry at Berhampur', 'The cavalry at Meerut', '7th Awadh Irregular Cavalry'], 'answer': 2, 'explanation': 'While Mangal Pandey\'s action at Barrackpore is considered a precursor, the actual revolt began with the cavalry rising at Meerut on 10 May 1857.'},
        {'subject': 'Geography', 'question': 'Which of the following Indian rivers form(s) an estuary?\n1. Narmada\n2. Ganga\n3. Tapi', 'options': ['1 and 3 only', '2 only', '1 only', '1, 2 and 3'], 'answer': 0, 'explanation': 'The Narmada and Tapi are west-flowing rivers forming estuaries. The Ganga forms a delta (Sundarbans) as an east-flowing river.'},
        {'subject': 'Science & Tech', 'question': 'What is the primary purpose of India\'s NavIC (IRNSS)?', 'options': ['Weather prediction', 'Regional navigation system', 'Missile guidance only', 'Deep space communication'], 'answer': 1, 'explanation': 'NavIC (Navigation with Indian Constellation) is India\'s independent regional satellite navigation system providing accurate position information over India and 1500 km beyond.'},
        {'subject': 'Environment', 'question': 'The "Ramsar Convention" is related to:', 'options': ['Conservation of wetlands', 'Climate change mitigation', 'Desertification control', 'Marine pollution prevention'], 'answer': 0, 'explanation': 'The Ramsar Convention (1971) is an intergovernmental treaty for the conservation and wise use of wetlands and their resources.'},
      ],
      '2022': [
        {'subject': 'Economy', 'question': 'Which institution releases the Consumer Price Index (CPI) in India?', 'options': ['RBI', 'NITI Aayog', 'National Statistical Office (NSO)', 'Ministry of Finance'], 'answer': 2, 'explanation': 'The National Statistical Office (NSO), under the Ministry of Statistics, compiles and releases CPI data in India.'},
        {'subject': 'Polity', 'question': 'The "basic structure doctrine" of the Indian Constitution was established in:', 'options': ['Golak Nath case (1967)', 'Kesavananda Bharati case (1973)', 'Minerva Mills case (1980)', 'Maneka Gandhi case (1978)'], 'answer': 1, 'explanation': 'The Basic Structure doctrine was established in the landmark Kesavananda Bharati v. State of Kerala case (1973), which held Parliament cannot alter the basic structure through amendments.'},
        {'subject': 'Geography', 'question': 'Which of the following pairs is/are correctly matched?\n1. Chilika Lake – Odisha\n2. Loktak Lake – Manipur\n3. Wular Lake – Jammu & Kashmir', 'options': ['1 and 2 only', '2 and 3 only', '1 and 3 only', '1, 2 and 3'], 'answer': 3, 'explanation': 'All three are correctly matched. Chilika (Odisha) is Asia\'s largest brackish water lake, Loktak (Manipur) has floating phumdis, and Wular (J&K) is India\'s largest freshwater lake.'},
        {'subject': 'Science & Tech', 'question': 'CRISPR-Cas9 technology is used for:', 'options': ['Renewable energy generation', 'Gene editing', 'Quantum computing', 'Weather modification'], 'answer': 1, 'explanation': 'CRISPR-Cas9 is a revolutionary gene-editing technology that can precisely modify DNA sequences, with applications in medicine, agriculture, and research.'},
        {'subject': 'History', 'question': 'The Indian National Congress was founded in which year?', 'options': ['1883', '1885', '1887', '1890'], 'answer': 1, 'explanation': 'The INC was founded on 28 December 1885 at Gokuldas Tejpal Sanskrit College, Bombay, by Allan Octavian Hume with 72 delegates.'},
      ],
    };

    return bank[_selectedYear] ?? bank['2024']!;
  }

  List<Map<String, dynamic>> _getMainsQuestions() {
    final bank = <String, List<Map<String, dynamic>>>{
      '2024': [
        {'subject': 'Polity', 'paper': 'GS-II', 'marks': 15, 'question': '"The Supreme Court of India has been playing a significant role in the protection of fundamental rights." Discuss with recent examples.', 'approach': 'Introduction: Role of SC as guardian of fundamental rights.\n\nBody:\n- Judicial review power (Art. 13, 32, 226)\n- Recent landmark cases: privacy (Puttaswamy), LGBTQ+ rights (Navtej Johar), Sabarimala\n- PIL mechanism expanding access to justice\n- Challenges: judicial overreach debate, pendency\n\nConclusion: Balance between activism and restraint.'},
        {'subject': 'Economy', 'paper': 'GS-III', 'marks': 15, 'question': 'Critically analyze the impact of digital payment systems on financial inclusion in India.', 'approach': 'Introduction: Digital India and UPI revolution.\n\nBody:\n- UPI growth: ₹200L cr+ transactions, Jan Dhan-Aadhaar-Mobile trinity\n- Positive: Banking the unbanked, reduced cash dependency, MSME empowerment\n- Challenges: Digital divide, cybersecurity, internet access in rural areas\n- Comparison with global models (China\'s WeChat Pay, Kenya\'s M-Pesa)\n\nConclusion: Inclusive digital infrastructure is key.'},
        {'subject': 'International Relations', 'paper': 'GS-II', 'marks': 10, 'question': 'Discuss India\'s role in the Quad and its implications for the Indo-Pacific strategy.', 'approach': 'Introduction: Quad formation and evolution.\n\nBody:\n- Pillars: Maritime security, tech cooperation, vaccine diplomacy, climate\n- India\'s strategic autonomy within Quad framework\n- China\'s reaction and regional dynamics\n- AUKUS complementarity\n\nConclusion: Quad as a platform, not an alliance — India\'s balancing act.'},
        {'subject': 'Ethics', 'paper': 'GS-IV', 'marks': 10, 'question': 'What do you understand by "conflict of interest"? How can public servants manage such conflicts?', 'approach': 'Introduction: Define conflict of interest — personal vs. public duty.\n\nBody:\n- Types: financial, relational, professional\n- Case studies: Government contracts with relatives\' firms, post-retirement jobs\n- Management: Disclosure norms, recusal, cooling-off period, ethics committees\n- International best practices (OECD guidelines)\n\nConclusion: Transparency and institutional mechanisms.'},
        {'subject': 'Essay', 'paper': 'Essay', 'marks': 125, 'question': '"Technology is a useful servant but a dangerous master." Discuss in the context of artificial intelligence.', 'approach': 'Structure:\n\n1. Introduction: Hook with AI\'s dual nature\n2. AI as servant: Healthcare diagnostics, agriculture, governance (e-courts)\n3. AI as master: Deepfakes, job displacement, algorithmic bias, surveillance\n4. India context: AI policy, NITI Aayog strategy, IT Act amendments\n5. Global perspective: EU AI Act, OpenAI developments\n6. Way forward: Responsible AI, regulation, skilling\n7. Conclusion: Human agency must remain central.'},
      ],
      '2023': [
        {'subject': 'Polity', 'paper': 'GS-II', 'marks': 15, 'question': 'Discuss the significance of the 73rd and 74th Constitutional Amendments for local self-governance in India.', 'approach': 'Introduction: Panchayati Raj and urban local bodies framework.\n\nBody:\n- 73rd Amendment: Panchayats — three-tier system, reservations, 11th Schedule\n- 74th Amendment: Municipalities — 12th Schedule, ward committees\n- Achievement: Women\'s political participation, decentralized planning\n- Challenges: Inadequate devolution of 3Fs (funds, functions, functionaries)\n\nConclusion: Vision vs. implementation gap.'},
        {'subject': 'Environment', 'paper': 'GS-III', 'marks': 15, 'question': 'Analyze India\'s commitment to achieve net-zero emissions by 2070. Is it achievable?', 'approach': 'Introduction: COP26 pledge and Panchamrit goals.\n\nBody:\n- India\'s targets: 500 GW non-fossil by 2030, carbon intensity reduction\n- Progress: Solar capacity growth, National Hydrogen Mission, EV policy\n- Challenges: Coal dependency (70% power), financing gap (\$10T needed)\n- Enabling factors: ISA, green bonds, PLI for solar manufacturing\n\nConclusion: Ambitious but requires international support and technology transfer.'},
        {'subject': 'History', 'paper': 'GS-I', 'marks': 10, 'question': 'Evaluate the contribution of Subhas Chandra Bose to India\'s freedom struggle.', 'approach': 'Introduction: Bose as a revolutionary leader.\n\nBody:\n- Forward Bloc, escape to Germany/Japan, INA formation\n- Azad Hind Government, \"Give me blood\" speech\n- INA trials — galvanized national sentiment, impacted British Indian Army loyalty\n- Ideological difference with Gandhi — means, not ends\n\nConclusion: Complementary role in achieving independence.'},
      ],
      '2022': [
        {'subject': 'Economy', 'paper': 'GS-III', 'marks': 15, 'question': 'Discuss the role of the Reserve Bank of India in maintaining financial stability during economic crises.', 'approach': 'Introduction: RBI as the central bank and its mandate.\n\nBody:\n- Tools: Monetary policy (repo, CRR, SLR), regulatory measures\n- COVID response: TLTRO, moratorium, restructuring schemes\n- Inflation targeting framework (4% ± 2%)\n- Challenges: Maintaining growth-inflation balance, currency management\n\nConclusion: RBI\'s evolving role in a complex global landscape.'},
        {'subject': 'Polity', 'paper': 'GS-II', 'marks': 10, 'question': 'Examine the role of the Election Commission in ensuring free and fair elections in India.', 'approach': 'Introduction: Constitutional mandate (Art. 324) of ECI.\n\nBody:\n- Powers: Model code, voter registration, VVPAT, delimitation inputs\n- Reforms: EVMs, NOTA, electoral bonds (SC struck down), online enrollment\n- Challenges: Criminalization, money power, social media regulation\n- Recent: One Nation One Election debate\n\nConclusion: Institutional integrity as the bedrock of democracy.'},
      ],
    };

    return bank[_selectedYear] ?? bank['2024']!;
  }
}
