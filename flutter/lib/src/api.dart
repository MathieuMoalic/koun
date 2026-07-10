import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class ApiException implements Exception {
  final String message;

  const ApiException(this.message);

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException() : super('Unauthorized');
}

class NounTranslation {
  final String polishSingular;
  final String polishPlural;
  final String english;

  const NounTranslation({
    required this.polishSingular,
    required this.polishPlural,
    required this.english,
  });

  factory NounTranslation.fromJson(Map<String, dynamic> json) {
    return NounTranslation(
      polishSingular: json['polish_singular'] as String? ?? '',
      polishPlural: json['polish_plural'] as String? ?? '',
      english: json['english'] as String? ?? '',
    );
  }
}

class AdjectiveTranslation {
  final String polishMasculine;
  final String polishFeminine;
  final String polishNeuter;
  final String english;

  const AdjectiveTranslation({
    required this.polishMasculine,
    required this.polishFeminine,
    required this.polishNeuter,
    required this.english,
  });

  factory AdjectiveTranslation.fromJson(Map<String, dynamic> json) {
    return AdjectiveTranslation(
      polishMasculine: json['polish_masculine'] as String? ?? '',
      polishFeminine: json['polish_feminine'] as String? ?? '',
      polishNeuter: json['polish_neuter'] as String? ?? '',
      english: json['english'] as String? ?? '',
    );
  }
}

class VerbTranslation {
  final String polishImperfective;
  final String polishPerfective;
  final String english;

  const VerbTranslation({
    required this.polishImperfective,
    required this.polishPerfective,
    required this.english,
  });

  factory VerbTranslation.fromJson(Map<String, dynamic> json) {
    return VerbTranslation(
      polishImperfective: json['polish_imperfective'] as String? ?? '',
      polishPerfective: json['polish_perfective'] as String? ?? '',
      english: json['english'] as String? ?? '',
    );
  }
}

class ApiClient {
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _serverUrlKey = 'server_url';
  static const _reviewQueueKey = 'review_queue';

  String _normalizeBaseUrl(String rawUrl) {
    var normalized = rawUrl.trim();
    if (normalized.isEmpty) {
      throw const ApiException('Server URL cannot be empty');
    }

    if (!normalized.contains('://')) {
      final isLocal =
          normalized.startsWith('localhost') ||
          normalized.startsWith('127.0.0.1') ||
          normalized.startsWith('0.0.0.0');
      normalized = '${isLocal ? 'http' : 'https'}://$normalized';
    }

    final parsed = Uri.tryParse(normalized);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw const ApiException('Invalid server URL');
    }

    return parsed
        .replace(path: '', queryParameters: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  String _defaultBaseUrl() {
    if (kIsWeb) {
      return Uri.base.origin;
    }

    const bool isReleaseMode = bool.fromEnvironment('dart.vm.release');
    const String releaseBaseUrl = 'https://koun.matmoa.eu';
    return isReleaseMode ? releaseBaseUrl : 'http://localhost:8080';
  }

  Future<String> _baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_serverUrlKey);

    if (savedUrl != null && savedUrl.isNotEmpty) {
      try {
        return _normalizeBaseUrl(savedUrl);
      } on ApiException {
        await prefs.remove(_serverUrlKey);
      }
    }

