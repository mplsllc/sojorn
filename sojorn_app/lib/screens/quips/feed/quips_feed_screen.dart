// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../providers/api_provider.dart';
import '../../../providers/feed_refresh_provider.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import 'quip_video_item.dart';
import '../../home/home_shell.dart';
import '../../../widgets/reactions/anchored_reaction_popup.dart';
import '../../../widgets/video_comments_sheet.dart';

class Quip {
  final String id;
  final String videoUrl;
  final String thumbnailUrl;
  final String caption;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String authorId;
  final int? durationMs;
  final int commentCount;
  final String? overlayJson;
  final Map<String, int> reactions;
  final Set<String> myReactions;

  const Quip({
    required this.id,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.caption,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.authorId = '',
    this.durationMs,
    this.commentCount = 0,
    this.overlayJson,
    this.reactions = const {},
    this.myReactions = const {},
  });

  factory Quip.fromMap(Map<String, dynamic> map) {
    final author = map['author'] as Map<String, dynamic>?;
    final resolvedVideo =
        (map['video_url'] ?? map['image_url'] ?? '') as String;
    final resolvedThumbnail =
        (map['thumbnail_url'] ?? map['image_url'] ?? '') as String;
    return Quip(
      id: map['id'] as String,
      videoUrl: resolvedVideo,
      thumbnailUrl: resolvedThumbnail,
      caption: (map['body'] ?? '') as String,
      username: (author?['handle'] ?? 'unknown') as String,
      displayName: author?['display_name'] as String?,
      avatarUrl: author?['avatar_url'] as String?,
      authorId: (author?['id'] ?? '') as String,
      durationMs: map['duration_ms'] as int?,
      commentCount: _parseCount(map['comment_count']),
      overlayJson: map['overlay_json'] as String?,
      reactions: _parseReactions(map['reactions']),
      myReactions: _parseMyReactions(map['my_reactions']),
    );
  }

  static Map<String, int> _parseReactions(dynamic v) {
    if (v is Map<String, dynamic>) {
      return v.map((k, val) => MapEntry(k, val is int ? val : (val is num ? val.toInt() : 0)));
    }
    return {};
  }

  static Set<String> _parseMyReactions(dynamic v) {
    if (v is List) return v.whereType<String>().toSet();
    return {};
  }

  static int _parseCount(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}

class QuipsFeedScreen extends ConsumerStatefulWidget {
  final bool? isActive;
  final String? initialPostId;
  const QuipsFeedScreen({super.key, this.isActive, this.initialPostId});


  @override
  ConsumerState<QuipsFeedScreen> createState() => _QuipsFeedScreenState();
}

class _QuipsFeedScreenState extends ConsumerState<QuipsFeedScreen>
    with WidgetsBindingObserver {
  final PageController _pageController = PageController();

  final List<Quip> _quips = [];
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, Future<void>> _controllerFutures = {};
  final Map<String, Map<String, int>> _reactionCounts = {};
  final Map<String, Set<String>> _myReactions = {};
  final Map<String, bool> _followStates = {};

  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  int _currentIndex = 0;
  bool _isScreenActive = false;
  bool _isUserPaused = false;
  int _lastRefreshToken = 0;

  static const int _branchIndex = 1;
  static const int _pageSize = 8;

  @override
  void initState() {
    super.initState();
    debugPrint('[QUIPS] initState — isActive=${widget.isActive}, initialPostId=${widget.initialPostId}');
    WidgetsBinding.instance.addObserver(this);
    _isScreenActive = widget.isActive ?? false;
    if (widget.initialPostId != null) {
      _isUserPaused = false;
    }
    _fetchQuips(refresh: widget.initialPostId != null);

  }



  void _checkFeedRefresh() {
    final refreshToken = ref.read(feedRefreshProvider);
    if (refreshToken != _lastRefreshToken) {
      _lastRefreshToken = refreshToken;
      _fetchQuips(refresh: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleScreenActive(_resolveActiveState());
    } else if (state == AppLifecycleState.paused) {
      _handleScreenActive(false);
    }
  }

  @override
  void didUpdateWidget(QuipsFeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _handleScreenActive(_resolveActiveState());
    }
    if (widget.initialPostId != oldWidget.initialPostId && widget.initialPostId != null) {
      _isUserPaused = false; // Auto-play if user explicitly clicked a quip
      _fetchQuips(refresh: true);
    }

  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handleScreenActive(_resolveActiveState());
  }

  bool _resolveActiveState() {
    if (widget.isActive != null) {
      return widget.isActive!;
    }
    final scope = NavigationShellScope.of(context);
    return scope?.currentIndex == _branchIndex;
  }

  void _handleScreenActive(bool isActive) {
    final wasActive = _isScreenActive;
    if (wasActive != isActive) {
      _isScreenActive = isActive;
      _updateVideoPlayback();
      
      // Auto-refresh when returning to this screen or when feed refresh triggered
      if (isActive && !wasActive) {
        _checkFeedRefresh();
      }
    } else if (isActive) {
      // Already active but check if refresh was triggered (e.g., after posting a quip)
      _checkFeedRefresh();
    }
  }

  void _updateVideoPlayback() {
    if (_isScreenActive && !_isUserPaused) {
      // Screen is active and not user-paused, play and unmute current
      for (final index in _controllers.keys) {
        final controller = _controllers[index];
        if (index == _currentIndex) {
          controller?.setVolume(1.0);
          controller?.play();
        } else {
          controller?.setVolume(0.0);
          controller?.pause();
        }
      }
    } else {
      // Screen is not active or user has paused, pause and mute all
      for (final controller in _controllers.values) {
        controller.setVolume(0.0);
        controller.pause();
      }
    }
  }

  void _toggleUserPause() {
    setState(() {
      _isUserPaused = !_isUserPaused;
    });
    _updateVideoPlayback();
  }

  Future<void> _fetchQuips({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        // We generally want to reset pagination state but keep items visible
        // until new data arrives to prevent UI flickering.
        _hasMore = true;
        // Do not clear _quips here.
      }
    });

