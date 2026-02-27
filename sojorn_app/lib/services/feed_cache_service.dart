// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/post.dart';

/// Lightweight feed cache for offline reading.
///
/// Stores the last [maxPosts] posts per feed key (e.g. neighborhood ID)
/// as JSON in a Hive box. On reconnect, callers should call [cachePosts]
/// with fresh data — this does a full-replace, never a merge, to avoid
/// surfacing stale or retracted content.
class FeedCacheService {
  FeedCacheService._();
  static final FeedCacheService instance = FeedCacheService._();

  static const String _boxName = 'feed_cache_v1';
  static const String _timestampBoxName = 'feed_cache_timestamps_v1';
  static const int maxPosts = 20;

  Box<String>? _box;
  Box<String>? _timestampBox;
  bool _ready = false;

  Future<void> _ensureBoxes() async {
    if (_ready) return;
    _box = await Hive.openBox<String>(_boxName);
    _timestampBox = await Hive.openBox<String>(_timestampBoxName);
    _ready = true;
  }

  /// Cache posts for a given feed key (full-replace, never merge).
  Future<void> cachePosts(String feedKey, List<Post> posts) async {
    try {
      await _ensureBoxes();
      final capped = posts.take(maxPosts).toList();
      final jsonList = capped.map((p) => jsonEncode(p.toJson())).toList();
      await _box!.put(feedKey, jsonEncode(jsonList));
      await _timestampBox!.put(feedKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('[FeedCache] Failed to cache posts for $feedKey: $e');
    }
  }

  /// Load cached posts for a feed key. Returns empty list if no cache.
  Future<List<Post>> getCachedPosts(String feedKey) async {
    try {
      await _ensureBoxes();
      final raw = _box!.get(feedKey);
      if (raw == null) return [];

      final jsonList = (jsonDecode(raw) as List).cast<String>();
      return jsonList
          .map((s) => Post.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[FeedCache] Failed to read cache for $feedKey: $e');
      return [];
    }
  }

  /// Get the timestamp of the last cache write for a feed key.
  DateTime? getLastCacheTime(String feedKey) {
    try {
      if (!_ready || _timestampBox == null) return null;
      final raw = _timestampBox!.get(feedKey);
      if (raw == null) return null;
      return DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Clear cache for a specific feed key.
  Future<void> clearFeed(String feedKey) async {
    await _ensureBoxes();
    await _box!.delete(feedKey);
    await _timestampBox!.delete(feedKey);
  }

  /// Clear all cached feeds.
  Future<void> clearAll() async {
    await _ensureBoxes();
    await _box!.clear();
    await _timestampBox!.clear();
  }
}
