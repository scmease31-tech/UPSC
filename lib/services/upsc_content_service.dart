import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Fetches simplified UPSC-relevant content from public APIs
/// (Wikipedia current events, government data, news summaries).
/// Caches results locally for offline access.
class UpscContentService {
  static const _cacheKey = 'upsc_web_content_cache';
  static const _cacheTimestampKey = 'upsc_web_content_ts';
  static const _cacheDuration = Duration(hours: 6);

  /// Fetch current affairs from Wikipedia's current events portal.
  /// Returns simplified bullet points relevant to UPSC.
  static Future<List<Map<String, dynamic>>> fetchCurrentAffairs() async {
    // Check cache first
    final cached = await _getCachedContent();
    if (cached != null) return cached;

    final results = <Map<String, dynamic>>[];

    // Fetch from multiple sources in parallel for faster loading
    final futures = await Future.wait([
      _fetchWikipediaCurrentEvents().catchError((e) {
        debugPrint('Wiki fetch error: $e');
        return <Map<String, dynamic>>[];
      }),
      _fetchGovernmentSchemes().catchError((e) {
        debugPrint('Gov content fetch error: $e');
        return <Map<String, dynamic>>[];
      }),
    ]);

    for (final content in futures) {
      if (content.isNotEmpty) results.addAll(content);
    }

    // Always include static curated content
    results.addAll(_curatedUpscContent());

    // Cache results
    if (results.isNotEmpty) await _cacheContent(results);

    return results;
  }

  /// Fetch Wikipedia current events and extract India-relevant items.
  static Future<List<Map<String, dynamic>>> _fetchWikipediaCurrentEvents() async {
    final now = DateTime.now();
    final year = now.year;

    final url = Uri.parse(
      'https://en.wikipedia.org/api/rest_v1/page/html/Portal:Current_events/${_monthName(now.month)}_$year',
    );

    final response = await http.get(url, headers: {
      'User-Agent': 'UPSCDailyEdge/1.0 (educational app)',
    }).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];

    // Parse HTML content and extract India-related events
    final body = response.body;
    final items = _extractIndiaEvents(body);

    if (items.isEmpty) return [];