    return _defaultBaseUrl();
  }

  Future<String> baseUrl() => _baseUrl();

  Future<void> setServerUrl(String url) async {
    final normalizedUrl = _normalizeBaseUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, normalizedUrl);
  }

  Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
  }

  Future<String> authToken() async {
    final token = await _token();
    if (token == null) {
      throw const ApiException('Missing auth token');
    }
    return token;
  }

  Future<VersionInfo> getVersion() async {
    final baseUrl = await _baseUrl();
    final response = await http.get(
      Uri.parse('$baseUrl/version'),
    );
    if (response.statusCode != 200) {
      throw const ApiException('Failed to fetch version');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return VersionInfo.fromJson(data);
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> login(String password) async {
    final baseUrl = await _baseUrl();
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );
    if (response.statusCode != 200) {
      throw ApiException('Login failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, data['token'] as String);
    await prefs.setString(_refreshTokenKey, data['refresh_token'] as String);
  }

  Future<bool> hasToken() async => (await _token()) != null;

  Future<String> cardAudioUrl(int cardId) async {
    final baseUrl = await _baseUrl();
    return '$baseUrl/cards/$cardId/audio';
  }

  Future<List<int>> downloadCardAudio(int cardId) async {
    final response = await _authedGet('/cards/$cardId/audio');
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to fetch card audio');
    }
    return response.bodyBytes;
  }

  Future<http.Response> _authedGet(String path) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    if (token == null) {
      throw const ApiException('Missing auth token');
    }
    final response = await http.get(Uri.parse('$baseUrl$path'), headers: {
      'Authorization': 'Bearer $token',
    });
    if (response.statusCode == 401) {
      final refreshed = await _refreshToken();
      if (!refreshed) throw UnauthorizedException();
      final newToken = await _token();
      if (newToken == null) throw UnauthorizedException();
      return http.get(Uri.parse('$baseUrl$path'), headers: {
        'Authorization': 'Bearer $newToken',
      });
    }
    return response;
  }

  Future<http.Response> _authedPost(
      String path, Map<String, dynamic> body) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    if (token == null) {
      throw const ApiException('Missing auth token');
    }
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 401) {
      final refreshed = await _refreshToken();
      if (!refreshed) throw UnauthorizedException();
      final newToken = await _token();
      if (newToken == null) throw UnauthorizedException();
      return http.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $newToken',
        },
        body: jsonEncode(body),
      );
    }
    return response;
  }

  Future<http.Response> _authedDelete(String path) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    if (token == null) {
      throw const ApiException('Missing auth token');
    }
    final response = await http.delete(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    if (response.statusCode == 401) {
      final refreshed = await _refreshToken();
      if (!refreshed) throw UnauthorizedException();
      final newToken = await _token();
      if (newToken == null) throw UnauthorizedException();
      return http.delete(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Authorization': 'Bearer $newToken',
        },
      );
    }
    return response;
  }

  Future<http.Response> _authedPut(
      String path, Map<String, dynamic> body) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    if (token == null) {
      throw const ApiException('Missing auth token');
    }
    final response = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 401) {
      final refreshed = await _refreshToken();
      if (!refreshed) throw UnauthorizedException();
      final newToken = await _token();
      if (newToken == null) throw UnauthorizedException();
      return http.put(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $newToken',
        },
        body: jsonEncode(body),
      );
    }
    return response;
  }

  Future<bool> _refreshToken() async {
    final baseUrl = await _baseUrl();
    final refreshToken = await _refreshTokenValue();
    if (refreshToken == null) return false;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, data['token'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _refreshTokenValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<NextReviewResponse> fetchNextReview() async {
    final response = await _authedGet('/reviews/next');
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to fetch next review');
    }
    return NextReviewResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> createCard({
    required String front,
    required String back,
    required CardType cardType,
    String? hint,
  }) async {
    final response = await _authedPost('/cards', {
      'front': front,
      'back': back,
      'hint': hint,
      'card_type': cardType.name,
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to create card');
    }
  }

  Future<void> createCardFromEnglish({
    required String english,
    required CardType cardType,
    String? hint,
  }) async {
    final response = await _authedPost('/cards/from-english', {
      'english': english,
      'hint': hint,
      'card_type': cardType.name,
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to create card from English');
    }
  }

  Future<void> updateCard({
    required int id,
    required String front,
    required String back,
    required CardType cardType,
    String? hint,
  }) async {
    final response = await _authedPut('/cards/$id', {
      'front': front,
      'back': back,
      'hint': hint,
      'card_type': cardType.name,
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to update card');
    }
  }

  Future<void> deleteCard(int id) async {
    final response = await _authedDelete('/cards/$id');
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 204) {
      throw const ApiException('Failed to delete card');
    }
  }

  Future<String> translateText({
    required String text,
    required TranslationDirection direction,
  }) async {
    final response = await _authedPost('/translate', {
      'text': text,
      'direction': direction.apiValue,
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to translate text');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['translation'] as String;
  }

  Future<NounTranslation> translateNounText({
    required String text,
    required TranslationDirection direction,
  }) async {
    final response = await _authedPost('/translate', {
      'text': text,
      'direction': direction.apiValue,
      'card_type': 'noun',
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to translate noun');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return NounTranslation.fromJson(data);
  }

  Future<AdjectiveTranslation> translateAdjectiveText({
    required String text,
    required TranslationDirection direction,
  }) async {
    final response = await _authedPost('/translate', {
      'text': text,
      'direction': direction.apiValue,
      'card_type': 'adjective',
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to translate adjective');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AdjectiveTranslation.fromJson(data);
  }

  Future<VerbTranslation> translateVerbText({
    required String text,
    required TranslationDirection direction,
  }) async {
    final response = await _authedPost('/translate', {
      'text': text,
      'direction': direction.apiValue,
      'card_type': 'verb',
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to translate verb');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return VerbTranslation.fromJson(data);
  }

  Future<List<CardModel>> listCards() async {
    final response = await _authedGet('/cards');
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to fetch cards');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => CardModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<ReviewsPerDay>> reviewsPerDay() async {
    final response = await _authedGet('/stats/reviews-per-day');
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to fetch stats');
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((item) => ReviewsPerDay.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<FsrsSettings> getFsrsSettings() async {
    final response = await _authedGet('/settings/fsrs');
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to fetch FSRS settings');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return FsrsSettings.fromJson(data);
  }

  Future<void> setFsrsSettings(FsrsSettings settings) async {
    final response = await _authedPut('/settings/fsrs', settings.toJson());
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to update FSRS settings');
    }
  }

  Future<void> submitReview(ReviewEvent event) async {
    try {
      await _syncEvents([event]);
    } on Exception {
      await _enqueueReview(event);
    }
  }

  Future<void> flushReviewQueue() async {
    final queue = await _loadQueue();
    if (queue.isEmpty) {
      return;
    }
    final events = queue
        .map((item) => ReviewEvent(
              cardId: item['card_id'] as int,
              rating: ReviewRating.values
                  .firstWhere((r) => r.name == item['rating']),
              reviewedAt: item['reviewed_at'] as int,
            ))
        .toList();
    await _syncEvents(events);
    await _saveQueue([]);
  }

  Future<void> _syncEvents(List<ReviewEvent> events) async {
    final response = await _authedPost('/reviews/sync', {
      'events': events.map((event) => event.toJson()).toList(),
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw const ApiException('Failed to sync reviews');
    }
  }

  Future<void> _enqueueReview(ReviewEvent event) async {
    final queue = await _loadQueue();
    queue.add(event.toJson());
    await _saveQueue(queue);
  }

  Future<List<Map<String, dynamic>>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_reviewQueueKey) ?? [];
    return raw.map((item) => jsonDecode(item) as Map<String, dynamic>).toList();
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _reviewQueueKey,
      queue.map(jsonEncode).toList(),
    );
  }
}
