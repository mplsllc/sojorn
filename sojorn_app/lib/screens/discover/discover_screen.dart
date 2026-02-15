import 'dart:async';
import '../../models/profile.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/api_provider.dart';
import '../../models/search_results.dart';
import '../../models/post.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sojorn_post_card.dart';
import '../../widgets/media/signed_media_image.dart';
import '../profile/viewable_profile_screen.dart';
import '../compose/compose_screen.dart';
import '../post/post_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/full_screen_shell.dart';

/// Model for discover page data
class DiscoverData {
  final List<Hashtag> topTags;
  final List<Post> popularPosts;

  DiscoverData({
    required this.topTags,
    required this.popularPosts,
  });

  factory DiscoverData.fromJson(Map<String, dynamic> json) {
    return DiscoverData(
      topTags: (json['top_tags'] as List? ?? [])
          .map((e) => Hashtag.fromJson(e))
          .toList(),
      popularPosts: (json['popular_posts'] as List? ?? [])
          .map((e) => Post.fromJson(e))
          .toList(),
    );
  }
}

class Hashtag {
  final String id;
  final String name;
  final String displayName;
  final int useCount;
  final bool isTrending;

  Hashtag({
    required this.id,
    required this.name,
    required this.displayName,
    required this.useCount,
    this.isTrending = false,
  });

  factory Hashtag.fromJson(Map<String, dynamic> json) {
    return Hashtag(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      displayName: json['display_name'] ?? json['name'] ?? '',
      useCount: json['use_count'] ?? 0,
      isTrending: json['is_trending'] ?? false,
    );
  }
}

class DiscoverScreen extends ConsumerStatefulWidget {
  final String? initialQuery;

  const DiscoverScreen({super.key, this.initialQuery});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final TextEditingController searchController = TextEditingController();
  final FocusNode focusNode = FocusNode();
  Timer? debounceTimer;
  bool isLoadingSearch = false;
  bool isLoadingDiscover = true;
  bool hasSearched = false;
  SearchResults? searchResults;
  DiscoverData? discoverData;
  List<RecentSearch> recentSearches = [];
  int _searchEpoch = 0;

  static const Duration debounceDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    loadRecentSearches();
    loadDiscoverData();

