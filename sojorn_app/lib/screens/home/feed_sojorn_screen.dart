// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/api_provider.dart';
import '../../providers/feed_refresh_provider.dart';
import '../../models/post.dart';
import '../../theme/theme_extensions.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/post/sojorn_swipeable_post.dart';
import '../../widgets/post/post_view_mode.dart';
import '../../widgets/sojorn_post_card.dart';
import '../../services/ad_integration_service.dart';
import '../compose/compose_screen.dart';
import '../../widgets/desktop/desktop_slide_panel.dart';

/// sojorn feed - TikTok/Reels style immersive swipeable feed
class FeedsojornScreen extends ConsumerStatefulWidget {
  const FeedsojornScreen({super.key});

  @override
  ConsumerState<FeedsojornScreen> createState() => _FeedsojornScreenState();
}

class _FeedsojornScreenState extends ConsumerState<FeedsojornScreen> {
  List<Post> _posts = [];
  List<Post> _feedItems = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  int _currentPage = 0;
  final PageController _pageController = PageController();
  late final AdIntegrationService _adService;

  // Positions in the feed where beacon alert cards are injected.
  static const List<int> _alertInjectionPositions = [2, 7];

  @override
  void initState() {
    super.initState();
    _adService = AdIntegrationService(ref.read);
    _loadPosts();
    _loadNearbyAlerts();
  }

  /// Fetches geo-alerts within 2 km and injects them into the feed.
  /// Runs fire-and-forget — the feed loads even if this fails.
  Future<void> _loadNearbyAlerts() async {
    try {
      // Check location permission — skip silently if not granted.
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 5));

      final apiService = ref.read(apiServiceProvider);
      final alerts = await apiService.fetchNearbyBeacons(
        lat: position.latitude,
        long: position.longitude,
        radius: 2000, // 2 km — only hyperlocal alerts in the feed
      );

      // Keep only active geo-alerts, sorted by severity (critical first) then recency.
      final filtered = alerts
          .where((p) => p.isBeaconPost && (p.beaconType?.isGeoAlert ?? false))
          .toList()
        // Sort by recency — most recent safety alerts surface first.
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Cap at 2 injected alerts so the feed doesn't feel like a siren.
      final capped = filtered.take(_alertInjectionPositions.length).toList();