    try {
      // If refreshing, we fetch the first page (offset 0)
      // otherwise start from current length
      final start = refresh ? 0 : _quips.length;
      final api = ref.read(apiServiceProvider);
      final data = await api.callGoApi(
        '/feed',
        method: 'GET',
        queryParams: {
          'limit': '$_pageSize',
          'offset': '$start',
          'has_video': 'true',
        },
      );
      final posts =
          (data['posts'] as List? ?? []).whereType<Map<String, dynamic>>();

      List<Quip> items = posts
          .map(Quip.fromMap)
          .where((quip) => quip.videoUrl.isNotEmpty)
          .toList();
      debugPrint('[QUIPS] Fetched ${items.length} quips (offset=$start, refresh=$refresh)');

      // If we have an initialPostId, ensure it's at the top
      // If we have an initialPostId, ensure it's at the top
      if (refresh && widget.initialPostId != null) {
        final existingIndex = items.indexWhere((q) => q.id == widget.initialPostId);
        if (existingIndex != -1) {
          final initial = items.removeAt(existingIndex);
          items.insert(0, initial);
        } else {
          try {
            final postData = await api.callGoApi('/posts/${widget.initialPostId}', method: 'GET');
            if (postData['post'] != null) {
              final quip = Quip.fromMap(postData['post'] as Map<String, dynamic>);
              if (quip.videoUrl.isNotEmpty) {
                items.insert(0, quip);
              } else {
              }
            } else {
            }
          } catch (_) {
            // Ignore — initial post will just not appear at top
          }
        }
      }



      if (!mounted) return;
      setState(() {
        if (refresh) {
          // Dispose all existing controllers since the indices will now map to different videos
          for (final controller in _controllers.values) {
            controller.dispose();
          }
          _controllers.clear();
          // Also clear futures
          _controllerFutures.clear();

          _quips.clear();
          _currentIndex = 0;

          if (_pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        }

        _quips.addAll(items);
        _hasMore = items.length == _pageSize;
        for (final item in items) {
          _reactionCounts.putIfAbsent(
              item.id, () => Map<String, int>.from(item.reactions));
          _myReactions.putIfAbsent(
              item.id, () => Set<String>.from(item.myReactions));
        }
      });

      if (_quips.isNotEmpty) {
        // Build the controllers for the new visible items
        _initializeController(_currentIndex);
        _preloadController(_currentIndex + 1);
      }
    } catch (e) {
      debugPrint('[QUIPS] Fetch error: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load quips: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initializeController(int index) async {
    if (index < 0 || index >= _quips.length) return;
    if (_controllers.containsKey(index)) return;
    if (_controllerFutures[index] != null) return;

    final quip = _quips[index];
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(quip.videoUrl));
    controller.setLooping(true);
    controller.setVolume(0);

    final initFuture = controller.initialize().then((_) {
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controllers[index] = controller;
      });
      if (index == _currentIndex && _isScreenActive && !_isUserPaused) {
        controller.setVolume(1.0);
        controller.play();
      } else {
        controller.setVolume(0.0);
        controller.pause();
      }
    }).catchError((_) {
      controller.dispose();
    });

