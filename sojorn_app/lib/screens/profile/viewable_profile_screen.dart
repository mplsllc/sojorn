import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../routes/app_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../models/profile.dart';
import '../../models/profile_privacy_settings.dart';
import '../../models/trust_state.dart';
import '../../models/trust_tier.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/country_flag.dart';
import '../../utils/url_launcher_helper.dart';
import '../../widgets/sojorn_post_card.dart';
import '../../widgets/media/signed_media_image.dart';
import '../compose/compose_screen.dart';
import '../secure_chat/secure_chat_screen.dart';
import '../../services/auth_service.dart';
import '../../services/secure_chat_service.dart';
import '../post/post_detail_screen.dart';
import 'profile_settings_screen.dart';
import 'followers_following_screen.dart';
import '../../widgets/harmony_explainer_modal.dart';
import '../../widgets/follow_button.dart';

/// Unified profile screen - handles both own profile and viewing others.
///
/// When [handle] is null, loads the current user's own profile with
/// edit controls, privacy settings, and avatar actions.
/// When [handle] is provided, loads the target user's profile with
/// follow/message actions.
class UnifiedProfileScreen extends ConsumerStatefulWidget {
  final String? handle;

  const UnifiedProfileScreen({
    super.key,
    this.handle,
  });

  @override
  ConsumerState<UnifiedProfileScreen> createState() =>
      _UnifiedProfileScreenState();
}

String _resolveAvatar(String? url) {
  if (url == null || url.isEmpty) return '';
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  return 'https://img.sojorn.net/${url.replaceFirst(RegExp('^/'), '')}';
}

