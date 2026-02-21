// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
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
import '../../providers/quip_upload_provider.dart';
import '../../providers/notification_provider.dart';
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
    _fabRotationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    WidgetsBinding.instance.addObserver(this);
    _chatService.startBackgroundSync();
    _initNotificationListener();
    _loadNavTapCounts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        OnboardingModal.showIfNeeded(context);
        _checkNeighborhoodOnboarding();
      }
    });
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
    try {
      final data = await ApiService.instance.getMyNeighborhood();
      if (data == null) return;
      final onboarded = data['onboarded'] as bool? ?? false;
      if (!onboarded && mounted) {
        // Small delay so the onboarding modal (if shown) has time to appear first
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          await _autoAssignNeighborhood();
        }
      }
    } catch (_) {
      // Non-critical — silently ignore if network unavailable
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
    _notifSub = NotificationService.instance.foregroundMessages.listen((message) {
      if (mounted) {
        NotificationService.instance.showNotificationBanner(context, message);
      }
    });
  }

  @override
  void dispose() {
    _fabRotationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _chatService.stopBackgroundSync();
    _notifSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _chatService.startBackgroundSync();
    } else if (state == AppLifecycleState.paused) {
      _chatService.stopBackgroundSync();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ComposeScreen(),
                          ),
                        );
                      },
                      onQuipTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const QuipCreationFlow(),
                          ),
                        );
                      },
                      onBeaconTap: () {
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

  Widget _buildBeaconCreateButton() {
    final beaconState = BeaconScreen.globalKey.currentState;
    final label = beaconState?.createLabel ?? 'Create';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
      child: FilledButton.icon(
        onPressed: () {
          final state = BeaconScreen.globalKey.currentState;
          if (state != null) {
            state.onCreateAction();
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              BeaconScreen.globalKey.currentState?.onCreateAction();
            });
          }
        },
        icon: const Icon(Icons.add, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.navyBlue,
          foregroundColor: SojornColors.basicWhite,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(0, 38),
          elevation: 1.5,
        ),
      ),
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
            _incrementNavTap(index);
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
                    assetPath != null
                        ? Image.asset(
                            (isActive && activeAssetPath != null) ? activeAssetPath : assetPath,
                            width: SojornNav.bottomBarIconSize,
                            height: SojornNav.bottomBarIconSize,
                          )
                        : Icon(
                            isActive ? activeIcon : icon,
                            color: isActive ? AppTheme.navyBlue : SojornColors.bottomNavUnselected,
                            size: SojornNav.bottomBarIconSize,
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
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: SojornNav.bottomBarLabelSize,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                    color: isActive ? AppTheme.navyBlue : SojornColors.bottomNavUnselected,
                  ),
                ),
              ],
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
