import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../post/post_detail_screen.dart';
import '../profile/viewable_profile_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _adService = AdIntegrationService(ref.read);
    _loadPosts();
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
          _feedItems = batchItems;
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
  }

  void _onPageChanged(int page) {
    _currentPage = page;
    // Load more when approaching the end
    if (page >= _feedItems.length - 3 && _hasMore && !_isLoading) {
      _loadPosts();
    }
  }

  void _openPostDetail(Post post) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(post: post),
      ),
    );
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
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => UnifiedProfileScreen(handle: post.author!.handle),
        ),
      );
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
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ComposeScreen(),
                      fullscreenDialog: true,
                    ),
                  );
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
            // Check if this is a sponsored post
            if (post.isSponsored) {
              return _SponsoredPostSlide(post: post);
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
