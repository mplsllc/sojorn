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
import '../../post/post_detail_screen.dart';
import 'quip_video_item.dart';
import '../../home/home_shell.dart';
import '../../../widgets/video_comments_sheet.dart';

class Quip {
  final String id;
  final String videoUrl;
  final String thumbnailUrl;
  final String caption;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final int? durationMs;
  final int? likeCount;
  final String? overlayJson;

  const Quip({
    required this.id,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.caption,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.durationMs,
    this.likeCount,
    this.overlayJson,
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
      durationMs: map['duration_ms'] as int?,
      likeCount: _parseLikeCount(map['metrics']),
      overlayJson: map['overlay_json'] as String?,
    );
  }

  static int? _parseLikeCount(dynamic metrics) {
    if (metrics is Map<String, dynamic>) {
      final val = metrics['like_count'];
      if (val is int) return val;
      if (val is num) return val.toInt();
    }
    return null;
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
  final Map<String, bool> _liked = {};
  final Map<String, int> _likeCounts = {};

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
          } catch (e) {
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
          _likeCounts.putIfAbsent(item.id, () => item.likeCount ?? 0);
        }
      });

      if (_quips.isNotEmpty) {
        // Build the controllers for the new visible items
        _initializeController(_currentIndex);
        _preloadController(_currentIndex + 1);
      }
    } catch (e) {
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

  Future<void> _toggleLike(Quip quip) async {
    final api = ref.read(apiServiceProvider);
    final currentlyLiked = _liked[quip.id] ?? false;
    setState(() {
      _liked[quip.id] = !currentlyLiked;
      final currentCount = _likeCounts[quip.id] ?? 0;
      final next = currentlyLiked ? currentCount - 1 : currentCount + 1;
      _likeCounts[quip.id] = next < 0 ? 0 : next;
    });

    try {
      if (currentlyLiked) {
        await api.unappreciatePost(quip.id);
      } else {
        await api.appreciatePost(quip.id);
      }
    } catch (_) {
      // revert on failure
      if (!mounted) return;
      setState(() {
        _liked[quip.id] = currentlyLiked;
        _likeCounts[quip.id] =
            (_likeCounts[quip.id] ?? 0) + (currentlyLiked ? 1 : -1);
        if ((_likeCounts[quip.id] ?? 0) < 0) {
          _likeCounts[quip.id] = 0;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update like. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _openComments(Quip quip) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SojornColors.transparent,
      builder: (context) => VideoCommentsSheet(
        postId: quip.id,
        initialCommentCount: 0,
        onCommentPosted: () {
          // Optional: handle reload if needed
        },
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

    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await _fetchQuips(refresh: true);
            },
            backgroundColor: AppTheme.cardSurface,
            color: AppTheme.brightNavy,
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              // Ensure physics allows scrolling to trigger refresh
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _quips.length,
              onPageChanged: (index) {
                _currentIndex = index;
                _preloadController(index + 1);
                _disposeFarControllers(index);
                if (_hasMore && index >= _quips.length - 3) {
                  _fetchMore();
                }
              },
              itemBuilder: (context, index) {
                final quip = _quips[index];
                final controller = _controllers[index];
                final isLiked = _liked[quip.id] ?? false;
                final likeCount = _likeCounts[quip.id] ?? quip.likeCount ?? 0;
                return VisibilityDetector(
                  key: ValueKey('quip-${quip.id}'),
                  onVisibilityChanged: (info) =>
                      _onVisibilityChanged(index, info.visibleFraction),
                  child: QuipVideoItem(
                    quip: quip,
                    controller: controller,
                    isActive: index == _currentIndex,
                    isLiked: isLiked,
                    likeCount: likeCount,
                    isUserPaused: _isUserPaused,
                    onLike: () => _toggleLike(quip),
                    onComment: () => _openComments(quip),
                    onShare: () => _shareQuip(quip),
                    onTogglePause: _toggleUserPause,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