    _controllerFutures[index] = initFuture;
    await initFuture;
    _controllerFutures.remove(index);
  }

  void _disposeFarControllers(int anchor) {
    final keys = _controllers.keys.toList();
    for (final key in keys) {
      if ((key - anchor).abs() > 1) {
        _controllers[key]?.dispose();
        _controllers.remove(key);
      }
    }
  }

  Future<void> _onVisibilityChanged(int index, double visible) async {
    if (visible >= 0.5) {
      _currentIndex = index;
      await _initializeController(index);
      _playController(index);
      _preloadController(index + 1);
      _disposeFarControllers(index);
      if (_hasMore && index >= _quips.length - 3) {
        _fetchMore();
      }
    } else {
      _pauseController(index);
    }
  }

  void _playController(int index) {
    if (_isScreenActive && !_isUserPaused) {
      final current = _controllers[index];
      current?.setVolume(1.0);
      current?.play();
    }

    _controllers.forEach((key, value) {
      if (key != index) {
        value.setVolume(0.0);
        value.pause();
      }
    });
  }

  void _pauseController(int index) {
    _controllers[index]?.pause();
  }

  Future<void> _preloadController(int index) async {
    if (index >= _quips.length) return;
    await _initializeController(index);
  }

  Future<void> _fetchMore() async {
    if (_isLoading || !_hasMore) return;
    await _fetchQuips();
  }

  Future<void> _toggleReaction(Quip quip, String emoji) async {
    final api = ref.read(apiServiceProvider);
    final currentCounts =
        Map<String, int>.from(_reactionCounts[quip.id] ?? quip.reactions);
    final currentMine =
        Set<String>.from(_myReactions[quip.id] ?? quip.myReactions);

    // Optimistic update
    final isRemoving = currentMine.contains(emoji);
    setState(() {
      if (isRemoving) {
        currentMine.remove(emoji);
        final newCount = (currentCounts[emoji] ?? 1) - 1;
        if (newCount <= 0) {
          currentCounts.remove(emoji);
        } else {
          currentCounts[emoji] = newCount;
        }
      } else {
        currentMine.add(emoji);
        currentCounts[emoji] = (currentCounts[emoji] ?? 0) + 1;
      }
      _reactionCounts[quip.id] = currentCounts;
      _myReactions[quip.id] = currentMine;
    });

    try {
      await api.toggleReaction(quip.id, emoji);
    } catch (_) {
      // Revert on failure
      if (!mounted) return;
      setState(() {
        _reactionCounts[quip.id] = Map<String, int>.from(quip.reactions);
        _myReactions[quip.id] = Set<String>.from(quip.myReactions);
      });
    }
  }

  void _openReactionPicker(Quip quip, Offset tapPosition) {
    showAnchoredReactionPicker(
      context: context,
      tapPosition: tapPosition,
      myReactions: _myReactions[quip.id] ?? quip.myReactions,
      reactionCounts: _reactionCounts[quip.id] ?? quip.reactions,
      onReaction: (emoji) => _toggleReaction(quip, emoji),
    );
  }

  Future<void> _handleNotInterested(Quip quip) async {
    final index = _quips.indexOf(quip);
    if (index == -1) return;

    // Optimistic removal — user sees it gone immediately
    setState(() {
      _quips.removeAt(index);
      final ctrl = _controllers.remove(index);
      ctrl?.dispose();
      // Remap controllers above the removed index
      final remapped = <int, VideoPlayerController>{};
      _controllers.forEach((k, v) {
        remapped[k > index ? k - 1 : k] = v;
      });
      _controllers
        ..clear()
        ..addAll(remapped);
      if (_currentIndex >= _quips.length && _currentIndex > 0) {
        _currentIndex = _quips.length - 1;
      }
    });

    // Fire-and-forget to backend — no revert on failure (signal still valuable)
    ref.read(apiServiceProvider).hidePost(quip.id).catchError((_) {});
  }

  Future<void> _toggleFollow(Quip quip) async {
    final id = quip.authorId;
    if (id.isEmpty) return;
    final isFollowing = _followStates[id] ?? false;
    setState(() => _followStates[id] = !isFollowing);
    try {
      final api = ref.read(apiServiceProvider);
      if (isFollowing) {
        await api.unfollowUser(id);
      } else {
        await api.followUser(id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _followStates[id] = isFollowing);
    }
  }

  Future<void> _openComments(Quip quip) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SojornColors.transparent,
      builder: (context) => VideoCommentsSheet(
        postId: quip.id,
        initialCommentCount: quip.commentCount,
        showNavActions: false,
        onCommentPosted: () {},
      ),
    );
  }

  void _shareQuip(Quip quip) {
    final url = AppRoutes.getQuipUrl(quip.id);
    final text = '${quip.caption}\n\n$url\n\n— @${quip.username} on Sojorn';
    Share.share(text);
  }



  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: SojornColors.basicBlack,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: SojornColors.basicWhite),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _fetchQuips(refresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_quips.isEmpty && _isLoading) {
      return const Scaffold(
        backgroundColor: SojornColors.basicBlack,
        body: Center(
          child: CircularProgressIndicator(color: SojornColors.basicWhite),
        ),
      );
    }

    if (_quips.isEmpty) {
      return const Scaffold(
        backgroundColor: SojornColors.basicBlack,
        body: Center(
          child: Text(
            'No quips yet. Be the first!',
            style: TextStyle(color: SojornColors.basicWhite),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = SojornBreakpoints.isDesktop(constraints.maxWidth);

        if (isDesktop) {
          return _buildDesktopQuips();
        }
        return _buildMobileQuips();
      },
    );
  }

  Widget _buildDesktopQuips() {
    final currentQuip = _quips.isNotEmpty ? _quips[_currentIndex] : null;

    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      body: Row(
        children: [
          // Centered video player in phone-shaped container
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(SojornRadii.card),
                    child: _buildQuipPageView(),
                  ),
                ),
              ),
            ),
          ),
          // Comments sidebar
          if (currentQuip != null)
            Container(
              width: SojornBreakpoints.sidebarWidth,
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                border: Border(
                  left: BorderSide(
                    color: SojornColors.basicWhite.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: VideoCommentsSheet(
                key: ValueKey('desktop-comments-${currentQuip.id}'),
                postId: currentQuip.id,
                initialCommentCount: currentQuip.commentCount,
                showNavActions: false,
                onCommentPosted: () {},
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileQuips() {
    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      body: Stack(
        children: [
          _buildQuipPageView(),
        ],
      ),
    );
  }

  Widget _buildQuipPageView() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchQuips(refresh: true);
      },
      backgroundColor: AppTheme.cardSurface,
      color: AppTheme.brightNavy,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: const PageScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        itemCount: _quips.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          _preloadController(index + 1);
          _disposeFarControllers(index);
          if (_hasMore && index >= _quips.length - 3) {
            _fetchMore();
          }
        },
        itemBuilder: (context, index) {
          final quip = _quips[index];
          final controller = _controllers[index];
          return VisibilityDetector(
            key: ValueKey('quip-${quip.id}'),
            onVisibilityChanged: (info) =>
                _onVisibilityChanged(index, info.visibleFraction),
            child: QuipVideoItem(
              quip: quip,
              controller: controller,
              isActive: index == _currentIndex,
              reactions: _reactionCounts[quip.id] ?? quip.reactions,
              myReactions: _myReactions[quip.id] ?? quip.myReactions,
              commentCount: quip.commentCount,
              isUserPaused: _isUserPaused,
              isFollowing: _followStates[quip.authorId] ?? false,
              onReact: (emoji) => _toggleReaction(quip, emoji),
              onOpenReactionPicker: (pos) => _openReactionPicker(quip, pos),
              onComment: () => _openComments(quip),
              onShare: () => _shareQuip(quip),
              onTogglePause: _toggleUserPause,
              onNotInterested: () => _handleNotInterested(quip),
              onFollow: quip.authorId.isNotEmpty ? () => _toggleFollow(quip) : null,
              onScrollUp: _currentIndex > 0 ? () => _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null,
              onScrollDown: _currentIndex < _quips.length - 1 ? () => _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null,
            ),
          );
        },
      ),
    );
  }
}
