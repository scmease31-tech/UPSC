import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Web search service that fetches real content from the internet.
/// Works WITHOUT any API keys — uses free public APIs:
/// - Wikipedia REST API for topic content
/// - DuckDuckGo Instant Answer API for summaries
/// - Google News RSS for current affairs & recent events
/// Provides UPSC-relevant content ready for display.
class WebSearchService {
  static const _cacheKey = 'web_search_cache';
  static const _cacheDuration = Duration(hours: 6);
  static final Map<String, _WebCacheEntry> _memCache = {};
  static const _maxMemCache = 30;

  static const _userAgent = 'UPSCDailyEdge/1.0 (educational app)';
  static const _timeout = Duration(seconds: 15);

  /// Common UPSC abbreviations for query expansion.
  static const _abbreviations = {
    'rbi': 'Reserve Bank of India',
    'sebi': 'Securities and Exchange Board of India',
    'niti': 'NITI Aayog',
    'isro': 'Indian Space Research Organisation',
    'drdo': 'Defence Research and Development Organisation',
    'upsc': 'Union Public Service Commission',
    'ias': 'Indian Administrative Service',
    'nato': 'North Atlantic Treaty Organization',
    'un': 'United Nations',
    'who': 'World Health Organization',
    'imf': 'International Monetary Fund',
    'gdp': 'Gross Domestic Product',
    'gst': 'Goods and Services Tax',
    'fdi': 'Foreign Direct Investment',
    'npa': 'Non Performing Assets',
    'pib': 'Press Information Bureau',
    'cag': 'Comptroller and Auditor General',
    'afspa': 'Armed Forces Special Powers Act',
    'dpsp': 'Directive Principles of State Policy',
    'rti': 'Right to Information',
    'eia': 'Environmental Impact Assessment',
    'ngt': 'National Green Tribunal',
    'nhrc': 'National Human Rights Commission',
    'pesa': 'Panchayats Extension to Scheduled Areas Act',
    'frbm': 'Fiscal Responsibility and Budget Management',
    'msp': 'Minimum Support Price',
    'pds': 'Public Distribution System',
    'mnrega': 'Mahatma Gandhi National Rural Employment Guarantee Act',
    'nrega': 'Mahatma Gandhi National Rural Employment Guarantee Act',
    'pm': 'Prime Minister',
    'sc': 'Supreme Court',
    'hc': 'High Court',
    'cop': 'Conference of Parties',
  };

  /// Hindi/Hinglish to English translations for common UPSC-related terms.
  static const _hindiToEnglish = {
    // Economy & Finance
    'bhav': 'price rate',
    'daam': 'price cost',
    'kimat': 'price value',
    'sona': 'gold',
    'chandi': 'silver',
    'tel': 'oil petroleum',
    'paisa': 'money currency',
    'mudra': 'currency',
    'bazaar': 'market',
    'mehngai': 'inflation price rise',
    'berozgari': 'unemployment',
    'garibi': 'poverty',
    'aarthik': 'economic',
    'vyapar': 'trade commerce',
    'udyog': 'industry',
    'karobar': 'business trade',
    'sampatti': 'property wealth',
    'aay': 'income',
    'kar': 'tax',
    'karz': 'debt loan',
    'nivesh': 'investment',
    'munafa': 'profit',
    // Agriculture
    'kisan': 'farmer agriculture',
    'krishi': 'agriculture farming',
    'fasal': 'crop harvest',
    'khadya': 'food grain',
    'kheti': 'farming cultivation',
    'sinchai': 'irrigation',
    // Governance & Politics
    'sarkar': 'government',
    'mantri': 'minister',
    'pradhan': 'prime chief',
    'neta': 'leader politician',
    'chunav': 'election',
    'sabha': 'assembly parliament',
    'vidhan': 'legislative',
    'rajya': 'state',
    'lok': 'people public',
    'sansad': 'parliament',
    'kanoon': 'law legislation',
    'nyay': 'justice judiciary',
    'samvidhan': 'constitution',
    'adhikar': 'rights',
    'shasan': 'governance administration',
    'panchayat': 'panchayat local governance',
    'nagar': 'urban city municipal',
    'gram': 'village rural',
    'yojana': 'scheme plan',
    // Defence & Security
    'raksha': 'defence defense',
    'sena': 'army military',
    'suraksha': 'security',
    'seemant': 'border',
    'yuddh': 'war conflict',
    'shanti': 'peace',
    // Geography & Environment
    'paryavaran': 'environment',
    'jalvayu': 'climate',
    'jal': 'water',
    'van': 'forest',
    'bhumi': 'land',
    'nadi': 'river',
    'parvat': 'mountain',
    'pradushaan': 'pollution',
    'bhu': 'earth land',
    // Infrastructure & Development
    'bijli': 'electricity power energy',
    'sadak': 'road infrastructure',
    'vikas': 'development',
    'shiksha': 'education',
    'swasthya': 'health',
    // International
    'videsh': 'foreign international',
    'desh': 'country nation',
    // General
    'sthiti': 'situation status',
    'samasya': 'problem issue',
    'niti': 'policy',
    'sudhar': 'reform',
    'badlav': 'change reform',
  };

  /// Keywords that indicate entertainment/media content (not relevant for UPSC).
  static const _entertainmentSignals = [
    'film', 'movie', 'tv series', 'television series', 'episode',
    'season', 'actor', 'actress', 'directed by', 'starring',
    'box office', 'album', 'single (song', 'music video',
    'singer', 'songwriter', 'novel', 'fiction', 'video game',
    'anime', 'manga', 'reality show', 'talk show', 'soap opera',
    'bollywood', 'hollywood', 'tollywood', 'web series',
    'sitcom', 'miniseries', 'telenovela', 'game show',
    'contestant', 'premiered', 'aired', 'broadcast',
    'fictional character', 'comic book', 'superhero',
    'soundtrack', 'discography', 'filmography', 'box set',
  ];

