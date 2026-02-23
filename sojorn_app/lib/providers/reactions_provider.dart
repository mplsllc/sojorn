// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _cdnBase = 'https://reactions.sojorn.net';

/// Parsed reaction package ready for use by [ReactionPicker].
class ReactionPackage {
  final List<String> tabOrder;
  final Map<String, List<String>> reactionSets; // tabId → list of identifiers (URL or emoji)
  final Map<String, String> folderCredits; // tabId → credit markdown

  const ReactionPackage({
    required this.tabOrder,
    required this.reactionSets,
    required this.folderCredits,
  });
}

/// Riverpod provider that loads reaction sets once per app session.
/// Priority: CDN index.json → local assets → hardcoded emoji.
final reactionPackageProvider = FutureProvider<ReactionPackage>((ref) async {
  // 1. Try CDN
  debugPrint('[Reactions] fetching CDN: $_cdnBase/index.json');
  try {
    final response = await http
        .get(Uri.parse('$_cdnBase/index.json'))
        .timeout(const Duration(seconds: 5));

    debugPrint('[Reactions] CDN status=${response.statusCode}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tabsRaw =
          (data['tabs'] as List? ?? []).whereType<Map<String, dynamic>>();

      final tabOrder = <String>['emoji'];
      final reactionSets = <String, List<String>>{'emoji': _defaultEmoji};
      final folderCredits = <String, String>{};

      for (final tab in tabsRaw) {
        final id = tab['id'] as String? ?? '';
        if (id.isEmpty || id == 'emoji') continue;

        final credit = tab['credit'] as String?;
        final files =
            (tab['reactions'] as List? ?? []).whereType<String>().toList();
        final urls = files.map((f) => '$_cdnBase/$id/$f').toList();

        tabOrder.add(id);
        reactionSets[id] = urls;
        if (credit != null && credit.isNotEmpty) {
          folderCredits[id] = credit;
        }
      }

      // Only return CDN result if we got actual image tabs (not just emoji)
      if (tabOrder.length > 1) {
        debugPrint('[Reactions] CDN loaded — tabs: ${tabOrder.join(', ')}');
        return ReactionPackage(
          tabOrder: tabOrder,
          reactionSets: reactionSets,
          folderCredits: folderCredits,
        );
      } else {
        debugPrint('[Reactions] CDN returned no image tabs — falling back');
      }
    }
  } catch (e) {
    debugPrint('[Reactions] ✗ CDN fetch failed: $e');
  }

  // 2. Fallback: local assets
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetPaths = manifest.listAssets();
    final reactionAssets = assetPaths.where((path) {
      final lp = path.toLowerCase();
      return lp.startsWith('assets/reactions/') &&
          (lp.endsWith('.png') ||
              lp.endsWith('.svg') ||
              lp.endsWith('.webp') ||
              lp.endsWith('.jpg') ||
              lp.endsWith('.jpeg') ||
              lp.endsWith('.gif'));
    }).toList();

    if (reactionAssets.isNotEmpty) {
      final tabOrder = <String>['emoji'];
      final reactionSets = <String, List<String>>{'emoji': _defaultEmoji};
      final folderCredits = <String, String>{};

      for (final path in reactionAssets) {
        final parts = path.split('/');
        if (parts.length >= 4) {
          final folder = parts[2];
          if (!reactionSets.containsKey(folder)) {
            tabOrder.add(folder);
            reactionSets[folder] = [];
            try {
              final creditPath = 'assets/reactions/$folder/credit.md';
              if (assetPaths.contains(creditPath)) {
                folderCredits[folder] =
                    await rootBundle.loadString(creditPath);
              }
            } catch (_) {}
          }
          reactionSets[folder]!.add(path);
        }
      }

      for (final key in reactionSets.keys) {
        if (key != 'emoji') {
          reactionSets[key]!
              .sort((a, b) => a.split('/').last.compareTo(b.split('/').last));
        }
      }

      return ReactionPackage(
        tabOrder: tabOrder,
        reactionSets: reactionSets,
        folderCredits: folderCredits,
      );
    }
  } catch (_) {}

  // 3. Hardcoded emoji fallback
  return ReactionPackage(
    tabOrder: ['emoji'],
    reactionSets: {'emoji': _defaultEmoji},
    folderCredits: {},
  );
});

const _defaultEmoji = [
  '❤️', '👍', '😂', '😮', '😢', '😡',
  '🎉', '🔥', '👏', '🙏', '💯', '🤔',
  '😍', '🤣', '😊', '👌', '🙌', '💪',
  '🎯', '⭐', '✨', '🌟', '💫', '☀️',
];

// ─────────────────────────────────────────────────────────────────────────────
// Recently-Used Reactions (Misskey-inspired)
//
// Misskey keeps a persistent "recently used" tray at the top of the reaction
// picker so your most-used emojis are always one tap away. We replicate this
// with a SharedPreferences-backed LRU list, capped at 8 entries.
// ─────────────────────────────────────────────────────────────────────────────

const _recentReactionsKey = 'recent_reactions_v1';
const _recentReactionsMaxSize = 8;

/// Provides the current recently-used reaction list.
final recentReactionsProvider =
    NotifierProvider<RecentReactionsNotifier, List<String>>(
  RecentReactionsNotifier.new,
);

class RecentReactionsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    // Load async on first build — state starts empty and updates when ready.
    Future.microtask(_load);
    return [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_recentReactionsKey) ?? [];
    state = saved;
  }

  /// Records a reaction use — inserts at front, deduplicates, caps at 8.
  /// Call this wherever a user picks a reaction in the app.
  Future<void> recordUse(String reaction) async {
    final updated = [
      reaction,
      ...state.where((r) => r != reaction),
    ].take(_recentReactionsMaxSize).toList();
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentReactionsKey, updated);
  }
}