      if (!mounted || capped.isEmpty) { return; }
      _setStateIfMounted(() {
        _feedItems = _injectAlerts(_feedItems, capped);
      });
    } catch (_) {
      // Silent fail — beacon alerts are ambient, never blocking.
    }
  }

  /// Injects beacon alert posts into the feed at [_alertInjectionPositions].
  List<Post> _injectAlerts(List<Post> base, List<Post> alerts) {
    final result = List<Post>.from(base);
    // Remove any previously injected alert posts first.
    result.removeWhere((p) => p.isBeaconPost);
    for (var i = 0; i < alerts.length; i++) {
      final pos = _alertInjectionPositions[i];
      if (pos <= result.length) {
        result.insert(pos, alerts[i]);
      } else {
        result.add(alerts[i]);
      }
    }
    return result;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading) return;

    debugPrint('[Feed/Sojorn] load — refresh=$refresh offset=${refresh ? 0 : _posts.length}');
    _setStateIfMounted(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _posts = [];
        _feedItems = [];
        _hasMore = true;
        _currentPage = 0;
      }
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final posts = await apiService.getSojornFeed(
        limit: 20,
        offset: refresh ? 0 : _posts.length,
      );
      debugPrint('[Feed/Sojorn] fetched ${posts.length} posts');

      final hasSponsored = posts.any((post) => post.isSponsored);
      List<Post> batchItems = posts;

      if (!hasSponsored && posts.isNotEmpty) {
        final ad = await _adService.loadSponsoredPostForPost(posts.first);
        batchItems = posts.interleaveWithAd(
          ad,
          interval: 10,
          maxAds: 2,
          fallbackAd: _adService.getAd(),
        );
      }

      _setStateIfMounted(() {
        if (refresh) {
          _posts = posts;
          // Re-inject any previously loaded beacon alerts into the fresh feed.
          _feedItems = _injectAlerts(batchItems, []);
        } else {
          _posts.addAll(posts);
          _feedItems.addAll(batchItems);
        }
        _hasMore = posts.length == 20;
        if (refresh && posts.isNotEmpty) {
          _currentPage = 0;
          _pageController.jumpToPage(0);
        }
      });
    } catch (e) {
      _setStateIfMounted(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      _setStateIfMounted(() {
        _isLoading = false;
      });
    }
    // Re-fetch alerts on manual refresh so the most current local safety
    // information always appears in the freshly loaded feed.
    if (refresh) _loadNearbyAlerts();
  }

  void _onPageChanged(int page) {
    _currentPage = page;
    // Load more when approaching the end
    if (page >= _feedItems.length - 3 && _hasMore && !_isLoading) {
      _loadPosts();
    }
  }

  void _openPostDetail(Post post) {
    context.push('/p/${post.id}', extra: post);
  }

  void _openChainComposer(Post post) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(chainParentPost: post),
        fullscreenDialog: true,
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _openAuthorProfile(Post post) {
    if (post.author != null && post.author!.handle.isNotEmpty) {
      context.push('/u/${post.author!.handle}');
    }
  }

  Future<void> _toggleLike(Post post) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      if (post.isLiked == true) {
        await apiService.unappreciatePost(post.id);
      } else {
        await apiService.appreciatePost(post.id);
      }
      // Reload posts to get updated like status
      _loadPosts(refresh: true);
    } catch (e) {
      // Handle error silently or show snackbar
    }
  }

  void _sharePost(Post post) {
    final text = post.body.isNotEmpty ? post.body : 'Check this out on Sojorn';
    Share.share(text, subject: 'Shared from Sojorn');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(feedRefreshProvider, (_, __) {
      _loadPosts(refresh: true);
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: _buildBody(),
        floatingActionButton: _feedItems.isNotEmpty
            ? FloatingActionButton(
                heroTag: 'sojorn_compose',
                onPressed: () {
                  final isDesktop = MediaQuery.of(context).size.width >= 900;
                  if (isDesktop) {
                    openDesktopSlidePanel(context, width: 520, child: const ComposeScreen());
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ComposeScreen(),
                        fullscreenDialog: true,
                      ),
                    );
                  }
                },
                backgroundColor: AppTheme.brightNavy,
                foregroundColor: SojornColors.basicWhite,
                child: const Icon(Icons.add),
              )
            : null,
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: () => _loadPosts(refresh: true),
      );
    }

    if (_feedItems.isEmpty && _isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: SojornColors.basicWhite,
        ),
      );
    }

    if (_feedItems.isEmpty && !_isLoading) {
      return const _EmptyState();
    }

    return Stack(
      children: [
        // Vertical swipeable feed
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          onPageChanged: _onPageChanged,
          itemCount: _feedItems.length,
          itemBuilder: (context, index) {
            final post = _feedItems[index];
            // Sponsored posts get their own full-screen branded slide.
            if (post.isSponsored) {
              return _SponsoredPostSlide(post: post);
            }
            // Beacon geo-alerts get an urgent inline alert card that
            // surfaces hyperlocal safety information without leaving the feed.
            if (post.isBeaconPost) {
              return _BeaconAlertFeedSlide(
                post: post,
                onViewMap: () {
                  // Navigate to the Beacons tab (index 2 in the shell).
                  // The NavigationShellScope is an InheritedWidget ancestor.
                  final nav = Navigator.of(context, rootNavigator: true);
                  nav.popUntil((r) => r.isFirst);
                },
                onDismiss: () {
                  if (!mounted) return;
                  setState(() {
                    _feedItems.removeAt(index);
                  });
                },
              );
            }
            // Regular post
            return sojornSwipeablePost(
              post: post,
              onLike: () => _toggleLike(post),
              onComment: () => _openPostDetail(post),
              onShare: () => _sharePost(post),
              onChain: () => _openChainComposer(post),
              onAuthorTap: () => _openAuthorProfile(post),
              onExpandText: () {},
            );
          },
        ),

        // Loading indicator at bottom when fetching more
        if (_isLoading && _posts.isNotEmpty)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: SojornColors.overlayDark,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SojornColors.basicWhite,
                  ),
                ),
              ),
            ),
          ),
        if (kDebugMode) _buildAdDebugOverlay(),
      ],
    );
  }

  Widget _buildAdDebugOverlay() {
    final adIndices = <int>[];
    for (var i = 0; i < _feedItems.length; i++) {
      if (_feedItems[i].isSponsored) {
        adIndices.add(i + 1);
      }
    }

    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SojornColors.overlayDark,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SojornColors.basicWhite.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ad Debug',
              style: TextStyle(
                color: SojornColors.basicWhite,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'items: ${_feedItems.length} | ads: ${adIndices.length}',
              style: TextStyle(
                color: SojornColors.basicWhite.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              adIndices.isEmpty
                  ? 'ad positions: none'
                  : 'ad positions: ${adIndices.join(', ')}',
              style: TextStyle(
                color: SojornColors.basicWhite.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SojornColors.feedNavyTop,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              style: AppTheme.bodyMedium.copyWith(
                color: SojornColors.basicWhite,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingMd),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Retry',
                style: TextStyle(color: SojornColors.basicWhite),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SojornColors.feedNavyTop,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.explore_outlined,
              size: 64.0,
              color: SojornColors.basicWhite.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            Text(
              'No active beacons or posts',
              style: AppTheme.headlineSmall.copyWith(
                color: SojornColors.basicWhite,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-screen beacon alert slide inserted into the home feed.
///
/// Surfaces hyperlocal safety/community alerts from within 2 km without
/// the user having to switch to the Beacons tab. The card's left-edge color
/// and icon match the BeaconType taxonomy, so the visual language is
/// identical to what users see on the Beacon map.
class _BeaconAlertFeedSlide extends StatelessWidget {
  final Post post;
  final VoidCallback onViewMap;
  final VoidCallback onDismiss;

  const _BeaconAlertFeedSlide({
    required this.post,
    required this.onViewMap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final beacon = post.toBeacon();
    final typeColor = post.beaconType?.color ?? AppTheme.error;
    final isRecent = beacon.isRecent;

    return Container(
      color: const Color(0xFF0A0A12),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Ambient Label ───────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: typeColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sensors, size: 12, color: typeColor),
                        const SizedBox(width: 5),
                        Text(
                          'NEARBY BEACON',
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Dismiss button
                  GestureDetector(
                    onTap: onDismiss,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, size: 16,
                          color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // ── Main Alert Card ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF141420),
                  borderRadius: BorderRadius.circular(20),
                  border: Border(
                    left: BorderSide(color: typeColor, width: 4),
                    top: BorderSide(color: typeColor.withValues(alpha: 0.2)),
                    right: BorderSide(color: typeColor.withValues(alpha: 0.2)),
                    bottom: BorderSide(color: typeColor.withValues(alpha: 0.2)),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Type row
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(post.beaconType?.icon ?? Icons.warning,
                              color: typeColor, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.beaconType?.displayName ?? 'Alert',
                                style: TextStyle(
                                  color: typeColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.schedule, size: 11,
                                      color: Colors.white.withValues(alpha: 0.4)),
                                  const SizedBox(width: 3),
                                  Text(
                                    beacon.getTimeAgo(),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(Icons.location_on, size: 11,
                                      color: Colors.white.withValues(alpha: 0.4)),
                                  const SizedBox(width: 3),
                                  Text(
                                    beacon.getFormattedDistance(),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (isRecent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: SojornColors.destructive
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text('LIVE',
                                          style: TextStyle(
                                            color: SojornColors.destructive,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          )),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Body text
                    if (post.body.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        post.body,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.5,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Actions ─────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onViewMap,
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('View on Map'),
                      style: FilledButton.styleFrom(
                        backgroundColor: typeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: onDismiss,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.6),
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                    ),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Swipe hint
              Center(
                child: Text(
                  'Swipe to continue your feed',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.25),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SponsoredPostSlide extends StatelessWidget {
  final Post post;

  const _SponsoredPostSlide({required this.post});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<SojornExt>()!.feedPalettes.forId(post.id);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.backgroundTop, palette.backgroundBottom],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: sojornPostCard(
                post: post,
                mode: PostViewMode.sponsored,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
