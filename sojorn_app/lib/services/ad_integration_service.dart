// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sponsored_post.dart';
import '../models/post.dart';
import '../providers/api_provider.dart';

/// Helper class for integrating sponsored content into feeds
///
/// Usage:
/// 1. Add a SponsoredPost? _currentAd field to your screen
/// 2. Call loadSponsoredPost(categoryId) when loading posts
/// 3. Insert the SponsoredPostCard widget at the desired position in the list
/// 4. Call recordAdImpression() when the ad becomes visible
class AdIntegrationService {
  final Function _read;

  AdIntegrationService(this._read);

  /// Currently loaded sponsored post (null if none available)
  SponsoredPost? get currentAd => _currentAd;
  SponsoredPost? _currentAd;

  /// Load a sponsored post for the given category
  Future<SponsoredPost?> loadSponsoredPost(String? categoryId) async {
    if (categoryId == null || categoryId.isEmpty) {
      return _currentAd;
    }
    try {
      final apiService = _read(apiServiceProvider);
      final ad = await apiService.getSponsoredPost(categoryId: categoryId);
      if (ad != null) {
        _currentAd = ad;
        return ad;
      }
      if (_currentAd != null && _currentAd!.matchesCategory(categoryId)) {
        return _currentAd;
      }
      return null;
    } catch (e) {
      if (_currentAd != null && _currentAd!.matchesCategory(categoryId)) {
        return _currentAd;
      }
      return null;
    }
  }

  /// Load a sponsored post based on an existing post's category
  Future<SponsoredPost?> loadSponsoredPostForPost(Post post) async {
    return loadSponsoredPost(post.categoryId);
  }

  /// Record an impression for the current ad
  Future<void> recordAdImpression() async {
    if (_currentAd != null) {
      try {
        final apiService = _read(apiServiceProvider);
        await apiService.recordAdImpression(_currentAd!.id);
      } catch (e) {
        // Silently fail - impression tracking is not critical
      }
    }
  }

  /// Clear the current ad (e.g., on refresh)
  void clearAd() {
    _currentAd = null;
  }

  /// Check if an ad is currently loaded
  bool get hasAd => _currentAd != null;

  /// Get the current ad for display
  SponsoredPost? getAd() => _currentAd;
}

/// Extension on List to interleave sponsored posts
extension ListAdExtension on List<Post> {
  /// Insert sponsored content at regular intervals
  ///
  /// [ad] - The sponsored post to insert
  /// [interval] - Insert after every N posts (default: 10)
  /// [maxAds] - Maximum number of ads to insert (default: 1)
  List<Post> interleaveWithAd(
    SponsoredPost? ad, {
    int interval = 10,
    int maxAds = 1,
    SponsoredPost? fallbackAd,
  }) {
    if (isEmpty) {
      return [...this];
    }

    final activeAd = ad ?? fallbackAd;
    if (activeAd == null) {
      return [...this];
    }

    final result = <Object>[];
    int adCount = 0;
    final safeInterval = interval <= 0 ? length : interval;
    final maxPossibleAds = length ~/ safeInterval;
    final effectiveMaxAds = maxAds.clamp(0, maxPossibleAds);
    final adPost = _sponsoredPostToPost(activeAd);

    for (int i = 0; i < length; i++) {
      result.add(this[i]);

      // Insert ad after every N posts, up to maxAds
      if ((i + 1) % safeInterval == 0 && adCount < effectiveMaxAds) {
        result.add(adPost);
        adCount++;
      }
    }

    return result.cast<Post>();
  }
}

/// Extension on AsyncData to handle ad loading
extension AdLoadingExtension on AsyncValue<List<Post>> {
  /// Transform posts to include sponsored content
  Future<AsyncValue<List<Post>>> withSponsoredContent(
    String? categoryId,
    Ref ref,
  ) async {
    final data = asData;
    if (data == null) {
      return this;
    }
    final posts = data.value;

    final adService = AdIntegrationService(ref.read);
    await adService.loadSponsoredPost(categoryId);

    final ad = adService.getAd();
    final postsWithAds = posts.interleaveWithAd(
      ad,
      interval: 10,
      maxAds: 2,
      fallbackAd: adService.getAd(),
    );

    return AsyncData(postsWithAds);
  }
}

Post _sponsoredPostToPost(SponsoredPost ad) {
  return Post(
    id: ad.id,
    authorId: 'sponsored',
    categoryId:
        ad.targetCategories.isNotEmpty ? ad.targetCategories.first : null,
    body: ad.body,
    status: PostStatus.active,
    detectedTone: ToneLabel.neutral,
    contentIntegrityScore: 1.0,
    createdAt: DateTime.now(),
    allowChain: false,
    imageUrl: ad.imageUrl,
    isSponsored: true,
    advertiserName: ad.advertiserName,
    ctaLink: ad.ctaLink,
    ctaText: ad.ctaText,
  );
}
