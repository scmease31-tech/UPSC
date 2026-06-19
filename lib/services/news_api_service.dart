import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Fetches UPSC-relevant news from free public APIs (no API key required).
/// Sources:
///   1. Google News RSS — India + UPSC topics
///   2. Wikipedia Current Events Portal — daily world events
/// Caches results for 2 hours to reduce network calls.
class NewsApiService {
  static const _userAgent = 'UPSCDailyEdge/1.0 (educational app)';
  static const _timeout = Duration(seconds: 15);
  static const _cacheTTL = Duration(hours: 2);
  static const _cacheKey = 'news_api_cache';
  static const _cacheTimestampKey = 'news_api_ts';

  // In-memory cache
  static List<Map<String, dynamic>>? _memCache;
  static DateTime? _memCacheTime;

  /// UPSC-relevant search topics to cycle through for comprehensive coverage.
  static const _upscTopics = [
    'India government policy',
    'India Supreme Court verdict',
    'India economy GDP',
    'India foreign affairs diplomacy',
    'India environment climate',
    'India defence military',
    'India science technology ISRO',
    'India education reform',
    'India Parliament bill legislation',
    'India social welfare scheme',
  ];

  /// Category mapping — keywords to UPSC categories.
  static const _categoryKeywords = {
    'Polity': [
      'parliament', 'supreme court', 'high court', 'constitution', 'election',
      'governor', 'president', 'bill', 'legislation', 'judiciary', 'fundamental',
      'amendment', 'lok sabha', 'rajya sabha', 'speaker', 'cabinet', 'minister',
      'panchayat', 'municipality', 'federal', 'state government', 'verdict',
      'petition', 'writ', 'article', 'schedule', 'commission', 'tribunal',
    ],
    'Economy': [
      'gdp', 'rbi', 'inflation', 'budget', 'tax', 'gst', 'fiscal', 'trade',
      'export', 'import', 'stock', 'market', 'bank', 'finance', 'investment',
      'fdi', 'startup', 'manufacturing', 'industry', 'employment', 'monetary',
      'subsidy', 'disinvestment', 'privatization', 'sebi', 'npa', 'credit',
    ],
    'International': [
      'un', 'united nations', 'nato', 'g20', 'g7', 'brics', 'bilateral',
      'treaty', 'summit', 'diplomat', 'foreign', 'ambassador', 'sanctions',
      'trade war', 'geopolitical', 'indo-pacific', 'quad', 'asean', 'saarc',
      'china', 'usa', 'russia', 'pakistan', 'afghanistan', 'middle east',
      'europe', 'africa', 'global', 'international', 'world', 'imf',
    ],
    'Environment': [
      'climate', 'pollution', 'deforestation', 'biodiversity', 'wildlife',
      'forest', 'carbon', 'emission', 'renewable', 'solar', 'green',
      'ngt', 'environment', 'ecology', 'conservation', 'water', 'river',
      'drought', 'flood', 'disaster', 'cop', 'paris agreement', 'ozone',
    ],
    'Science & Tech': [
      'isro', 'space', 'satellite', 'ai', 'artificial intelligence', 'cyber',
      'digital', 'technology', 'innovation', 'research', 'drdo', 'missile',
      'nuclear', 'quantum', 'biotech', 'genome', 'vaccine', 'pharma',
      'semiconductor', '5g', 'internet', 'robotics', 'drone', 'it',
    ],
    'Social Issues': [
      'caste', 'reservation', 'gender', 'women', 'child', 'education',
      'health', 'poverty', 'tribal', 'minority', 'migration', 'population',
      'urbanization', 'rural', 'literacy', 'malnutrition', 'sanitation',
      'housing', 'inequality', 'human rights', 'ngo', 'welfare', 'census',
    ],
    'Government Schemes': [
      'scheme', 'yojana', 'mission', 'programme', 'initiative', 'ayushman',
      'swachh', 'ujjwala', 'pm kisan', 'mudra', 'jan dhan', 'make in india',
      'digital india', 'skill india', 'smart city', 'amrit', 'gram sadak',
      'mnrega', 'nrega', 'midday meal', 'beti bachao', 'atal', 'pradhan mantri',
    ],
  };

