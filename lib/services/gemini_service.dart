import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for AI-powered UPSC content search using Google Gemini API.
/// Supports multiple API keys with automatic rotation on rate limit.
class GeminiService {
  // Free Gemini API endpoint
  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';
  // Models to try in order — if one is unavailable, fall back to next
  static const _models = ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-1.5-flash-latest'];
  static int _activeModelIndex = 0;
  static const _maxKeys = 5;

  // Cache for recent searches
  static final Map<String, _CachedResult> _searchCache = {};
  static const _cacheDuration = Duration(hours: 12);
  static const _maxCacheSize = 50;

  /// All configured API keys — stored in SharedPreferences.
  static List<String> _apiKeys = [];

  /// Track which keys are rate-limited and when they cooldown.
  static final Map<int, DateTime> _rateLimitedKeys = {};
  static const _rateLimitCooldown = Duration(seconds: 65); // Gemini resets per minute
  static const _maxAutoRetries = 2; // Auto-retry up to 2 times after waiting

  /// Index of the currently active key.
  static int _currentKeyIndex = 0;

  /// Initialize the service and load saved API keys.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    // Load multi-key list
    final keysJson = prefs.getString('gemini_api_keys');
    if (keysJson != null) {
      try {
        _apiKeys = List<String>.from(jsonDecode(keysJson));
      } catch (_) {
        _apiKeys = [];
      }
    }

