// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../routes/app_routes.dart';
import 'media/sojorn_avatar.dart';

/// Wraps a child widget and shows a profile hover card on desktop.
/// On mobile (touch), this is a no-op pass-through.
class UserHoverCard extends StatefulWidget {
  final String handle;
  final Widget child;

  const UserHoverCard({
    super.key,
    required this.handle,
    required this.child,
  });

  @override
  State<UserHoverCard> createState() => _UserHoverCardState();
}

class _UserHoverCardState extends State<UserHoverCard> {
  OverlayEntry? _overlayEntry;
  Timer? _showTimer;
  Timer? _hideTimer;
  bool _isHoveringCard = false;
  Offset _lastPointerPosition = Offset.zero;

  /// Shared cache across all hover cards — avoids re-fetching for the same user.
  static final Map<String, _CachedHoverData> _globalCache = {};

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _onEnter(PointerEvent event) {
    _lastPointerPosition = event.position;
    _hideTimer?.cancel();
    _showTimer?.cancel();
    _showTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _showOverlay();
    });
  }

  void _onHover(PointerEvent event) {
    _lastPointerPosition = event.position;
  }

  void _onExit(PointerEvent _) {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_isHoveringCard) _removeOverlay();
    });
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    final screenSize = MediaQuery.of(context).size;
    const cardWidth = 280.0;

    // Anchor to the widget's position for stable placement
    final renderBox = context.findRenderObject() as RenderBox?;
    final widgetPos = renderBox?.localToGlobal(Offset.zero) ?? _lastPointerPosition;
    final widgetSize = renderBox?.size ?? Size.zero;

    final anchorX = widgetPos.dx;
    final anchorY = widgetPos.dy + widgetSize.height;

    // Place below widget with a small gap, or above if not enough space
    final spaceBelow = screenSize.height - anchorY;
    final showAbove = spaceBelow < 260;
    final top = showAbove ? null : anchorY + 4;
    final bottom = showAbove ? screenSize.height - widgetPos.dy + 4 : null;

    // Align left edge with the widget
    var left = anchorX;
    if (left + cardWidth > screenSize.width - 10) left = screenSize.width - cardWidth - 10;
    if (left < 10) left = 10;

    _overlayEntry = OverlayEntry(
      builder: (_) => _HoverCardOverlay(
        top: top,
        bottom: bottom,
        left: left,
        handle: widget.handle,
        onEnterCard: () {
          _isHoveringCard = true;
          _hideTimer?.cancel();
        },
        onExitCard: () {
          _isHoveringCard = false;
          _hideTimer?.cancel();
          _hideTimer = Timer(const Duration(milliseconds: 150), () {
            _removeOverlay();
          });
        },
        onDismiss: _removeOverlay,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isHoveringCard = false;
  }

  @override
  Widget build(BuildContext context) {
    // Only show hover cards on desktop (wide screens)
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (!isDesktop) return widget.child;

    return MouseRegion(
      onEnter: _onEnter,
      onHover: _onHover,
      onExit: _onExit,
      child: widget.child,
    );
  }
}

class _CachedHoverData {
  final Profile profile;
  final ProfileStats? stats;
  final DateTime fetchedAt;

  _CachedHoverData({required this.profile, this.stats, required this.fetchedAt});

  bool get isStale => DateTime.now().difference(fetchedAt).inMinutes > 5;
}

class _HoverCardOverlay extends StatefulWidget {
  final double? top;
  final double? bottom;
  final double left;
  final String handle;
  final VoidCallback onEnterCard;
  final VoidCallback onExitCard;
  final VoidCallback onDismiss;

  const _HoverCardOverlay({
    this.top,
    this.bottom,
    required this.left,
    required this.handle,
    required this.onEnterCard,
    required this.onExitCard,
    required this.onDismiss,
  });

  @override
  State<_HoverCardOverlay> createState() => _HoverCardOverlayState();
}

class _HoverCardOverlayState extends State<_HoverCardOverlay> {
  Profile? _profile;
  ProfileStats? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // Check global cache
    final cached = _UserHoverCardState._globalCache[widget.handle];
    if (cached != null && !cached.isStale) {
      if (mounted) {
        setState(() {
          _profile = cached.profile;
          _stats = cached.stats;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final data = await ApiService.instance.getProfile(handle: widget.handle);
      final profile = data['profile'] as Profile;
      final stats = data['stats'] as ProfileStats?;

      // Cache it
      _UserHoverCardState._globalCache[widget.handle] = _CachedHoverData(
        profile: profile,
        stats: stats,
        fetchedAt: DateTime.now(),
      );

      if (mounted) {
        setState(() {
          _profile = profile;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Could not load profile';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.top,
      bottom: widget.bottom,
      left: widget.left,
      child: MouseRegion(
        onEnter: (_) => widget.onEnterCard(),
        onExit: (_) => widget.onExitCard(),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(SojornRadii.card),
          shadowColor: Colors.black26,
          child: Container(
            width: 280,
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(SojornRadii.card),
              border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.08)),
            ),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!, style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.5), fontSize: 12)),
                      )
                    : _buildCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    final p = _profile!;
    return InkWell(
      onTap: () {
        widget.onDismiss();
        AppRoutes.navigateToProfile(context, p.handle);
      },
      borderRadius: BorderRadius.circular(SojornRadii.card),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + name row
            Row(
              children: [
                SojornAvatar(displayName: p.displayName, avatarUrl: p.avatarUrl, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.displayName,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.navyText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@${p.handle}',
                        style: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Bio
            if ((p.bio ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                p.bio!,
                style: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.7), height: 1.4),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // Stats row
            if (_stats != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _StatChip('${_stats!.posts}', 'posts'),
                  const SizedBox(width: 12),
                  _StatChip('${_stats!.followers}', 'followers'),
                  const SizedBox(width: 12),
                  _StatChip('${_stats!.following}', 'following'),
                ],
              ),
            ],
            // Status text
            if ((p.statusText ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.royalPurple.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  p.statusText!,
                  style: TextStyle(fontSize: 11, color: AppTheme.royalPurple, fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String count;
  final String label;

  const _StatChip(this.count, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(count, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.5))),
      ],
    );
  }
}
