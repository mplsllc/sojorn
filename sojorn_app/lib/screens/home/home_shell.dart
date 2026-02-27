// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/secure_chat_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../notifications/notifications_screen.dart';
import '../compose/compose_screen.dart';
import '../discover/discover_screen.dart';
import '../beacon/beacon_screen.dart';
import '../quips/create/quip_creation_flow.dart';
import '../secure_chat/secure_chat_full_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/radial_menu_overlay.dart';
import '../../widgets/onboarding_modal.dart';
import '../../widgets/offline_indicator.dart';
import '../../widgets/neighborhood/neighborhood_picker_sheet.dart';
import '../../services/api_service.dart';
import '../../services/analytics_service.dart';
import '../../providers/quip_upload_provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/profile.dart';
import '../../models/dashboard_widgets.dart';
import '../../widgets/dashboard/dashboard_editor_panel.dart';
import '../../widgets/desktop/desktop_sidebar_widgets.dart';
import '../settings/privacy_settings_screen.dart';
import '../../widgets/desktop/hover_scale.dart';
import '../../widgets/desktop/command_palette.dart';
import '../../widgets/media/sojorn_avatar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root shell for the main tabs. The active tab is controlled by GoRouter's
/// [StatefulNavigationShell] so navigation state and tab selection stay in sync.
class HomeShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const HomeShell({super.key, required this.navigationShell});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _isRadialMenuVisible = false;
  late final AnimationController _fabRotationController;
  final SecureChatService _chatService = SecureChatService();
  StreamSubscription<RemoteMessage>? _notifSub;

  // Desktop sidebar state
  Profile? _desktopProfile;
  Map<String, int> _desktopStats = {};
  List<Map<String, dynamic>> _desktopFriends = [];
  List<Map<String, dynamic>> _desktopOnlineUsers = [];
  DashboardLayout _dashboardLayout = DashboardLayout.defaultLayout;
  bool _isDashboardEditing = false;
  DashboardWidget? _editingWidget;
  bool _isCommandPaletteOpen = false;
  int _logoTapCount = 0;
  Timer? _logoTapTimer;
  bool _logoInverted = false;

  // Nav helper badges — show descriptive subtitle for first N taps
  static const _maxHelperShows = 3;
  Map<int, int> _navTapCounts = {};

  static const _helperBadges = {
    1: 'Videos',   // Quips tab
    2: 'Alerts',   // Beacons tab
  };

  static const _longPressTooltips = {
    0: 'Your main feed with posts from people you follow',
    1: 'Quips are short-form videos — your stories',
    2: 'Beacons are local alerts and real-time updates',
    3: 'Your profile, settings, and saved posts',
  };

  @override
  void initState() {
    super.initState();
    if (kDebugMode) debugPrint('[SHELL] HomeShell initState');
    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _fabRotationController = AnimationController(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
      vsync: this,
    );
    WidgetsBinding.instance.addObserver(this);
    _chatService.startBackgroundSync();
    if (kDebugMode) debugPrint('[SHELL] Chat background sync started');
    _initNotificationListener();
    _loadNavTapCounts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        OnboardingModal.showIfNeeded(context);
        _checkNeighborhoodOnboarding();
        _loadDesktopSidebarData();
      }
    });
  }

  Future<void> _loadDesktopSidebarData() async {
    try {
      final profileData = await ApiService.instance.getProfile();
      final profile = profileData['profile'] as Profile;
      final stats = profileData['stats'] as ProfileStats;
      final following = await ApiService.instance.getFollowing(profile.id);
      if (mounted) {
        setState(() {
          _desktopProfile = profile;
          _desktopStats = {
            'posts': stats.posts,
            'followers': stats.followers,
            'following': stats.following,
          };
          // Full following list — used for Top 8 picker and friend activity filter
          _desktopFriends = following;
          // Online users — placeholder until presence API exists
          _desktopOnlineUsers = following.take(5).map((u) {
            return {...u, 'status': 'online'};
          }).toList();
        });
      }
      // Load dashboard layout (non-blocking — defaults already set)
      try {
        final layoutData = await ApiService.instance.getDashboardLayout();
        if (mounted) {
          setState(() => _dashboardLayout = DashboardLayout.fromJson(layoutData));
        }
      } catch (_) {
        // Use default layout on error
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SHELL] Desktop sidebar data load failed: $e');
    }
  }

  void _showDesktopStatusEditor() {
    final profile = _desktopProfile;
    if (profile == null) return;
    final ctrl = TextEditingController(text: profile.statusText ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SojornRadii.modal)),
        title: Text('Set Status',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.navyText)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          style: TextStyle(fontSize: 14, color: AppTheme.postContent),
          decoration: InputDecoration(
            hintText: 'at the coffee shop',
            hintStyle: TextStyle(
                color: AppTheme.navyText.withValues(alpha: 0.35),
                fontStyle: FontStyle.italic),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                borderSide: BorderSide(color: AppTheme.brightNavy)),
          ),
        ),
        actions: [
          if ((profile.statusText ?? '').isNotEmpty)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final updated =
                      await ApiService.instance.updateProfile(statusText: '');
                  if (mounted) setState(() => _desktopProfile = updated);
                } catch (_) {}
              },
              child: Text('Clear', style: TextStyle(color: AppTheme.error)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppTheme.textDisabled)),
          ),
          FilledButton(
            onPressed: () async {
              final text = ctrl.text.trim();
              Navigator.pop(ctx);
              if (text == (profile.statusText ?? '')) return;
              try {
                final updated =
                    await ApiService.instance.updateProfile(statusText: text);
                if (mounted) setState(() => _desktopProfile = updated);
              } catch (_) {}
            },
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brightNavy),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadNavTapCounts() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _navTapCounts = {
          for (final i in [1, 2])
            i: prefs.getInt('nav_tap_$i') ?? 0,
        };
      });
    }
  }

  Future<void> _incrementNavTap(int index) async {
    if (!_helperBadges.containsKey(index)) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt('nav_tap_$index') ?? 0;
    await prefs.setInt('nav_tap_$index', current + 1);
    if (mounted) {
      setState(() => _navTapCounts[index] = current + 1);
    }
  }

  Future<void> _checkNeighborhoodOnboarding() async {
    if (kDebugMode) debugPrint('[SHELL] Checking neighborhood onboarding...');
    try {
      final data = await ApiService.instance.getMyNeighborhood();
      if (data == null) {
        if (kDebugMode) debugPrint('[SHELL] No neighborhood data returned');
        return;
      }
      final onboarded = data['onboarded'] as bool? ?? false;
      if (kDebugMode) debugPrint('[SHELL] Neighborhood onboarded=$onboarded');
      if (!onboarded && mounted) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          if (kDebugMode) debugPrint('[SHELL] Starting auto-assign neighborhood');
          await _autoAssignNeighborhood();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[SHELL] Neighborhood check failed: $e');
    }
  }

  /// Auto-assigns the nearest neighborhood based on GPS. Falls back to the
  /// picker sheet if GPS is unavailable or no neighborhood is found nearby.
  Future<void> _autoAssignNeighborhood() async {
    if (kIsWeb) {
      // Web can't GPS reliably — show the picker
      if (mounted) await NeighborhoodPickerSheet.show(context);
      return;
    }

    try {
      // Request / check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // No permission — fall back to manual picker
        if (mounted) await NeighborhoodPickerSheet.show(context);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      final detected = await ApiService.instance.detectNeighborhood(
        lat: position.latitude,
        long: position.longitude,
      );

      final hood = detected?['neighborhood'] as Map<String, dynamic>?;
      final id = hood?['id']?.toString();

      if (hood == null || id == null || id.isEmpty) {
        // No nearby neighborhood found — show picker so user can search by ZIP
        if (mounted) await NeighborhoodPickerSheet.show(context);
        return;
      }

      // Silently assign the detected neighborhood
      await ApiService.instance.chooseNeighborhood(id);

      final name = hood['name'] as String? ?? 'your neighborhood';
      final city = hood['city'] as String? ?? '';
      final label = city.isNotEmpty ? '$name, $city' : name;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_city_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Welcome to $label!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.brightNavy,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Change',
              textColor: Colors.white.withValues(alpha: 0.8),
              onPressed: () {
                if (mounted) NeighborhoodPickerSheet.show(context, isChangeMode: true);
              },
            ),
          ),
        );
      }
    } catch (_) {
      // Any error — fall back to picker so user is never left without a neighborhood
      if (mounted) await NeighborhoodPickerSheet.show(context);
    }
  }

  void _initNotificationListener() {
    if (kDebugMode) debugPrint('[SHELL] Initializing notification listener');
    _notifSub = NotificationService.instance.foregroundMessages.listen((message) {
      if (kDebugMode) debugPrint('[SHELL] Foreground notification received: ${message.notification?.title}');
      if (mounted) {
        NotificationService.instance.showNotificationBanner(context, message);
      }
    });
  }

  @override
  void dispose() {
    if (kDebugMode) debugPrint('[SHELL] HomeShell disposing');
    _fabRotationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _chatService.stopBackgroundSync();
    _notifSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) debugPrint('[SHELL] Lifecycle: $state');
    if (state == AppLifecycleState.resumed) {
      _chatService.startBackgroundSync();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive ||
               state == AppLifecycleState.hidden) {
      _chatService.stopBackgroundSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = SojornBreakpoints.isDesktop(constraints.maxWidth);

        // Close radial menu if crossing to desktop while it's open
        if (isDesktop && _isRadialMenuVisible) {
          _isRadialMenuVisible = false;
          _fabRotationController.reverse();
        }

        if (isDesktop) {
          return _buildDesktopLayout(constraints.maxWidth);
        }
        return _buildMobileLayout();
      },
    );
  }

  void _showCommandPalette() {
    if (_isCommandPaletteOpen) return;
    _isCommandPaletteOpen = true;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black26,
      barrierLabel: 'Close',
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, anim, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: CommandPaletteOverlay(
              onDismiss: () => Navigator.of(ctx).pop(),
              onNavigateBranch: (index) {
                Navigator.of(ctx).pop();
                widget.navigationShell.goBranch(index, initialLocation: true);
              },
              onNavigateRoute: (route) {
                Navigator.of(ctx).pop();
                context.push(route);
              },
            ),
          ),
        );
      },
    ).then((_) => _isCommandPaletteOpen = false);
  }

  void _onLogoTap() {
    widget.navigationShell.goBranch(0, initialLocation: true);
    _logoTapCount++;
    _logoTapTimer?.cancel();
    _logoTapTimer = Timer(const Duration(milliseconds: 500), () => _logoTapCount = 0);
    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      setState(() => _logoInverted = true);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _logoInverted = false);
      });
    }
  }

  Color _ambientColor() {
    final hour = DateTime.now().hour;
    if (AppTheme.isDark) {
      if (hour >= 6 && hour < 10) return const Color(0xFF161724);
      if (hour >= 10 && hour < 16) return SojornColors.darkScaffoldBg;
      if (hour >= 16 && hour < 20) return const Color(0xFF151625);
      return const Color(0xFF121320);
    }
    if (hour >= 6 && hour < 10) return const Color(0xFFFFF8F0);
    if (hour >= 10 && hour < 16) return SojornColors.basicQueenPinkLight;
    if (hour >= 16 && hour < 20) return const Color(0xFFF5F0F8);
    return const Color(0xFFF0F0F8);
  }

  Widget _buildDesktopLayout(double width) {
    final currentIndex = widget.navigationShell.currentIndex;
    final isHome = currentIndex == 0;

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
            const _OpenCommandPaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
            const _OpenCommandPaletteIntent(),
        // J / K  — vim-style next / previous post in any feed ListView.
        LogicalKeySet(LogicalKeyboardKey.keyJ): const _ScrollFeedIntent(forward: true),
        LogicalKeySet(LogicalKeyboardKey.keyK): const _ScrollFeedIntent(forward: false),
        // /  — jump to Discover (search).
        LogicalKeySet(LogicalKeyboardKey.slash): const _FocusSearchIntent(),
        // Esc — dismiss dialogs / slide panels.
        LogicalKeySet(LogicalKeyboardKey.escape): const _DismissTopIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenCommandPaletteIntent: CallbackAction<_OpenCommandPaletteIntent>(
            onInvoke: (_) { _showCommandPalette(); return null; },
          ),
          _ScrollFeedIntent: CallbackAction<_ScrollFeedIntent>(
            onInvoke: (intent) {
              final ctrl = PrimaryScrollController.maybeOf(context);
              if (ctrl != null && ctrl.hasClients) {
                final delta = intent.forward ? 320.0 : -320.0;
                ctrl.animateTo(
                  (ctrl.offset + delta).clamp(
                    ctrl.position.minScrollExtent,
                    ctrl.position.maxScrollExtent,
                  ),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              }
              return null;
            },
          ),
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              widget.navigationShell.goBranch(4);
              return null;
            },
          ),
          _DismissTopIntent: CallbackAction<_DismissTopIntent>(
            onInvoke: (_) {
              final nav = Navigator.of(context, rootNavigator: false);
              if (nav.canPop()) nav.pop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: AppTheme.scaffoldBg,
            body: Column(
              children: [
                const OfflineIndicator(),
                _buildDesktopTopNav(currentIndex),
                Expanded(
                  child: (isHome || currentIndex == 3 || currentIndex == 4 || currentIndex == 5)
                      ? _buildDesktop3Column(currentIndex)
                      : NavigationShellScope(
                          currentIndex: currentIndex,
                          child: widget.navigationShell,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildDesktopTopNav(int currentIndex) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          border: Border(
            bottom: BorderSide(
              color: AppTheme.royalPurple.withValues(alpha: 0.08),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.royalPurple.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            // ── Left: Logo ────────────────────────────────────
            GestureDetector(
              onTap: _onLogoTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: ColorFiltered(
                  colorFilter: _logoInverted
                      ? const ColorFilter.matrix(<double>[
                          -1, 0, 0, 0, 255,
                          0, -1, 0, 0, 255,
                          0, 0, -1, 0, 255,
                          0, 0, 0, 1, 0,
                        ])
                      : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                  child: Image.asset('assets/images/toplogo.png', height: 32),
                ),
              ),
            ),
            const SizedBox(width: 28),
            // ── Center: Nav items ─────────────────────────────
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildDesktopNavItem(Icons.home_outlined, Icons.home, 'Home', 0, currentIndex),
                  _buildDesktopNavItem(Icons.video_collection_outlined, Icons.video_collection, 'Quips', 1, currentIndex),
                  _buildDesktopNavItem(Icons.sensors_outlined, Icons.sensors, 'Beacons', 2, currentIndex),
                  _buildDesktopNavItem(Icons.location_city_outlined, Icons.location_city, 'Commons', 6, currentIndex),
                  _buildDesktopNavItem(Icons.groups_outlined, Icons.groups, 'Groups', 7, currentIndex),
                  _buildDesktopNavItem(Icons.explore_outlined, Icons.explore, 'Discover', 4, currentIndex),
                  _buildDesktopNavItem(Icons.mail_outline, Icons.mail, 'Messages', 5, currentIndex),
                ],
              ),
            ),
            // ── Right: Create, Notifications, Avatar ──────────
            DesktopCreateButton(
              onPost: () {
                final isDesktop = MediaQuery.of(context).size.width >= 900;
                if (isDesktop) {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierColor: Colors.black38,
                    barrierLabel: 'Close',
                    transitionDuration: const Duration(milliseconds: 250),
                    pageBuilder: (ctx, anim, _) => const SizedBox.shrink(),
                    transitionBuilder: (ctx, anim, _, child) {
                      final slide = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                      return Align(
                        alignment: Alignment.centerRight,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(slide),
                          child: Material(
                            elevation: 16,
                            child: SafeArea(
                              child: SizedBox(
                                width: 520,
                                height: double.infinity,
                                child: const ComposeScreen(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                } else {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComposeScreen()));
                }
              },
              onQuip: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const QuipCreationFlow()),
              ),
              onBeacon: () {
                // If not already on the beacon branch, navigate there first then trigger create
                final currentIndex = widget.navigationShell.currentIndex;
                if (currentIndex != 2) {
                  widget.navigationShell.goBranch(2);
                  // Wait for branch to mount before triggering create
                  Future.delayed(const Duration(milliseconds: 200), () {
                    if (mounted) BeaconScreen.globalKey.currentState?.onCreateAction();
                  });
                } else {
                  BeaconScreen.globalKey.currentState?.onCreateAction();
                }
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                currentIndex == 3
                    ? Icons.person_pin_outlined
                    : Icons.dashboard_customize_outlined,
                color: AppTheme.navyBlue,
                size: 20,
              ),
              tooltip: 'Customize Dashboard',
              onPressed: currentIndex == 3 ? null : _openDashboardEditor,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Consumer(
                builder: (context, ref, child) {
                  final badge = ref.watch(currentBadgeProvider);
                  return Badge(
                    label: Text(badge.notificationCount.toString()),
                    isLabelVisible: badge.notificationCount > 0,
                    backgroundColor: SojornColors.destructive,
                    child: Icon(Icons.notifications_none, color: AppTheme.navyBlue, size: 22),
                  );
                },
              ),
              tooltip: 'Notifications',
              onPressed: () {
                final isDesktop = MediaQuery.of(context).size.width >= 900;
                if (isDesktop) {
                  showGeneralDialog(
                    context: context,
                    barrierDismissible: true,
                    barrierColor: Colors.black26,
                    barrierLabel: 'Close',
                    transitionDuration: const Duration(milliseconds: 250),
                    pageBuilder: (ctx, anim, _) => const SizedBox.shrink(),
                    transitionBuilder: (ctx, anim, _, child) {
                      final slide = CurvedAnimation(parent: anim, curve: Curves.easeOut);
                      return Align(
                        alignment: Alignment.centerRight,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(slide),
                          child: Material(
                            elevation: 16,
                            child: SafeArea(
                              child: SizedBox(
                                width: 380,
                                height: double.infinity,
                                child: const NotificationsScreen(),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                } else {
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  );
                }
              },
            ),
            const SizedBox(width: 4),
            // User avatar with dropdown menu
            if (_desktopProfile != null)
              PopupMenuButton<String>(
                offset: const Offset(0, 44),
                onSelected: (value) async {
                  switch (value) {
                    case 'profile':
                      widget.navigationShell.goBranch(3);
                    case 'settings':
                      context.push('/settings');
                    case 'privacy':
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PrivacySettingsScreen(),
                      ));
                    case 'signout':
                      await AuthService.instance.signOut();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'profile',
                    child: Row(children: [Icon(Icons.person_outline, size: 18), SizedBox(width: 10), Text('My Profile')]),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: Row(children: [Icon(Icons.settings_outlined, size: 18), SizedBox(width: 10), Text('Settings')]),
                  ),
                  const PopupMenuItem(
                    value: 'privacy',
                    child: Row(children: [Icon(Icons.lock_outline, size: 18), SizedBox(width: 10), Text('Privacy')]),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'signout',
                    child: Row(children: [Icon(Icons.logout, size: 18, color: Colors.red), SizedBox(width: 10), Text('Sign Out', style: TextStyle(color: Colors.red))]),
                  ),
                ],
                child: SojornAvatar(
                  displayName: _desktopProfile!.displayName,
                  avatarUrl: _desktopProfile!.avatarUrl,
                  size: 34,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopNavItem(IconData icon, IconData activeIcon, String label, int index, int currentIndex) {
    return _DesktopNavItem(
      icon: icon,
      activeIcon: activeIcon,
      label: label,
      index: index,
      currentIndex: currentIndex,
      onTap: () => widget.navigationShell.goBranch(index, initialLocation: index == currentIndex),
    );
  }

  void _openDashboardEditor() {
    // Navigate to home first so the user can see the sidebars being edited
    widget.navigationShell.goBranch(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isDashboardEditing = true;
      });
    });
  }



  Widget _buildDesktop3Column(int currentIndex) {
    final isProfileBranch = currentIndex == 3;

    return Container(
      decoration: BoxDecoration(
        color: _ambientColor().withValues(alpha: 0.5),
      ),
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1340),
        child: isProfileBranch
            ? _buildProfileColumns()
            : _buildDashboardColumns(currentIndex),
      ),
    );
  }

  /// Profile branch — full-width, no sidebars. Profile screen handles its own layout.
  Widget _buildProfileColumns() {
    return NavigationShellScope(
      currentIndex: 3,
      child: widget.navigationShell,
    );
  }

  /// Standard 3-column layout for home / discover / other branches.
  Widget _buildDashboardColumns(int currentIndex) {
    final isEditing = _isDashboardEditing;
    final leftWidgets = _dashboardLayout.leftSidebar;
    final rightWidgets = _dashboardLayout.rightSidebar;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left sidebar ── 260px fixed ──
        SizedBox(
          width: 260,
          child: isEditing
              ? _buildEditableSidebar(leftWidgets, true)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: currentIndex == 4
                        ? _buildDiscoverLeftSidebar(leftWidgets)
                        : _buildSidebarWidgets(leftWidgets),
                  ),
                ),
        ),
        // ── Center: feed / page content ── flex with 660px cap ──
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: _editingWidget != null
                  ? WidgetSettingsPanel(
                      widgetData: _editingWidget!,
                      onSave: (cfg) {
                        _updateWidgetConfig(_editingWidget!, cfg);
                        setState(() => _editingWidget = null);
                      },
                      onCancel: () => setState(() => _editingWidget = null),
                    )
                  : isEditing
                      ? DashboardEditorPanel(
                          layout: _dashboardLayout,
                          onLayoutChanged: (layout) {
                            setState(() => _dashboardLayout = layout);
                          },
                          onClose: () {
                            setState(() => _isDashboardEditing = false);
                          },
                        )
                      : NavigationShellScope(
                          currentIndex: currentIndex,
                          child: widget.navigationShell,
                        ),
            ),
          ),
        ),
        // ── Right sidebar ── 280px fixed ──
        SizedBox(
          width: 280,
          child: isEditing
              ? _buildEditableSidebar(rightWidgets, false)
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: currentIndex == 4
                        ? _buildDiscoverRightSidebar()
                        : _buildSidebarWidgets(rightWidgets),
                  ),
                ),
        ),
      ],
    );
  }

  // ── Discover-specific sidebar builders ────────────────────────────────────

  List<Widget> _buildDiscoverLeftSidebar(List<DashboardWidget> leftWidgets) {
    return [
      // Discover banner
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.royalPurple.withValues(alpha: 0.12),
              AppTheme.brightNavy.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(SojornRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.explore, size: 18, color: AppTheme.royalPurple),
                const SizedBox(width: 8),
                Text('Discover',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.navyText)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Find new people, trending topics, and popular content.',
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.navyText.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // Profile card (identity anchor)
      if (_desktopProfile != null)
        DesktopProfileCard(
          profile: _desktopProfile!,
          stats: _desktopStats,
          onProfileTap: () => widget.navigationShell.goBranch(3),
          onEditTap: () => widget.navigationShell.goBranch(3),
          onStatusTap: _showDesktopStatusEditor,
        ),
      const SizedBox(height: 12),
      // Suggested users to follow
      const DesktopSuggestedUsersCard(),
    ];
  }

  List<Widget> _buildDiscoverRightSidebar() {
    return [
      const DesktopTrendingHashtagsCard(),
      const SizedBox(height: 12),
      const DesktopPopularGroupsCard(),
      const SizedBox(height: 12),
      // Keep calendar — events are discoverable content
      ..._buildSidebarWidgets(
        _dashboardLayout.rightSidebar
            .where((w) => w.type == DashboardWidgetType.upcomingEvents)
            .toList(),
      ),
    ];
  }

  /// Sidebar in edit mode: draggable widgets with visual chrome.
  Widget _buildEditableSidebar(List<DashboardWidget> widgets, bool isLeft) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.royalPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.view_sidebar_outlined,
                    size: 14, color: AppTheme.royalPurple),
                const SizedBox(width: 6),
                Text(
                  isLeft ? 'Left Sidebar' : 'Right Sidebar',
                  style: TextStyle(
                    color: AppTheme.royalPurple,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // Render each widget with edit chrome
          for (int i = 0; i < widgets.length; i++)
            if (widgets[i].isEnabled) ...[
              _buildEditableWidgetWrapper(widgets[i]),
              if (i < widgets.length - 1) const SizedBox(height: 12),
            ] else ...[
              // Disabled widgets show as ghosted
              Opacity(
                opacity: 0.35,
                child: _buildEditableWidgetWrapper(widgets[i]),
              ),
              if (i < widgets.length - 1) const SizedBox(height: 12),
            ],
          if (widgets.isEmpty)
            Container(
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.royalPurple.withValues(alpha: 0.2),
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(SojornRadii.card),
                color: AppTheme.royalPurple.withValues(alpha: 0.03),
              ),
              child: Center(
                child: Text('Empty',
                    style: TextStyle(
                        color: AppTheme.navyText.withValues(alpha: 0.3),
                        fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  /// Persists a widget config update into the layout state and auto-saves.
  void _updateWidgetConfig(DashboardWidget dw, Map<String, dynamic> newConfig) {
    List<DashboardWidget> patchList(List<DashboardWidget> list) => list.map((w) {
      if (w.type == dw.type && w.order == dw.order) return w.copyWith(config: newConfig);
      return w;
    }).toList();

    final updated = DashboardLayout(
      leftSidebar: patchList(_dashboardLayout.leftSidebar),
      rightSidebar: patchList(_dashboardLayout.rightSidebar),
      feedTopbar: patchList(_dashboardLayout.feedTopbar),
      updatedAt: _dashboardLayout.updatedAt,
    );
    setState(() => _dashboardLayout = updated);
    // Fire-and-forget save — non-blocking
    ApiService.instance.saveDashboardLayout(updated.toJson()).catchError((_) => <String, dynamic>{});
  }

  // Profile widget editing removed — profile uses fixed Facebook-style layout.

  /// Wraps a dashboard widget with a dashed border and label during edit mode.
  Widget _buildEditableWidgetWrapper(DashboardWidget dw) {
    final rendered = _renderDashboardWidget(dw);
    if (rendered == null) {
      return Container(
        height: 60,
        decoration: BoxDecoration(
          border: Border.all(
              color: AppTheme.royalPurple.withValues(alpha: 0.15)),
          borderRadius: BorderRadius.circular(SojornRadii.card),
        ),
        child: Center(
          child: Text(dw.type.displayName,
              style: TextStyle(
                  color: AppTheme.navyText.withValues(alpha: 0.4),
                  fontSize: 11)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card + 2),
        border: Border.all(
          color: AppTheme.royalPurple.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        child: rendered,
      ),
    );
  }

  /// Renders a list of dashboard widgets dynamically based on saved layout.
  List<Widget> _buildSidebarWidgets(
    List<DashboardWidget> widgets, {
    void Function(DashboardWidget, Map<String, dynamic>)? configSaver,
  }) {
    final rendered = <Widget>[];
    int staggerIdx = 0;
    for (final w in widgets) {
      if (!w.isEnabled) continue;
      final built = _renderDashboardWidget(w, configSaver: configSaver);
      if (built != null) {
        if (rendered.isNotEmpty) rendered.add(const SizedBox(height: 12));
        rendered.add(
          _StaggeredFadeIn(
            index: staggerIdx++,
            child: HoverScale(scale: 1.01, borderRadius: BorderRadius.circular(SojornRadii.card), child: built),
          ),
        );
      }
    }
    return rendered;
  }

  /// Maps a DashboardWidget to the actual widget instance.
  /// [configSaver] overrides the default save path (used for profile sidebar widgets).
  Widget? _renderDashboardWidget(
    DashboardWidget dw, {
    void Function(DashboardWidget, Map<String, dynamic>)? configSaver,
  }) {
    void save(Map<String, dynamic> cfg) =>
        configSaver != null ? configSaver(dw, cfg) : _updateWidgetConfig(dw, cfg);

    switch (dw.type) {
      case DashboardWidgetType.profileCard:
        if (_desktopProfile == null) return null;
        return DesktopProfileCard(
          profile: _desktopProfile!,
          stats: _desktopStats,
          onProfileTap: () => widget.navigationShell.goBranch(3),
          onEditTap: () => widget.navigationShell.goBranch(3),
          onStatusTap: _showDesktopStatusEditor,
        );
      case DashboardWidgetType.top8Friends:
        if (_desktopFriends.isEmpty) return null;
        return Top8FriendsGrid(
          friends: _desktopFriends,
          config: dw.config,
          onViewAll: () => widget.navigationShell.goBranch(3),
          onFriendTap: (handle) => context.push('/u/$handle'),
          onConfigChange: (cfg) => save(cfg),
        );
      case DashboardWidgetType.upcomingEvents:
        return UpcomingEventsWidget(
          config: dw.config,
          onConfigChange: (cfg) => save(cfg),
        );
      case DashboardWidgetType.whosOnline:
        return WhosOnlineList(
          onlineUsers: _desktopOnlineUsers,
          onUserTap: (handle) => context.push('/u/$handle'),
          config: dw.config,
          onConfigChange: (cfg) => save(cfg),
        );
      case DashboardWidgetType.nowPlaying:
      case DashboardWidgetType.musicPlayer:
        return const SizedBox.shrink(); // hidden until audio library is configured
      case DashboardWidgetType.quote:
        return QuoteWidget(
          config: dw.config,
          onSettingsTap: () => setState(() => _editingWidget = dw),
        );
      case DashboardWidgetType.customText:
        return CustomTextWidget(
          config: dw.config,
          onSettingsTap: () => setState(() => _editingWidget = dw),
        );
      case DashboardWidgetType.photoFrame:
        return PhotoFrameWidget(
          config: dw.config,
          onSettingsTap: () => setState(() => _editingWidget = dw),
        );
      case DashboardWidgetType.groupEvents:
        return GroupEventsWidget(
          config: dw.config,
          onConfigChange: (cfg) => save(cfg),
        );
      case DashboardWidgetType.friendActivity:
        return FriendActivityWidget(
          config: dw.config,
          onConfigChange: (cfg) => save(cfg),
          allFriends: _desktopFriends,
        );
      case DashboardWidgetType.pinnedPost:
        return null; // requires API support — skip for now
      case DashboardWidgetType.moodStatus:
        return MoodStatusWidget(
          config: dw.config,
          onSettingsTap: () => setState(() => _editingWidget = dw),
        );
      case DashboardWidgetType.favoriteMedia:
        return FavoriteMediaWidget(
          config: dw.config,
          onSettingsTap: () => setState(() => _editingWidget = dw),
        );
      case DashboardWidgetType.countdown:
        return CountdownWidget(
          config: dw.config,
          onSettingsTap: () => setState(() => _editingWidget = dw),
        );
      case DashboardWidgetType.socialLinks:
        return SocialLinksWidget(
          config: dw.config,
          onSettingsTap: () => setState(() => _editingWidget = dw),
        );
    }
  }

  Widget _buildMobileLayout() {
    final currentIndex = widget.navigationShell.currentIndex;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppTheme.scaffoldBg,
          appBar: _buildAppBar(),
          body: Column(
            children: [
              const OfflineIndicator(),
              Expanded(
                child: Stack(
                  children: [
                    NavigationShellScope(
                      currentIndex: currentIndex,
                      child: widget.navigationShell,
                    ),
                    RadialMenuOverlay(
                      isVisible: _isRadialMenuVisible,
                      onDismiss: () {
                        setState(() => _isRadialMenuVisible = false);
                        _fabRotationController.reverse();
                      },
                      onPostTap: () {
                        AnalyticsService.instance.event('fab_action', value: 'post');
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ComposeScreen(),
                          ),
                        );
                      },
                      onQuipTap: () {
                        AnalyticsService.instance.event('fab_action', value: 'quip');
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const QuipCreationFlow(),
                          ),
                        );
                      },
                      onBeaconTap: () {
                        AnalyticsService.instance.event('fab_action', value: 'beacon');
                        setState(() => _isRadialMenuVisible = false);
                        _fabRotationController.reverse();
                        widget.navigationShell.goBranch(2);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          BeaconScreen.globalKey.currentState?.onCreateAction();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: BottomAppBar(
          padding: EdgeInsets.zero,
          height: SojornNav.bottomBarHeight,
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SojornNav.bottomBarVerticalPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavBarItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    index: 0,
                    label: 'Home',
                  ),
                  _buildNavBarItem(
                    icon: Icons.play_circle_outline,
                    activeIcon: Icons.play_circle,
                    index: 1,
                    label: 'Quips',
                    assetPath: 'assets/icon/quips.png',
                    activeAssetPath: 'assets/icon/quipso.png',
                  ),
                  const SizedBox(width: SojornNav.bottomFabGap),
                  _buildNavBarItem(
                    icon: Icons.sensors_outlined,
                    activeIcon: Icons.sensors,
                    index: 2,
                    label: 'Beacons',
                    assetPath: 'assets/icon/beacon.png',
                    activeAssetPath: 'assets/icon/beacono.png',
                  ),
                  _buildNavBarItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    index: 3,
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
        ),
        // FAB — positioned absolutely so nothing (snackbars, banners) can push it
        Positioned(
          left: 0,
          right: 0,
          bottom: SojornNav.bottomBarHeight / 2 - 2,
          child: Center(
            child: GestureDetector(
              onTap: () {
                setState(() => _isRadialMenuVisible = !_isRadialMenuVisible);
                if (_isRadialMenuVisible) {
                  _fabRotationController.forward();
                  AnalyticsService.instance.event('fab_opened');
                } else {
                  _fabRotationController.reverse();
                }
              },
              child: Consumer(
                builder: (context, ref, child) {
                  final upload = ref.watch(quipUploadProvider);
                  final isDone = !upload.isUploading && upload.progress >= 1.0;
                  final isUploading = upload.isUploading;
                  final hasState = isUploading || isDone;

                  return Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: hasState ? AppTheme.brightNavy : AppTheme.navyBlue,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: (hasState ? AppTheme.brightNavy : AppTheme.navyBlue).withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (hasState)
                          SizedBox(
                            width: 42,
                            height: 42,
                            child: CustomPaint(
                              painter: _VerticalBorderProgressPainter(
                                progress: upload.progress,
                                color: SojornColors.basicWhite,
                                backgroundColor: SojornColors.basicWhite.withValues(alpha: 0.2),
                                strokeWidth: 3.0,
                                borderRadius: 10,
                              ),
                            ),
                          ),
                        if (isDone)
                          const Icon(Icons.check, color: SojornColors.basicWhite, size: 24)
                        else if (isUploading)
                          Text(
                            '${(upload.progress * 100).toInt()}%',
                            style: GoogleFonts.outfit(
                              color: SojornColors.basicWhite,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          AnimatedBuilder(
                            animation: _fabRotationController,
                            builder: (context, child) => Transform.rotate(
                              angle: _fabRotationController.value * 0.785398,
                              child: child,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: SojornColors.basicWhite,
                              size: 28,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isBeacon = widget.navigationShell.currentIndex == 2;

    return AppBar(
      title: InkWell(
        onTap: () => widget.navigationShell.goBranch(0),
        child: Image.asset(
          isBeacon ? 'assets/images/beacons.png' : 'assets/images/toplogo.png',
          height: isBeacon ? 34 : 38,
          fit: BoxFit.contain,
        ),
      ),
      centerTitle: false,
      elevation: 0,
      backgroundColor: AppTheme.scaffoldBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      actions: [
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.all(12),
          icon: Icon(Icons.search, color: AppTheme.navyBlue),
          tooltip: 'Discover',
          onPressed: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => const DiscoverScreen(),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.all(12),
          icon: Consumer(
            builder: (context, ref, child) {
              final badge = ref.watch(currentBadgeProvider);
              return Badge(
                label: Text(badge.messageCount.toString()),
                isLabelVisible: badge.messageCount > 0,
                backgroundColor: AppTheme.brightNavy,
                child: Icon(Icons.chat_bubble_outline, color: AppTheme.navyBlue),
              );
            },
          ),
          tooltip: 'Messages',
          onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => const SecureChatFullScreen(),
                  fullscreenDialog: true,
                ),
              );
          },
        ),
        const SizedBox(width: 2),
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.all(12),
          icon: Consumer(
            builder: (context, ref, child) {
              final badge = ref.watch(currentBadgeProvider);
              return Badge(
                label: Text(badge.notificationCount.toString()),
                isLabelVisible: badge.notificationCount > 0,
                backgroundColor: SojornColors.destructive,
                child: Icon(Icons.notifications_none, color: AppTheme.navyBlue),
              );
            },
          ),
          tooltip: 'Notifications',
          onPressed: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildNavBarItem({
    required IconData icon,
    required IconData activeIcon,
    required int index,
    required String label,
    String? assetPath,
    String? activeAssetPath,
  }) {
    final isActive = widget.navigationShell.currentIndex == index;
    final helperBadge = _helperBadges[index];
    final tapCount = _navTapCounts[index] ?? 0;
    final showHelper = helperBadge != null && tapCount < _maxHelperShows;
    final tooltip = _longPressTooltips[index];

    return Expanded(
      child: Semantics(
        selected: isActive,
        label: label,
        button: true,
        child: GestureDetector(
        onLongPress: tooltip != null ? () {
          final overlay = Overlay.of(context);
          late OverlayEntry entry;
          entry = OverlayEntry(
            builder: (ctx) => _NavTooltipOverlay(
              message: tooltip,
              onDismiss: () => entry.remove(),
            ),
          );
          overlay.insert(entry);
          Future.delayed(const Duration(seconds: 2), () {
            if (entry.mounted) entry.remove();
          });
        } : null,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            final tabs = ['Home', 'Quips', 'Beacons', 'Profile'];
            if (kDebugMode) debugPrint('[NAV] Tab tapped: ${index < tabs.length ? tabs[index] : index}');
            _incrementNavTap(index);
            AnalyticsService.instance.event('nav_tab_tap', value: tabs[index].toLowerCase());
            widget.navigationShell.goBranch(
              index,
              initialLocation: index == widget.navigationShell.currentIndex,
            );
          },
          child: Container(
            height: double.infinity,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ExcludeSemantics(
                      child: assetPath != null
                        ? Image.asset(
                            (isActive && activeAssetPath != null) ? activeAssetPath : assetPath,
                            width: SojornNav.bottomBarIconSize,
                            height: SojornNav.bottomBarIconSize,
                            semanticLabel: label,
                          )
                        : Icon(
                            isActive ? activeIcon : icon,
                            color: isActive ? AppTheme.navyBlue : SojornColors.bottomNavUnselected,
                            size: SojornNav.bottomBarIconSize,
                            semanticLabel: label,
                          ),
                    ),
                    if (showHelper)
                      Positioned(
                        right: -18,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.brightNavy,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(helperBadge, style: const TextStyle(
                            fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white,
                          )),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: SojornNav.bottomBarLabelTopGap),
                ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: SojornNav.bottomBarLabelSize,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                      color: isActive ? AppTheme.navyBlue : SojornColors.bottomNavUnselected,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

// ── Nav Tooltip Overlay (long-press on nav items) ─────────────────────────
class _NavTooltipOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _NavTooltipOverlay({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: onDismiss,
        behavior: HitTestBehavior.translucent,
        child: Align(
          alignment: const Alignment(0, 0.85),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.navyBlue,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(message, style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500,
            ), textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}

class _VerticalBorderProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;
  final double borderRadius;

  _VerticalBorderProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    this.strokeWidth = 3.0,
    this.borderRadius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Draw background border
    canvas.drawRRect(rrect, bgPaint);

    // Draw progress border
    if (progress > 0) {
      final progressPaint = Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Clip to vertical progress
      canvas.save();
      final clipRect = Rect.fromLTWH(
        0,
        size.height * (1.0 - progress),
        size.width,
        size.height * progress,
      );
      canvas.clipRect(clipRect);
      canvas.drawRRect(rrect, progressPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalBorderProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

/// Provides the current navigation shell index to descendants that need to
/// react (e.g. pausing quip playback when the tab is not active).
class NavigationShellScope extends InheritedWidget {
  final int currentIndex;

  const NavigationShellScope({
    super.key,
    required this.currentIndex,
    required super.child,
  });

  static NavigationShellScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<NavigationShellScope>();
  }

  @override
  bool updateShouldNotify(covariant NavigationShellScope oldWidget) {
    return currentIndex != oldWidget.currentIndex;
  }
}

/// Desktop nav item with hover animation (scale + color shift).
class _DesktopNavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final VoidCallback onTap;

  const _DesktopNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<_DesktopNavItem> createState() => _DesktopNavItemState();
}

class _DesktopNavItemState extends State<_DesktopNavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.index == widget.currentIndex;
    final isMessages = widget.index == 5;

    final baseColor = isActive
        ? AppTheme.royalPurple
        : _hovering
            ? AppTheme.royalPurple.withValues(alpha: 0.6)
            : SojornColors.bottomNavUnselected;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppTheme.royalPurple.withValues(alpha: 0.06),
          child: AnimatedScale(
            scale: _hovering && !isActive ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? AppTheme.royalPurple : SojornColors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  isMessages
                      ? Consumer(
                          builder: (context, ref, child) {
                            final badge = ref.watch(currentBadgeProvider);
                            return Badge(
                              label: Text(badge.messageCount.toString(),
                                  style: const TextStyle(fontSize: 9)),
                              isLabelVisible: badge.messageCount > 0,
                              backgroundColor: AppTheme.brightNavy,
                              child: Icon(widget.icon, color: baseColor, size: 20),
                            );
                          },
                        )
                      : Icon(
                          isActive ? widget.activeIcon : widget.icon,
                          color: baseColor,
                          size: 20,
                        ),
                  const SizedBox(height: 2),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: baseColor,
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenCommandPaletteIntent extends Intent {
  const _OpenCommandPaletteIntent();
}

class _ScrollFeedIntent extends Intent {
  final bool forward;
  const _ScrollFeedIntent({required this.forward});
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _DismissTopIntent extends Intent {
  const _DismissTopIntent();
}

/// Staggered fade-in + slide-up animation for sidebar widgets.
class _StaggeredFadeIn extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggeredFadeIn({required this.index, required this.child});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    // Stagger: each widget delays 60ms more than the previous
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