    return [
      {
        'category': 'Current Affairs',
        'title': 'Latest Current Affairs (${_monthName(now.month)} $year)',
        'facts': items.take(20).toList(),
        'source': 'Wikipedia Current Events',
        'isFromWeb': true,
      },
    ];
  }

  /// Extract India-relevant events from Wikipedia HTML.
  static List<String> _extractIndiaEvents(String html) {
    final events = <String>[];

    // Use RegExp to extract list items from HTML
    final liRegex = RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true);
    final tagRegex = RegExp(r'<[^>]+>');

    for (final match in liRegex.allMatches(html)) {
      var text = match.group(1) ?? '';
      text = text.replaceAll(tagRegex, '').trim();
      text = text.replaceAll(RegExp(r'\s+'), ' ');

      if (text.length < 20 || text.length > 300) continue;

      // Filter for India-relevant keywords
      final indiaKeywords = [
        'india', 'indian', 'delhi', 'mumbai', 'modi', 'bjp', 'congress',
        'isro', 'rbi', 'supreme court', 'parliament', 'lok sabha',
        'rajya sabha', 'kashmir', 'himalaya', 'monsoon', 'cricket',
        'rupee', 'gdp', 'election', 'pm ', 'prime minister',
        'south asia', 'pakistan', 'china', 'bangladesh', 'sri lanka',
        'asean', 'g20', 'brics', 'un ', 'united nations',
        'climate', 'nuclear', 'missile', 'defence', 'defense',
        'economy', 'trade', 'inflation', 'oil', 'energy',
      ];

      final lowerText = text.toLowerCase();
      final isRelevant = indiaKeywords.any((kw) => lowerText.contains(kw));

      if (isRelevant) {
        events.add(_simplifyText(text));
      }
    }

    return events;
  }

  /// Fetch curated government schemes content.
  static Future<List<Map<String, dynamic>>> _fetchGovernmentSchemes() async {
    // Use Wikipedia API to fetch summaries of important Indian topics
    final topics = [
      'Make_in_India',
      'Digital_India',
      'Atmanirbhar_Bharat',
      'National_Education_Policy_2020',
    ];

    final facts = <String>[];

    for (final topic in topics) {
      try {
        final url = Uri.parse(
          'https://en.wikipedia.org/api/rest_v1/page/summary/$topic',
        );
        final response = await http.get(url, headers: {
          'User-Agent': 'UPSCDailyEdge/1.0 (educational app)',
        }).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final extract = data['extract'] as String? ?? '';
          if (extract.length > 50) {
            // Take first 2 sentences as a simplified fact
            final sentences = extract.split(RegExp(r'(?<=[.!?])\s+'));
            final simplified = sentences.take(2).join(' ');
            if (simplified.length > 30) {
              facts.add(simplified);
            }
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (facts.isEmpty) return [];

    return [
      {
        'category': 'Governance',
        'title': 'Government Initiatives (Updated)',
        'facts': facts,
        'source': 'Wikipedia Summaries',
        'isFromWeb': true,
      },
    ];
  }

  /// Simplify text for UPSC aspirants — remove jargon, shorten.
  static String _simplifyText(String text) {
    // Remove citations like [1], [2]
    text = text.replaceAll(RegExp(r'\[\d+\]'), '');
    // Trim extra spaces
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Capitalize first letter
    if (text.isNotEmpty) {
      text = text[0].toUpperCase() + text.substring(1);
    }
    return text;
  }

  static String _monthName(int month) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return months[month];
  }

  // ── Cache management ──

  static Future<List<Map<String, dynamic>>?> _getCachedContent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tsStr = prefs.getString(_cacheTimestampKey);
      if (tsStr == null) return null;

      final ts = DateTime.tryParse(tsStr);
      if (ts == null || DateTime.now().difference(ts) > _cacheDuration) {
        return null;
      }

      final cached = prefs.getString(_cacheKey);
      if (cached == null) return null;

      final list = json.decode(cached) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _cacheContent(List<Map<String, dynamic>> content) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(content));
      await prefs.setString(_cacheTimestampKey, DateTime.now().toIso8601String());
    } catch (_) {
      // Non-critical — skip caching
    }
  }

  /// Clear cached web content.
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheTimestampKey);
  }

  // ── Curated static content that supplements Firestore & local data ──

  static List<Map<String, dynamic>> _curatedUpscContent() {
    return [
      {
        'category': 'Current Affairs',
        'title': 'Important Current Affairs 2025-26',
        'facts': [
          'India\'s GDP growth rate for 2025-26 projected at 6.5-7% by RBI. Focus on capital expenditure and infrastructure-led growth',
          'India assumes G20 troika role alongside South Africa (presidency) and Brazil (past presidency). Continuity of New Delhi Declaration priorities',
          'ISRO\'s Gaganyaan mission: First uncrewed test flight completed. Human spaceflight targeted for 2025. Astronaut training in Bengaluru & Russia',
          'India-Middle East-Europe Economic Corridor (IMEC): Feasibility studies ongoing. Rail + shipping connectivity. Strategic counter to China\'s BRI',
          'National Green Hydrogen Mission progress: Pilot projects in steel, transport, and ammonia sectors. Electrolyzer manufacturing incentives under SIGHT',
          'Digital Personal Data Protection Act 2023: Rules being framed. Data Protection Board of India being constituted. Consent framework implementation',
          'One Nation One Election: Law Commission studying feasibility. Constitutional amendment required. Simultaneous elections for Lok Sabha & state assemblies',
          'India\'s semiconductor mission: Micron\'s Gujarat fab, Tata-PSMC in Dholera. Goal: reduce chip import dependency. USD 10B+ investment planned',
          'Uniform Civil Code debate: Law Commission report submitted. Article 44 (DPSP) mandate. States like Uttarakhand, Goa have implemented versions',
          'Lateral Entry into Civil Services: UPSC recruitment for joint secretary posts from private sector. 45 positions across ministries. Meritocracy vs reservation debate',
          'India\'s defence exports cross USD 2.5 billion. BrahMos sold to Philippines. Tejas LCA interest from Malaysia, Argentina. Atmanirbhar in defence manufacturing',
          'Supreme Court on Electoral Bonds: Struck down as unconstitutional (2024). Right to information of voters vs right to privacy of donors. SBI disclosure',
          'Women-led development: Nari Shakti Vandan Adhiniyam (33% reservation), Lakhpati Didi, self-help groups. Women in workforce: 37% LFPR (PLFS)',
          'India Space Policy 2023: IN-SPACe promotes private participation. Skyroot, Agnikul, Dhruva Space — Indian space startups. Target: USD 50B space economy',
          'Climate finance negotiations: India demands USD 1 trillion/year from developed nations. Loss & Damage Fund operationalized at COP-28. Green bonds issued',
        ],
        'source': 'Curated',
        'isFromWeb': false,
      },
      {
        'category': 'Economy',
        'title': 'Budget & Economic Updates 2025-26',
        'facts': [
          'Union Budget 2025-26: Capital expenditure ₹11.11 lakh crore (3.4% of GDP). Infrastructure focus: roads, railways, smart cities',
          'Tax reforms: New income tax regime made default. Simplified slabs. Standard deduction increased. Corporate tax stability at 25%',
          'Fiscal deficit target: 4.5% of GDP for 2025-26. Revenue deficit declining. Aim for 3% FRBM target by 2028',
          'Foreign Exchange Reserves: ~USD 650 billion. Import cover of 10+ months. RBI intervenes to manage rupee volatility (73-84 range)',
          'India\'s merchandise exports: USD 450 billion target. PLI driving electronics, pharma exports. Services exports: USD 340+ billion (IT, business services)',
          'Cryptocurrency regulation: 30% tax + 1% TDS. Virtual Digital Assets framework. RBI CBDC (e-Rupee) retail pilot in 15 cities',
          'Green bonds: India issued sovereign green bonds worth ₹16,000 crore. Used for renewable energy, clean transport, water management',
          'Privatization & disinvestment: Strategic sale of IDBI Bank. LIC partial listing. Monetization of brownfield assets via NMP pipeline',
          'GIFT IFSC: Gujarat International Finance Tec-City. International financial services hub. Tax benefits, regulatory ease. Smart regulation',
          'PM Surya Ghar Muft Bijli Yojana: Free electricity up to 300 units/month via rooftop solar. 1 crore households target. ₹75,000 crore scheme',
        ],
        'source': 'Curated',
        'isFromWeb': false,
      },
      {
        'category': 'Science & Technology',
        'title': 'Recent Science & Tech Breakthroughs',
        'facts': [
          'ISRO SPADEX mission: Space Docking Experiment — India became 4th nation to achieve space docking. Critical for Gaganyaan & space station plans',
          'Aditya-L1 breakthrough: Detected solar wind patterns & coronal mass ejections from L1 point. Data helping predict space weather affecting Earth',
          'India\'s AI regulation approach: Risk-based framework proposed. AI Advisory Council. Focus on responsible AI. No blanket regulation — sector-specific',
          'Quantum technology: QKD (Quantum Key Distribution) demonstrated over 300 km fiber. DRDO, ISRO collaborating on quantum communication',
          'BharOS: Indian mobile operating system developed by IIT Madras. Focus on security, no pre-installed apps. Alternative to Android for strategic devices',
          'India\'s EV ecosystem: FAME-III expected. Battery localizing with ACC PLI. Lithium reserves found in J&K (5.9 million tonnes, Reasi district)',
          'Gene therapy advances: India approved CAR-T cell therapy for blood cancers. NexCAR19 by IIT-Bombay & ImmunoACT — world\'s most affordable',
          'Digital Agriculture: Agri Stack for farmer data. Kisan Drone, precision farming. Satellite imagery for crop insurance. DBT for PM-KISAN',
          'Deep Ocean Mission: Samudrayaan — manned submersible MATSYA 6000 for 6,000m depth. Mineral exploration, biodiversity, desalination tech',
          '6G research: India launched Bharat 6G Alliance. THz communication research at IITs. Standard development for 2030 deployment',
        ],
        'source': 'Curated',
        'isFromWeb': false,
      },
    ];
  }
}