  /// Fetch latest UPSC-relevant news from multiple free sources.
  /// Returns a list of news items ready for display.
  static Future<List<Map<String, dynamic>>> fetchLatestNews({bool forceRefresh = false}) async {
    // Check in-memory cache
    if (!forceRefresh && _memCache != null && _memCacheTime != null) {
      if (DateTime.now().difference(_memCacheTime!) < _cacheTTL) {
        return _memCache!;
      }
    }

    // Check disk cache
    if (!forceRefresh) {
      final diskCached = await _getDiskCache();
      if (diskCached != null) {
        _memCache = diskCached;
        _memCacheTime = DateTime.now();
        return diskCached;
      }
    }

    debugPrint('[NewsAPI] Fetching fresh UPSC news...');

    final allNews = <Map<String, dynamic>>[];
    final seenTitles = <String>{};

    // Fetch from multiple UPSC topics in parallel (pick 4 random topics + 1 general)
    final topicsToFetch = <String>['India UPSC current affairs'];
    final now = DateTime.now();
    final dayIndex = now.day % _upscTopics.length;
    for (int i = 0; i < 4; i++) {
      topicsToFetch.add(_upscTopics[(dayIndex + i) % _upscTopics.length]);
    }

    final futures = topicsToFetch.map((topic) => _fetchGoogleNewsRss(topic).catchError((e) {
      debugPrint('[NewsAPI] Error fetching "$topic": $e');
      return <Map<String, dynamic>>[];
    }));

    final results = await Future.wait(futures);

    for (final items in results) {
      for (final item in items) {
        final title = (item['title'] as String? ?? '').toLowerCase().trim();
        // Deduplicate by similar titles
        if (title.isNotEmpty && !seenTitles.any((s) => _isSimilarTitle(s, title))) {
          seenTitles.add(title);
          allNews.add(item);
        }
      }
    }

    // Also fetch from professional Indian news sources
    final proFeeds = await _fetchProfessionalNewsFeeds().catchError((e) {
      debugPrint('[NewsAPI] Professional feeds error: $e');
      return <Map<String, dynamic>>[];
    });

    for (final item in proFeeds) {
      final title = (item['title'] as String? ?? '').toLowerCase().trim();
      if (title.isNotEmpty && !seenTitles.any((s) => _isSimilarTitle(s, title))) {
        seenTitles.add(title);
        allNews.add(item);
      }
    }

    // Sort by date (newest first)
    allNews.sort((a, b) {
      final dateA = a['publishedAt'] as DateTime? ?? DateTime(2000);
      final dateB = b['publishedAt'] as DateTime? ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    // Limit to 50 items
    final finalNews = allNews.take(50).toList();

    // Cache
    _memCache = finalNews;
    _memCacheTime = DateTime.now();
    await _setDiskCache(finalNews);

    debugPrint('[NewsAPI] Total unique news items: ${finalNews.length}');
    return finalNews;
  }

  /// Fetch news from Google News RSS feed (no API key needed).
  static Future<List<Map<String, dynamic>>> _fetchGoogleNewsRss(String query) async {
    final encoded = Uri.encodeComponent(query);
    final url = Uri.parse(
      'https://news.google.com/rss/search?q=$encoded&hl=en-IN&gl=IN&ceid=IN:en',
    );

    final response = await http.get(url, headers: {
      'User-Agent': _userAgent,
    }).timeout(_timeout);

    if (response.statusCode != 200) return [];

    final items = _parseRssItems(response.body);
    return items.where((item) {
      // Filter out entertainment/sports/celebrity news
      final title = (item['title'] as String? ?? '').toLowerCase();
      return !_isIrrelevantNews(title);
    }).take(8).toList();
  }

  /// Professional Indian news RSS feed URLs (no API key required).
  static const _professionalFeeds = [
    // The Hindu — National news
    'https://www.thehindu.com/news/national/feeder/default.rss',
    // The Hindu — International
    'https://www.thehindu.com/news/international/feeder/default.rss',
    // Indian Express — India section
    'https://indianexpress.com/section/india/feed/',
    // Indian Express — Political Pulse
    'https://indianexpress.com/section/political-pulse/feed/',
    // NDTV — India
    'https://feeds.feedburner.com/ndtvnews-india-news',
    // LiveMint — Politics
    'https://www.livemint.com/rss/politics',
    // LiveMint — Economy
    'https://www.livemint.com/rss/economy',
  ];

  /// Fetch news from professional Indian newspaper RSS feeds.
  static Future<List<Map<String, dynamic>>> _fetchProfessionalNewsFeeds() async {
    debugPrint('[NewsAPI] Fetching professional news feeds...');
    final allItems = <Map<String, dynamic>>[];

    // Fetch all feeds in parallel
    final futures = _professionalFeeds.map((feedUrl) async {
      try {
        final response = await http.get(
          Uri.parse(feedUrl),
          headers: {'User-Agent': _userAgent},
        ).timeout(_timeout);

        if (response.statusCode != 200) return <Map<String, dynamic>>[];

        final items = _parseRssItems(response.body);
        // Override source name from RSS feed domain
        final source = _sourceNameFromUrl(feedUrl);
        for (final item in items) {
          item['source'] = source;
        }
        return items.where((item) {
          final title = (item['title'] as String? ?? '').toLowerCase();
          return !_isIrrelevantNews(title);
        }).take(6).toList();
      } catch (e) {
        debugPrint('[NewsAPI] Feed error ($feedUrl): $e');
        return <Map<String, dynamic>>[];
      }
    });

    final results = await Future.wait(futures);
    for (final items in results) {
      allItems.addAll(items);
    }

    debugPrint('[NewsAPI] Professional feeds returned ${allItems.length} items');
    return allItems;
  }

  /// Extract a readable source name from feed URL.
  static String _sourceNameFromUrl(String url) {
    if (url.contains('thehindu.com')) return 'The Hindu';
    if (url.contains('indianexpress.com')) return 'Indian Express';
    if (url.contains('ndtv')) return 'NDTV';
    if (url.contains('livemint.com')) return 'LiveMint';
    if (url.contains('pib.gov.in')) return 'PIB';
    if (url.contains('hindustantimes.com')) return 'Hindustan Times';
    return 'News';
  }

  /// Parse RSS XML into structured news items.
  static List<Map<String, dynamic>> _parseRssItems(String xml) {
    final items = <Map<String, dynamic>>[];
    final itemPattern = RegExp(r'<item>(.*?)</item>', dotAll: true);
    final titlePattern = RegExp(r'<title>(.*?)</title>', dotAll: true);
    final linkPattern = RegExp(r'<link>(.*?)</link>', dotAll: true);
    final descPattern = RegExp(r'<description>(.*?)</description>', dotAll: true);
    final pubDatePattern = RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true);
    final sourcePattern = RegExp(r'<source[^>]*>(.*?)</source>', dotAll: true);

    for (final match in itemPattern.allMatches(xml)) {
      final itemXml = match.group(1) ?? '';
      final title = _stripHtml(_xmlDecode(titlePattern.firstMatch(itemXml)?.group(1) ?? ''));
      final link = _xmlDecode(linkPattern.firstMatch(itemXml)?.group(1) ?? '');
      final desc = _stripHtml(_xmlDecode(descPattern.firstMatch(itemXml)?.group(1) ?? ''));
      final pubDateStr = pubDatePattern.firstMatch(itemXml)?.group(1) ?? '';
      final source = _stripHtml(_xmlDecode(sourcePattern.firstMatch(itemXml)?.group(1) ?? ''));

      if (title.isEmpty) continue;

      final pubDate = _parseRssDate(pubDateStr);
      final category = _detectCategory('$title $desc');
      final months = [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];

      items.add({
        'title': title,
        'summary': desc.isNotEmpty ? desc : title,
        'source': source.isNotEmpty ? source : 'Google News',
        'category': category,
        'publishedAt': pubDate,
        'dateStr': '${pubDate.day} ${months[pubDate.month]} ${pubDate.year}',
        'url': link,
        'isFromApi': true,
      });
    }

    return items;
  }

  /// Detect UPSC category from text content.
  static String _detectCategory(String text) {
    final lower = text.toLowerCase();
    int bestScore = 0;
    String bestCategory = 'General';

    for (final entry in _categoryKeywords.entries) {
      int score = 0;
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestCategory = entry.key;
      }
    }

    return bestCategory;
  }