  /// Sections to strip from Wikipedia full content (irrelevant for UPSC searches).
  static const _irrelevantSections = [
    'Honours', 'Awards', 'Honors', 'Personal life', 'Filmography',
    'Discography', 'Bibliography', 'See also', 'References',
    'External links', 'Further reading', 'Notes', 'Footnotes',
    'Awards and honours', 'Decorations', 'Medals', 'Legacy',
    'In popular culture', 'Media', 'Gallery',
  ];

  /// Detect if a query is about recent/current events (contains dates, "latest", etc.).
  static bool _isCurrentAffairsQuery(String query) {
    final lower = query.toLowerCase();
    // Date patterns: "23 march 2026", "march 2026", "2026", "today", "yesterday"
    final datePattern = RegExp(
      r'\b(\d{1,2}[\s/-](jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|'
      r'january|february|march|april|may|june|july|august|september|october|'
      r'november|december)[\s/-]?\d{0,4})\b|'
      r'\b(january|february|march|april|may|june|july|august|september|'
      r'october|november|december)\s+\d{4}\b|'
      r'\b20\d{2}\b|'
      r'\b(today|yesterday|recent|latest|current|new|breaking|announced|'
      r'speech|visit|summit|meeting|launch|inaugurat|passed|bill|policy|'
      r'statement|press conference)\b',
      caseSensitive: false,
    );
    return datePattern.hasMatch(lower);
  }

  /// Build an optimized search query for current affairs.
  static String _buildNewsQuery(String query) {
    final cleaned = _preprocessQuery(query);
    final lower = cleaned.toLowerCase();
    // Already has "UPSC" or "India" context? Use as-is, else add India context
    if (lower.contains('upsc') || lower.contains('india')) {
      return cleaned;
    }
    return '$cleaned India';
  }

  /// Preprocess query: strip emojis, expand abbreviations, normalize.
  static String _preprocessQuery(String query) {
    // Strip emojis and special symbols
    var cleaned = query.replaceAll(RegExp(r'[\p{So}\p{Cn}]+', unicode: true), '').trim();
    // Collapse multiple spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) cleaned = query.trim();
    return cleaned;
  }

  /// Check if content is about entertainment/media (not UPSC-relevant).
  static bool _isEntertainmentContent(String title, String description) {
    final combined = '$title $description'.toLowerCase();
    int hitCount = 0;
    for (final signal in _entertainmentSignals) {
      if (combined.contains(signal)) hitCount++;
    }
    return hitCount >= 2;
  }

  /// Translate Hindi/Hinglish words in query to English equivalents.
  static String _translateHindi(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+'));
    final translated = <String>[];
    bool didTranslate = false;
    for (final word in words) {
      final clean = word.replaceAll(RegExp(r'[^a-z]'), '');
      if (_hindiToEnglish.containsKey(clean)) {
        translated.add(_hindiToEnglish[clean]!);
        didTranslate = true;
      } else {
        translated.add(word);
      }
    }
    if (didTranslate) {
      debugPrint('[WebSearch] Hindi translation: "$query" → "${translated.join(' ')}"');
    }
    return didTranslate ? translated.join(' ') : query;
  }

  /// Add UPSC/India context to translated queries for better search results.
  static String _addUpscContext(String query) {
    final lower = query.toLowerCase();
    // Don't add context if already present
    if (lower.contains('india') || lower.contains('upsc') || lower.contains('government')) {
      return query;
    }
    // Detect economic terms and add India context
    const economicTerms = ['price', 'rate', 'market', 'trade', 'tax', 'inflation',
      'currency', 'investment', 'budget', 'gdp', 'income', 'export', 'import'];
    for (final term in economicTerms) {
      if (lower.contains(term)) return '$query India';
    }
    return query;
  }

  /// Expand abbreviations and translate Hindi terms to improve search.
  static String _expandQuery(String query) {
    final words = query.split(' ');
    final expanded = <String>[];
    bool didExpand = false;
    for (final word in words) {
      final lower = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (_abbreviations.containsKey(lower)) {
        expanded.add(_abbreviations[lower]!);
        didExpand = true;
      } else {
        expanded.add(word);
      }
    }
    final afterAbbrev = didExpand ? expanded.join(' ') : query;
    // Also translate Hindi/Hinglish terms
    final afterHindi = _translateHindi(afterAbbrev);
    return afterHindi;
  }

