import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
  final String name, address;
  final double latitude, longitude;

  factory PlaceResult.fromJson(Map<String, dynamic> json) {
    final address = json['display_name'] as String? ?? '';
    return PlaceResult(
      name: json['name'] as String? ?? address.split(',').first,
      address: address,
      latitude: double.parse(json['lat'].toString()),
      longitude: double.parse(json['lon'].toString()),
    );
  }
}

class PlaceSearchException implements Exception {
  const PlaceSearchException(this.message);
  final String message;
}

/// Explicit-submit search for an operator-provided Nominatim-compatible API.
/// The public OSM endpoint is deliberately not enabled by default. Production
/// operators must use a proxy with global throttling and response caching.
class PlaceSearchService {
  static const _recentKey = 'place_search_recent_v1';
  /// The production worker returns the app's compact Nominatim-compatible
  /// contract: [{name, display_name, lat, lon}]. A release can override this
  /// endpoint with --dart-define=PLACE_SEARCH_URL=... when it is migrated.
  static const _defaultEndpoint = 'https://almost-there.corche00.workers.dev/';
  static const _configuredEndpoint = String.fromEnvironment(
    'PLACE_SEARCH_URL',
    defaultValue: _defaultEndpoint,
  );
  static final Map<String, List<PlaceResult>> _cache = {};
  static DateTime? _lastRequest;
  static bool _inFlight = false;

  Future<List<PlaceResult>> search(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2) {
      throw const PlaceSearchException('장소 이름을 두 글자 이상 입력해 주세요.');
    }
    final preferences = await SharedPreferences.getInstance();
    // An operator may update this preference from remote configuration at run
    // time, allowing provider changes without publishing another app release.
    final endpoint =
        preferences.getString('place_search_endpoint') ?? _configuredEndpoint;
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const PlaceSearchException(
        '장소 검색이 아직 준비되지 않았어요. 지도를 눌러 목적지를 선택해 주세요.',
      );
    }
    final cacheKey = '$endpoint|$normalized';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;
    final diskKey = 'place_search_cache:${Uri.encodeComponent(cacheKey)}';
    final diskValue = preferences.getString(diskKey);
    if (diskValue != null) {
      try {
        final saved = jsonDecode(diskValue) as Map<String, dynamic>;
        final cachedAt = DateTime.fromMillisecondsSinceEpoch(
          saved['at'] as int,
        );
        if (DateTime.now().difference(cachedAt) < const Duration(days: 7)) {
          final rows = (saved['results'] as List).cast<Map<String, dynamic>>();
          return _cache[cacheKey] = rows.map(PlaceResult.fromJson).toList();
        }
      } catch (_) {
        await preferences.remove(diskKey);
      }
    }
    if (_inFlight) throw const PlaceSearchException('앞선 검색이 끝나면 다시 시도해 주세요.');
    _inFlight = true;
    try {
      if (_lastRequest != null) {
        final gap = DateTime.now().difference(_lastRequest!);
        if (gap < const Duration(milliseconds: 1100)) {
          await Future<void>.delayed(const Duration(milliseconds: 1100) - gap);
        }
      }
      _lastRequest = DateTime.now();
      final response = await http
          .get(
            uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                'q': normalized,
                'format': 'jsonv2',
                'limit': '5',
                'accept-language': 'ko',
              },
            ),
            headers: {
              'Accept': 'application/json',
              'User-Agent':
                  'AlmostThere/1.0 (arrival alarm; explicit user search)',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const PlaceSearchException('지금은 장소를 검색할 수 없어요. 잠시 후 다시 시도해 주세요.');
      }
      final rows = (jsonDecode(utf8.decode(response.bodyBytes)) as List)
          .cast<Map<String, dynamic>>();
      final results = rows.map(PlaceResult.fromJson).toList();
      _cache[cacheKey] = results;
      await preferences.setString(
        diskKey,
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'results': rows,
        }),
      );
      return results;
    } on PlaceSearchException {
      rethrow;
    } catch (_) {
      throw const PlaceSearchException('인터넷 연결을 확인한 후 다시 검색해 주세요.');
    } finally {
      _inFlight = false;
    }
  }

  Future<List<PlaceResult>> recentSearches() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_recentKey);
    if (value == null) return const [];
    try {
      return (jsonDecode(value) as List)
          .cast<Map<String, dynamic>>()
          .map(PlaceResult.fromJson)
          .toList();
    } catch (_) {
      await preferences.remove(_recentKey);
      return const [];
    }
  }

  Future<void> remember(PlaceResult place) async {
    final existing = await recentSearches();
    final unique = <PlaceResult>[place];
    for (final item in existing) {
      if (item.latitude != place.latitude || item.longitude != place.longitude) {
        unique.add(item);
      }
    }
    final rows = unique.take(6).map((item) => {
      'name': item.name,
      'display_name': item.address,
      'lat': item.latitude.toString(),
      'lon': item.longitude.toString(),
    }).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_recentKey, jsonEncode(rows));
  }

  /// The configured endpoint exposes text search only. Query a small set of
  /// useful landmark categories and retain the closest returned result for
  /// each category, so the editor can offer a compact nearby shortlist.
  Future<List<PlaceResult>> nearbyHighlights({
    required double latitude,
    required double longitude,
  }) async {
    const categories = ['역', '터미널', '병원', '편의점'];
    final highlights = <PlaceResult>[];
    for (final category in categories) {
      try {
        final candidates = await search(category);
        if (candidates.isEmpty) continue;
        candidates.sort((a, b) => Geolocator.distanceBetween(
              latitude,
              longitude,
              a.latitude,
              a.longitude,
            ).compareTo(Geolocator.distanceBetween(
              latitude,
              longitude,
              b.latitude,
              b.longitude,
            )));
        final closest = candidates.first;
        if (!highlights.any((item) =>
            item.latitude == closest.latitude && item.longitude == closest.longitude)) {
          highlights.add(closest);
        }
      } on PlaceSearchException {
        // A single unavailable category should not hide the rest.
      }
    }
    return highlights;
  }
}