    if (widget.initialQuery != null) {
      final query = widget.initialQuery!;
      searchController.text = query;
      Future.delayed(const Duration(milliseconds: 100), () {
        performSearch(query);
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    focusNode.dispose();
    debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> loadDiscoverData() async {
    setState(() => isLoadingDiscover = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.get('/discover');
      if (!mounted) return;
      
      setState(() {
        discoverData = DiscoverData.fromJson(response);
        isLoadingDiscover = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => isLoadingDiscover = false);
      }
    }
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
        searchResults = null;
        hasSearched = false;
        isLoadingSearch = false;
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
      isLoadingSearch = true;
      hasSearched = true;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final results = await apiService.search(normalizedQuery);
      if (!mounted || requestId != _searchEpoch) return;

      if (results.users.isNotEmpty) {
        await saveRecentSearch(RecentSearch(
          id: results.users.first.id,
          text: results.users.first.username,
          searchedAt: DateTime.now(),
          type: RecentSearchType.user,
        ));
      } else if (results.tags.isNotEmpty) {
        await saveRecentSearch(RecentSearch(
          id: 'tag_${results.tags.first.tag}',
          text: results.tags.first.tag,
          searchedAt: DateTime.now(),
          type: RecentSearchType.tag,
        ));
      }

      if (!mounted || requestId != _searchEpoch) return;
      setState(() {
        searchResults = results;
        isLoadingSearch = false;
      });
    } catch (e) {
      if (!mounted || requestId != _searchEpoch) return;
      setState(() {
        isLoadingSearch = false;
        searchResults = SearchResults(users: [], tags: [], posts: []);
      });
    }
  }

  void clearSearch() {
    searchController.clear();
    setState(() {
      searchResults = null;
      hasSearched = false;
      isLoadingSearch = false;
    });
    focusNode.unfocus();
  }

  void _navigateToHashtag(String name) {
    final query = '#$name';
    searchController.text = query;
    performSearch(query);
  }

  void _navigateToProfile(String handle) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UnifiedProfileScreen(handle: handle),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return FullScreenShell(
      titleText: 'Search',
      showSearch: false,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: hasSearched ? _buildSearchResults() : _buildDiscoverContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        boxShadow: [
          BoxShadow(
            color: const Color(0x0D000000),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _buildSearchField()),
          if (hasSearched)
            IconButton(
              icon: Icon(Icons.close, color: AppTheme.egyptianBlue),
              onPressed: clearSearch,
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
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
                hintText: 'Search people, hashtags, posts...',
                hintStyle: TextStyle(color: AppTheme.egyptianBlue.withValues(alpha: 0.5)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: AppTheme.bodyMedium,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  performSearch(value.trim());
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverContent() {
    if (isLoadingDiscover) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: loadDiscoverData,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text(
                'Top Trending',
                style: AppTheme.labelLarge.copyWith(
                  color: AppTheme.navyBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: discoverData?.topTags.length ?? 0,
                itemBuilder: (context, index) {
                  final tag = discoverData!.topTags[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ActionChip(
                      label: Text('#${tag.displayName}'),
                      labelStyle: TextStyle(
                        color: AppTheme.royalPurple,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      backgroundColor: AppTheme.royalPurple.withValues(alpha: 0.1),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      onPressed: () => _navigateToHashtag(tag.name),
                    ),
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Popular Now',
                style: AppTheme.labelLarge.copyWith(
                  color: AppTheme.navyBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (discoverData?.popularPosts.isEmpty ?? true)
            const SliverFillRemaining(
              child: Center(
                child: Text('No popular posts yet.'),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final post = discoverData!.popularPosts[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: sojornPostCard(
                      post: post,
                      onTap: () => _openPostDetail(post),
                      onChain: () => _openChainComposer(post),
                    ),
                  );
                },
                childCount: discoverData!.popularPosts.length,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (isLoadingSearch) {
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
                style: AppTheme.labelMedium.copyWith(color: AppTheme.egyptianBlue)),
          ],
        ),
      );
    }

    if (searchResults == null ||
        (searchResults!.users.isEmpty &&
            searchResults!.tags.isEmpty &&
            searchResults!.posts.isEmpty)) {
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
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.egyptianBlue)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        if (searchResults!.users.isNotEmpty) ...[
          _buildSectionHeader('People', icon: Icons.people),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: searchResults!.users.length,
              itemBuilder: (context, index) {
                final user = searchResults!.users[index];
                return _buildUserResultItem(user);
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
        if (searchResults!.tags.isNotEmpty) ...[
          _buildSectionHeader('Hashtags', icon: Icons.tag),
          ...searchResults!.tags.map((tag) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTagResultItem(tag),
              )),
          const SizedBox(height: 24),
        ],
        if (searchResults!.posts.isNotEmpty) ...[
          _buildSectionHeader('Posts', icon: Icons.article),
          ...searchResults!.posts.map((post) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildPostResultItem(post),
              )),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppTheme.royalPurple),
            const SizedBox(width: 8),
          ],
          Text(
            title,
            style: AppTheme.labelMedium.copyWith(
              color: AppTheme.navyBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserResultItem(SearchUser user) {
    return GestureDetector(
      onTap: () => _navigateToProfile(user.username),
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppTheme.royalPurple.withValues(alpha: 0.2),
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
                      style: TextStyle(
                          color: AppTheme.royalPurple,
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

  Widget _buildTagResultItem(SearchTag tag) {
    return GestureDetector(
      onTap: () => _navigateToHashtag(tag.tag),
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

  Widget _buildPostResultItem(SearchPost post) {
    // Convert SearchPost to minimal Post immediately
    final minimalPost = Post(
      id: post.id,
      body: post.body,
      authorId: post.authorId,
      createdAt: post.createdAt,
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
      isLiked: false,
      likeCount: 0,
      commentCount: 0,
      tags: [],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: sojornPostCard(
        post: minimalPost,
        onTap: () => _openPostDetail(minimalPost),
        onChain: () => _openChainComposer(minimalPost),
      ),
    );
  }
}