  /// Check if content is relevant to India or UPSC topics.
  static bool _isIndiaOrUpscRelevant(String text) {
    final lower = text.toLowerCase();
    const relevantTerms = [
      'india', 'indian', 'delhi', 'mumbai', 'parliament', 'modi',
      'supreme court', 'high court', 'lok sabha', 'rajya sabha',
      'rbi', 'isro', 'drdo', 'niti', 'union', 'pradhan mantri',
      'south asia', 'bilateral', 'g20', 'brics', 'un general',
      'climate', 'world bank', 'imf', 'who', 'unesco',
      'nuclear', 'missile', 'defence', 'border', 'kashmir',
      'trade agreement', 'sanction', 'election', 'constitutional',
    ];
    return relevantTerms.any((term) => lower.contains(term));
  }

  /// Check if news is irrelevant (entertainment, sports, celebrity).
  static bool _isIrrelevantNews(String title) {
    const irrelevant = [
      'cricket', 'ipl', 'bollywood', 'movie', 'film', 'actor', 'actress',
      'celebrity', 'entertainment', 'box office', 'trailer', 'song',
      'album', 'concert', 'wedding', 'divorce', 'gossip', 'controversy',
      'bigg boss', 'reality show', 'football', 'soccer', 'tennis',
      'wrestling', 'boxing', 'f1', 'formula', 'nba', 'nfl',
    ];
    return irrelevant.any((term) => title.contains(term));
  }

