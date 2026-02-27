// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
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
import '../../services/image_upload_service.dart';
import '../../services/secure_chat_service.dart';
import '../../models/sojorn_media_result.dart';
import '../post/post_detail_screen.dart';
import 'profile_settings_screen.dart';
import 'followers_following_screen.dart';
import '../../widgets/desktop/desktop_dialog_helper.dart';
import '../../widgets/desktop/desktop_slide_panel.dart';
import '../../models/profile_widgets.dart';
import '../../widgets/harmony_explainer_modal.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/composer/composer_bar.dart';
import '../../utils/snackbar_ext.dart';

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
  List<String> _top8SelectedIds = [];
  bool _isMutualFollowersLoading = false;

  /// Returns Top 8 friends ordered by dashboard config (if curated), else first 8.
  List<Map<String, dynamic>> get _resolvedTop8 {
    if (_top8SelectedIds.isEmpty) return _mutualFollowers.take(8).toList();
    final ordered = _top8SelectedIds
        .map((id) => _mutualFollowers.cast<Map<String, dynamic>?>().firstWhere(
              (f) => f?['id'] == id || f?['user_id'] == id,
              orElse: () => null,
            ))
        .whereType<Map<String, dynamic>>()
        .toList();
    if (ordered.length < 8) {
      final selectedSet = _top8SelectedIds.toSet();
      final extras = _mutualFollowers
          .where((f) => !selectedSet.contains(f['id'] as String? ?? f['user_id'] as String? ?? ''))
          .take(8 - ordered.length);
      ordered.addAll(extras);
    }
    return ordered.take(8).toList();
  }

  bool _isBannerUploading = false;
  double _bannerUploadProgress = 0.0;
  final ImagePicker _imagePicker = ImagePicker();
  final ImageUploadService _imageUploadService = ImageUploadService();

  // Inline composer state
  bool _composerExpanded = false;
  final _composerFocusNode = FocusNode();

  /// True when no handle was provided (bottom-nav profile tab)
  bool get _isOwnProfileMode => widget.handle == null;

  late TabController _tabController;
  int _activeTab = 0;
  bool _isGridView = false; // default list view; toggled by user

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
    debugPrint('[PROFILE] initState — ${_isOwnProfileMode ? "own profile" : "viewing @${widget.handle}"}');
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
    _composerFocusNode.dispose();
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
      debugPrint('[PROFILE] Loaded @${profile.handle} — posts=${stats.posts}, followers=${stats.followers}, following=${stats.following}, isPrivate=$isPrivate, coverUrl=${profile.coverUrl}');
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
      // Load Top 8 friends in parallel with posts
      _loadMutualFollowers(profile.id, isOwnProfile);
      await _loadPosts(refresh: true);
    } catch (error) {
      debugPrint('[PROFILE] Load error: $error');
      if (!mounted) return;

      // Auto-create profile if own profile and profile not found
      if (_isOwnProfileMode && _shouldAutoCreateProfile(error)) {
        debugPrint('[PROFILE] Auto-creating profile for new user');
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

  Future<void> _loadMutualFollowers(String userId, bool isOwn) async {
    if (_isMutualFollowersLoading) return;
    _isMutualFollowersLoading = true;
    try {
      final apiService = ref.read(apiServiceProvider);
      final followers = await apiService.getMutualFollowers(userId);
      if (!mounted) return;

      // For own profile, load dashboard config to get curated Top 8 order
      List<String> selectedIds = [];
      if (isOwn) {
        try {
          final layout = await apiService.getDashboardLayout();
          // Find top8 widget config in left or right sidebar
          for (final slot in ['left_sidebar', 'right_sidebar']) {
            final widgets = layout[slot] as List? ?? [];
            for (final w in widgets) {
              if (w is Map<String, dynamic> && w['type'] == 'top8') {
                final config = w['config'] as Map<String, dynamic>? ?? {};
                selectedIds = (config['selected_friend_ids'] as List?)?.cast<String>() ?? [];
                break;
              }
            }
            if (selectedIds.isNotEmpty) break;
          }
        } catch (_) {}
      }

      setState(() {
        _mutualFollowers = followers;
        _top8SelectedIds = selectedIds;
      });
    } catch (e) {
      debugPrint('[PROFILE] Failed to load mutual followers: $e');
    } finally {
      _isMutualFollowersLoading = false;
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
        await apiService.followUser(_profile!.id);
        if (!mounted) return;
        setState(() {
          _followStatus = 'accepted';
          _isFollowing = true;
          _isFriend = _isFollowing && _isFollowedBy;
          if (_stats != null) {
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

    final settingsScreen = ProfileSettingsScreen(
      profile: profile,
      settings: settings,
    );

    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (isDesktop) {
      openDesktopSlidePanel(
        context,
        width: 520,
        child: settingsScreen,
      );
      // Desktop panel is fire-and-forget; reload profile when user returns.
    } else {
      final result = await Navigator.of(context, rootNavigator: true)
          .push<ProfileSettingsResult>(
        MaterialPageRoute(builder: (_) => settingsScreen),
      );

      if (result != null && mounted) {
        setState(() {
          _profile = result.profile;
          _privacySettings = result.settings;
        });
      }
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
    openDesktopDialog(
      context,
      width: 600,
      child: FollowersFollowingScreen(
        userId: _profile!.id,
        initialTabIndex: tabIndex,
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

  void _showBannerActions() {
    final hasBanner = (_profile?.coverUrl ?? '').isNotEmpty;
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SojornRadii.modal),
          ),
          title: Text(hasBanner ? 'Cover Photo' : 'Add Cover Photo',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasBanner)
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: const Text('View cover photo'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _viewBannerFullscreen();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(hasBanner ? 'Choose from gallery' : 'Choose from gallery'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickAndUploadBanner();
                },
              ),
              if (hasBanner)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: AppTheme.error),
                  title: Text('Remove cover photo', style: TextStyle(color: AppTheme.error)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _removeBanner();
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _viewBannerFullscreen() {
    final url = _profile?.coverUrl;
    if (url == null || url.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(
            child: SignedMediaImage(url: url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  /// Banner resolution: 1440×480 (3:1 ratio), matching the 720×200 display at 2x
  Future<void> _pickAndUploadBanner() async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    // Open editor locked to 3:1 banner crop with resolution hint
    final result = await Navigator.push<SojornMediaResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _BannerImageEditor(imageBytes: bytes, imageName: file.name),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _isBannerUploading = true;
      _bannerUploadProgress = 0.0;
    });

    void onProgress(double p) {
      if (mounted) setState(() => _bannerUploadProgress = p);
    }

    try {
      final String url;
      if (result.bytes != null) {
        url = await _imageUploadService.uploadImageBytes(
          result.bytes!,
          fileName: result.name ?? 'banner.jpg',
          maxWidth: 1440,
          maxHeight: 480,
          quality: 90,
          onProgress: onProgress,
        );
      } else {
        url = await _imageUploadService.uploadImage(
          File(result.filePath!),
          maxWidth: 1440,
          maxHeight: 480,
          quality: 90,
          onProgress: onProgress,
        );
      }

      // Update profile with new cover URL
      if (mounted) setState(() => _bannerUploadProgress = 0.95);
      await ref.read(apiServiceProvider).updateProfile(coverUrl: url);

      if (mounted) {
        setState(() {
          _profile = _profile?.copyWith(coverUrl: url);
          _isBannerUploading = false;
          _bannerUploadProgress = 0.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBannerUploading = false;
          _bannerUploadProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Banner upload failed: $e')),
        );
      }
    }
  }

  Future<void> _removeBanner() async {
    try {
      await ref.read(apiServiceProvider).updateProfile(coverUrl: '');
      if (mounted) {
        setState(() {
          _profile = _profile?.copyWith(coverUrl: '');
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove banner: $e')),
        );
      }
    }
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
                SojornAvatar(
                  displayName: profile.displayName,
                  avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                  size: 144,
                  borderRadius: 36,
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

    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (isDesktop) {
      return _buildDesktopProfile();
    }
    return _buildMobileProfile();
  }

  Widget _buildDesktopProfile() {
    final profile = _profile!;
    final hasBanner = (profile.coverUrl ?? '').isNotEmpty;
    final flag = getCountryFlag(profile.originCountry ?? 'US');

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ══════════════════════════════════════════════════════════════
              // BANNER + AVATAR + UNIFIED INFO CARD (overlapping via Stack)
              // ══════════════════════════════════════════════════════════════
              SizedBox(
                height: 260,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Banner image
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (hasBanner)
                              SignedMediaImage(url: profile.coverUrl!, fit: BoxFit.cover)
                            else
                              Container(decoration: BoxDecoration(gradient: _ProfileHeader._generateGradientStatic(profile.handle))),
                            // Gradient overlay
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
                                  stops: const [0.3, 1.0],
                                ),
                              ),
                            ),
                            // Banner upload overlay with progress
                            if (_isBannerUploading)
                              Container(
                                color: Colors.black.withValues(alpha: 0.5),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            CircularProgressIndicator(
                                              value: _bannerUploadProgress > 0 ? _bannerUploadProgress : null,
                                              strokeWidth: 3,
                                              color: Colors.white,
                                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                                            ),
                                            if (_bannerUploadProgress > 0)
                                              Text(
                                                '${(_bannerUploadProgress * 100).toInt()}%',
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text('Uploading cover...', style: TextStyle(color: Colors.white, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ),
                            // Edit cover button (own profile)
                            if (_isOwnProfile && !_isBannerUploading)
                              Positioned(
                                top: 12,
                                right: 12,
                                child: _buildChipButton(
                                  icon: Icons.camera_alt_outlined,
                                  label: hasBanner ? 'Edit Cover' : 'Add Cover',
                                  onTap: _showBannerActions,
                                ),
                              ),
                            // Back button (viewing others)
                            if (!_isOwnProfileMode)
                              Positioned(
                                top: 12,
                                left: 12,
                                child: _buildChipButton(
                                  icon: Icons.arrow_back,
                                  label: 'Back',
                                  onTap: () {
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();
                                    } else {
                                      context.go(AppRoutes.homeAlias);
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Avatar (overlapping banner bottom)
                    Positioned(
                      bottom: -48,
                      left: 40,
                      child: GestureDetector(
                        onTap: _isOwnProfile ? _showAvatarActions : () => _showAvatarPreview(profile),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.cardSurface, width: 4),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 4))],
                          ),
                          child: SojornAvatar(
                            displayName: profile.displayName,
                            avatarUrl: _resolveAvatar(profile.avatarUrl),
                            size: 110,
                            borderRadius: 55,
                          ),
                        ),
                      ),
                    ),

                    // Unified info card (overlapping banner bottom)
                    Positioned(
                      bottom: -90,
                      left: 180,
                      right: 40,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                        decoration: BoxDecoration(
                          color: AppTheme.cardSurface,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 4)),
                          ],
                          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Name + badge + action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          profile.displayName,
                                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1a1a2e)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (profile.trustState != null)
                                        _DesktopHarmonyBadge(trustState: profile.trustState!),
                                    ],
                                  ),
                                ),
                                // Action buttons
                                if (_isOwnProfile)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: _openSettings,
                                        icon: const Icon(Icons.edit_outlined, size: 14),
                                        label: const Text('Edit Profile', style: TextStyle(fontSize: 12)),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppTheme.royalPurple,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      OutlinedButton.icon(
                                        onPressed: () {},
                                        icon: const Icon(Icons.ios_share_outlined, size: 14),
                                        label: const Text('Share', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppTheme.isDark ? AppTheme.navyText : AppTheme.navyText.withValues(alpha: 0.7),
                                          backgroundColor: AppTheme.isDark ? AppTheme.navyText.withValues(alpha: 0.08) : null,
                                          side: BorderSide(color: AppTheme.navyText.withValues(alpha: AppTheme.isDark ? 0.15 : 0.2)),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildFollowButtonDesktop(),
                                      if (_isFriend) ...[
                                        const SizedBox(width: 6),
                                        OutlinedButton.icon(
                                          onPressed: _openMessage,
                                          icon: const Icon(Icons.mail_outline, size: 14),
                                          label: const Text('Message', style: TextStyle(fontSize: 12)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppTheme.isDark ? AppTheme.navyText : AppTheme.navyText.withValues(alpha: 0.7),
                                            backgroundColor: AppTheme.isDark ? AppTheme.navyText.withValues(alpha: 0.08) : null,
                                            side: BorderSide(color: AppTheme.navyText.withValues(alpha: AppTheme.isDark ? 0.15 : 0.2)),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Handle + location + flag
                            Row(
                              children: [
                                Text(
                                  '@${profile.handle}',
                                  style: TextStyle(fontSize: 13, color: AppTheme.navyText.withValues(alpha: 0.55)),
                                ),
                                if (profile.location != null && profile.location!.isNotEmpty) ...[
                                  Text(' · ', style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.35))),
                                  Icon(Icons.location_on, size: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      profile.location!,
                                      style: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.55)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                if (flag != null) ...[
                                  const SizedBox(width: 5),
                                  Text(flag, style: const TextStyle(fontSize: 12)),
                                ],
                              ],
                            ),
                            // Stats row
                            if (_stats != null) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Container(
                                  height: 1,
                                  color: AppTheme.navyText.withValues(alpha: 0.06),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  children: [
                                    _DesktopStat(value: _stats!.posts, label: 'Posts'),
                                    const SizedBox(width: 24),
                                    _DesktopStat(value: _stats!.followers, label: 'Followers', onTap: () => _navigateToConnections(0)),
                                    const SizedBox(width: 24),
                                    _DesktopStat(value: _stats!.following, label: 'Following', onTap: () => _navigateToConnections(1)),
                                    if (profile.trustState != null) ...[
                                      const SizedBox(width: 16),
                                      Container(height: 28, width: 1, color: AppTheme.navyText.withValues(alpha: 0.08)),
                                      const SizedBox(width: 16),
                                      GestureDetector(
                                        onTap: () => HarmonyExplainerModal.show(context, profile.trustState!),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(profile.trustState!.tier.emoji, style: const TextStyle(fontSize: 13)),
                                            const SizedBox(width: 4),
                                            Text('Harmony: ', style: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.6))),
                                            Text(
                                              '${profile.trustState!.harmonyScore}%',
                                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: profile.trustState!.tier.color),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Spacer for the overlapping card
              const SizedBox(height: 110),

              // ══════════════════════════════════════════════════════════════
              // TABS
              // ══════════════════════════════════════════════════════════════
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.royalPurple,
                  unselectedLabelColor: AppTheme.navyText.withValues(alpha: 0.5),
                  indicatorColor: AppTheme.royalPurple,
                  indicatorWeight: 3,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  tabs: [
                    const Tab(text: 'Posts'),
                    const Tab(text: 'Saved'),
                    const Tab(text: 'Chains'),
                    if (!_isOwnProfileMode) const Tab(text: 'About'),
                  ],
                ),
              ),

              Divider(height: 1, color: AppTheme.navyText.withValues(alpha: 0.08)),

              // ══════════════════════════════════════════════════════════════
              // TWO-COLUMN CONTENT: Left info sidebar + Right post feed
              // ══════════════════════════════════════════════════════════════
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 24, 40, 60),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Left column: info cards (340px) ──
                    SizedBox(
                      width: 340,
                      child: _buildDesktopInfoSidebar(),
                    ),
                    const SizedBox(width: 24),
                    // ── Right column: feed ──
                    Expanded(
                      child: _buildDesktopFeedColumn(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChipButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.isDark
              ? SojornColors.darkSurfaceElevated.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: AppTheme.isDark ? 0.3 : 0.1), blurRadius: 8)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.isDark ? SojornColors.darkPostContent : const Color(0xFF374151)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.isDark ? SojornColors.darkPostContent : const Color(0xFF374151))),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowButtonDesktop() {
    final isPending = _followStatus == 'pending';
    final label = _isFriend
        ? 'Friends'
        : _isFollowing
            ? 'Following'
            : (isPending ? 'Requested' : (_isPrivate ? 'Request' : 'Follow'));

    return FilledButton(
      onPressed: _isFollowActionLoading ? null : _toggleFollow,
      style: FilledButton.styleFrom(
        backgroundColor: _isFollowing
            ? (AppTheme.isDark ? AppTheme.royalPurple.withValues(alpha: 0.15) : Colors.white)
            : AppTheme.royalPurple,
        foregroundColor: _isFollowing ? AppTheme.royalPurple : Colors.white,
        side: _isFollowing ? BorderSide(color: AppTheme.royalPurple, width: AppTheme.isDark ? 1 : 2) : null,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _isFollowActionLoading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }

  /// Left sidebar: About card, Top 8, Now Playing, Beacon Activity
  Widget _buildDesktopInfoSidebar() {
    final profile = _profile!;

    return Column(
      children: [
        // ── About Card ──
        _DesktopCard(
          title: 'About',
          children: [
            if ((profile.bio ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  profile.bio!,
                  style: TextStyle(fontSize: 14, height: 1.6, color: AppTheme.navyText.withValues(alpha: 0.85)),
                ),
              )
            else if (_isOwnProfile)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: GestureDetector(
                  onTap: _openSettings,
                  child: Text(
                    'Add a bio to tell people about yourself...',
                    style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: AppTheme.navyText.withValues(alpha: 0.35)),
                  ),
                ),
              ),
            if ((profile.location ?? '').isNotEmpty)
              _InfoRow(icon: Icons.location_on, text: profile.location!),
            _InfoRow(icon: Icons.calendar_today, text: 'Joined ${_formatJoinDate(profile.createdAt)}'),
            if ((profile.website ?? '').isNotEmpty)
              _InfoRow(
                icon: Icons.link,
                child: GestureDetector(
                  onTap: () => UrlLauncherHelper.launchUrlSafely(context, profile.website!),
                  child: Text(
                    profile.website!,
                    style: TextStyle(fontSize: 14, color: AppTheme.royalPurple, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, decorationColor: AppTheme.royalPurple.withValues(alpha: 0.5)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            // Metadata fields
            if (profile.metadataFields.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(height: 1, color: AppTheme.navyText.withValues(alpha: 0.06)),
              const SizedBox(height: 12),
              ...profile.metadataFields.map((field) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(field.key, style: TextStyle(fontSize: 13, color: AppTheme.navyText.withValues(alpha: 0.5), fontWeight: FontWeight.w500)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (field.verified)
                          Icon(Icons.check, size: 14, color: const Color(0xFF16A34A)),
                        if (field.verified) const SizedBox(width: 4),
                        Text(
                          field.value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: field.verified ? const Color(0xFF16A34A) : AppTheme.navyText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )),
            ],
            // Interests
            if ((profile.interests ?? []).isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: AppTheme.navyText.withValues(alpha: 0.06)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: profile.interests!.map((interest) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.queenPink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.25)),
                  ),
                  child: Text(interest, style: TextStyle(fontSize: 12, color: AppTheme.navyText)),
                )).toList(),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // ── Top 8 Card ──
        _DesktopCard(
          title: 'Top 8',
          trailing: GestureDetector(
            onTap: () => _navigateToConnections(0),
            child: Text('See all friends', style: TextStyle(fontSize: 13, color: AppTheme.royalPurple, fontWeight: FontWeight.w600)),
          ),
          children: [
            if (_mutualFollowers.isEmpty && !_isMutualFollowersLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No friends yet', style: TextStyle(fontSize: 13, color: AppTheme.navyText.withValues(alpha: 0.4))),
                ),
              )
            else if (_mutualFollowers.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _resolvedTop8.map((f) {
                  final name = f['display_name'] ?? f['handle'] ?? '?';
                  final avatar = _resolveAvatar(f['avatar_url'] as String?);
                  final handle = f['handle'] as String? ?? '';
                  return GestureDetector(
                    onTap: () => AppRoutes.navigateToProfile(context, handle),
                    child: SizedBox(
                      width: 68,
                      child: Column(
                        children: [
                          SojornAvatar(displayName: name, avatarUrl: avatar.isNotEmpty ? avatar : null, size: 56, borderRadius: 28),
                          const SizedBox(height: 4),
                          Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.navyText), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ],
    );
  }

  String _formatJoinDate(DateTime date) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[date.month - 1]} ${date.year}';
  }

  // ── Inline expanding composer ──────────────────────────────────────────

  Widget _buildInlineComposer() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: avatar + hint/text field
          GestureDetector(
            onTap: () {
              if (!_composerExpanded) {
                setState(() => _composerExpanded = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _composerFocusNode.requestFocus();
                });
              }
            },
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, _composerExpanded ? 0 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SojornAvatar(
                    displayName: _profile!.displayName,
                    avatarUrl: _resolveAvatar(_profile!.avatarUrl),
                    size: 40,
                    borderRadius: 20,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _composerExpanded
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.scaffoldBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "What's on your mind?",
                              style: TextStyle(fontSize: 14, color: AppTheme.navyText.withValues(alpha: 0.4)),
                            ),
                          ),
                  ),
                  if (!_composerExpanded) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        setState(() => _composerExpanded = true);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _composerFocusNode.requestFocus();
                        });
                      },
                      icon: Icon(Icons.photo_outlined, size: 20, color: AppTheme.navyText.withValues(alpha: 0.4)),
                      tooltip: 'Photo',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded: ComposerBar with full options
          if (_composerExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: ComposerBar(
                config: const ComposerConfig(
                  allowImages: true,
                  allowGifs: true,
                  hintText: "What's on your mind?",
                  maxLines: 5,
                ),
                focusNode: _composerFocusNode,
                onSend: _onComposerSend,
              ),
            ),
            // Cancel row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _composerExpanded = false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _onComposerSend(String text, String? mediaUrl) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final post = await apiService.publishPost(
        body: text,
        imageUrl: mediaUrl,
        visibility: 'public',
      );
      if (mounted) {
        setState(() {
          _composerExpanded = false;
          _posts.insert(0, post);
        });
        context.showSuccess('Post published!');
      }
    } catch (e) {
      if (mounted) context.showError('Failed to post: $e');
      rethrow;
    }
  }

  /// Right column: composer + post feed based on active tab
  Widget _buildDesktopFeedColumn() {
    // About tab
    if (_activeTab == 3 && !_isOwnProfileMode) {
      return _buildAboutTab();
    }

    final List<Post> posts;
    final bool isLoading;
    final bool isLoadingMore;
    final bool hasMore;
    final String? error;
    final VoidCallback onRefresh;
    final VoidCallback onLoadMore;

    if (_activeTab == 1) {
      posts = _savedPosts; isLoading = _isSavedLoading; isLoadingMore = _isSavedLoadingMore;
      hasMore = _hasMoreSaved; error = _savedError;
      onRefresh = () => _loadSaved(refresh: true); onLoadMore = () => _loadSaved(refresh: false);
    } else if (_activeTab == 2) {
      posts = _chainedPosts; isLoading = _isChainedLoading; isLoadingMore = _isChainedLoadingMore;
      hasMore = _hasMoreChained; error = _chainedError;
      onRefresh = () => _loadChained(refresh: true); onLoadMore = () => _loadChained(refresh: false);
    } else {
      posts = _posts; isLoading = _isPostsLoading; isLoadingMore = _isPostsLoadingMore;
      hasMore = _hasMorePosts; error = _postsError;
      onRefresh = () => _loadPosts(refresh: true); onLoadMore = () => _loadPosts(refresh: false);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Inline composer (own profile, Posts tab only)
        if (_isOwnProfile && _activeTab == 0)
          _buildInlineComposer(),
        if (_isOwnProfile && _activeTab == 0) const SizedBox(height: 16),

        // Chains empty state
        if (_activeTab == 2 && posts.isEmpty && !isLoading)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                Icon(Icons.link, size: 48, color: AppTheme.royalPurple.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text('Chains', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
                const SizedBox(height: 8),
                Text(
                  'Chains are threaded conversations that build on each other. When you reply to a post and others reply to your reply, it creates a Chain.',
                  style: TextStyle(fontSize: 14, color: AppTheme.navyText.withValues(alpha: 0.6)),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

        // Error
        if (error != null)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(error, style: TextStyle(color: AppTheme.error, fontSize: 14), textAlign: TextAlign.center),
          ),

        // Loading
        if (isLoading && posts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          ),

        // Posts list
        ...posts.map((post) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: sojornPostCard(
            post: post,
            onTap: () => _openPostDetail(post),
            onChain: () => _openChainComposer(post),
          ),
        )),

        // Load more
        if (isLoadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!isLoadingMore && hasMore && posts.isNotEmpty)
          Center(
            child: TextButton(
              onPressed: onLoadMore,
              child: const Text('Load more'),
            ),
          ),

        // Empty posts
        if (posts.isEmpty && !isLoading && _activeTab != 2)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text('No posts yet', style: TextStyle(fontSize: 14, color: AppTheme.navyText.withValues(alpha: 0.5))),
            ),
          ),

        // End indicator
        if (posts.isNotEmpty && !hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text("That's all for now", style: TextStyle(fontSize: 14, color: AppTheme.navyText.withValues(alpha: 0.35))),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileProfile() {
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
    return SliverToBoxAdapter(
      child: _ProfileHeader(
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
        onBannerTap: _isOwnProfile ? _showBannerActions : null,
        isBannerUploading: _isBannerUploading,
        bannerUploadProgress: _bannerUploadProgress,
        onConnectionsTap: _isOwnProfile ? _navigateToConnections : null,
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
            const Tooltip(message: 'Posts you\'ve replied to or continued', child: Tab(text: 'Chains')),
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
        emptyStateWidget: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link, size: 48, color: AppTheme.royalPurple.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  'Chains',
                  style: AppTheme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navyText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Chains are threaded conversations that build on each other. When you reply to a post and others reply to your reply, it creates a Chain. Your longest and most engaging Chains appear here.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.navyText.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ComposeScreen(),
                      fullscreenDialog: true,
                    ),
                  ),
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('Start a Chain'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.royalPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
      showToggle: true,
    );
  }

  Widget _buildFeedView(
    List<Post> posts,
    bool isLoading,
    bool isLoadingMore,
    bool hasMore,
    String? error,
    VoidCallback onRefresh,
    VoidCallback onLoadMore, {
    bool showToggle = false,
    Widget? emptyStateWidget,
  }) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: [
          // Grid/List toggle header (Posts tab only)
          if (showToggle && (posts.isNotEmpty || isLoading))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: () => setState(() => _isGridView = false),
                      icon: Icon(
                        Icons.view_list_outlined,
                        color: _isGridView
                            ? AppTheme.navyText.withValues(alpha: 0.35)
                            : AppTheme.royalPurple,
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'List view',
                    ),
                    IconButton(
                      onPressed: () => setState(() => _isGridView = true),
                      icon: Icon(
                        Icons.grid_on_outlined,
                        color: _isGridView
                            ? AppTheme.royalPurple
                            : AppTheme.navyText.withValues(alpha: 0.35),
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Grid view',
                    ),
                  ],
                ),
              ),
            ),
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
              child: emptyStateWidget ?? Center(
                child: Text(
                  'No posts yet',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.navyText.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          if (posts.isNotEmpty && showToggle && _isGridView)
            SliverPadding(
              padding: const EdgeInsets.all(AppTheme.spacingXs),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final post = posts[index];
                    final imageUrl = post.imageUrl ?? post.thumbnailUrl;
                    return GestureDetector(
                      onTap: () => _openPostDetail(post),
                      child: imageUrl != null && imageUrl.isNotEmpty
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                SignedMediaImage(url: imageUrl, fit: BoxFit.cover),
                                if (post.videoUrl != null)
                                  const Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Icon(
                                      Icons.play_circle_filled,
                                      color: Colors.white,
                                      size: 20,
                                      shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                                    ),
                                  ),
                              ],
                            )
                          : _buildTextGridCell(post),
                    );
                  },
                  childCount: posts.length,
                ),
              ),
            )
          else if (posts.isNotEmpty)
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
                        decorationColor: AppTheme.brightNavy.withValues(alpha: 0.5),
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

  Color _getTierColor(TrustTier tier) => tier.color;

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

  /// Mini post card for grid cells that have no image or thumbnail.
  Widget _buildTextGridCell(Post post) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border.all(
          color: AppTheme.navyBlue.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Stack(
        children: [
          if (post.body.isNotEmpty)
            Text(
              post.body,
              maxLines: 6,
              overflow: TextOverflow.fade,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.navyText.withValues(alpha: 0.85),
                height: 1.35,
              ),
            ),
          if (post.videoUrl != null)
            Positioned(
              bottom: 4,
              right: 4,
              child: Icon(
                Icons.play_circle_outline,
                color: AppTheme.brightNavy,
                size: 18,
              ),
            ),
        ],
      ),
    );
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
  final VoidCallback? onBannerTap;
  final bool isBannerUploading;
  final double bannerUploadProgress;
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
    this.onBannerTap,
    this.isBannerUploading = false,
    this.bannerUploadProgress = 0.0,
    this.onConnectionsTap,
  });

  @override
  Widget build(BuildContext context) {
    const bannerHeight = 150.0;
    final flag = getCountryFlag(profile.originCountry ?? 'US');
    final hasBanner = (profile.coverUrl ?? '').isNotEmpty;

    const avatarSize = 88.0;
    const avatarRingExtra = 11.0; // strokeWidth*2 + 4 from _HarmonyAvatar
    const avatarTotalSize = avatarSize + avatarRingExtra;
    const avatarOverlap = avatarTotalSize / 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Banner + avatar overlap area ─────────────────────────────────
        SizedBox(
          height: bannerHeight + avatarOverlap, // extra space for avatar overhang
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Banner image/gradient (only fills top bannerHeight)
              Positioned(
                top: 0, left: 0, right: 0,
                height: bannerHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (hasBanner)
                      SignedMediaImage(url: profile.coverUrl!, fit: BoxFit.cover)
                    else
                      Container(decoration: BoxDecoration(gradient: _generateGradient(profile.handle))),
                    if (hasBanner)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.45),
                            ],
                          ),
                        ),
                      ),
                    // Top-right: settings icons (own profile)
                    if (isOwnProfile)
                      Positioned(
                        top: 8, right: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: onPrivacyTap,
                              icon: const Icon(Icons.lock_outline, color: Colors.white, size: 20),
                              tooltip: 'Privacy',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            IconButton(
                              onPressed: onSettingsTap,
                              icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 20),
                              tooltip: 'Settings',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    // Banner upload loading overlay
                    if (isBannerUploading)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.5),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 44, height: 44,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: bannerUploadProgress > 0 ? bannerUploadProgress : null,
                                        strokeWidth: 3,
                                        color: Colors.white,
                                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                                      ),
                                      if (bannerUploadProgress > 0)
                                        Text(
                                          '${(bannerUploadProgress * 100).toInt()}%',
                                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text('Uploading cover...', style: TextStyle(color: Colors.white, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Bottom-right: edit cover chip
                    if (isOwnProfile && !isBannerUploading)
                      Positioned(
                        bottom: 10, right: 10,
                        child: GestureDetector(
                          onTap: onBannerTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 14),
                                const SizedBox(width: 5),
                                Text(
                                  hasBanner ? 'Edit cover' : 'Add cover',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Background fill below banner (so avatar area has scaffoldBg)
              Positioned(
                top: bannerHeight, left: 0, right: 0, bottom: 0,
                child: Container(color: AppTheme.scaffoldBg),
              ),
              // Avatar (straddles the banner/content boundary)
              Positioned(
                top: bannerHeight - avatarOverlap,
                left: 20,
                child: GestureDetector(
                  onTap: onAvatarTap,
                  child: _HarmonyAvatar(profile: profile, radius: avatarSize / 2),
                ),
              ),
              // Action buttons (right-aligned, bottom of overlap area)
              Positioned(
                right: 20,
                bottom: 4,
                child: isOwnProfile
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCompactIconButton(Icons.edit_outlined, onSettingsTap, tooltip: 'Edit profile'),
                        const SizedBox(width: 8),
                        _buildCompactIconButton(Icons.ios_share_outlined, () {}, tooltip: 'Share profile'),
                      ],
                    )
                  : _buildRelationshipActions(),
              ),
            ],
          ),
        ),

        // ── Info section (below banner+avatar area) ──────────────────────
        Container(
          color: AppTheme.scaffoldBg,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Name ──────────────────────────────────────────────
              Text(
                profile.displayName,
                style: AppTheme.headlineMedium.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              // ── @handle ───────────────────────────────────────────
              Row(
                children: [
                  Text(
                    '@${profile.handle}',
                    style: AppTheme.bodyMedium.copyWith(
                      fontSize: 13,
                      color: AppTheme.navyText.withValues(alpha: 0.5),
                    ),
                  ),
                  if (flag != null) ...[
                    const SizedBox(width: 4),
                    Text(flag, style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
              // ── Bio ───────────────────────────────────────────────
              if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  profile.bio!,
                  style: AppTheme.bodyMedium.copyWith(fontSize: 14, height: 1.5),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else if (isOwnProfile) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onSettingsTap,
                  child: Text(
                    'Add a bio to tell people about yourself',
                    style: AppTheme.bodyMedium.copyWith(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.navyText.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ],
              // ── Status line ───────────────────────────────────────
              if (profile.statusText != null && profile.statusText!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        color: const Color(0xFF43A047),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF43A047).withValues(alpha: 0.5), blurRadius: 5),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        profile.statusText!,
                        style: AppTheme.bodyMedium.copyWith(
                          fontSize: 12, fontStyle: FontStyle.italic,
                          color: AppTheme.navyText.withValues(alpha: 0.65),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              // ── Trust badge ───────────────────────────────────────
              if (profile.trustState != null) ...[
                const SizedBox(height: 4),
                _ProfileTrustBadge(trustState: profile.trustState!),
              ],
              // ── Stats ─────────────────────────────────────────────
              if (stats != null) ...[
                const SizedBox(height: 12),
                _buildInlineStats(stats!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactIconButton(IconData icon, VoidCallback? onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, size: 16, color: AppTheme.navyText.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineStats(ProfileStats stats) {
    return Row(
      children: [
        _InlineStat(
          value: stats.posts.toString(),
          label: 'Posts',
        ),
        const SizedBox(width: 24),
        _InlineStat(
          value: stats.followers.toString(),
          label: 'Followers',
          onTap: onConnectionsTap != null ? () => onConnectionsTap!(0) : null,
        ),
        const SizedBox(width: 24),
        _InlineStat(
          value: stats.following.toString(),
          label: 'Following',
          onTap: onConnectionsTap != null ? () => onConnectionsTap!(1) : null,
        ),
      ],
    );
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
              foregroundColor: AppTheme.royalPurple,
              backgroundColor: AppTheme.isDark ? AppTheme.royalPurple.withValues(alpha: 0.1) : null,
              side: BorderSide(color: AppTheme.royalPurple.withValues(alpha: 0.6)),
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
              style: AppTheme.labelMedium.copyWith(color: AppTheme.royalPurple),
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

  LinearGradient _generateGradient(String seed) => _generateGradientStatic(seed);

  static LinearGradient _generateGradientStatic(String seed) {
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
// INLINE STAT — compact left-aligned version for new header row
// ==============================================================================

class _InlineStat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _InlineStat({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: AppTheme.navyText,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: AppTheme.navyText.withValues(alpha: 0.55),
            fontSize: 10,
          ),
        ),
      ],
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: content);
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
    double harmonyScore = 0.0;

    if (trustState != null) {
      harmonyScore = (trustState.harmonyScore / 100.0).clamp(0.0, 1.0);
      if (harmonyScore >= 0.8) {
        ringColor = const Color(0xFFFFD700);
      } else if (harmonyScore >= 0.5) {
        ringColor = AppTheme.royalPurple;
      } else if (harmonyScore >= 0.3) {
        ringColor = AppTheme.egyptianBlue;
      } else {
        ringColor = AppTheme.textDisabled;
      }
    }

    const strokeWidth = 3.5;
    final totalSize = radius * 2 + strokeWidth * 2 + 4;

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Progress arc ring (rounded square to match avatar shape)
          CustomPaint(
            size: Size(totalSize, totalSize),
            painter: _HarmonyRingPainter(
              value: harmonyScore,
              strokeWidth: strokeWidth,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: ringColor,
              cornerRadius: radius * 0.4 + strokeWidth + 2,
            ),
          ),
          // Avatar image
          ClipRRect(
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
        ],
      ),
    );
  }
}

// ==============================================================================
// HARMONY RING PAINTER — rounded-square progress arc
// ==============================================================================

class _HarmonyRingPainter extends CustomPainter {
  final double value;
  final double strokeWidth;
  final Color backgroundColor;
  final Color valueColor;
  final double cornerRadius;

  const _HarmonyRingPainter({
    required this.value,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.valueColor,
    required this.cornerRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final half = strokeWidth / 2;
    final rect = Rect.fromLTWH(half, half, size.width - strokeWidth, size.height - strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
    final path = Path()..addRRect(rrect);

    // Background track
    canvas.drawPath(
      path,
      Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    // Progress arc
    if (value > 0) {
      final metrics = path.computeMetrics().first;
      final progressPath = metrics.extractPath(0, metrics.length * value.clamp(0.0, 1.0));
      canvas.drawPath(
        progressPath,
        Paint()
          ..color = valueColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_HarmonyRingPainter old) =>
      old.value != value || old.valueColor != valueColor || old.backgroundColor != backgroundColor;
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

    badgeColor = tier.color;
    textColor = badgeColor;

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
      case TrustTier.established: return Icons.verified;
      case TrustTier.elder:       return Icons.local_florist;
      case TrustTier.trusted:     return Icons.check_circle;
      case TrustTier.sprout:      return Icons.eco;
      case TrustTier.new_user:    return Icons.fiber_new;
    }
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

/// Harmony trust badge rendered in the profile header (gradient banner context).
/// Uses white-tinted palette so it reads over any banner color.
class _ProfileTrustBadge extends StatelessWidget {
  final TrustState trustState;
  const _ProfileTrustBadge({required this.trustState});

  @override
  Widget build(BuildContext context) {
    final emoji = trustState.tier.emoji;
    final label = trustState.tier.displayName;
    final score = trustState.harmonyScore;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              Text(
                '$label · Harmony $score%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ==============================================================================
// DESKTOP PROFILE HELPER WIDGETS
// ==============================================================================

class _DesktopHarmonyBadge extends StatelessWidget {
  final TrustState trustState;
  const _DesktopHarmonyBadge({required this.trustState});

  @override
  Widget build(BuildContext context) {
    final tier = trustState.tier;
    final color = tier.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tier.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Text(
            tier.displayName,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _DesktopStat extends StatelessWidget {
  final int value;
  final String label;
  final VoidCallback? onTap;
  const _DesktopStat({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.navyText.withValues(alpha: 0.5))),
      ],
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: content);
    return content;
  }
}

class _DesktopCard extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? trailing;
  final List<Widget> children;
  const _DesktopCard({this.title, this.titleWidget, this.trailing, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || titleWidget != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  titleWidget ?? Text(title!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String? text;
  final Widget? child;
  const _InfoRow({required this.icon, this.text, this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Icon(icon, size: 16, color: AppTheme.navyText.withValues(alpha: 0.5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: child ?? Text(
              text!,
              style: TextStyle(fontSize: 14, color: AppTheme.navyText.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner Image Editor — locked to 3:1 aspect ratio (1440×480 target)
// ─────────────────────────────────────────────────────────────────────────────

class _BannerImageEditor extends StatefulWidget {
  final Uint8List imageBytes;
  final String? imageName;

  const _BannerImageEditor({required this.imageBytes, this.imageName});

  @override
  State<_BannerImageEditor> createState() => _BannerImageEditorState();
}

class _BannerImageEditorState extends State<_BannerImageEditor> {
  final _editorKey = GlobalKey<ProImageEditorState>();

  static const Color _matteBlack = Color(0xFF0B0B0B);

  ThemeData _buildEditorTheme() {
    final baseTheme = ThemeData.dark(useMaterial3: true);
    return baseTheme.copyWith(
      scaffoldBackgroundColor: _matteBlack,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: AppTheme.brightNavy,
        secondary: AppTheme.brightNavy,
        surface: _matteBlack,
        onSurface: SojornColors.basicWhite,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _matteBlack,
        foregroundColor: SojornColors.basicWhite,
        elevation: 0,
      ),
      sliderTheme: baseTheme.sliderTheme.copyWith(
        activeTrackColor: AppTheme.brightNavy,
        inactiveTrackColor: SojornColors.basicWhite.withValues(alpha: 0.24),
        thumbColor: AppTheme.brightNavy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _matteBlack,
      body: Stack(
        children: [
          ProImageEditor.memory(
            widget.imageBytes,
            key: _editorKey,
            configs: ProImageEditorConfigs(
              theme: _buildEditorTheme(),
              imageGeneration: const ImageGenerationConfigs(
                maxOutputSize: Size(1440, 480),
                jpegQuality: 85,
                outputFormat: OutputFormat.jpg,
              ),
              cropRotateEditor: const CropRotateEditorConfigs(
                initAspectRatio: 3.0,
                aspectRatios: [
                  AspectRatioItem(text: 'Banner (3:1)', value: 3.0),
                ],
              ),
            ),
            callbacks: ProImageEditorCallbacks(
              mainEditorCallbacks: MainEditorCallbacks(
                onAfterViewInit: () {
                  // Auto-open crop editor so users go directly to crop
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _editorKey.currentState?.openCropRotateEditor();
                  });
                },
              ),
              onImageEditingComplete: (Uint8List editedBytes) async {
                if (!context.mounted) return;

                if (kIsWeb) {
                  Navigator.pop(
                    context,
                    SojornMediaResult.image(
                      bytes: editedBytes,
                      name: widget.imageName ?? 'banner.jpg',
                    ),
                  );
                  return;
                }

                try {
                  final tempDir = await getTemporaryDirectory();
                  final ts = DateTime.now().millisecondsSinceEpoch;
                  final file = File('${tempDir.path}/sojorn_banner_$ts.jpg');
                  await file.writeAsBytes(editedBytes);

                  if (!context.mounted) return;
                  Navigator.pop(
                    context,
                    SojornMediaResult.image(filePath: file.path, name: file.path.split('/').last),
                  );
                } catch (_) {
                  if (!context.mounted) return;
                  Navigator.pop(
                    context,
                    SojornMediaResult.image(bytes: editedBytes, name: widget.imageName ?? 'banner.jpg'),
                  );
                }
              },
            ),
          ),
          // Resolution hint overlay
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Banner: 1440 × 480 px (3:1)',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