    // Backward compat: migrate single key → multi-key
    if (_apiKeys.isEmpty) {
      final oldKey = prefs.getString('gemini_api_key');
      if (oldKey != null && oldKey.isNotEmpty) {
        _apiKeys = [oldKey];
        await _persistKeys();
      }
    }
  }

  /// Set and persist multiple API keys.
  static Future<void> setApiKeys(List<String> keys) async {
    _apiKeys = keys.where((k) => k.trim().isNotEmpty).map((k) => k.trim()).toList();
    if (_apiKeys.length > _maxKeys) _apiKeys = _apiKeys.sublist(0, _maxKeys);
    _currentKeyIndex = 0;
    _rateLimitedKeys.clear();
    await _persistKeys();
  }

  /// Add a single key (appends if not duplicate, max 5).
  static Future<void> addApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty || _apiKeys.contains(trimmed)) return;
    if (_apiKeys.length >= _maxKeys) return;
    _apiKeys.add(trimmed);
    await _persistKeys();
  }

  /// Remove a key by index.
  static Future<void> removeApiKey(int index) async {
    if (index < 0 || index >= _apiKeys.length) return;
    _apiKeys.removeAt(index);
    _rateLimitedKeys.remove(index);
    if (_currentKeyIndex >= _apiKeys.length) _currentKeyIndex = 0;
    await _persistKeys();
  }

  /// Legacy setApiKey — sets as the only key (for backward compat).
  static Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    if (!_apiKeys.contains(trimmed)) {
      if (_apiKeys.length >= _maxKeys) {
        _apiKeys[0] = trimmed; // replace oldest
      } else {
        _apiKeys.add(trimmed);
      }
    }
    await _persistKeys();
  }

  static Future<void> _persistKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_keys', jsonEncode(_apiKeys));
    // Also keep legacy key for backward compat
    if (_apiKeys.isNotEmpty) {
      await prefs.setString('gemini_api_key', _apiKeys.first);
    }
  }

  /// Get all configured API keys.
  static List<String> get apiKeys => List.unmodifiable(_apiKeys);

  /// Legacy getter — returns first key.
  static String? get apiKey => _apiKeys.isNotEmpty ? _apiKeys.first : null;

  /// Number of configured keys.
  static int get keyCount => _apiKeys.length;

  /// Check if at least one API key is configured.
  static bool get isConfigured => _apiKeys.isNotEmpty;

  /// Get the next available (non-rate-limited) key. Returns null if all exhausted.
  static String? _getAvailableKey() {
    if (_apiKeys.isEmpty) return null;

    // Clear expired cooldowns
    final now = DateTime.now();
    _rateLimitedKeys.removeWhere((_, expiry) => now.isAfter(expiry));

    // Try from current index forward, wrapping around
    for (var i = 0; i < _apiKeys.length; i++) {
      final idx = (_currentKeyIndex + i) % _apiKeys.length;
      if (!_rateLimitedKeys.containsKey(idx)) {
        _currentKeyIndex = idx;
        return _apiKeys[idx];
      }
    }
    return null; // All keys rate-limited
  }

  /// Mark current key as rate-limited and rotate to next.
  static void _markRateLimited(int keyIndex) {
    _rateLimitedKeys[keyIndex] = DateTime.now().add(_rateLimitCooldown);
    _currentKeyIndex = (keyIndex + 1) % _apiKeys.length;
    debugPrint('Key ${keyIndex + 1}/${_apiKeys.length} rate-limited, rotating...');
  }

  /// Get status info (for UI display).
  static Map<String, dynamic> get keyStatus {
    final now = DateTime.now();
    _rateLimitedKeys.removeWhere((_, expiry) => now.isAfter(expiry));
    return {
      'total': _apiKeys.length,
      'available': _apiKeys.length - _rateLimitedKeys.length,
      'rateLimited': _rateLimitedKeys.length,
      'activeIndex': _currentKeyIndex,
    };
  }

  /// Search and simplify a UPSC topic using Gemini AI.
  /// Returns structured content with simplified explanation, key points,
  /// exam relevance, and related topics.
  static Future<Map<String, dynamic>> searchTopic(String query, {
    String? category,
    String? examType, // 'Prelims', 'Mains', 'Both'
  }) async {
    if (!isConfigured) {
      return _errorResult('API key not configured. Please add your Gemini API key in Settings.');
    }

    // Check cache
    final cacheKey = '${query.toLowerCase().trim()}_${category ?? ''}_${examType ?? ''}';
    if (_searchCache.containsKey(cacheKey)) {
      final cached = _searchCache[cacheKey]!;
      if (DateTime.now().difference(cached.timestamp) < _cacheDuration) {
        return cached.data;
      }
      _searchCache.remove(cacheKey);
    }

    try {
      final prompt = _buildPrompt(query, category, examType);
      final response = await _callGemini(prompt);

      if (response != null) {
        final parsed = _parseResponse(response, query);
        // Cache result
        if (_searchCache.length >= _maxCacheSize) {
          _searchCache.remove(_searchCache.keys.first);
        }
        _searchCache[cacheKey] = _CachedResult(data: parsed, timestamp: DateTime.now());
        return parsed;
      }

      return _errorResult('Could not get a response. Please try again.');
    } catch (e) {
      debugPrint('Gemini search error: $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      return _errorResult(msg.length > 200 ? '${msg.substring(0, 200)}...' : msg);
    }
  }

  /// Get AI-simplified newspaper article analysis.
  static Future<Map<String, dynamic>> simplifyArticle(String title, String content) async {
    if (!isConfigured) {
      return _errorResult('API key not configured.');
    }

    try {
      final prompt = '''
You are a UPSC exam preparation expert. Simplify this newspaper article for a UPSC aspirant.

Article Title: $title
Article Content: ${content.length > 3000 ? content.substring(0, 3000) : content}

Respond in this EXACT JSON format:
{
  "simplified_title": "Clear, exam-focused title",
  "summary": "2-3 sentence simple summary that a student can easily understand",
  "key_points": ["point 1", "point 2", "point 3", "point 4", "point 5"],
  "exam_relevance": "Prelims/Mains/Both",
  "gs_paper": "GS-I/GS-II/GS-III/GS-IV/Essay",
  "syllabus_topic": "Exact syllabus topic this maps to",
  "mnemonic": "Memory aid for key facts",
  "important_terms": {"term1": "definition1", "term2": "definition2"},
  "previous_year_connection": "How this connects to past UPSC questions",
  "answer_framework": "Brief Mains answer structure: Introduction → Body points → Conclusion"
}
Only output valid JSON. No markdown, no extra text.''';

      final response = await _callGemini(prompt);
      if (response != null) {
        return _parseJsonResponse(response);
      }
      return _errorResult('Could not simplify article.');
    } catch (e) {
      return _errorResult('Simplification failed: $e');
    }
  }

  /// Generate quiz questions on a topic using AI.
  static Future<List<Map<String, dynamic>>> generateQuizQuestions(String topic, {int count = 5}) async {
    if (!isConfigured) return [];

    try {
      final prompt = '''
You are a UPSC exam question setter with expertise in setting challenging but fair questions. Generate $count multiple-choice questions on: "$topic"

Requirements:
- Questions should be at UPSC Prelims difficulty level
- Each question must have exactly 4 options (no more, no less)
- Include clear, educational explanations for the correct answer
- Mix factual, conceptual, and application-based questions
- Make all 4 options plausible — avoid obviously wrong options
- Ensure questions test understanding, not just memorization
- Cover different aspects of the topic
- Each question must have exactly one correct answer

Respond in this EXACT JSON array format (no markdown, no extra text):
[
  {
    "question": "Clear, well-formed question text ending with a question mark?",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "correctAnswerIndex": 0,
    "explanation": "Detailed explanation of why the answer is correct and why others are wrong",
    "difficulty": "Easy",
    "category": "Polity"
  },
  {
    "question": "Second question?",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "correctAnswerIndex": 2,
    "explanation": "Detailed explanation",
    "difficulty": "Medium",
    "category": "Economy"
  }
]

CRITICAL: Output ONLY a valid JSON array. No markdown code blocks, no backticks, no text before or after the JSON.''';

      final response = await _callGemini(prompt);
      if (response != null) {
        final cleaned = _extractJson(response);
        debugPrint('[Gemini] Quiz raw response length: ${response.length}');
        try {
          final decoded = jsonDecode(cleaned);
          if (decoded is List) {
            final result = <Map<String, dynamic>>[];
            for (final item in decoded) {
              if (item is Map<String, dynamic> &&
                  item['question'] != null &&
                  item['options'] is List &&
                  (item['options'] as List).length == 4) {
                result.add(item);
              }
            }
            debugPrint('[Gemini] Quiz parsed ${result.length} valid questions');
            return result;
          }
        } catch (parseErr) {
          debugPrint('[Gemini] Quiz JSON parse error: $parseErr');
          debugPrint('[Gemini] Cleaned response: ${cleaned.substring(0, cleaned.length.clamp(0, 500))}');
        }
      }
      return [];
    } catch (e) {
      debugPrint('[Gemini] Quiz generation error: $e');
      return [];
    }
  }

  /// Get daily current affairs summary.
  static Future<Map<String, dynamic>> getDailyCurrentAffairs() async {
    if (!isConfigured) {
      return _errorResult('API key not configured.');
    }

    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Check cache
      final cacheKey = 'daily_ca_$dateStr';
      if (_searchCache.containsKey(cacheKey)) {
        return _searchCache[cacheKey]!.data;
      }

      final prompt = '''
You are a UPSC current affairs expert. Provide today's ($dateStr) most important current affairs for UPSC preparation.

Cover these categories:
1. National News (2-3 items)
2. International News (2-3 items)
3. Economy & Finance (2-3 items)
4. Science & Technology (1-2 items)
5. Environment (1-2 items)
6. Government Schemes & Policies (1-2 items)

Respond in this EXACT JSON format:
{
  "date": "$dateStr",
  "categories": [
    {
      "name": "Category Name",
      "icon": "icon_name",
      "items": [
        {
          "title": "Brief headline",
          "summary": "2-3 sentence UPSC-focused summary",
          "exam_relevance": "Prelims/Mains/Both",
          "gs_paper": "GS-I/GS-II/GS-III"
        }
      ]
    }
  ],
  "one_liner_facts": ["Fact 1 for quick revision", "Fact 2", "Fact 3", "Fact 4", "Fact 5"]
}
Only output valid JSON. No markdown, no extra text.''';

      final response = await _callGemini(prompt);
      if (response != null) {
        final parsed = _parseJsonResponse(response);
        _searchCache[cacheKey] = _CachedResult(data: parsed, timestamp: DateTime.now());
        return parsed;
      }
      return _errorResult('Could not fetch current affairs.');
    } catch (e) {
      return _errorResult('Current affairs fetch failed: $e');
    }
  }

  /// Private: Build the search prompt.
  static String _buildPrompt(String query, String? category, String? examType) {
    final categoryHint = category != null ? '\nSubject area: $category' : '';
    final examHint = examType != null ? '\nExam focus: $examType' : '';

    return '''
You are an expert UPSC (Union Public Service Commission) exam preparation tutor with deep knowledge of Indian polity, economy, history, geography, environment, science, international relations, ethics, and governance.

The student is searching for: "$query"
$categoryHint$examHint

CRITICAL ACCURACY RULES:
1. ONLY state facts you are confident about. If unsure, say "This requires verification" rather than guessing.
2. Focus PRECISELY on what was asked — "$query". Do not pad with unrelated information.
3. If the query is about a specific event, date, policy, or speech — address THAT specifically, not general background.
4. Include specific data: years, article numbers, act names, constitutional provisions, statistics.
5. Cross-reference: mention which Constitutional Articles, Acts, or Committees are relevant.
6. If you don't have reliable information about a very recent event, clearly state that.
7. Do NOT hallucinate facts, dates, or statistics — accuracy is paramount for exam preparation.

Provide a comprehensive, simplified explanation suitable for UPSC preparation.

Respond in this EXACT JSON format:
{
  "title": "Clear, specific topic title matching the query",
  "summary": "A 3-4 sentence simplified overview that DIRECTLY answers what was asked. Include the most important fact/date/provision.",
  "detailed_explanation": "A comprehensive but simple explanation in 250-400 words. Use paragraphs. Cover: (1) What it is, (2) Why it matters, (3) Key provisions/features, (4) Current status/significance. Be specific with facts.",
  "key_points": ["Specific factual point with date/number", "Point 2 with constitutional reference", "Point 3", "Point 4", "Point 5", "Point 6"],
  "exam_relevance": {
    "prelims": true,
    "mains": true,
    "papers": ["GS-I", "GS-III"],
    "syllabus_topic": "Exact syllabus topic this maps to",
    "frequency": "High/Medium/Low — based on how often this topic appears in UPSC"
  },
  "mnemonic": "A creative, memorable memory aid for the key facts (acronym, rhyme, or association)",
  "important_terms": {
    "Term 1": "Precise definition with context",
    "Term 2": "Precise definition with context"
  },
  "related_topics": ["Closely related UPSC topic 1", "Related Topic 2", "Related Topic 3"],
  "previous_year_questions": ["Actual or closely related PYQ from UPSC with year if known"],
  "flowchart": ["Step/Cause 1", "Step/Cause 2", "Step/Effect 3", "Result 4"],
  "answer_framework": "For Mains: Introduction (define + context) → Body (3-4 specific points with examples) → Conclusion (way forward/significance)",
  "quick_revision_notes": ["One-liner fact 1 for last-minute revision", "One-liner fact 2", "One-liner fact 3", "One-liner fact 4"]
}
Only output valid JSON. No markdown code blocks, no extra text before or after.''';
  }

  /// Private: Call Gemini API with automatic key rotation on rate limit.
  /// Auto-retries after waiting if all keys are temporarily exhausted.
  static Future<String?> _callGemini(String prompt) async {
    if (_apiKeys.isEmpty) {
      throw Exception('No API keys configured. Please add your Gemini API key(s).');
    }

    for (var retry = 0; retry <= _maxAutoRetries; retry++) {
      // If this is a retry, wait for the shortest cooldown to expire
      if (retry > 0) {
        final waitTime = _getShortestCooldownWait();
        if (waitTime != null && waitTime.inSeconds > 0) {
          debugPrint('All keys exhausted. Auto-retry $retry/$_maxAutoRetries — waiting ${waitTime.inSeconds}s...');
          await Future.delayed(waitTime + const Duration(seconds: 2)); // +2s buffer
          _rateLimitedKeys.removeWhere((_, expiry) => DateTime.now().isAfter(expiry));
        }
      }

      // Try each available key
      String? lastError;
      final triedKeys = <int>{};
      bool allRateLimited = false;

      for (var attempt = 0; attempt < _apiKeys.length; attempt++) {
        final key = _getAvailableKey();
        if (key == null) {
          allRateLimited = true;
          break; // All keys currently rate-limited
        }

        final keyIndex = _currentKeyIndex;
        if (triedKeys.contains(keyIndex)) break;
        triedKeys.add(keyIndex);

        try {
          final result = await _makeRequest(key, prompt);
          if (result != null) {
            debugPrint('Success with key ${keyIndex + 1}/${_apiKeys.length}');
            return result;
          }
        } on _RateLimitException {
          _markRateLimited(keyIndex);
          lastError = 'Key ${keyIndex + 1} rate-limited';
          debugPrint('$lastError, trying next...');
          continue;
        } on _ApiException catch (e) {
          // Non-retryable API error (bad key, invalid request)
          throw Exception(e.message);
        }
        // For any other error, try next key
      }

      if (!allRateLimited && triedKeys.isNotEmpty) {
        // Keys tried but none worked for a non-rate-limit reason
        throw Exception(lastError ?? 'Could not get a response from any API key.');
      }

      // All keys are rate-limited — loop will auto-retry if retries remain
      if (retry == _maxAutoRetries) {
        final status = keyStatus;
        final nextAvailable = _getShortestCooldownWait();
        final waitSec = nextAvailable?.inSeconds ?? 60;
        throw Exception(
          'All ${status['total']} keys are temporarily busy. '
          'Next key available in ~${waitSec}s. Please try again shortly.',
        );
      }
    }

    return null;
  }

  /// Make a single HTTP request to Gemini API.
  /// Logs full error details so we can diagnose issues.
  static Future<String?> _makeRequest(String apiKey, String prompt) async {
    final model = _models[_activeModelIndex];
    final url = Uri.parse('$_baseUrl/$model:generateContent?key=$apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'topP': 0.85,
        'maxOutputTokens': 6144,
      },
    });

    debugPrint('[Gemini] POST $model with key ...${apiKey.length > 6 ? apiKey.substring(apiKey.length - 4) : "?"}');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 30));

    debugPrint('[Gemini] Response: ${response.statusCode} (${response.body.length} bytes)');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text'] as String?;
        }
      }
      debugPrint('[Gemini] 200 but no candidates in response');
      return null;
    }

    // Log full error body for debugging
    final errorBody = response.body;
    debugPrint('[Gemini] ERROR ${response.statusCode}: $errorBody');

    if (response.statusCode == 429) {
      throw _RateLimitException();
    }

    final errorLower = errorBody.toLowerCase();

    if (response.statusCode == 404 || errorLower.contains('not found') || errorLower.contains('is not found')) {
      // Model doesn't exist — try next model
      debugPrint('[Gemini] Model "$model" not found, trying fallback...');
      if (_activeModelIndex < _models.length - 1) {
        _activeModelIndex++;
        debugPrint('[Gemini] Switching to model: ${_models[_activeModelIndex]}');
        return _makeRequest(apiKey, prompt); // Retry with next model
      }
      throw _ApiException('No available Gemini model found. Tried: ${_models.join(", ")}');
    }

    if (response.statusCode == 403) {
      if (errorLower.contains('resource_exhausted') || errorLower.contains('quota')) {
        throw _RateLimitException();
      }
      if (errorLower.contains('api_key_invalid') || errorLower.contains('api key not valid')) {
        throw _ApiException('API key is invalid. Please check and re-enter your key.');
      }
      if (errorLower.contains('permission') || errorLower.contains('denied')) {
        // Enable API suggestion
        throw _ApiException(
          'API not enabled. Go to console.cloud.google.com → APIs → '
          'Enable "Generative Language API" for your project.',
        );
      }
      throw _ApiException('Access denied (403): ${_extractErrorMessage(errorBody)}');
    }

    if (response.statusCode == 400) {
      throw _ApiException('Bad request: ${_extractErrorMessage(errorBody)}');
    }

    throw _ApiException('HTTP ${response.statusCode}: ${_extractErrorMessage(errorBody)}');
  }

  /// Extract the error message from Google API error response.
  static String _extractErrorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;
      return error?['message']?.toString() ?? body.substring(0, body.length.clamp(0, 200));
    } catch (_) {
      return body.length > 200 ? '${body.substring(0, 200)}...' : body;
    }
  }

  /// Get the shortest time until any rate-limited key becomes available.
  static Duration? _getShortestCooldownWait() {
    if (_rateLimitedKeys.isEmpty) return null;
    final now = DateTime.now();
    Duration? shortest;
    for (final expiry in _rateLimitedKeys.values) {
      final remaining = expiry.difference(now);
      if (remaining.isNegative) return Duration.zero;
      if (shortest == null || remaining < shortest) {
        shortest = remaining;
      }
    }
    return shortest;
  }

  /// Private: Parse the AI response into structured data.
  static Map<String, dynamic> _parseResponse(String response, String query) {
    try {
      return _parseJsonResponse(response);
    } catch (_) {
      // If JSON parsing fails, create structured data from raw text
      return {
        'title': query,
        'summary': response.length > 500 ? '${response.substring(0, 500)}...' : response,
        'detailed_explanation': response,
        'key_points': <String>[],
        'exam_relevance': {'prelims': true, 'mains': true, 'papers': ['General'], 'syllabus_topic': query, 'frequency': 'Medium'},
        'related_topics': <String>[],
        'error': false,
      };
    }
  }

  /// Private: Extract and parse JSON from response text.
  static Map<String, dynamic> _parseJsonResponse(String response) {
    final cleaned = _extractJson(response);
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic>) {
      decoded['error'] = false;
      return decoded;
    }
    throw const FormatException('Response is not a JSON object');
  }

  /// Private: Extract JSON from text that may contain markdown code blocks or extra text.
  static String _extractJson(String text) {
    var cleaned = text.trim();

    // Remove markdown code blocks
    if (cleaned.startsWith('```json')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.trim();

    // If there's text before the JSON, extract just the JSON part
    // Find first { or [ which starts the JSON
    final firstBrace = cleaned.indexOf('{');
    final firstBracket = cleaned.indexOf('[');
    int start = -1;
    if (firstBrace >= 0 && firstBracket >= 0) {
      start = firstBrace < firstBracket ? firstBrace : firstBracket;
    } else if (firstBrace >= 0) {
      start = firstBrace;
    } else if (firstBracket >= 0) {
      start = firstBracket;
    }

    if (start > 0) {
      cleaned = cleaned.substring(start);
    }

    // Find matching end brace/bracket
    if (cleaned.startsWith('{')) {
      final lastBrace = cleaned.lastIndexOf('}');
      if (lastBrace > 0) cleaned = cleaned.substring(0, lastBrace + 1);
    } else if (cleaned.startsWith('[')) {
      final lastBracket = cleaned.lastIndexOf(']');
      if (lastBracket > 0) cleaned = cleaned.substring(0, lastBracket + 1);
    }

    return cleaned.trim();
  }

  /// Private: Create an error result map.
  static Map<String, dynamic> _errorResult(String message) {
    return {
      'error': true,
      'message': message,
    };
  }

  /// Search topic using pre-fetched web content as context.
  /// Gemini analyzes real, live web data instead of relying on training data.
  static Future<Map<String, dynamic>> searchWithWebContext(
    String query,
    String webContext, {
    String? category,
    String? examType,
  }) async {
    if (!isConfigured) {
      return _errorResult('API key not configured.');
    }

    final cacheKey = 'web_${query.toLowerCase().trim()}_${category ?? ''}_${examType ?? ''}';
    if (_searchCache.containsKey(cacheKey)) {
      final cached = _searchCache[cacheKey]!;
      if (DateTime.now().difference(cached.timestamp) < _cacheDuration) {
        return cached.data;
      }
      _searchCache.remove(cacheKey);
    }

    try {
      final categoryHint = category != null ? '\nFocus on: $category' : '';
      final examHint = examType != null ? '\nExam focus: $examType' : '';

      final prompt = '''
You are an expert UPSC exam preparation tutor with deep subject expertise. A student is searching for: "$query"
$categoryHint$examHint

I have gathered the following REAL, UP-TO-DATE web content about this topic. Use this as your PRIMARY source of information:

$webContext

CRITICAL ACCURACY RULES:
1. Base your response PRIMARILY on the web content provided above — it is real, verified data.
2. Focus PRECISELY on the student's query: "$query" — not on tangentially related topics.
3. If the query mentions a specific date, event, policy, or speech — focus on THAT, not general background.
4. CROSS-REFERENCE the web content: if multiple sources agree on a fact, it's reliable. If only one source mentions something, note it.
5. Do NOT include irrelevant info (awards, personal life, honours) unless specifically asked.
6. If the web content contradicts your knowledge, prefer the web content (it's more current).
7. If the web content doesn't have enough relevant info for the specific query, honestly say "Limited information available" rather than filling with unrelated content.
8. Include specific data from the web content: dates, numbers, article references, act names.
9. Do NOT hallucinate or invent facts not present in the web content or your training data.

Based on this research, provide a comprehensive UPSC-focused analysis:

Respond in this EXACT JSON format:
{
  "title": "Clear topic title matching what the student searched",
  "summary": "A 3-4 sentence simplified overview directly answering the student's query, with key facts from the web sources",
  "detailed_explanation": "A comprehensive but simple explanation in 250-400 words, based on the web content. Cover: what, why, how, and UPSC significance.",
  "key_points": ["Specific factual point from web sources", "Point 2 with data", "Point 3", "Point 4", "Point 5", "Point 6"],
  "exam_relevance": {
    "prelims": true,
    "mains": true,
    "papers": ["GS-I", "GS-III"],
    "syllabus_topic": "Exact syllabus topic mapping",
    "frequency": "High/Medium/Low"
  },
  "mnemonic": "A creative, memorable memory aid for the key facts",
  "important_terms": {"Term 1": "Precise definition from content", "Term 2": "Definition"},
  "related_topics": ["Related Topic 1", "Related Topic 2", "Related Topic 3"],
  "previous_year_questions": ["Actual or closely related PYQ with year"],
  "flowchart": ["Step 1", "Step 2", "Step 3", "Step 4"],
  "answer_framework": "Introduction (define + context) → Body (3-4 points with examples) → Conclusion (significance/way forward)",
  "quick_revision_notes": ["One-liner 1", "One-liner 2", "One-liner 3", "One-liner 4"]
}
Only output valid JSON. No markdown code blocks, no extra text.''';

      final response = await _callGemini(prompt);
      if (response != null) {
        final parsed = _parseResponse(response, query);
        parsed['enhanced_by_ai'] = true;
        if (_searchCache.length >= _maxCacheSize) {
          _searchCache.remove(_searchCache.keys.first);
        }
        _searchCache[cacheKey] = _CachedResult(data: parsed, timestamp: DateTime.now());
        return parsed;
      }

      return _errorResult('Could not get AI analysis.');
    } catch (e) {
      debugPrint('Gemini web-context search error: $e');
      final msg = e.toString().replaceFirst('Exception: ', '');
      return _errorResult(msg.length > 200 ? '${msg.substring(0, 200)}...' : msg);
    }
  }

  /// Clear the search cache.
  static void clearCache() {
    _searchCache.clear();
  }

  /// Clear all rate-limit flags (for manual retry).
  static void clearRateLimits() {
    _rateLimitedKeys.clear();
    _currentKeyIndex = 0;
  }
}

/// Internal: Thrown when Gemini returns 429 or quota exceeded.
class _RateLimitException implements Exception {}

/// Internal: Thrown for non-retryable API errors.
class _ApiException implements Exception {
  final String message;
  _ApiException(this.message);
}

class _CachedResult {
  final Map<String, dynamic> data;
  final DateTime timestamp;
  _CachedResult({required this.data, required this.timestamp});
}