  /// Main search method — fetches content from multiple web sources.
  /// Returns structured result ready for display, or null on failure.
  static Future<Map<String, dynamic>?> searchWeb(String query, {String? category}) async {
    final cacheKey = '${query.toLowerCase().trim()}_${category ?? ''}';

    // Check memory cache
    if (_memCache.containsKey(cacheKey)) {
      final entry = _memCache[cacheKey]!;
      if (DateTime.now().difference(entry.timestamp) < _cacheDuration) {
        return entry.data;
      }
      _memCache.remove(cacheKey);
    }

    // Check disk cache
    final diskCached = await _getDiskCache(cacheKey);
    if (diskCached != null) {
      _memCache[cacheKey] = _WebCacheEntry(data: diskCached, timestamp: DateTime.now());
      return diskCached;
    }

    final cleanedQuery = _preprocessQuery(query);
    final isCurrentAffairs = _isCurrentAffairsQuery(cleanedQuery);
    debugPrint('[WebSearch] Query: "$query" → cleaned: "$cleanedQuery", isCurrentAffairs: $isCurrentAffairs');

    // Generate expanded query for better Wikipedia results
    final expandedQuery = _expandQuery(cleanedQuery);
    // Also generate a Hindi-translated version of the original cleaned query
    final translatedQuery = _translateHindi(cleanedQuery);
    // If Hindi words were translated, add UPSC context for better results
    final searchQuery = translatedQuery != cleanedQuery
        ? _addUpscContext(translatedQuery)
        : cleanedQuery;

    // Fetch from web sources in parallel — use cleaned and expanded queries
    final results = await Future.wait([
      _fetchWikipedia(searchQuery, expandedQuery: expandedQuery).catchError((e) {
        debugPrint('[WebSearch] Wikipedia error: $e');
        return <String, dynamic>{};
      }),
      _fetchDuckDuckGo(searchQuery).catchError((e) {
        debugPrint('[WebSearch] DuckDuckGo error: $e');
        return <String, dynamic>{};
      }),
      _fetchWikipediaSearch(searchQuery).catchError((e) {
        debugPrint('[WebSearch] Wiki search error: $e');
        return <String, dynamic>{};
      }),
      _fetchGoogleNews(searchQuery).catchError((e) {
        debugPrint('[WebSearch] Google News error: $e');
        return <String, dynamic>{};
      }),
    ]);

    final wikiContent = results[0];
    final ddgContent = results[1];
    final wikiSearchResults = results[2];
    final newsContent = results[3];

    // Merge all sources into a structured result
    final merged = _mergeResults(query, wikiContent, ddgContent, wikiSearchResults, category, newsContent: newsContent, isCurrentAffairs: isCurrentAffairs);

    if (merged != null) {
      // Cache
      if (_memCache.length >= _maxMemCache) {
        _memCache.remove(_memCache.keys.first);
      }
      _memCache[cacheKey] = _WebCacheEntry(data: merged, timestamp: DateTime.now());
      await _setDiskCache(cacheKey, merged);
    }

    return merged;
  }

