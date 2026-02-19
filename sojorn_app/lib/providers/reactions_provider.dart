import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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
