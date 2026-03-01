// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class SoundItem {
  final String id;
  final String title;
  final String bucket;
  final int? durationMs;
  final int useCount;
  final String audioUrl;

  const SoundItem({
    required this.id,
    required this.title,
    required this.bucket,
    this.durationMs,
    required this.useCount,
    required this.audioUrl,
  });

  factory SoundItem.fromJson(Map<String, dynamic> j) => SoundItem(
        id: j['id'] as String,
        title: j['title'] as String,
        bucket: j['bucket'] as String,
        durationMs: j['duration_ms'] as int?,
        useCount: (j['use_count'] as num?)?.toInt() ?? 0,
        audioUrl: j['audio_url'] as String,
      );

  String get formattedDuration {
    if (durationMs == null) return '';
    final s = (durationMs! / 1000).round();
    final m = s ~/ 60;
    final rem = s % 60;
    return '$m:${rem.toString().padLeft(2, '0')}';
  }
}

class SoundsState {
  final List<SoundItem> trending;
  final List<SoundItem> library;
  final bool loading;
  final String? error;

  const SoundsState({
    this.trending = const [],
    this.library = const [],
    this.loading = false,
    this.error,
  });

  SoundsState copyWith({
    List<SoundItem>? trending,
    List<SoundItem>? library,
    bool? loading,
    String? error,
  }) =>
      SoundsState(
        trending: trending ?? this.trending,
        library: library ?? this.library,
        loading: loading ?? this.loading,
        error: error,
      );
}

class SoundsNotifier extends Notifier<SoundsState> {
  @override
  SoundsState build() => const SoundsState();

  Future<void> load() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final userRes = await ApiService.instance.get('/sounds', queryParams: {'bucket': 'user', 'limit': '50'});
      final libRes = await ApiService.instance.get('/sounds', queryParams: {'bucket': 'library', 'limit': '50'});

      final trending = (userRes['sounds'] as List? ?? [])
          .map((e) => SoundItem.fromJson(e as Map<String, dynamic>))
          .toList();
      final library = (libRes['sounds'] as List? ?? [])
          .map((e) => SoundItem.fromJson(e as Map<String, dynamic>))
          .toList();

      state = state.copyWith(trending: trending, library: library, loading: false);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> recordUse(String soundId) async {
    try {
      await ApiService.instance.post('/sounds/$soundId/use', {});
    } catch (_) {
      // Non-critical — fire and forget
    }
  }
}

final soundsProvider = NotifierProvider<SoundsNotifier, SoundsState>(SoundsNotifier.new);