  /// Fetch Wikipedia article content via REST API.
  /// Searches with multiple query variations and picks the best matching article.
  static Future<Map<String, dynamic>> _fetchWikipedia(String query, {String? expandedQuery}) async {
    // Step 1: Search Wikipedia with original and expanded queries in parallel
    final queriesToTry = <String>{query.trim()};
    if (expandedQuery != null && expandedQuery != query.trim()) {
      queriesToTry.add(expandedQuery.trim());
    }

    final allSearchResults = <Map<String, dynamic>>[];
    for (final q in queriesToTry) {
      final searchEncoded = Uri.encodeComponent(q);
      final searchUrl = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=query&list=search'
        '&srsearch=$searchEncoded&srlimit=5&format=json&utf8=1',
      );

      debugPrint('[WebSearch] Wikipedia search: $searchUrl');

      try {
        final searchResp = await http.get(searchUrl, headers: {
          'User-Agent': _userAgent,
        }).timeout(_timeout);

        if (searchResp.statusCode == 200) {
          final searchData = jsonDecode(searchResp.body) as Map<String, dynamic>;
          final results = searchData['query']?['search'] as List<dynamic>?;
          if (results != null) {
            for (final r in results) {
              if (r is Map<String, dynamic>) {
                allSearchResults.add(r);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[WebSearch] Wikipedia search error for "$q": $e');
      }
    }

    if (allSearchResults.isEmpty) {
      debugPrint('[WebSearch] Wikipedia search: no results for "$query"');
      return {};
    }

    // Step 2: Score and rank results for relevance
    final queryWords = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final scoredResults = <MapEntry<Map<String, dynamic>, double>>[];
    final seenTitles = <String>{};
    for (final result in allSearchResults) {
      final title = (result['title'] as String? ?? '').toLowerCase();
      if (seenTitles.contains(title)) continue;
      seenTitles.add(title);
      final snippet = (result['snippet'] as String? ?? '').toLowerCase();
      double score = 0;
      // Title match is most important
      for (final word in queryWords) {
        if (title.contains(word)) score += 3.0;
        if (snippet.contains(word)) score += 1.0;
      }
      // Exact title match bonus
      if (title == query.toLowerCase().trim()) score += 10.0;
      if (title.contains(query.toLowerCase().trim())) score += 5.0;
      // Word count from article size (prefer longer articles)
      final wordCount = result['wordcount'] as int? ?? 0;
      if (wordCount > 5000) {
        score += 2.0;
      } else if (wordCount > 1000) {
        score += 1.0;
      }

      // Penalize entertainment/media content heavily
      if (_isEntertainmentContent(title, snippet)) {
        score -= 15.0;
        debugPrint('[WebSearch] Penalized entertainment result: "$title"');
      }
      // Penalize disambiguation pages
      if (title.contains('disambiguation') || snippet.contains('may refer to')) {
        score -= 10.0;
      }
      // Penalize results about people (actors, musicians) unless query is about a person
      final personSignals = ['born', 'biography', 'career', 'personal life', 'early life'];
      final isPersonQuery = queryWords.any((w) => ['who', 'biography', 'leader', 'minister', 'president', 'chief'].contains(w));
      if (!isPersonQuery) {
        int personHits = 0;
        for (final signal in personSignals) {
          if (snippet.contains(signal)) personHits++;
        }
        if (personHits >= 2) score -= 5.0;
      }

      scoredResults.add(MapEntry(result, score));
    }
    scoredResults.sort((a, b) => b.value.compareTo(a.value));
    final searchResults = scoredResults.map((e) => e.key).toList();
    debugPrint('[WebSearch] Wikipedia: ${searchResults.length} results, best: "${searchResults.first['title']}" (score: ${scoredResults.first.value})');

    // Skip results with very negative scores (entertainment/irrelevant)
    final validResults = scoredResults.where((e) => e.value > -5).map((e) => e.key).toList();
    if (validResults.isEmpty) {
      debugPrint('[WebSearch] All Wikipedia results filtered as irrelevant');
      return {};
    }

    // Use the first (best) valid match
    final bestTitle = validResults[0]['title'] as String;
    final encodedTitle = Uri.encodeComponent(bestTitle);
    debugPrint('[WebSearch] Wikipedia best match: "$bestTitle"');

    // Step 2: Fetch summary of the best matching article
    final summaryUrl = Uri.parse(
      'https://en.wikipedia.org/api/rest_v1/page/summary/$encodedTitle',
    );

    final response = await http.get(summaryUrl, headers: {
      'User-Agent': _userAgent,
      'Accept': 'application/json',
    }).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final extract = data['extract'] as String? ?? '';
      final description = data['description'] as String? ?? '';

      debugPrint('[WebSearch] Wikipedia got summary: ${extract.length} chars, desc: "$description"');

      // Check if this article is entertainment — if so, try next valid result
      if (_isEntertainmentContent(bestTitle, description) && validResults.length > 1) {
        debugPrint('[WebSearch] Best result "$bestTitle" is entertainment, trying next...');
        final nextTitle = validResults[1]['title'] as String;
        final nextEncoded = Uri.encodeComponent(nextTitle);
        try {
          final nextResp = await http.get(
            Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$nextEncoded'),
            headers: {'User-Agent': _userAgent, 'Accept': 'application/json'},
          ).timeout(_timeout);
          if (nextResp.statusCode == 200) {
            final nextData = jsonDecode(nextResp.body) as Map<String, dynamic>;
            final nextDesc = nextData['description'] as String? ?? '';
            if (!_isEntertainmentContent(nextTitle, nextDesc)) {
              // Use this one instead
              return _buildWikiResult(nextData, nextEncoded, validResults, 2);
            }
          }
        } catch (_) {}
      }

      if (extract.length > 30) {
        return _buildWikiResult(data, encodedTitle, validResults, 1);
      }
    }

    debugPrint('[WebSearch] Wikipedia summary fetch failed: ${response.statusCode}');
    return {};
  }

  /// Helper to build Wikipedia result map from API data.
  static Future<Map<String, dynamic>> _buildWikiResult(
    Map<String, dynamic> data,
    String encodedTitle,
    List<Map<String, dynamic>> validResults,
    int supplementaryStartIndex,
  ) async {
    final extract = data['extract'] as String? ?? '';
    final description = data['description'] as String? ?? '';
    final thumbnail = data['thumbnail'] as Map<String, dynamic>?;
    final imageUrl = thumbnail?['source'] as String?;
    final pageUrl = data['content_urls']?['desktop']?['page'] as String? ?? '';
    final title = data['title'] as String? ?? '';

    // Fetch full content for detail (filtered for relevance)
    final rawFullContent = await _fetchWikipediaFullContent(encodedTitle);
    final fullContent = _filterWikiContent(rawFullContent);

    // Also fetch article from next best result if available
    String supplementaryContent = '';
    if (validResults.length > supplementaryStartIndex) {
      try {
        final nextTitle = Uri.encodeComponent(
          validResults[supplementaryStartIndex]['title'] as String,
        );
        final nextRaw = await _fetchWikipediaFullContent(nextTitle);
        if (nextRaw.isNotEmpty) {
          supplementaryContent = _filterWikiContent(nextRaw);
        }
      } catch (_) {}
    }

    return {
      'title': title,
      'summary': extract,
      'description': description,
      'imageUrl': imageUrl,
      'pageUrl': pageUrl,
      'fullContent': fullContent,
      'supplementaryContent': supplementaryContent,
      'source': 'Wikipedia',
      'hasContent': true,
    };
  }

  /// Fetch full Wikipedia article sections for detailed content.
  static Future<String> _fetchWikipediaFullContent(String encodedTitle) async {
    try {
      final url = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=query&titles=$encodedTitle'
        '&prop=extracts&exintro=false&explaintext=true&exsectionformat=plain'
        '&format=json&redirects=1&utf8=1',
      );

      final response = await http.get(url, headers: {
        'User-Agent': _userAgent,
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final pages = data['query']?['pages'] as Map<String, dynamic>?;
        if (pages != null && pages.isNotEmpty) {
          final page = pages.values.first as Map<String, dynamic>;
          final extract = page['extract'] as String? ?? '';
          debugPrint('[WebSearch] Wikipedia full content: ${extract.length} chars');
          return extract.length > 8000 ? extract.substring(0, 8000) : extract;
        }
      }
    } catch (e) {
      debugPrint('[WebSearch] Full content fetch error: $e');
    }
    return '';
  }

  /// Filter Wikipedia content to remove irrelevant sections like Awards, Honours, etc.
  static String _filterWikiContent(String content) {
    if (content.isEmpty) return content;

    final lines = content.split('\n');
    final filtered = StringBuffer();
    bool skipSection = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        // Check if this line matches known irrelevant section names
        final lowerTrimmed = trimmed.toLowerCase();
        final matchesIrrelevant = _irrelevantSections.any(
          (s) => lowerTrimmed == s.toLowerCase() ||
                 lowerTrimmed.startsWith('${s.toLowerCase()} ') ||
                 lowerTrimmed.endsWith(' ${s.toLowerCase()}'),
        );
        if (matchesIrrelevant && trimmed.length < 60) {
          skipSection = true;
          continue;
        }
        // If it's a new non-irrelevant section header, stop skipping
        if (trimmed.length < 60 && trimmed.length > 2 &&
            !trimmed.contains('.') && !matchesIrrelevant) {
          if (skipSection) skipSection = false;
        }
      }

      if (!skipSection) {
        filtered.writeln(line);
      }
    }

    final result = filtered.toString().trim();
    // Limit to 5000 chars for display, AI gets access to more via supplementary content
    return result.length > 5000 ? result.substring(0, 5000) : result;
  }

