import 'dart:async';
import '../../models/profile.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/api_provider.dart';
import '../../models/search_results.dart';
import '../../models/post.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/sojorn_post_card.dart';
import '../../widgets/media/signed_media_image.dart';
import '../profile/viewable_profile_screen.dart';
import '../compose/compose_screen.dart';
import '../post/post_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController searchController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  Timer? debounceTimer;
  bool isLoading = false;
  bool hasSearched = false;
  SearchResults? results;
  List<RecentSearch> recentSearches = [];
  int _searchEpoch = 0;
  
  // Discovery State
  bool _isDiscoveryLoading = false;
  List<Post> _discoveryPosts = [];

  static const Duration debounceDuration = Duration(milliseconds: 300);
  static const List<String> trendingTags = [
    'safety',
    'wellness',
    'growth',
    'focus',
    'community',
    'insights',
    'reflection',
    'nature',
  ];

  @override
  void initState() {
    super.initState();
    loadRecentSearches();

    // If we have an initial query, set it and search
    if (widget.initialQuery != null) {
      final query = widget.initialQuery!;
      searchController.text = query;
      Future.delayed(const Duration(milliseconds: 100), () {
        performSearch(query);
      });
    } else {
      Future.delayed(const Duration(milliseconds: 100), () {
        focusNode.requestFocus();
      });
    }

    _loadDiscoveryContent();
  }
  
  Future<void> _loadDiscoveryContent() async {
    setState(() => _isDiscoveryLoading = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      // Fetch feed content to use as "Popular Now" / Discovery
      final posts = await apiService.getSojornFeed(limit: 10);
      if (mounted) {
        setState(() {
          _discoveryPosts = posts;
          _isDiscoveryLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isDiscoveryLoading = false);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    focusNode.dispose();
    debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentJson = prefs.getStringList('recent_searches') ?? [];
      setState(() {
        recentSearches = recentJson
            .map((e) => RecentSearch.fromJson(jsonDecode(e)))
            .toList();
      });
    } catch (e) {
    }
  }

  Future<void> saveRecentSearch(RecentSearch search) async {
    try {
      recentSearches.removeWhere(
          (s) => s.text.toLowerCase() == search.text.toLowerCase());
      recentSearches.insert(0, search);
      if (recentSearches.length > 10) {
        recentSearches = recentSearches.sublist(0, 10);
      }
      final prefs = await SharedPreferences.getInstance();
      final recentJson =
          recentSearches.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList('recent_searches', recentJson);

      if (mounted) setState(() {});
    } catch (e) {
    }
  }

  Future<void> clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recent_searches');
      setState(() {
        recentSearches = [];
      });
    } catch (e) {
    }
  }

  void onSearchChanged(String value) {
    debounceTimer?.cancel();

    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        results = null;
        hasSearched = false;
        isLoading = false;
      });
      return;
    }

    debounceTimer = Timer(debounceDuration, () {
      if (query.length >= 2) {
        performSearch(query);
      }
    });
  }

  Future<void> performSearch(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;
    final requestId = ++_searchEpoch;

    setState(() {
      isLoading = true;
      hasSearched = true;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final searchResults = await apiService.search(normalizedQuery);
      if (!mounted || requestId != _searchEpoch) {
        return;
      }


      if (searchResults.users.isNotEmpty) {
        await saveRecentSearch(RecentSearch(
          id: searchResults.users.first.id,
          text: searchResults.users.first.username,
          searchedAt: DateTime.now(),
          type: RecentSearchType.user,
        ));
      } else if (searchResults.tags.isNotEmpty) {
        await saveRecentSearch(RecentSearch(
          id: 'tag_${searchResults.tags.first.tag}',
          text: searchResults.tags.first.tag,
          searchedAt: DateTime.now(),
          type: RecentSearchType.tag,
        ));
      }

      if (!mounted || requestId != _searchEpoch) return;
      setState(() {
        results = searchResults;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted || requestId != _searchEpoch) return;
      setState(() {
        isLoading = false;
        results = SearchResults(users: [], tags: [], posts: []);
      });
    }
  }

  void clearSearch() {
    searchController.clear();
    setState(() {
      results = null;
      hasSearched = false;
      isLoading = false;
    });
    focusNode.requestFocus();
  }

  void _openPostDetail(Post post) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(post: post),
      ),
    );
  }

  void _openChainComposer(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposeScreen(chainParentPost: post),
        fullscreenDialog: true,
      ),
    );
  }

  void onRecentSearchTap(RecentSearch search) {
    final query =
        search.type == RecentSearchType.tag ? '#${search.text}' : search.text;
    searchController.text = query;
    performSearch(query);
  }

  Color getTierColor(String tier) {
    switch (tier) {
      case 'trusted':
        return AppTheme.tierTrusted;
      case 'established':
        return AppTheme.tierEstablished;
      default:
        return AppTheme.tierNew;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppTheme.cardSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.navyBlue),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: buildSearchField(),
        actions: [
          if (searchController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear, color: AppTheme.egyptianBlue),
              onPressed: clearSearch,
            ),
        ],
      ),
      body: buildBody(),
    );
  }

  Widget buildSearchField() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.search,
              color: AppTheme.egyptianBlue.withValues(alpha: 0.6), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: searchController,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: 'Search sojorn...',
                hintStyle: TextStyle(color: AppTheme.egyptianBlue),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: AppTheme.bodyMedium,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildBody() {
    if (isLoading) return buildLoadingState();
    if (hasSearched && results != null) return buildResultsState();
    if (recentSearches.isNotEmpty) return buildRecentSearchesState();
    return buildDiscoveryState();
  }

  Widget buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppTheme.royalPurple,
            ),
          ),
          const SizedBox(height: 16),
          Text('Searching...',
              style:
                  AppTheme.labelMedium.copyWith(color: AppTheme.egyptianBlue)),
        ],
      ),
    );
  }

  Widget buildResultsState() {
    if (results == null ||
        (results!.users.isEmpty &&
            results!.tags.isEmpty &&
            results!.posts.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off,
                size: 64, color: AppTheme.egyptianBlue.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No results found',
                style: AppTheme.headlineSmall
                    .copyWith(color: AppTheme.navyText.withValues(alpha: 0.7))),
            const SizedBox(height: 8),
            Text('Try a different search term',
                style:
                    AppTheme.bodyMedium.copyWith(color: AppTheme.egyptianBlue)),
          ],
        ),
      );
    }

    final isTagSearch = searchController.text.trim().startsWith('#');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (results!.users.isNotEmpty) ...[
            buildSectionHeader('People'),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: results!.users.length,
                itemBuilder: (context, index) {
                  final user = results!.users[index];
                  return UserResultItem(
                    user: user,
                    tierColor: getTierColor(user.harmonyTier),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              UnifiedProfileScreen(handle: user.username)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (results!.posts.isNotEmpty) ...[
            buildSectionHeader('Posts'),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: results!.posts.length,
              itemBuilder: (context, index) {
                final post = results!.posts[index];
                return buildPostResultItem(post);
              },
            ),
            const SizedBox(height: 24),
          ],
          if (results!.tags.isNotEmpty) ...[
            buildSectionHeader(isTagSearch ? 'Tag' : 'Tags'),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: results!.tags.length,
              itemBuilder: (context, index) {
                final tag = results!.tags[index];
                return TagResultItem(
                  tag: tag,
                  onTap: () {
                    final query = '#${tag.tag}';
                    searchController.text = query;
                    performSearch(query);
                    saveRecentSearch(RecentSearch(
                      id: 'tag_${tag.tag}',
                      text: tag.tag,
                      searchedAt: DateTime.now(),
                      type: RecentSearchType.tag,
                    ));
                  },
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget buildRecentSearchesState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Searches',
                  style:
                      AppTheme.labelMedium.copyWith(color: AppTheme.navyBlue)),
              TextButton(
                onPressed: clearRecentSearches,
                child: Text('Clear all',
                    style:
                        TextStyle(color: AppTheme.egyptianBlue, fontSize: 13)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: recentSearches.length,
            itemBuilder: (context, index) {
              final search = recentSearches[index];
              return ListTile(
                leading: Icon(
                  search.type == RecentSearchType.user
                      ? Icons.person
                      : Icons.tag,
                  color: AppTheme.egyptianBlue.withValues(alpha: 0.6),
                ),
                title: Text(
                  search.type == RecentSearchType.user
                      ? '@${search.text}'
                      : '#${search.text}',
                  style: AppTheme.bodyMedium,
                ),
                trailing: Icon(Icons.history,
                    color: AppTheme.egyptianBlue.withValues(alpha: 0.4), size: 18),
                onTap: () => onRecentSearchTap(search),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget buildDiscoveryState() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Top Trending',
                style: AppTheme.labelMedium.copyWith(color: AppTheme.navyBlue)),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: trendingTags.length,
            itemBuilder: (context, index) {
              final tag = trendingTags[index];
              return TrendingTagItem(
                tag: tag,
                onTap: () {
                  final query = '#$tag';
                  searchController.text = query;
                  performSearch(query);
                },
              );
            },
          ),
          
          if (_isDiscoveryLoading) ...[
            const SizedBox(height: 32),
            const Center(child: CircularProgressIndicator()),
          ] else if (_discoveryPosts.isNotEmpty) ...[
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Popular Now',
                  style: AppTheme.labelMedium.copyWith(color: AppTheme.navyBlue)),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _discoveryPosts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final post = _discoveryPosts[index];
                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
                  ),
                  child: sojornPostCard(
                    post: post,
                    onTap: () => _openPostDetail(post),
                    onChain: () => _openChainComposer(post),
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Text(
        title,
        style: AppTheme.labelMedium.copyWith(
          color: AppTheme.navyBlue,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget buildPostResultItem(SearchPost post) {
    // Convert SearchPost to minimal Post immediately
    final minimalPost = Post(
      id: post.id,
      body: post.body,
      authorId: post.authorId,
      createdAt: post.createdAt,
      
      // REQUIRED fields missing previously
      status: PostStatus.active,
      detectedTone: ToneLabel.neutral,
      contentIntegrityScore: 0.0,
      
      author: Profile(
        id: post.authorId,
        handle: post.authorHandle,
        displayName: post.authorDisplayName,
        createdAt: DateTime.now(),
        avatarUrl: null, 
      ),
      // Set defaults for rest
      isLiked: false,
      likeCount: 0,
      commentCount: 0, 
      tags: [],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
        ),
        child: sojornPostCard(
          post: minimalPost,
          onTap: () => _openPostDetail(minimalPost),
          onChain: () => _openChainComposer(minimalPost),
          // showActions removed (not supported)
        ),
      ),
    ); 
  }
}

class UserResultItem extends StatelessWidget {
  final SearchUser user;
  final Color tierColor;
  final VoidCallback onTap;

  const UserResultItem(
      {super.key,
      required this.user,
      required this.tierColor,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: tierColor,
                child: user.avatarUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: SignedMediaImage(
                          url: user.avatarUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Text(
                      user.displayName.isNotEmpty
                          ? user.displayName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: SojornColors.basicWhite,
                          fontWeight: FontWeight.bold,
                          fontSize: 22),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              user.displayName,
              style: TextStyle(
                  color: AppTheme.navyText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '@${user.username}',
              style: TextStyle(
                  color: AppTheme.egyptianBlue.withValues(alpha: 0.7), fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class TagResultItem extends StatelessWidget {
  final SearchTag tag;
  final VoidCallback onTap;

  const TagResultItem({super.key, required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.royalPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.tag, color: AppTheme.royalPurple, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${tag.tag}',
                      style: TextStyle(
                          color: AppTheme.navyText,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  Text('${tag.count} posts',
                      style: TextStyle(
                          color: AppTheme.egyptianBlue.withValues(alpha: 0.7),
                          fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppTheme.egyptianBlue.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

class TrendingTagItem extends StatelessWidget {
  final String tag;
  final VoidCallback onTap;

  const TrendingTagItem({super.key, required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.trending_up, color: AppTheme.royalPurple, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '#$tag',
                style: TextStyle(
                    color: AppTheme.navyText,
                    fontWeight: FontWeight.w600,
                    fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

