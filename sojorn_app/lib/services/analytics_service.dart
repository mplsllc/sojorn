// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Privacy-compliant analytics via self-hosted Umami.
///
/// All tracking goes through this singleton so the opt-out flag is respected
/// everywhere. Never call the Umami API directly — always use this service.
///
/// Rules:
/// - No user IDs, post IDs, or PII in any event payload
/// - No events from secure chat or capsule screens
/// - No search queries, GPS coordinates, or message content
/// - Fire-and-forget: analytics never blocks UI
/// - Disabled in debug/profile builds
class AnalyticsService {
  static final AnalyticsService instance = AnalyticsService._();
  AnalyticsService._();

  static const _umamiUrl = 'https://stats.mp.ls';
  static const _websiteId = 'd61ba694-1d3a-49c8-b3ce-62ad0711d3d4';
  static const _hostname = 'sojorn.app';
  static const _prefKey = 'analytics_opt_out';

  final _client = http.Client();
  bool _initialized = false;
  bool _optedOut = false;

  /// Events queued before init completes (so early screen views aren't lost).
  final List<_QueuedEvent> _queue = [];

  /// Initialize the service. Call once at app startup (deferred is fine).
  Future<void> initialize() async {
    if (_initialized) return;

    // Always disabled outside release builds.
    if (!kReleaseMode) {
      _initialized = true;
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _optedOut = prefs.getBool(_prefKey) ?? false;
    } catch (_) {
      // If prefs fail, default to tracking enabled.
    }

    _initialized = true;

    // Flush queued events.
    if (!_optedOut) {
      for (final e in _queue) {
        _send(url: e.url, eventName: e.eventName, eventData: e.eventData);
      }
    }
    _queue.clear();
  }

  /// Whether the user has opted out of analytics.
  bool get isOptedOut => _optedOut;

  /// Toggle opt-out. Persists to SharedPreferences.
  Future<void> setOptOut(bool value) async {
    if (value && !_optedOut) {
      // Fire one last event before opting out.
      event('analytics_opted_out');
    }
    _optedOut = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (_) {}
  }

  /// Track a screen view. [path] should be a clean, non-identifying path
  /// like "/home", "/quips", "/profile/other" — never include IDs.
  void screen(String path) {
    if (!kReleaseMode) return;
    if (_optedOut) return;

    if (!_initialized) {
      _queue.add(_QueuedEvent(url: path));
      return;
    }

    _send(url: path);
  }

  /// Track a feature event. [name] is the event name (snake_case).
  /// [value] is an optional string value (e.g., "image", "public").
  void event(String name, {String? value}) {
    if (!kReleaseMode) return;
    if (_optedOut) return;

    final data = value != null ? {'value': value} : null;

    if (!_initialized) {
      _queue.add(_QueuedEvent(url: '/', eventName: name, eventData: data));
      return;
    }

    _send(url: '/', eventName: name, eventData: data);
  }

  /// POST to Umami's /api/send endpoint. Fire-and-forget.
  void _send({
    required String url,
    String? eventName,
    Map<String, dynamic>? eventData,
  }) {
    final payload = <String, dynamic>{
      'hostname': _hostname,
      'language': 'en-US',
      'url': url,
      'website': _websiteId,
    };
    if (eventName != null) payload['name'] = eventName;
    if (eventData != null) payload['data'] = eventData;

    // Fire-and-forget — never await, never throw.
    _client
        .post(
          Uri.parse('$_umamiUrl/api/send'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'type': 'event', 'payload': payload}),
        )
        .then((_) {})
        .catchError((_) {});
  }
}

class _QueuedEvent {
  final String url;
  final String? eventName;
  final Map<String, dynamic>? eventData;
  const _QueuedEvent({required this.url, this.eventName, this.eventData});
}