  /// Fetch news articles from Google News RSS feed (free, no API key).
  static Future<Map<String, dynamic>> _fetchGoogleNews(String query) async {
    try {
      final newsQuery = _buildNewsQuery(query);
      final encoded = Uri.encodeComponent(newsQuery.trim());
      final url = Uri.parse(
        'https://news.google.com/rss/search?q=$encoded&hl=en-IN&gl=IN&ceid=IN:en',
      );

      debugPrint('[WebSearch] Google News RSS: $url');

      final response = await http.get(url, headers: {
        'User-Agent': _userAgent,
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = response.body;
        // Parse RSS XML manually (lightweight, no extra dependency)
        final items = _parseRssItems(body);
        debugPrint('[WebSearch] Google News: found ${items.length} items');

        if (items.isNotEmpty) {
          // Build summary from top news items
          final summaryBuf = StringBuffer();
          for (final item in items.take(5)) {
            summaryBuf.writeln('• ${item['title']}');
            if ((item['description'] ?? '').isNotEmpty) {
              summaryBuf.writeln('  ${item['description']}');
            }
            summaryBuf.writeln();
          }

          return {
            'hasContent': true,
            'items': items,
            'summary': summaryBuf.toString().trim(),
            'source': 'Google News',
          };
        }
      } else {
        debugPrint('[WebSearch] Google News status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[WebSearch] Google News error: $e');
    }
    return {};
  }

  /// Parse RSS XML items (lightweight parser — no dependency needed).
  static List<Map<String, String>> _parseRssItems(String xml) {
    final items = <Map<String, String>>[];
    final itemPattern = RegExp(r'<item>(.*?)</item>', dotAll: true);
    final titlePattern = RegExp(r'<title>(.*?)</title>', dotAll: true);
    final linkPattern = RegExp(r'<link>(.*?)</link>', dotAll: true);
    final descPattern = RegExp(r'<description>(.*?)</description>', dotAll: true);
    final pubDatePattern = RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true);
    final sourcePattern = RegExp(r'<source[^>]*>(.*?)</source>', dotAll: true);

    for (final match in itemPattern.allMatches(xml)) {
      final itemXml = match.group(1) ?? '';
      final title = _xmlDecode(titlePattern.firstMatch(itemXml)?.group(1) ?? '');
      final link = _xmlDecode(linkPattern.firstMatch(itemXml)?.group(1) ?? '');
      final desc = _xmlDecode(descPattern.firstMatch(itemXml)?.group(1) ?? '');
      final pubDate = pubDatePattern.firstMatch(itemXml)?.group(1) ?? '';
      final source = _xmlDecode(sourcePattern.firstMatch(itemXml)?.group(1) ?? '');

      if (title.isNotEmpty) {
        items.add({
          'title': _stripHtml(title),
          'link': link,
          'description': _stripHtml(desc),
          'pubDate': pubDate,
          'source': source,
        });
      }
      if (items.length >= 10) break;
    }
    return items;
  }

  /// Decode XML entities.
  static String _xmlDecode(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  /// Strip HTML tags from text.
  static String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  /// Fetch DuckDuckGo Instant Answer API for quick summaries.
  static Future<Map<String, dynamic>> _fetchDuckDuckGo(String query) async {
    final encoded = Uri.encodeComponent(query.trim());
    final url = Uri.parse(
      'https://api.duckduckgo.com/?q=$encoded&format=json&no_html=1&skip_disambig=1',
    );

    debugPrint('[WebSearch] DuckDuckGo: $url');

    final response = await http.get(url, headers: {
      'User-Agent': _userAgent,
    }).timeout(_timeout);

    debugPrint('[WebSearch] DuckDuckGo status: ${response.statusCode}, body length: ${response.body.length}');

    if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final abstractText = data['AbstractText'] as String? ?? '';
      final abstractSource = data['AbstractSource'] as String? ?? '';
      final abstractUrl = data['AbstractURL'] as String? ?? '';
      final heading = data['Heading'] as String? ?? '';
      final imageUrl = data['Image'] as String? ?? '';
      final relatedTopics = data['RelatedTopics'] as List<dynamic>? ?? [];

      // Extract related topics (filter out entertainment)
      final related = <Map<String, String>>[];
      for (final topic in relatedTopics.take(12)) {
        if (topic is Map<String, dynamic>) {
          final text = topic['Text'] as String? ?? '';
          final firstUrl = topic['FirstURL'] as String? ?? '';
          if (text.isNotEmpty && !_isEntertainmentContent(text, '')) {
            related.add({'text': text, 'url': firstUrl});
          }
        }
      }

      debugPrint('[WebSearch] DuckDuckGo: abstract=${abstractText.length} chars, related=${related.length}');

      if (abstractText.isNotEmpty || related.isNotEmpty) {
        return {
          'heading': heading,
          'abstract': abstractText,
          'source': abstractSource,
          'url': abstractUrl,
          'imageUrl': imageUrl.isNotEmpty ? 'https://duckduckgo.com$imageUrl' : '',
          'relatedTopics': related,
          'hasContent': true,
        };
      }
    }

    return {};
  }

  /// Search Wikipedia for related articles.
  static Future<Map<String, dynamic>> _fetchWikipediaSearch(String query) async {
    final encoded = Uri.encodeComponent(query.trim());
    final url = Uri.parse(
      'https://en.wikipedia.org/w/api.php?action=opensearch&search=$encoded'
      '&limit=8&format=json&redirects=resolve',
    );

    debugPrint('[WebSearch] Wiki opensearch: $url');

    final response = await http.get(url, headers: {
      'User-Agent': _userAgent,
    }).timeout(_timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as List<dynamic>;
      if (data.length >= 4) {
        final titles = (data[1] as List<dynamic>).cast<String>();
        final descriptions = (data[2] as List<dynamic>).cast<String>();
        final urls = (data[3] as List<dynamic>).cast<String>();

        final articles = <Map<String, String>>[];
        for (var i = 0; i < titles.length; i++) {
          articles.add({
            'title': titles[i],
            'description': i < descriptions.length ? descriptions[i] : '',
            'url': i < urls.length ? urls[i] : '',
          });
        }

        if (articles.isNotEmpty) {
          return {
            'articles': articles,
            'hasContent': true,
          };
        }
      }
    }

    return {};
  }

  /// Get raw web text for Gemini to analyze (called when Gemini is available).
  /// Provides richer context (up to ~4000 chars) so AI has more data for accurate answers.
  static String getWebContextForAI(Map<String, dynamic> webResult) {
    final buf = StringBuffer();
    buf.writeln('=== Web Research Results ===');

    // News content first (most relevant for current affairs)
    if (webResult['news_summary'] != null) {
      final newsSummary = webResult['news_summary'] as String;
      if (newsSummary.isNotEmpty) {
        buf.writeln('\n--- Latest News Headlines ---');
        buf.writeln(newsSummary);
      }
    }

    if (webResult['wiki_summary'] != null) {
      buf.writeln('\n--- Wikipedia Summary ---');
      buf.writeln(webResult['wiki_summary']);
    }
    // Use internal full content keys (prefixed with _ to avoid display)
    if (webResult['_wiki_full_content'] != null) {
      final content = webResult['_wiki_full_content'] as String;
      if (content.isNotEmpty) {
        buf.writeln('\n--- Wikipedia Full Article ---');
        buf.writeln(content.length > 3500 ? content.substring(0, 3500) : content);
      }
    }
    if (webResult['_supplementaryContent'] != null) {
      final supp = webResult['_supplementaryContent'] as String;
      if (supp.isNotEmpty) {
        buf.writeln('\n--- Additional Wikipedia Context ---');
        buf.writeln(supp.length > 1500 ? supp.substring(0, 1500) : supp);
      }
    }
    if (webResult['ddg_abstract'] != null) {
      final abstract_ = webResult['ddg_abstract'] as String;
      if (abstract_.isNotEmpty) {
        buf.writeln('\n--- DuckDuckGo Summary ---');
        buf.writeln(abstract_);
      }
    }
    if (webResult['web_sources'] != null) {
      buf.writeln('\n--- Related Web Articles ---');
      final sources = webResult['web_sources'] as List<dynamic>;
      for (final s in sources.take(8)) {
        if (s is Map) {
          final desc = s['description'] as String? ?? '';
          buf.writeln('• ${s['title']}${desc.isNotEmpty ? ': $desc' : ''}');
        }
      }
    }

    return buf.toString();
  }

  /// Merge results from all sources into a unified display-ready format.
  static Map<String, dynamic>? _mergeResults(
    String query,
    Map<String, dynamic> wiki,
    Map<String, dynamic> ddg,
    Map<String, dynamic> wikiSearch,
    String? category, {
    Map<String, dynamic> newsContent = const {},
    bool isCurrentAffairs = false,
  }) {
    final hasWiki = wiki['hasContent'] == true;
    final hasDdg = ddg['hasContent'] == true;
    final hasSearch = wikiSearch['hasContent'] == true;
    final hasNews = newsContent['hasContent'] == true;

    if (!hasWiki && !hasDdg && !hasSearch && !hasNews) return null;

    // Build the merged result
    final result = <String, dynamic>{
      'error': false,
      'source': 'web',
    };

    // For current affairs queries, prefer news title; otherwise use Wikipedia
    if (isCurrentAffairs && hasNews) {
      final newsItems = newsContent['items'] as List<Map<String, String>>? ?? [];
      result['title'] = newsItems.isNotEmpty ? newsItems.first['title'] ?? query : query;
    } else {
      result['title'] = (hasWiki ? wiki['title'] : hasDdg ? ddg['heading'] : query) ?? query;
    }

    // Summary — for current affairs: news first; otherwise Wikipedia summary (clean extract)
    final wikiSummary = hasWiki ? wiki['summary'] as String? ?? '' : '';
    final ddgAbstract = hasDdg ? ddg['abstract'] as String? ?? '' : '';
    final newsSummary = hasNews ? newsContent['summary'] as String? ?? '' : '';
    String summary;

    if (isCurrentAffairs && newsSummary.isNotEmpty) {
      // Current affairs: lead with news, add wiki context if available
      summary = newsSummary;
      if (wikiSummary.isNotEmpty) {
        summary += '\n\nBackground: $wikiSummary';
      }
    } else {
      // Use only the clean wiki summary or DDG abstract — NOT raw full content
      summary = wikiSummary.isNotEmpty ? wikiSummary : ddgAbstract;
      if (summary.isNotEmpty && newsSummary.isNotEmpty) {
        summary += '\n\nLatest News:\n$newsSummary';
      } else if (summary.isEmpty && newsSummary.isNotEmpty) {
        summary = newsSummary;
      }
    }

    // If no summary yet, build one from search result descriptions
    if (summary.isEmpty && hasSearch) {
      final articles = wikiSearch['articles'] as List<Map<String, String>>? ?? [];
      final descriptions = articles
          .map((a) => a['description'] ?? '')
          .where((d) => d.isNotEmpty)
          .take(3)
          .toList();
      if (descriptions.isNotEmpty) {
        summary = descriptions.join('. ');
      }
    }

    result['summary'] = summary;
    result['wiki_summary'] = wikiSummary;
    result['ddg_abstract'] = ddgAbstract;
    result['news_summary'] = newsSummary;

    // Store full Wikipedia content internally for AI context only (not for display)
    if (hasWiki && wiki['fullContent'] != null) {
      result['_wiki_full_content'] = wiki['fullContent'];
    }
    if (hasWiki && wiki['supplementaryContent'] != null) {
      result['_supplementaryContent'] = wiki['supplementaryContent'];
    }

    // For current affairs: news key points first
    if (isCurrentAffairs && hasNews) {
      final newsItems = newsContent['items'] as List<Map<String, String>>? ?? [];
      final newsKeyPoints = newsItems
          .take(6)
          .map((item) => '${item['title']} (${item['source'] ?? 'News'})')
          .toList();
      result['key_points'] = newsKeyPoints;
    } else if (hasWiki && wiki['fullContent'] != null) {
      // Extract clean key points from Wikipedia (short factual statements only)
      final fullContent = wiki['fullContent'] as String;
      result['key_points'] = _extractKeyPoints(fullContent, query);

      // Append news key points if available
      if (hasNews) {
        final newsItems = newsContent['items'] as List<Map<String, String>>? ?? [];
        final existing = result['key_points'] as List<String>? ?? [];
        final newsPoints = newsItems
            .take(3)
            .map((item) => '${item['title']}')
            .toList();
        result['key_points'] = [...existing.take(5), ...newsPoints];
      }
    } else if (ddgAbstract.isNotEmpty) {
      result['key_points'] = _extractKeyPoints(ddgAbstract, query);
    } else if (hasNews) {
      // Only news available
      final newsItems = newsContent['items'] as List<Map<String, String>>? ?? [];
      result['key_points'] = newsItems
          .take(6)
          .map((item) => '${item['title']} (${item['source'] ?? 'News'})')
          .toList();
    } else if (hasSearch) {
      final articles = wikiSearch['articles'] as List<Map<String, String>>? ?? [];
      result['key_points'] = articles
          .where((a) => (a['description'] ?? '').isNotEmpty)
          .map((a) => '${a['title']}: ${a['description']}')
          .take(6)
          .toList();
    }

    // Image
    final wikiImage = hasWiki ? wiki['imageUrl'] as String? : null;
    final ddgImage = hasDdg ? ddg['imageUrl'] as String? : null;
    result['imageUrl'] = wikiImage ?? ddgImage;

    // Source URLs
    final sources = <Map<String, String>>[];
    if (hasWiki && (wiki['pageUrl'] as String? ?? '').isNotEmpty) {
      sources.add({
        'title': 'Wikipedia: ${wiki['title']}',
        'url': wiki['pageUrl'] as String,
        'source': 'Wikipedia',
      });
    }
    if (hasDdg && (ddg['url'] as String? ?? '').isNotEmpty) {
      sources.add({
        'title': '${ddg['source'] ?? 'Web'}: ${ddg['heading'] ?? query}',
        'url': ddg['url'] as String,
        'source': ddg['source'] as String? ?? 'Web',
      });
    }

    // Wikipedia search results as additional sources
    if (hasSearch) {
      final articles = wikiSearch['articles'] as List<Map<String, String>>? ?? [];
      for (final article in articles.take(5)) {
        if (article['url']!.isNotEmpty && !sources.any((s) => s['url'] == article['url'])) {
          sources.add({
            'title': article['title']!,
            'url': article['url']!,
            'description': article['description']!,
            'source': 'Wikipedia',
          });
        }
      }
    }

    // News sources (insert at top for current affairs)
    if (hasNews) {
      final newsItems = newsContent['items'] as List<Map<String, String>>? ?? [];
      final newsSources = <Map<String, String>>[];
      for (final item in newsItems.take(5)) {
        if ((item['link'] ?? '').isNotEmpty) {
          newsSources.add({
            'title': item['title'] ?? '',
            'url': item['link']!,
            'description': item['description'] ?? '',
            'source': item['source'] ?? 'News',
          });
        }
      }
      if (isCurrentAffairs) {
        sources.insertAll(0, newsSources); // News first for current affairs
      } else {
        sources.addAll(newsSources);
      }
    }
    result['web_sources'] = sources;

    // Related topics from DuckDuckGo
    if (hasDdg) {
      final ddgRelated = ddg['relatedTopics'] as List<Map<String, String>>? ?? [];
      result['related_topics'] = ddgRelated
          .map((r) => r['text'] ?? '')
          .where((t) => t.isNotEmpty && t.length < 100)
          .take(6)
          .toList();
    }

    // UPSC-specific categorization (basic, without AI)
    result['exam_relevance'] = _guessExamRelevance(query, category);

    return result;
  }

  /// Extract key points from full text content using relevance scoring.
  static List<String> _extractKeyPoints(String content, String query) {
    final queryWords = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final sentences = content
        .split(RegExp(r'[.!?]\s+'))
        .where((s) => s.trim().length > 30 && s.trim().length < 250)
        .map((s) => s.trim().replaceAll(RegExp(r'\s+'), ' '))
        .toSet() // deduplicate
        .toList();

    if (sentences.isEmpty) return [];

    // Score each sentence for relevance
    final scored = <MapEntry<String, double>>[];
    for (var i = 0; i < sentences.length; i++) {
      final sentence = sentences[i];
      final lower = sentence.toLowerCase();
      double score = 0;

      // Query word matches (most important)
      for (final word in queryWords) {
        if (lower.contains(word)) score += 3.0;
      }

      // Position boost: first sentences of content are usually most important
      if (i < 5) score += 2.0;
      else if (i < 15) score += 1.0;

      // First sentence of a paragraph (after empty line) is usually a key statement
      if (i > 0 && sentences[i - 1].isEmpty) score += 1.5;

      // UPSC-relevant signal words
      const highValueWords = [
        'established', 'founded', 'enacted', 'amended', 'ratified',
        'constitution', 'article', 'amendment', 'act', 'policy',
        'supreme court', 'parliament', 'india', 'government',
        'launched', 'implemented', 'commission', 'committee',
        'objective', 'provision', 'mandate', 'jurisdiction',
        'billion', 'million', 'percent', 'growth', 'target',
        'treaty', 'agreement', 'convention', 'protocol',
        'significant', 'important', 'major', 'key', 'critical',
        'headquartered', 'member', 'chairman', 'appointed',
      ];
      for (final word in highValueWords) {
        if (lower.contains(word)) {
          score += 1.0;
          break; // Only count once per sentence for signal words
        }
      }

      // Contains numbers/dates (factual content is valuable)
      if (RegExp(r'\d{4}').hasMatch(sentence)) score += 0.5;
      if (RegExp(r'\d+[%]|\d+\.\d+').hasMatch(sentence)) score += 0.5;

      // Penalize sentences that are too short or just list items
      if (sentence.length < 40) score -= 1.0;
      if (sentence.startsWith('See ') || sentence.startsWith('For ') || sentence.startsWith('Main ')) score -= 2.0;

      scored.add(MapEntry(sentence, score));
    }

    // Sort by score, take top points
    scored.sort((a, b) => b.value.compareTo(a.value));

    final points = <String>[];
    for (final entry in scored) {
      if (points.length >= 6) break;
      var point = entry.key.trim();
      // Ensure point ends with a period
      if (!point.endsWith('.') && !point.endsWith('!') && !point.endsWith('?')) {
        point = '$point.';
      }
      // Trim overly long points to keep them clean
      if (point.length > 200) {
        final cutoff = point.lastIndexOf(' ', 200);
        point = '${point.substring(0, cutoff > 150 ? cutoff : 200)}...';
      }
      // Avoid near-duplicate points
      if (!points.any((existing) => _isSimilar(existing, point))) {
        points.add(point);
      }
    }

    return points;
  }

  /// Check if two strings are too similar (to avoid duplicate key points).
  static bool _isSimilar(String a, String b) {
    if (a == b) return true;
    final wordsA = a.toLowerCase().split(' ').toSet();
    final wordsB = b.toLowerCase().split(' ').toSet();
    final overlap = wordsA.intersection(wordsB).length;
    final minLen = wordsA.length < wordsB.length ? wordsA.length : wordsB.length;
    return minLen > 0 && overlap / minLen > 0.7;
  }

  /// Extract a readable detailed content from full Wikipedia text.
  static String _extractDetailedContent(String fullContent) {
    if (fullContent.isEmpty) return '';
    // Get first ~1000 chars of meaningful content
    final paragraphs = fullContent.split('\n\n').where((p) => p.trim().length > 50).toList();
    final buf = StringBuffer();
    for (final p in paragraphs) {
      buf.writeln(p.trim());
      buf.writeln();
      if (buf.length > 1200) break;
    }
    return buf.toString().trim();
  }

  /// Guess exam relevance from query keywords (basic heuristic).
  static Map<String, dynamic> _guessExamRelevance(String query, String? category) {
    final lower = query.toLowerCase();
    final papers = <String>[];
    String frequency = 'Medium';

    if (lower.contains('constitution') || lower.contains('article') ||
        lower.contains('parliament') || lower.contains('judiciary') ||
        lower.contains('election') || lower.contains('fundamental') ||
        lower.contains('polity') || category == 'Polity') {
      papers.addAll(['GS-II', 'Prelims']);
      frequency = 'High';
    }
    if (lower.contains('economy') || lower.contains('budget') ||
        lower.contains('rbi') || lower.contains('gdp') ||
        lower.contains('tax') || lower.contains('inflation') ||
        category == 'Economy') {
      papers.addAll(['GS-III', 'Prelims']);
      frequency = 'High';
    }
    if (lower.contains('history') || lower.contains('revolt') ||
        lower.contains('mughal') || lower.contains('independence') ||
        lower.contains('gandhi') || category == 'History') {
      papers.addAll(['GS-I', 'Prelims']);
    }
    if (lower.contains('geography') || lower.contains('river') ||
        lower.contains('mountain') || lower.contains('climate') ||
        lower.contains('monsoon') || category == 'Geography') {
      papers.addAll(['GS-I', 'Prelims']);
    }
    if (lower.contains('environment') || lower.contains('biodiversity') ||
        lower.contains('climate change') || lower.contains('pollution') ||
        category == 'Environment') {
      papers.addAll(['GS-III', 'Prelims']);
    }
    if (lower.contains('technology') || lower.contains('isro') ||
        lower.contains('space') || lower.contains('ai ') ||
        lower.contains('cyber') || category == 'Science & Technology') {
      papers.addAll(['GS-III', 'Prelims']);
    }
    if (lower.contains('international') || lower.contains('foreign') ||
        lower.contains('china') || lower.contains('pakistan') ||
        lower.contains('un ') || lower.contains('nato') ||
        category == 'International Relations') {
      papers.addAll(['GS-II']);
    }
    if (lower.contains('ethics') || lower.contains('integrity') ||
        lower.contains('governance') || category == 'Ethics' || category == 'Governance') {
      papers.addAll(['GS-IV']);
    }

    if (papers.isEmpty) {
      papers.addAll(['General', 'Prelims']);
    }

    return {
      'prelims': true,
      'mains': true,
      'papers': papers.toSet().toList(),
      'syllabus_topic': category ?? 'General Studies',
      'frequency': frequency,
    };
  }

  // ═════════════════════════════════════════════════════════════════
  //  DISK CACHE
  // ═════════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>?> _getDiskCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${_cacheKey}_$key');
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final ts = data['_cached_at'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - ts > _cacheDuration.inMilliseconds) {
        await prefs.remove('${_cacheKey}_$key');
        return null;
      }
      data.remove('_cached_at');
      return data;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _setDiskCache(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toStore = Map<String, dynamic>.from(data);
      toStore['_cached_at'] = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString('${_cacheKey}_$key', jsonEncode(toStore));
    } catch (_) {}
  }
}

class _WebCacheEntry {
  final Map<String, dynamic> data;
  final DateTime timestamp;
  _WebCacheEntry({required this.data, required this.timestamp});
}
