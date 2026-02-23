// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/api_provider.dart';
import '../../providers/feed_refresh_provider.dart';
import '../../models/post.dart';
import '../../models/feed_filter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sojorn_post_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feed_filter_button.dart';
import '../compose/compose_screen.dart';
import '../post/post_detail_screen.dart';
import '../../widgets/desktop/desktop_dialog_helper.dart';
import '../../widgets/first_use_hint.dart';
import '../../widgets/skeleton_loader.dart';

/// Personal feed - chronological posts from followed users, presented vibrantly
class FeedPersonalScreen extends ConsumerStatefulWidget {
  const FeedPersonalScreen({super.key});

  @override
  ConsumerState<FeedPersonalScreen> createState() => _FeedPersonalScreenState();
}

class _FeedPersonalScreenState extends ConsumerState<FeedPersonalScreen> {
  List<Post> _posts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  FeedFilter _currentFilter = FeedFilter.all;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  void _setStateIfMounted(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_isLoading) return;

    debugPrint('[Feed/Personal] load — refresh=$refresh offset=${refresh ? 0 : _posts.length} filter=${_currentFilter.typeValue}');
    _setStateIfMounted(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _posts = [];
        _hasMore = true;
      }
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final posts = await apiService.getPersonalFeed(
        limit: 50,
        offset: refresh ? 0 : _posts.length,
        filterType: _currentFilter.typeValue,
      );
      debugPrint('[Feed/Personal] fetched ${posts.length} posts');

      _setStateIfMounted(() {
        if (refresh) {
          _posts = posts;
        } else {
          _posts.addAll(posts);
        }
        _hasMore = posts.length == 50;
      });
    } catch (e) {
      debugPrint('[Feed/Personal] ✗ load failed: $e');
      _setStateIfMounted(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      _setStateIfMounted(() {
        _isLoading = false;
      });
    }
  }

  void _openPostDetail(Post post) {
    openDesktopDialog(context, width: 700, child: PostDetailScreen(post: post));
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

  void _onFilterChanged(FeedFilter filter) {
    setState(() => _currentFilter = filter);
    _loadPosts(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(feedRefreshProvider, (_, __) {
      _loadPosts(refresh: true);
    });

    return AppScaffold(
      title: '',
      showAppBar: false,
      actions: [
        FeedFilterButton(
          currentFilter: _currentFilter,
          onFilterChanged: _onFilterChanged,
        ),
      ],
      body: _error != null
          ? _ErrorState(
              message: _error!,
              onRetry: () => _loadPosts(refresh: true),
            )
          : _posts.isEmpty && !_isLoading
              ? const _EmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadPosts(refresh: true),
                  child: CustomScrollView(
                    slivers: [
                      const SliverToBoxAdapter(
                        child: FirstUseHint(
                          storageKey: 'hint_following',
                          text: 'People you’ve chosen',
                        ),
                      ),
                      if (_isLoading && _posts.isEmpty)
                        const SliverToBoxAdapter(
                          child: SkeletonFeedList(count: 5),
                        ),
                      SliverPadding(
                        padding: EdgeInsets.only(
                          top: AppTheme.spacingSm,
                          bottom: AppTheme.spacingLg *
                              2, // Replaced AppTheme.spacing4xl
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index == _posts.length - 1 &&
                                  _hasMore &&
                                  !_isLoading) {
                                _loadPosts();
                              }

                              final post = _posts[index];
                              return sojornPostCard(
                                post: post,
                                onTap: () => _openPostDetail(post),
                                onChain: () => _openChainComposer(post),
                              );
                            },
                            childCount: _posts.length,
                          ),
                        ),
                      ),
                      if (_isLoading && _posts.isNotEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppTheme.spacingLg,
                            ),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      if (!_hasMore && _posts.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: AppTheme.spacingMd,
                              bottom: AppTheme.spacingLg *
                                  2, // Replaced AppTheme.spacing4xl
                            ),
                            child: Text(
                              'You’ve reached the end.',
                              style: AppTheme.textTheme.labelSmall?.copyWith(
                                // Replaced bodySmall
                                color: AppTheme
                                    .egyptianBlue, // Replaced AppTheme.textTertiary
                              ),
                              textAlign: TextAlign.center,
                            ),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacingMd),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64.0,
            color: AppTheme.egyptianBlue,
          ),
          const SizedBox(height: AppTheme.spacingMd),
          Text(
            'Your feed is vibrant!', // Updated text
            style: AppTheme.headlineSmall.copyWith(
              color: AppTheme.navyText
                  .withValues(alpha: 0.8), // Replaced AppTheme.textSecondary
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            'Posts from your chosen categories appear here',
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.egyptianBlue, // Replaced AppTheme.textTertiary
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
