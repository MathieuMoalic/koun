import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class UnauthorizedException extends HttpException {
  UnauthorizedException() : super('Unauthorized');
}
class ApiClient {
  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _serverUrlKey = 'server_url';
  static const _reviewQueueKey = 'review_queue';

  Future<String> _baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverUrlKey) ?? 'http://localhost:8080';
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, url);
  }

  Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
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
      throw HttpException('Login failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, data['token'] as String);
    await prefs.setString(_refreshTokenKey, data['refresh_token'] as String);
  }

  Future<bool> hasToken() async => (await _token()) != null;

  Future<http.Response> _authedGet(String path) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    if (token == null) {
      throw HttpException('Missing auth token');
    }
    return http.get(Uri.parse('$baseUrl$path'), headers: {
      'Authorization': 'Bearer $token',
    });
  }

  Future<http.Response> _authedPost(String path, Map<String, dynamic> body) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    if (token == null) {
      throw HttpException('Missing auth token');
    }
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
  }

  Future<http.Response> _authedPut(String path, Map<String, dynamic> body) async {
    final baseUrl = await _baseUrl();
    final token = await _token();
    if (token == null) {
      throw HttpException('Missing auth token');
    }
    return http.put(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
  }

  Future<NextReviewResponse> fetchNextReview() async {
    final response = await _authedGet('/reviews/next');
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw HttpException('Failed to fetch next review');
    }
    return NextReviewResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> createCard({
    required String front,
    required String back,
    String? hint,
  }) async {
    final response = await _authedPost('/cards', {
      'front': front,
      'back': back,
      'hint': hint,
    });
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw HttpException('Failed to create card');
    }
  }

  Future<List<CardModel>> listCards() async {
    final response = await _authedGet('/cards');
    if (response.statusCode == 401) {
      throw UnauthorizedException();
    }
    if (response.statusCode != 200) {
      throw HttpException('Failed to fetch cards');
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
      throw HttpException('Failed to fetch stats');
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
      throw HttpException('Failed to fetch FSRS settings');
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
      throw HttpException('Failed to update FSRS settings');
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
      throw HttpException('Failed to sync reviews');
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
    return raw
        .map((item) => jsonDecode(item) as Map<String, dynamic>)
        .toList();
  }

  Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _reviewQueueKey,
      queue.map(jsonEncode).toList(),
    );
  }
}