  /// Check if two titles are similar enough to be duplicates.
  static bool _isSimilarTitle(String a, String b) {
    if (a == b) return true;
    // Check if one contains most of the other
    final wordsA = a.split(RegExp(r'\s+')).where((w) => w.length > 3).toSet();
    final wordsB = b.split(RegExp(r'\s+')).where((w) => w.length > 3).toSet();
    if (wordsA.isEmpty || wordsB.isEmpty) return false;
    final overlap = wordsA.intersection(wordsB).length;
    final minLen = wordsA.length < wordsB.length ? wordsA.length : wordsB.length;
    return minLen > 0 && overlap / minLen > 0.6;
  }

  /// Parse RSS date string to DateTime.
  static DateTime _parseRssDate(String dateStr) {
    try {
      // RSS format: "Wed, 26 Mar 2026 10:30:00 GMT"
      final parts = dateStr.trim().split(' ');
      if (parts.length >= 5) {
        final day = int.tryParse(parts[1]) ?? 1;
        final monthStr = parts[2].toLowerCase();
        final year = int.tryParse(parts[3]) ?? DateTime.now().year;
        final months = {
          'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
          'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
        };
        final month = months[monthStr] ?? 1;
        return DateTime(year, month, day);
      }
    } catch (_) {}
    return DateTime.now();
  }

  // ─── XML / HTML helpers ──────────────────────────────────────────────

  static String _xmlDecode(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  static String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  // ─── Disk cache helpers ──────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> _getDiskCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt(_cacheTimestampKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((now - ts) > _cacheTTL.inMilliseconds) return null;

      final json = prefs.getString(_cacheKey);
      if (json == null) return null;

      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      // Restore DateTime objects
      for (final item in list) {
        if (item['publishedAt'] is String) {
          item['publishedAt'] = DateTime.tryParse(item['publishedAt'] as String) ?? DateTime.now();
        } else if (item['publishedAt'] is int) {
          item['publishedAt'] = DateTime.fromMillisecondsSinceEpoch(item['publishedAt'] as int);
        }
      }
      return list;
    } catch (e) {
      debugPrint('[NewsAPI] Disk cache read error: $e');
      return null;
    }
  }

  static Future<void> _setDiskCache(List<Map<String, dynamic>> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Convert DateTime to ISO string for JSON serialization
      final serializable = items.map((item) {
        final copy = Map<String, dynamic>.from(item);
        if (copy['publishedAt'] is DateTime) {
          copy['publishedAt'] = (copy['publishedAt'] as DateTime).toIso8601String();
        }
        return copy;
      }).toList();
      await prefs.setString(_cacheKey, jsonEncode(serializable));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[NewsAPI] Disk cache write error: $e');
    }
  }

  /// Clear all caches (useful for force refresh).
  static void clearCache() {
    _memCache = null;
    _memCacheTime = null;
  }
}