class _UnifiedProfileScreenState extends ConsumerState<UnifiedProfileScreen>
    with SingleTickerProviderStateMixin {
  static const int _postsPageSize = 20;
  StreamSubscription? _authSubscription;

  Profile? _profile;
  ProfileStats? _stats;
  bool _isFollowing = false;
  bool _isFollowedBy = false;
  bool _isFriend = false;
  String? _followStatus;
  bool _isLoadingProfile = false;
  bool _isFollowActionLoading = false;
  String? _profileError;
  bool _isPrivate = false;
  bool _isOwnProfile = false;
  bool _isCreatingProfile = false;
  ProfilePrivacySettings? _privacySettings;
  bool _isPrivacyLoading = false;
  List<Map<String, dynamic>> _mutualFollowers = [];
  bool _isMutualFollowersLoading = false;

  /// True when no handle was provided (bottom-nav profile tab)
  bool get _isOwnProfileMode => widget.handle == null;

  late TabController _tabController;
  int _activeTab = 0;

  List<Post> _posts = [];
  bool _isPostsLoading = false;
  bool _isPostsLoadingMore = false;
  bool _hasMorePosts = true;
  String? _postsError;

  List<Post> _savedPosts = [];
  bool _isSavedLoading = false;
  bool _isSavedLoadingMore = false;
  bool _hasMoreSaved = true;
  String? _savedError;

  List<Post> _chainedPosts = [];
  bool _isChainedLoading = false;
  bool _isChainedLoadingMore = false;
  bool _hasMoreChained = true;
  String? _chainedError;

  @override
  void initState() {
    super.initState();
    // Own profile gets 3 tabs (Posts, Saved, Chains), others get 4 (+About)
    _tabController = TabController(length: _isOwnProfileMode ? 3 : 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _activeTab = _tabController.index;
        });
        _loadActiveFeed();
      }
    });

    _loadProfile();

    // Listen for auth changes when viewing own profile
    if (_isOwnProfileMode) {
      _authSubscription = AuthService.instance.authStateChanges.listen((data) {
        if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.tokenRefreshed) {
          _loadProfile();
        }
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      // Own profile: no handle arg; other profile: pass handle
      final data = _isOwnProfileMode
          ? await apiService.getProfile()
          : await apiService.getProfile(handle: widget.handle);
      final profile = data['profile'] as Profile;
      final stats = data['stats'] as ProfileStats;
      final followStatus = data['follow_status'] as String?;
      final isFollowing = data['is_following'] as bool? ?? false;
      final isFollowedBy = data['is_followed_by'] as bool? ?? false;
      final isFriend = data['is_friend'] as bool? ?? false;
      final isPrivate = data['is_private'] as bool? ?? false;
      final currentUserId = AuthService.instance.currentUser?.id;
      final isOwnProfile = _isOwnProfileMode ||
          (currentUserId != null &&
              currentUserId.toLowerCase() == profile.id.toLowerCase());

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _stats = stats;
        _isFollowing = isFollowing;
        _isFollowedBy = isFollowedBy;
        _isFriend = isFriend;
        _followStatus = followStatus;
        _isPrivate = isPrivate;
        _isOwnProfile = isOwnProfile;
      });

      if (isOwnProfile) {
        await _loadPrivacySettings();
      }
      await _loadPosts(refresh: true);
    } catch (error) {
      if (!mounted) return;

      // Auto-create profile if own profile and profile not found
      if (_isOwnProfileMode && _shouldAutoCreateProfile(error)) {
        await _createProfileIfMissing();
        return;
      }

      setState(() {
        _profileError = error.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    }
  }

  bool _shouldAutoCreateProfile(dynamic error) {
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('profile not found') ||
        errorStr.contains('no profile');
  }

  Future<void> _createProfileIfMissing() async {
    if (_isCreatingProfile) return;

    setState(() {
      _isCreatingProfile = true;
      _profileError = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final user = AuthService.instance.currentUser;

      if (user == null) {
        throw Exception('No authenticated user');
      }

      final defaultHandle =
          user.email?.split('@').first ?? 'user${user.id.substring(0, 8)}';
      final defaultDisplayName = user.email?.split('@').first ?? 'User';

      await apiService.createProfile(
        handle: defaultHandle,
        displayName: defaultDisplayName,
      );

      if (!mounted) return;
      await _loadProfile();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _profileError =
            'Could not create profile: ${error.toString().replaceAll('Exception: ', '')}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingProfile = false;
        });
      }
    }
  }

  Future<void> _loadActiveFeed() async {
    switch (_activeTab) {
      case 0:
        if (_posts.isEmpty) _loadPosts(refresh: true);
        break;
      case 1:
        if (_savedPosts.isEmpty) _loadSaved(refresh: true);
        break;
      case 2:
        if (_chainedPosts.isEmpty) _loadChained(refresh: true);
        break;
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (_profile == null) return;

    if (refresh) {
      setState(() {
        _posts = [];
        _hasMorePosts = true;
        _postsError = null;
      });
    } else if (!_hasMorePosts || _isPostsLoadingMore) {
      return;
    }

    setState(() {
      if (refresh) {
        _isPostsLoading = true;
      } else {
        _isPostsLoadingMore = true;
      }
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final posts = await apiService.getProfilePosts(
        authorId: _profile!.id,
        limit: _postsPageSize,
        offset: refresh ? 0 : _posts.length,
      );

      if (!mounted) return;

      setState(() {
        if (refresh) {
          _posts = posts;
        } else {
          _posts.addAll(posts);
        }
        _hasMorePosts = posts.length == _postsPageSize;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _postsError = error.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPostsLoading = false;
          _isPostsLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadSaved({bool refresh = false}) async {
    if (_profile == null) return;

    if (refresh) {
      setState(() {
        _savedPosts = [];
        _hasMoreSaved = true;
        _savedError = null;
      });
    } else if (!_hasMoreSaved || _isSavedLoadingMore) {
      return;
    }

    setState(() {
      if (refresh) {
        _isSavedLoading = true;
      } else {
        _isSavedLoadingMore = true;
      }
      if (!refresh) {
        _savedError = null;
      }
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      // NOTE: This will only return posts if the backend/permission allows.
      final posts = await apiService.getSavedPosts(
        userId: _profile!.id,
        limit: _postsPageSize,
        offset: refresh ? 0 : _savedPosts.length,
      );

      if (!mounted) return;

      setState(() {
        if (refresh) {
          _savedPosts = posts;
        } else {
          _savedPosts.addAll(posts);
        }
        _hasMoreSaved = posts.length == _postsPageSize;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savedError = error.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSavedLoading = false;
          _isSavedLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadChained({bool refresh = false}) async {
    if (_profile == null) return;

    if (refresh) {
      setState(() {
        _chainedPosts = [];
        _hasMoreChained = true;
        _chainedError = null;
      });
    } else if (!_hasMoreChained || _isChainedLoadingMore) {
      return;
    }

    setState(() {
      if (refresh) {
        _isChainedLoading = true;
      } else {
        _isChainedLoadingMore = true;
      }
      if (!refresh) {
        _chainedError = null;
      }
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final posts = await apiService.getChainedPostsForAuthor(
        authorId: _profile!.id,
        limit: _postsPageSize,
        offset: refresh ? 0 : _chainedPosts.length,
      );

      if (!mounted) return;

      setState(() {
        if (refresh) {
          _chainedPosts = posts;
        } else {
          _chainedPosts.addAll(posts);
        }
        _hasMoreChained = posts.length == _postsPageSize;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _chainedError = error.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isChainedLoading = false;
          _isChainedLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadPrivacySettings() async {
    if (_isPrivacyLoading) return;

    setState(() {
      _isPrivacyLoading = true;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final settings = await apiService.getPrivacySettings();

      if (!mounted) return;
      setState(() {
        _privacySettings = settings;
      });
    } catch (error) {
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() {
          _isPrivacyLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (_profile == null || _isFollowActionLoading) return;

    setState(() {
      _isFollowActionLoading = true;
    });

    try {
      final apiService = ref.read(apiServiceProvider);

      if (_isFollowing || _followStatus == 'pending') {
        await apiService.unfollowUser(_profile!.id);
        if (!mounted) return;
        setState(() {
          _isFollowing = false;
          _isFriend = false;
          _followStatus = null;
          if (_stats != null) {
            _stats = ProfileStats(
              posts: _stats!.posts,
              followers: _stats!.followers - 1,
              following: _stats!.following,
            );
          }
        });
      } else {
        final status = await apiService.followUser(_profile!.id);
        if (!mounted) return;
        setState(() {
          _followStatus = status;
          _isFollowing = status == 'accepted';
          _isFriend = _isFollowing && _isFollowedBy;
          if (_stats != null && _isFollowing) {
            _stats = ProfileStats(
              posts: _stats!.posts,
              followers: _stats!.followers + 1,
              following: _stats!.following,
            );
          }
        });
      }

      if (!mounted) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFollowing
                ? 'Following @${_profile!.handle}'
                : (_followStatus == 'pending'
                    ? 'Request sent to @${_profile!.handle}'
                    : 'Unfollowed @${_profile!.handle}')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Failed to ${_isFollowing ? "unfollow" : "follow"} user'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFollowActionLoading = false;
        });
      }
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

  Future<void> _openMessage() async {
    final profile = _profile;
    if (profile == null || !_isFriend) return;

    final chatService = SecureChatService();

    try {
      final isReady = await chatService.isReady();
      if (!isReady) {
        await chatService.initialize();
      }

      final conversation = await chatService.getOrCreateConversation(profile.id);
      if (!mounted) return;
      if (conversation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to start a conversation.')),
        );
        return;
      }

      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => SecureChatScreen(conversation: conversation),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _openSettings() async {
    final profile = _profile;
    if (profile == null) return;

    final settings =
        _privacySettings ?? ProfilePrivacySettings.defaults(profile.id);

    final result = await Navigator.of(context, rootNavigator: true)
        .push<ProfileSettingsResult>(
      MaterialPageRoute(
        builder: (_) => ProfileSettingsScreen(
          profile: profile,
          settings: settings,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _profile = result.profile;
        _privacySettings = result.settings;
      });
    }
  }

  Future<void> _openPrivacyMenu() async {
    final profile = _profile;
    if (profile == null) return;

    final apiService = ref.read(apiServiceProvider);
    final currentSettings =
        _privacySettings ?? ProfilePrivacySettings.defaults(profile.id);
    ProfilePrivacySettings draft = currentSettings;

    final result = await showModalBottomSheet<ProfilePrivacySettings>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) {
        bool isSaving = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> handleSave() async {
              if (isSaving) return;
              setModalState(() => isSaving = true);
              try {
                final saved = await apiService.updatePrivacySettings(draft);
                if (!context.mounted) return;
                Navigator.of(context).pop(saved);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Privacy settings updated.'),
                    ),
                  );
                }
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      error.toString().replaceAll('Exception: ', ''),
                    ),
                    backgroundColor: AppTheme.error,
                  ),
                );
              } finally {
                if (context.mounted) {
                  setModalState(() => isSaving = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: AppTheme.spacingLg,
                right: AppTheme.spacingLg,
                top: AppTheme.spacingLg,
                bottom:
                    MediaQuery.of(context).viewInsets.bottom +
                    AppTheme.spacingLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Privacy', style: AppTheme.headlineSmall),
                  const SizedBox(height: AppTheme.spacingSm),
                  Text(
                    'Control who can see your profile and posts.',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.navyText.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingLg),
                  _PrivacyDropdown(
                    label: 'Profile visibility',
                    value: draft.profileVisibility,
                    onChanged: (value) {
                      setModalState(() {
                        draft = draft.copyWith(profileVisibility: value);
                      });
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingMd),
                  _PrivacyDropdown(
                    label: 'Posts visibility',
                    value: draft.postsVisibility,
                    onChanged: (value) {
                      setModalState(() {
                        draft = draft.copyWith(postsVisibility: value);
                      });
                    },
                  ),
                  const SizedBox(height: AppTheme.spacingLg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSaving ? null : handleSave,
                      child: isSaving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.white,
                                ),
                              ),
                            )
                          : const Text('Save'),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _privacySettings = result;
      });
    }
  }

  Future<void> _refreshAll() async {
    await _loadProfile();
  }

  void _navigateToConnections(int tabIndex) {
    if (_profile == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FollowersFollowingScreen(
          userId: _profile!.id,
          initialTabIndex: tabIndex,
        ),
      ),
    );
  }

  void _showAvatarActions() {
    final profile = _profile;
    if (profile == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View profile photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAvatarPreview(profile);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Change profile photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openSettings();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAvatarPreview(Profile profile) {
    showDialog(
      context: context,
      builder: (context) {
        final avatarUrl = _resolveAvatar(profile.avatarUrl);
        return Dialog(
          backgroundColor: SojornColors.transparent,
          insetPadding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Profile Photo',
                  style: AppTheme.headlineSmall,
                ),
                const SizedBox(height: AppTheme.spacingLg),
                CircleAvatar(
                  radius: 72,
                  backgroundColor: AppTheme.queenPink,
                  child: avatarUrl.isNotEmpty
                      ? ClipOval(
                          child: SizedBox(
                            width: 144,
                            height: 144,
                            child: SignedMediaImage(
                              url: avatarUrl,
                              width: 144,
                              height: 144,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : Text(
                          profile.displayName.isNotEmpty
                              ? profile.displayName[0].toUpperCase()
                              : '?',
                          style: AppTheme.headlineMedium.copyWith(
                            color: AppTheme.royalPurple,
                          ),
                        ),
                ),
                const SizedBox(height: AppTheme.spacingLg),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _isOwnProfileMode ? 'Profile' : '@${widget.handle ?? ''}';

    if (_profileError != null && _profile == null && !_isLoadingProfile) {
      return Scaffold(
        appBar: _isOwnProfileMode ? null : AppBar(title: Text(titleText)),
        body: _buildErrorState(),
      );
    }

    if (_isLoadingProfile && _profile == null) {
      return Scaffold(
        appBar: _isOwnProfileMode ? null : AppBar(title: Text(titleText)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_profile == null) {
      return Scaffold(
        appBar: _isOwnProfileMode ? null : AppBar(title: Text(titleText)),
        body: const Center(child: Text('No profile found')),
      );
    }

    // Own profile: no top AppBar (SliverAppBar only, like the old ProfileScreen)
    if (_isOwnProfileMode) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              _buildSliverAppBar(_profile!),
              _buildSliverTabBar(),
            ];
          },
          body: _buildTabBarView(),
        ),
      );
    }

    // Viewing another user: AppBar with back button
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: Text('@${_profile!.handle}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(AppRoutes.homeAlias);
            }
          },
        ),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            _buildSliverAppBar(_profile!),
            _buildSliverTabBar(),
          ];
        },
        body: _buildTabBarView(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _profileError ?? 'Something went wrong',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingMd),
            ElevatedButton(
              onPressed: _loadProfile,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(Profile profile) {
    return SliverAppBar(
      expandedHeight: _isOwnProfile ? 263 : 303,
      pinned: true,
      toolbarHeight: 0,
      collapsedHeight: 0,
      automaticallyImplyLeading: false,
      backgroundColor: SojornColors.transparent,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: _ProfileHeader(
          profile: profile,
          stats: _stats,
          isFollowing: _isFollowing,
          isFriend: _isFriend,
          followStatus: _followStatus,
          isPrivate: _isPrivate,
          isFollowActionLoading: _isFollowActionLoading,
          isOwnProfile: _isOwnProfile,
          onFollowToggle: _toggleFollow,
          onMessageTap: _openMessage,
          onSettingsTap: _openSettings,
          onPrivacyTap: _openPrivacyMenu,
          onAvatarTap: _isOwnProfile ? _showAvatarActions : null,
          onConnectionsTap: _isOwnProfile ? _navigateToConnections : null,
        ),
      ),
    );
  }

  Widget _buildSliverTabBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SliverTabBarDelegate(
        TabBar(
          controller: _tabController,
          labelColor: AppTheme.navyText,
          unselectedLabelColor: AppTheme.navyText.withValues(alpha: 0.6),
          indicatorColor: AppTheme.royalPurple,
          indicatorWeight: 3,
          labelStyle: AppTheme.labelMedium,
          tabs: [
            const Tab(text: 'Posts'),
            const Tab(text: 'Saved'),
            const Tab(text: 'Chains'),
            if (!_isOwnProfileMode) const Tab(text: 'About'),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBarView() {
    if (_activeTab == 3) {
      return _buildAboutTab();
    }

    if (_activeTab == 1) {
      return _buildFeedView(
        _savedPosts,
        _isSavedLoading,
        _isSavedLoadingMore,
        _hasMoreSaved,
        _savedError,
        () => _loadSaved(refresh: true),
        () => _loadSaved(refresh: false),
      );
    }

    if (_activeTab == 2) {
      return _buildFeedView(
        _chainedPosts,
        _isChainedLoading,
        _isChainedLoadingMore,
        _hasMoreChained,
        _chainedError,
        () => _loadChained(refresh: true),
        () => _loadChained(refresh: false),
      );
    }

    return _buildFeedView(
      _posts,
      _isPostsLoading,
      _isPostsLoadingMore,
      _hasMorePosts,
      _postsError,
      () => _loadPosts(refresh: true),
      () => _loadPosts(refresh: false),
    );
  }

  Widget _buildFeedView(
    List<Post> posts,
    bool isLoading,
    bool isLoadingMore,
    bool hasMore,
    String? error,
    VoidCallback onRefresh,
    VoidCallback onLoadMore,
  ) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: [
          if (error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spacingLg),
                child: Text(
                  error,
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          if (isLoading && posts.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: AppTheme.spacingLg),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (posts.isEmpty && !isLoading)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'No posts yet',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.navyText.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          if (posts.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingMd,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = posts[index];
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == posts.length - 1
                            ? 0
                            : AppTheme.spacingSm,
                      ),
                      child: sojornPostCard(
                        post: post,
                        onTap: () => _openPostDetail(post),
                        onChain: () => _openChainComposer(post),
                      ),
                    );
                  },
                  childCount: posts.length,
                ),
              ),
            ),
          if (isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: AppTheme.spacingLg),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (!isLoadingMore && hasMore && posts.isNotEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: TextButton(
                  onPressed: onLoadMore,
                  child: const Text('Load more'),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: AppTheme.spacingLg * 2),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab() {
    final profile = _profile!;

    // Show private account message if profile is private
    if (_isPrivate) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: AppTheme.navyText.withValues(alpha: 0.5),
              ),
              const SizedBox(height: AppTheme.spacingMd),
              Text(
                'This Account is Private',
                style: AppTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.spacingSm),
              Text(
                'Follow @${profile.handle} to see their bio, location, website, and interests.',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.navyText.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            Text(
              'Bio',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.navyText,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              profile.bio!,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.navyText.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: AppTheme.spacingLg),
          ],
          if (profile.location != null && profile.location!.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.location_on, size: 16, color: AppTheme.navyText),
                const SizedBox(width: AppTheme.spacingXs),
                Text(
                  profile.location!,
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.navyText.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSm),
          ],
          if (profile.website != null && profile.website!.isNotEmpty) ...[
            InkWell(
              onTap: () => UrlLauncherHelper.launchUrlSafely(context, profile.website!),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: [
                  Icon(Icons.link, size: 16, color: AppTheme.navyText),
                  const SizedBox(width: AppTheme.spacingXs),
                  Expanded(
                    child: Text(
                      profile.website!,
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.brightNavy,
                        decoration: TextDecoration.underline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
          ],
          if (profile.interests != null && profile.interests!.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSm),
            Text(
              'Interests',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.navyText,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSm),
            Wrap(
              spacing: AppTheme.spacingSm,
              runSpacing: AppTheme.spacingSm,
              children: profile.interests!.map((interest) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSm,
                    vertical: AppTheme.spacingXs,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.queenPink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(
                      color: AppTheme.royalPurple.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    interest,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.navyText,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppTheme.spacingLg),
          ],
          Text(
            'Joined',
            style: AppTheme.labelMedium.copyWith(
              color: AppTheme.navyText,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Text(
            _formatDate(profile.createdAt),
            style: AppTheme.bodyMedium.copyWith(
              color: AppTheme.navyText.withValues(alpha: 0.85),
            ),
          ),
          if (profile.trustState != null) ...[
            const SizedBox(height: AppTheme.spacingLg),
            _buildTrustInfo(profile.trustState!),
          ],
        ],
      ),
    );
  }

  Widget _buildTrustInfo(TrustState trustState) {
    return GestureDetector(
      onTap: () => HarmonyExplainerModal.show(context, trustState),
      child: Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
          color: AppTheme.egyptianBlue,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trust Status',
            style: AppTheme.labelMedium.copyWith(
              color: AppTheme.navyText,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          Row(
            children: [
              Text(
                'Tier: ',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.navyText.withValues(alpha: 0.85),
                ),
              ),
              Text(
                trustState.tier.displayName,
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _getTierColor(trustState.tier),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingXs),
          Row(
            children: [
              Text(
                'Harmony Score: ',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.navyText.withValues(alpha: 0.85),
                ),
              ),
              Text(
                '${trustState.harmonyScore}',
                style: AppTheme.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.royalPurple,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Color _getTierColor(TrustTier tier) {
    switch (tier) {
      case TrustTier.established:
        return const Color(0xFFFFD700);
      case TrustTier.trusted:
        return AppTheme.royalPurple;
      case TrustTier.new_user:
        return AppTheme.egyptianBlue;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years year${years > 1 ? "s" : ""} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months month${months > 1 ? "s" : ""} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? "s" : ""} ago';
    } else {
      return 'Today';
    }
  }
}

// ==============================================================================
// UNIFIED PROFILE HEADER
// ==============================================================================

class _ProfileHeader extends StatelessWidget {
  final Profile profile;
  final ProfileStats? stats;
  final bool isFollowing;
  final bool isFriend;
  final String? followStatus;
  final bool isPrivate;
  final bool isFollowActionLoading;
  final bool isOwnProfile;
  final VoidCallback onFollowToggle;
  final VoidCallback onMessageTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onPrivacyTap;
  final VoidCallback? onAvatarTap;
  final void Function(int tabIndex)? onConnectionsTap;

  const _ProfileHeader({
    required this.profile,
    required this.stats,
    required this.isFollowing,
    required this.isFriend,
    required this.followStatus,
    required this.isPrivate,
    required this.isFollowActionLoading,
    required this.isOwnProfile,
    required this.onFollowToggle,
    required this.onMessageTap,
    required this.onSettingsTap,
    required this.onPrivacyTap,
    this.onAvatarTap,
    this.onConnectionsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: _generateGradient(profile.handle),
      ),
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxHeight < 240;
            final avatarRadius = isCompact ? 38.0 : 44.0;
            return Padding(
              padding: EdgeInsets.only(
                top: 0,
                bottom: isCompact ? 4 : 6,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isOwnProfile)
                    Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.only(top: 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: onPrivacyTap,
                              icon: Icon(Icons.lock_outline, color: AppTheme.white),
                              tooltip: 'Privacy',
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: onSettingsTap,
                              icon: Icon(Icons.settings_outlined, color: AppTheme.white),
                              tooltip: 'Settings',
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (onAvatarTap != null)
                    InkResponse(
                      onTap: onAvatarTap,
                      radius: 40,
                      child: _HarmonyAvatar(
                        profile: profile,
                        radius: avatarRadius,
                      ),
                    )
                  else
                    _HarmonyAvatar(
                      profile: profile,
                      radius: avatarRadius,
                    ),
                  SizedBox(height: isCompact ? 4 : 6),
                  Text(
                    profile.displayName,
                    style: AppTheme.headlineMedium.copyWith(
                      color: AppTheme.white.withValues(alpha: 0.95),
                      fontSize: isCompact ? 16 : 18,
                      shadows: [
                        Shadow(
                          color: const Color(0x33000000),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '@${profile.handle}',
                        style: AppTheme.bodyMedium.copyWith(
                          fontSize: 12,
                          color: AppTheme.white.withValues(alpha: 0.85),
                          shadows: [
                            Shadow(
                              color: const Color(0x33000000),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      if (getCountryFlag(profile.originCountry ?? 'US') != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          getCountryFlag(profile.originCountry ?? 'US')!,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                  if (!isOwnProfile) ...[
                    SizedBox(height: isCompact ? 8 : 12),
                    _buildRelationshipActions(),
                  ],
                  if (stats != null && !isCompact) ...[
                    const SizedBox(height: 8),
                    _buildStats(stats!),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    if (isOwnProfile) {
      return Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: AppTheme.spacingSm,
          runSpacing: AppTheme.spacingXs,
          alignment: WrapAlignment.end,
          children: [
            _HeaderActionButton(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onPressed: onSettingsTap,
            ),
            _HeaderActionButton(
              icon: Icons.lock_outline,
              label: 'Privacy',
              onPressed: onPrivacyTap,
            ),
          ],
        ),
      );
    }
    return _buildFollowButton();
  }

  Widget _buildRelationshipActions() {
    return Wrap(
      spacing: AppTheme.spacingSm,
      runSpacing: AppTheme.spacingXs,
      alignment: WrapAlignment.center,
      children: [
        _buildFollowButton(),
        if (isFriend)
          OutlinedButton.icon(
            onPressed: onMessageTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.white,
              side: BorderSide(color: AppTheme.white.withValues(alpha: 0.7)),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMd,
                vertical: AppTheme.spacingSm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: Text(
              'Message',
              style: AppTheme.labelMedium.copyWith(color: AppTheme.white),
            ),
          ),
      ],
    );
  }

  Widget _buildFollowButton() {
    final isPending = followStatus == 'pending';
    final label = isFriend
        ? 'Friends'
        : isFollowing
            ? 'Following'
            : (isPending ? 'Requested' : (isPrivate ? 'Request' : 'Follow'));
    final isDisabled = isFollowActionLoading;

    return ElevatedButton(
      onPressed: isDisabled ? null : onFollowToggle,
      style: ElevatedButton.styleFrom(
        backgroundColor: isFollowing ? AppTheme.queenPink : AppTheme.royalPurple,
        foregroundColor: isFollowing ? AppTheme.navyBlue : AppTheme.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg,
          vertical: AppTheme.spacingSm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: isFollowing
              ? BorderSide(color: AppTheme.egyptianBlue, width: 1)
              : BorderSide.none,
        ),
      ),
      child: isFollowActionLoading
          ? SizedBox(
              width: 60,
              height: 16,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isFollowing ? AppTheme.navyBlue : AppTheme.white,
                    ),
                  ),
                ),
              ),
            )
          : Text(
              label,
              style: AppTheme.labelMedium.copyWith(
                color: isFollowing ? AppTheme.navyBlue : AppTheme.white,
              ),
            ),
    );
  }

  Widget _buildStats(ProfileStats stats) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: const Color(0x59000000),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatItem(label: 'Posts', value: stats.posts.toString()),
            const SizedBox(width: AppTheme.spacingMd),
            _StatItem(
              label: 'Followers',
              value: stats.followers.toString(),
              onTap: onConnectionsTap != null ? () => onConnectionsTap!(0) : null,
            ),
            const SizedBox(width: AppTheme.spacingMd),
            _StatItem(
              label: 'Following',
              value: stats.following.toString(),
              onTap: onConnectionsTap != null ? () => onConnectionsTap!(1) : null,
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient _generateGradient(String seed) {
    final hash = seed.hashCode.abs();
    final hue = (hash % 360).toDouble();

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        HSLColor.fromAHSL(1.0, hue, 0.6, 0.55).toColor(),
        HSLColor.fromAHSL(1.0, (hue + 60) % 360, 0.6, 0.45).toColor(),
      ],
    );
  }
}

// ==============================================================================
// STAT ITEM
// ==============================================================================

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StatItem({
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTheme.headlineSmall.copyWith(
            color: SojornColors.basicWhite,
            fontSize: 16,
            shadows: [
              Shadow(
                color: const Color(0x4D000000),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: SojornColors.basicWhite.withValues(alpha: 0.85),
            shadows: [
              Shadow(
                color: const Color(0x4D000000),
                blurRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }
    return content;
  }
}

// ==============================================================================
// HARMONY AVATAR WITH RING
// ==============================================================================

class _HarmonyAvatar extends StatelessWidget {
  final Profile profile;
  final double radius;

  const _HarmonyAvatar({
    required this.profile,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final trustState = profile.trustState;
    final avatarLetter =
        profile.handle.isNotEmpty ? profile.handle[0].toUpperCase() : '?';

    Color ringColor = AppTheme.egyptianBlue;
    double ringWidth = 3;

    if (trustState != null) {
      final harmonyScore = trustState.harmonyScore / 100.0;

      if (harmonyScore >= 0.8) {
        ringColor = const Color(0xFFFFD700);
        ringWidth = 5;
      } else if (harmonyScore >= 0.5) {
        ringColor = AppTheme.royalPurple;
        ringWidth = 4;
      } else if (harmonyScore >= 0.3) {
        ringColor = AppTheme.egyptianBlue;
        ringWidth = 3;
      } else {
        ringColor = AppTheme.textDisabled;
        ringWidth = 2;
      }
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius * 0.45),
        border: Border.all(
          color: ringWidth >= 4 ? ringColor : ringColor.withValues(alpha: 0.8),
          width: ringWidth,
        ),
        boxShadow: [
          if (ringWidth >= 4)
            BoxShadow(
              color: ringColor.withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 2,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius * 0.4),
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
              ? SignedMediaImage(
                  url: profile.avatarUrl!,
                  fit: BoxFit.cover,
                )
              : Container(
                  color: AppTheme.queenPink,
                  alignment: Alignment.center,
                  child: Text(
                    avatarLetter,
                    style: AppTheme.headlineMedium.copyWith(
                      fontSize: radius * 0.6,
                      color: AppTheme.royalPurple,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ==============================================================================
// HARMONY BADGE
// ==============================================================================

class _HarmonyBadge extends StatelessWidget {
  final TrustState trustState;

  const _HarmonyBadge({
    required this.trustState,
  });

  @override
  Widget build(BuildContext context) {
    final tier = trustState.tier;
    Color badgeColor;
    Color textColor;

    switch (tier) {
      case TrustTier.established:
        badgeColor = const Color(0xFFFFD700);
        break;
      case TrustTier.trusted:
        badgeColor = AppTheme.royalPurple;
        break;
      case TrustTier.new_user:
        badgeColor = AppTheme.egyptianBlue;
        break;
    }
    textColor = tier == TrustTier.new_user ? AppTheme.white : badgeColor;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        border: Border.all(color: badgeColor, width: 1.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getIconForTier(tier),
            size: 12,
            color: badgeColor,
          ),
          const SizedBox(width: 4),
          Text(
            tier.displayName,
            style: AppTheme.labelSmall.copyWith(
              color: textColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForTier(TrustTier tier) {
    switch (tier) {
      case TrustTier.established:
        return Icons.verified;
      case TrustTier.trusted:
        return Icons.check_circle;
      case TrustTier.new_user:
        return Icons.fiber_new;
    }
  }
}

// ==============================================================================
// HEADER ACTION BUTTON
// ==============================================================================

class _HeaderActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _HeaderActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.white,
        side: BorderSide(color: AppTheme.white.withValues(alpha: 0.7)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMd,
          vertical: AppTheme.spacingSm,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: AppTheme.labelMedium.copyWith(color: AppTheme.white),
      ),
    );
  }
}

// ==============================================================================
// PRIVACY DROPDOWN
// ==============================================================================

class _PrivacyDropdown extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _PrivacyDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  static const Map<String, String> _options = {
    'public': 'Public',
    'followers': 'Followers only',
    'private': 'Private',
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: _options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}

// ==============================================================================
// SLIVER TAB BAR DELEGATE
// ==============================================================================

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppTheme.cardSurface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return false;
  }
}
