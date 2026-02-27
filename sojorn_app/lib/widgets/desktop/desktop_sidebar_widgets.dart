// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../../config/api_config.dart';
import '../../models/dashboard_widgets.dart';
import '../../models/event.dart';
import '../../models/profile.dart';
import '../../screens/events/event_detail_screen.dart';
import '../../models/trust_state.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../media/sojorn_avatar.dart';


// ─── Flip Card Widget (wraps sidebar widgets with settings flip) ─────────────

class _FlipCard extends StatefulWidget {
  final Widget front;
  final Widget Function(VoidCallback flipBack) back;
  final Widget Function(VoidCallback flip)? frontBuilder;

  const _FlipCard({required this.front, required this.back, this.frontBuilder});

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  bool _isBack = false;

  @override
  void initState() {
    super.initState();
    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _ctrl = AnimationController(vsync: this, duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 350));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flip() {
    setState(() => _isBack = !_isBack);
    _isBack ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (ctx, _) {
        final angle = _anim.value * 3.14159265;
        final isFrontVisible = _anim.value < 0.5;
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(angle);

        Widget face;
        if (isFrontVisible) {
          if (widget.frontBuilder != null) {
            face = KeyedSubtree(key: const ValueKey('front'), child: widget.frontBuilder!(_flip));
          } else {
            face = Stack(
              key: const ValueKey('front'),
              children: [
                widget.front,
                Positioned(
                  top: 10,
                  right: 10,
                  child: Semantics(
                    button: true,
                    label: 'Widget settings',
                    child: GestureDetector(
                      onTap: _flip,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.royalPurple.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.2)),
                        ),
                        child: Icon(Icons.tune, size: 14, color: AppTheme.royalPurple.withValues(alpha: 0.7)),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        } else {
          face = Transform(
            key: const ValueKey('back'),
            transform: Matrix4.rotationY(3.14159265),
            alignment: Alignment.center,
            child: widget.back(_flip),
          );
        }

        return Transform(
          transform: transform,
          alignment: Alignment.center,
          child: face,
        );
      },
    );
  }
}

// ─── Settings back panel helper ────────────────────────────────────────────

Widget _settingsBackPanel({
  required VoidCallback onDone,
  required String title,
  required List<Widget> children,
}) {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: AppTheme.cardSurface,
      borderRadius: BorderRadius.circular(SojornRadii.card),
    ),
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppTheme.navyText,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            GestureDetector(
              onTap: onDone,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.brightNavy, AppTheme.royalPurple]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

// ─── Desktop Profile Card (Left Sidebar) ────────────────────────────────────

class DesktopProfileCard extends StatelessWidget {
  final Profile profile;
  final Map<String, int> stats;
  final VoidCallback? onProfileTap;
  final VoidCallback? onEditTap;
  final VoidCallback? onStatusTap;

  const DesktopProfileCard({
    super.key,
    required this.profile,
    required this.stats,
    this.onProfileTap,
    this.onEditTap,
    this.onStatusTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalPurple.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header with PFP inside the gradient ──
          _buildHeader(),
          // ── Name, handle, bio, stats, button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onProfileTap,
                      child: Text(
                        profile.displayName,
                        style: TextStyle(
                          color: AppTheme.navyText,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${profile.handle}',
                      style: TextStyle(
                        color: AppTheme.royalPurple.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    profile.bio!,
                    style: TextStyle(
                      color: AppTheme.navyText.withValues(alpha: 0.65),
                      fontSize: 12,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // Status line — AIM-style ephemeral presence text.
                if (profile.statusText != null && profile.statusText!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onStatusTap,
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: const Color(0xFF43A047),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF43A047).withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            profile.statusText!,
                            style: TextStyle(
                              color: AppTheme.navyText.withValues(alpha: 0.55),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (onStatusTap != null) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onStatusTap,
                    child: Row(
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 12,
                            color: AppTheme.navyText.withValues(alpha: 0.3)),
                        const SizedBox(width: 6),
                        Text('Set a status...',
                            style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: AppTheme.navyText.withValues(alpha: 0.35),
                            )),
                      ],
                    ),
                  ),
                ],
                // Harmony trust badge — visible reward for community contribution.
                if (profile.trustState != null) ...[
                  const SizedBox(height: 8),
                  _TrustBadge(trustState: profile.trustState!),
                ],
                const SizedBox(height: 14),
                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    _buildStat('Posts', stats['posts'] ?? 0),
                    _buildDivider(),
                    _buildStat('Followers', stats['followers'] ?? 0),
                    _buildDivider(),
                    _buildStat('Following', stats['following'] ?? 0),
                  ],
                ),
                const SizedBox(height: 14),
                // Edit profile button
                if (onEditTap != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onEditTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.royalPurple,
                        side: BorderSide(color: AppTheme.royalPurple.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Edit Profile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    Widget avatarWidget = GestureDetector(
      onTap: onProfileTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SojornColors.basicWhite.withValues(alpha: 0.5), width: 2),
          boxShadow: [
            BoxShadow(
              color: SojornColors.basicBlack.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: SojornAvatar(
          displayName: profile.displayName,
          avatarUrl: profile.avatarUrl,
          size: 52,
        ),
      ),
    );

    // If user has a cover image, show that
    if (profile.coverUrl != null && profile.coverUrl!.isNotEmpty) {
      final hour = DateTime.now().hour;
      final coverGreeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
      return SizedBox(
        height: 90,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(profile.coverUrl!, fit: BoxFit.cover),
            // Gradient overlay for text legibility
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    SojornColors.basicBlack.withValues(alpha: 0.35),
                    SojornColors.basicBlack.withValues(alpha: 0.15),
                    SojornColors.basicBlack.withValues(alpha: 0.35),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              right: 14,
              child: Row(
                children: [
                  avatarWidget,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$coverGreeting, ${profile.displayName.split(' ').first}',
                      style: TextStyle(
                        color: SojornColors.basicWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            color: SojornColors.basicBlack.withValues(alpha: 0.6),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                          Shadow(
                            color: SojornColors.basicBlack.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: Offset.zero,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Default: vibrant gradient header with PFP left-aligned + greeting
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return Container(
      height: 90,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.brightNavy,
            AppTheme.royalPurple,
            SojornColors.basicKsuPurple,
            AppTheme.royalPurple.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.35, 0.7, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _GradientPatternPainter()),
          ),
          Positioned(
            left: 14,
            top: 0,
            bottom: 0,
            right: 14,
            child: Row(
              children: [
                avatarWidget,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$greeting, ${profile.displayName.split(' ').first}',
                    style: TextStyle(
                      color: SojornColors.basicWhite,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(
                          color: SojornColors.basicBlack.withValues(alpha: 0.5),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(
            _formatCount(count),
            style: TextStyle(
              color: AppTheme.navyText,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.navyText.withValues(alpha: 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      color: AppTheme.navyText.withValues(alpha: 0.08),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

/// Subtle diagonal pattern for the profile gradient header
class _GradientPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SojornColors.basicWhite.withValues(alpha: 0.06)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Diagonal lines for texture
    for (double i = -size.height; i < size.width + size.height; i += 16) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Top 8 Friends Grid ─────────────────────────────────────────────────────

class Top8FriendsGrid extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>>? onConfigChange;
  final VoidCallback? onViewAll;
  final void Function(String userId)? onFriendTap;

  const Top8FriendsGrid({
    super.key,
    required this.friends,
    this.config = const {},
    this.onConfigChange,
    this.onViewAll,
    this.onFriendTap,
  });

  @override
  State<Top8FriendsGrid> createState() => _Top8FriendsGridState();
}

class _Top8FriendsGridState extends State<Top8FriendsGrid> {
  // Friend picker state (loaded lazily when settings panel opens)
  List<Map<String, dynamic>>? _allFriends;
  bool _loadingFriends = false;

  int get _maxCount => widget.config['max_count'] as int? ?? 8;
  List<String> get _selectedIds =>
      (widget.config['selected_friend_ids'] as List?)?.cast<String>() ?? [];

  /// Returns the friends to display, respecting any pinned selection.
  List<Map<String, dynamic>> get _resolvedFriends {
    final selected = _selectedIds;
    if (selected.isEmpty) return widget.friends.take(_maxCount).toList();
    final ordered = selected
        .map((id) => widget.friends.cast<Map<String, dynamic>?>().firstWhere(
              (f) => f?['id'] == id || f?['user_id'] == id,
              orElse: () => null,
            ))
        .whereType<Map<String, dynamic>>()
        .toList();
    // Fill remaining slots with non-selected friends if fewer than maxCount selected
    if (ordered.length < _maxCount) {
      final selectedSet = selected.toSet();
      final extras = widget.friends
          .where((f) => !selectedSet.contains(f['id'] as String? ?? f['user_id'] as String? ?? ''))
          .take(_maxCount - ordered.length);
      ordered.addAll(extras);
    }
    return ordered.take(_maxCount).toList();
  }

  void _setMaxCount(int count) {
    final cfg = Map<String, dynamic>.from(widget.config)..['max_count'] = count;
    widget.onConfigChange?.call(cfg);
  }

  void _toggleFriendSelection(String id) {
    final current = List<String>.from(_selectedIds);
    if (current.contains(id)) {
      current.remove(id);
    } else if (current.length < _maxCount) {
      current.add(id);
    }
    final cfg = Map<String, dynamic>.from(widget.config)
      ..['selected_friend_ids'] = current;
    widget.onConfigChange?.call(cfg);
  }

  Future<void> _loadFriends() async {
    if (_allFriends != null || _loadingFriends) return;
    setState(() => _loadingFriends = true);
    try {
      // Reuse the already-loaded friends list from the widget (full following list)
      // If we need more than what's passed in, we could fetch here.
      setState(() {
        _allFriends = List.of(widget.friends);
        _loadingFriends = false;
      });
    } catch (_) {
      setState(() => _loadingFriends = false);
    }
  }

  Widget _buildSettings(VoidCallback flipBack) {
    // Lazy-load the friends list when settings panel opens
    if (_allFriends == null && !_loadingFriends) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFriends());
    }

    return _settingsBackPanel(
      onDone: flipBack,
      title: 'Top Friends',
      children: [
        // Count picker
        Text('Show how many?',
            style: TextStyle(
                color: AppTheme.navyText.withValues(alpha: 0.6), fontSize: 12)),
        const SizedBox(height: 8),
        Row(
          children: [4, 8].map((count) {
            final isSelected = _maxCount == count;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _setMaxCount(count),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.royalPurple
                        : AppTheme.royalPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                        color:
                            isSelected ? Colors.white : AppTheme.royalPurple,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      )),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        // Friend picker
        Row(
          children: [
            Text('Choose friends:',
                style: TextStyle(
                    color: AppTheme.navyText.withValues(alpha: 0.6),
                    fontSize: 12)),
            const SizedBox(width: 6),
            Text('(${_selectedIds.length}/$_maxCount selected)',
                style: TextStyle(
                    color: AppTheme.royalPurple.withValues(alpha: 0.7),
                    fontSize: 11)),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingFriends)
          const Center(
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)))
        else if (widget.friends.isEmpty)
          Text('No friends to choose from',
              style: TextStyle(
                  color: AppTheme.navyText.withValues(alpha: 0.4),
                  fontSize: 12))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.friends.length,
              itemBuilder: (context, i) {
                final f = widget.friends[i];
                final id = f['id'] as String? ?? f['user_id'] as String? ?? '';
                final name = f['display_name'] as String? ??
                    f['handle'] as String? ??
                    '?';
                final avatar = f['avatar_url'] as String?;
                final isSelected = _selectedIds.contains(id);
                final canSelect = isSelected || _selectedIds.length < _maxCount;
                return InkWell(
                  onTap: canSelect ? () => setState(() => _toggleFriendSelection(id)) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SojornAvatar(
                            displayName: name, avatarUrl: avatar, size: 32),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name,
                              style: TextStyle(
                                color: canSelect
                                    ? AppTheme.navyText
                                    : AppTheme.navyText.withValues(alpha: 0.3),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Checkbox(
                          value: isSelected,
                          onChanged:
                              canSelect ? (_) => setState(() => _toggleFriendSelection(id)) : null,
                          activeColor: AppTheme.royalPurple,
                          side: BorderSide(
                              color: AppTheme.navyText.withValues(alpha: 0.3)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (_selectedIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              final cfg = Map<String, dynamic>.from(widget.config)
                ..['selected_friend_ids'] = <String>[];
              widget.onConfigChange?.call(cfg);
            },
            child: Text('Clear selection',
                style: TextStyle(
                    color: AppTheme.royalPurple,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.friends.isEmpty) return const SizedBox.shrink();

    final displayFriends = _resolvedFriends;

    final frontCard = Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalPurple.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top ${_maxCount == 4 ? '4' : '8'}',
            style: TextStyle(
              color: AppTheme.navyText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 6,
              // 0.68 gives each cell ~2px extra headroom so floating-point
              // rounding in avatar sizing never produces the "OVERFLOWED BY
              // 0.23px" Flutter debug overlay that appeared in edit mode.
              childAspectRatio: 0.68,
            ),
            itemCount: displayFriends.length.clamp(0, _maxCount),
            itemBuilder: (context, index) {
              final friend = displayFriends[index];
              final name = friend['display_name'] as String? ??
                  friend['handle'] as String? ??
                  '?';
              final avatar = friend['avatar_url'] as String?;
              final handle = friend['handle'] as String? ?? '';

              return GestureDetector(
                onTap: () => widget.onFriendTap?.call(handle),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final avatarSize =
                        (constraints.maxWidth * 0.78).clamp(32.0, 52.0);
                    return Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppTheme.royalPurple.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: SojornAvatar(
                            displayName: name,
                            avatarUrl: avatar,
                            size: avatarSize,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          name.split(' ').first,
                          style: TextStyle(
                            color: AppTheme.navyText.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
          if (widget.onViewAll != null) ...[
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTap: widget.onViewAll,
                child: Text(
                  'View all friends',
                  style: TextStyle(
                    color: AppTheme.royalPurple,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return _FlipCard(
      front: frontCard,
      back: _buildSettings,
    );
  }
}

// ─── Who's Online List (Right Sidebar) ──────────────────────────────────────

class WhosOnlineList extends StatelessWidget {
  final List<Map<String, dynamic>> onlineUsers;
  final void Function(String userId)? onUserTap;
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>>? onConfigChange;

  const WhosOnlineList({
    super.key,
    required this.onlineUsers,
    this.onUserTap,
    this.config = const {},
    this.onConfigChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalPurple.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Who's Online",
                style: TextStyle(
                  color: AppTheme.navyText,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (onlineUsers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No friends online right now',
                style: TextStyle(
                  color: AppTheme.navyText.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            )
          else
            ...onlineUsers.take(config['max_items'] as int? ?? 10).map((user) => _buildOnlineUser(user)),
        ],
      ),
    );
  }

  Widget _buildOnlineUser(Map<String, dynamic> user) {
    final name = user['display_name'] as String? ?? user['handle'] as String? ?? '?';
    final avatar = user['avatar_url'] as String?;
    final handle = user['handle'] as String? ?? '';
    final status = user['status'] as String? ?? 'online';

    return InkWell(
      onTap: () => onUserTap?.call(handle),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Stack(
              children: [
                SojornAvatar(
                  displayName: name,
                  avatarUrl: avatar,
                  size: 38,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _statusColor(status),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.cardSurface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: AppTheme.navyText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'online':
        return const Color(0xFF22C55E);
      case 'away':
        return const Color(0xFFFBBF24);
      case 'dnd':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF22C55E);
    }
  }
}

// ─── Upcoming Shows Calendar (Right Sidebar) ─────────────────────────────────

class UpcomingEventsWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>>? onConfigChange;

  const UpcomingEventsWidget({super.key, this.config = const {}, this.onConfigChange});

  @override
  State<UpcomingEventsWidget> createState() => _UpcomingEventsWidgetState();
}

class _UpcomingEventsWidgetState extends State<UpcomingEventsWidget> {
  List<GroupEvent> _events = [];
  bool _loading = true;
  Set<int> _eventDays = {};

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      var raw = await ApiService.instance.fetchMyEvents(limit: 10);
      // Fallback: if the user has no personal RSVPs, show community events
      if (raw.isEmpty) {
        raw = await ApiService.instance.fetchUpcomingEvents(limit: 10);
      }
      final events = raw.map((e) => GroupEvent.fromJson(e)).toList();
      if (!mounted) return;
      final now = DateTime.now();
      final days = <int>{};
      for (final e in events) {
        final local = e.startsAt.toLocal();
        if (local.year == now.year && local.month == now.month) {
          days.add(local.day);
        }
      }
      setState(() {
        _events = events;
        _eventDays = days;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [
          BoxShadow(
            color: AppTheme.royalPurple.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_outlined, size: 16, color: AppTheme.royalPurple),
              const SizedBox(width: 6),
              Text(
                'Upcoming Shows',
                style: TextStyle(
                  color: AppTheme.navyText,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMiniCalendar(now),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (_events.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._events.take(widget.config['max_items'] as int? ?? 3).map((e) => _buildEventCard(e)),
          ],
        ],
      ),
    );
  }

  Widget _buildEventCard(GroupEvent event) {
    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(SojornRadii.md),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EventDetailScreen(
            groupId: event.groupId,
            eventId: event.id,
            initialEvent: event,
          ),
        )),
        child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.royalPurple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(SojornRadii.md),
          border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            // Date badge
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppTheme.brightNavy, AppTheme.royalPurple]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${event.startsAt.toLocal().day}',
                style: const TextStyle(color: SojornColors.basicWhite, fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: TextStyle(color: AppTheme.navyText, fontSize: 12, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dateFmt.format(event.startsAt.toLocal())} · ${timeFmt.format(event.startsAt.toLocal())}',
                    style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.5), fontSize: 10),
                  ),
                  if (event.groupName != null)
                    Text(
                      event.groupName!,
                      style: TextStyle(color: AppTheme.royalPurple.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
            // RSVP indicator
            if (event.myRsvp == RSVPStatus.going)
              Icon(Icons.check_circle, size: 16, color: const Color(0xFF22C55E))
            else if (event.myRsvp == RSVPStatus.interested)
              Icon(Icons.star, size: 16, color: const Color(0xFFFBBF24)),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildMiniCalendar(DateTime now) {
    final firstOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final startWeekday = firstOfMonth.weekday % 7; // Sunday = 0

    const dayLabels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Column(
      children: [
        // Month header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _monthName(now.month),
              style: TextStyle(
                color: AppTheme.navyText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${now.year}',
              style: TextStyle(
                color: AppTheme.navyText.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Day labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: dayLabels
              .map((d) => SizedBox(
                    width: 28,
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.navyText.withValues(alpha: 0.4),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        // Day grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 2,
            crossAxisSpacing: 0,
          ),
          itemCount: startWeekday + daysInMonth,
          itemBuilder: (context, index) {
            if (index < startWeekday) return const SizedBox.shrink();
            final day = index - startWeekday + 1;
            final isToday = day == now.day;
            final hasEvent = _eventDays.contains(day);

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.brightNavy, AppTheme.royalPurple],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.royalPurple.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        )
                      : null,
                  child: Text(
                    '$day',
                    style: TextStyle(
                      color: isToday ? SojornColors.basicWhite : AppTheme.navyText.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                if (hasEvent)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: AppTheme.royalPurple,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _monthName(int month) {
    const names = ['', 'January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return names[month];
  }
}

// ─── Desktop Create Button ──────────────────────────────────────────────────

class DesktopCreateButton extends StatelessWidget {
  final VoidCallback onPost;
  final VoidCallback onQuip;
  final VoidCallback onBeacon;

  const DesktopCreateButton({
    super.key,
    required this.onPost,
    required this.onQuip,
    required this.onBeacon,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'post': onPost();
          case 'quip': onQuip();
          case 'beacon': onBeacon();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'post',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 18),
            SizedBox(width: 10),
            Text('New Post'),
          ]),
        ),
        PopupMenuItem(
          value: 'quip',
          child: Row(children: [
            Icon(Icons.videocam_outlined, size: 18),
            SizedBox(width: 10),
            Text('New Quip'),
          ]),
        ),
        PopupMenuItem(
          value: 'beacon',
          child: Row(children: [
            Icon(Icons.sensors_outlined, size: 18),
            SizedBox(width: 10),
            Text('New Beacon'),
          ]),
        ),
      ],
      offset: const Offset(0, 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.brightNavy, AppTheme.royalPurple],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.royalPurple.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, color: SojornColors.basicWhite, size: 18),
            SizedBox(width: 6),
            Text('Create', style: TextStyle(
              color: SojornColors.basicWhite,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            )),
          ],
        ),
      ),
    );
  }
}

// ─── Now Playing Card (Feed area — music integration) ────────────────────────

class NowPlayingCard extends StatelessWidget {
  final String trackTitle;
  final String artistName;
  final String? albumArtUrl;
  final VoidCallback? onTap;

  const NowPlayingCard({
    super.key,
    required this.trackTitle,
    required this.artistName,
    this.albumArtUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.royalPurple.withValues(alpha: 0.12),
              AppTheme.brightNavy.withValues(alpha: 0.08),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(SojornRadii.card),
          border: Border.all(
            color: AppTheme.royalPurple.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    color: AppTheme.royalPurple,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Icon(Icons.play_circle_filled, color: AppTheme.royalPurple, size: 24),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Album art
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      colors: [AppTheme.brightNavy, AppTheme.royalPurple],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.royalPurple.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: albumArtUrl != null
                      ? Image.network(albumArtUrl!, fit: BoxFit.cover)
                      : const Icon(Icons.music_note, color: SojornColors.basicWhite, size: 20),
                ),
                const SizedBox(width: 10),
                // Track info — takes remaining width
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trackTitle,
                        style: TextStyle(
                          color: AppTheme.navyText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artistName,
                        style: TextStyle(
                          color: AppTheme.navyText.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Mini waveform visualization — full width
            CustomPaint(
              size: const Size(double.infinity, 20),
              painter: _WaveformPainter(color: AppTheme.royalPurple),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple waveform visualization for the music player card
class _WaveformPainter extends CustomPainter {
  final Color color;
  _WaveformPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    // Static waveform bars
    const bars = [0.3, 0.6, 0.9, 0.5, 0.8, 0.4, 0.7, 0.35, 0.65, 0.5];
    final barWidth = size.width / bars.length;

    for (int i = 0; i < bars.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barHeight = size.height * bars[i];
      final top = (size.height - barHeight) / 2;
      canvas.drawLine(
        Offset(x, top),
        Offset(x, top + barHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Compact trust tier badge — sidebar profile card + full profile pages.
class _TrustBadge extends StatelessWidget {
  final TrustState trustState;
  const _TrustBadge({required this.trustState});

  @override
  Widget build(BuildContext context) {
    final emoji = trustState.tier.emoji;
    final label = trustState.tier.displayName;
    final color = trustState.tier.color;
    final score = trustState.harmonyScore;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (score / 100).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: color.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 2),
              Text('Harmony $score%',
                  style: TextStyle(
                      color: AppTheme.navyText.withValues(alpha: 0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Music Player Widget ─────────────────────────────────────────────────────

class MusicPlayerWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final void Function(Map<String, dynamic>)? onConfigChange;

  const MusicPlayerWidget({
    super.key,
    this.config = const {},
    this.onConfigChange,
  });

  @override
  State<MusicPlayerWidget> createState() => _MusicPlayerWidgetState();
}

class _MusicPlayerWidgetState extends State<MusicPlayerWidget>
    with TickerProviderStateMixin {
  VideoPlayerController? _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  String _trackTitle = '';
  String _artist = '';
  String? _listenUrl;

  // Waveform animation
  late final AnimationController _waveCtrl;
  late final Animation<double> _waveAnim;

  // Settings panel state
  bool _settingsLoading = false;
  List<Map<String, dynamic>> _searchResults = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _waveAnim = CurvedAnimation(parent: _waveCtrl, curve: Curves.easeInOut);

    // Load from config if available
    _trackTitle = widget.config['track_title'] as String? ?? '';
    _artist = widget.config['artist'] as String? ?? '';
    _listenUrl = widget.config['listen_url'] as String?;
    if (_listenUrl != null && _listenUrl!.isNotEmpty) {
      _initPlayer(_listenUrl!);
    }
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _player?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initPlayer(String url) async {
    await _player?.dispose();
    setState(() { _isLoading = true; _player = null; });
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      setState(() { _player = ctrl; _isLoading = false; });
    } catch (_) {
      ctrl.dispose();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePlay() async {
    final p = _player;
    if (p == null) return;
    if (p.value.isPlaying) {
      await p.pause();
      setState(() => _isPlaying = false);
    } else {
      await p.play();
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _stopPlay() async {
    await _player?.pause();
    await _player?.seekTo(Duration.zero);
    setState(() => _isPlaying = false);
  }

  Future<void> _searchTracks(String q) async {
    setState(() => _settingsLoading = true);
    try {
      final params = <String, String>{'q': q.isEmpty ? 'ambient' : q};
      final data = await ApiService.instance.callGoApi(
        '/audio/library',
        method: 'GET',
        queryParams: params,
      );
      final results = (data['tracks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) setState(() => _searchResults = results.take(6).toList());
    } catch (_) {
      if (mounted) setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _settingsLoading = false);
    }
  }

  void _selectTrack(Map<String, dynamic> track) {
    final title = (track['title'] as String?) ?? 'Unknown';
    final artist = (track['artist'] as String?) ?? '';
    final id = track['id']?.toString() ?? '';
    final url = '${ApiConfig.baseUrl}/audio/library/$id/listen';

    setState(() {
      _trackTitle = title;
      _artist = artist;
      _listenUrl = url;
      _isPlaying = false;
    });

    widget.onConfigChange?.call({
      'track_title': title,
      'artist': artist,
      'listen_url': url,
    });

    _initPlayer(url);
  }

  Widget _buildFront(VoidCallback onFlip) {
    final hasTrack = _trackTitle.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.royalPurple.withValues(alpha: 0.12),
            AppTheme.brightNavy.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'NOW PLAYING',
                style: TextStyle(
                  color: AppTheme.royalPurple,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onFlip,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.royalPurple.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.2)),
                  ),
                  child: Icon(Icons.tune, size: 14, color: AppTheme.royalPurple.withValues(alpha: 0.7)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Album art placeholder
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(colors: [AppTheme.brightNavy, AppTheme.royalPurple]),
                  boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.3), blurRadius: 8)],
                ),
                child: const Icon(Icons.music_note, color: SojornColors.basicWhite, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasTrack ? _trackTitle : 'No track selected',
                      style: TextStyle(
                        color: AppTheme.navyText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      hasTrack ? (_artist.isNotEmpty ? _artist : 'Freesound') : 'Tap ⚙ to browse sounds',
                      style: TextStyle(
                        color: AppTheme.navyText.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Waveform
          AnimatedBuilder(
            animation: _waveAnim,
            builder: (_, __) {
              return CustomPaint(
                size: const Size(double.infinity, 20),
                painter: _AnimatedWaveformPainter(
                  color: AppTheme.royalPurple,
                  progress: _isPlaying ? _waveAnim.value : 0.0,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _controlBtn(
                icon: Icons.stop,
                onTap: _stopPlay,
                enabled: _player != null,
              ),
              const SizedBox(width: 12),
              _isLoading
                  ? const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 2))
                  : GestureDetector(
                      onTap: _player != null ? _togglePlay : null,
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [AppTheme.brightNavy, AppTheme.royalPurple]),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.35), blurRadius: 8)],
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: SojornColors.basicWhite,
                          size: 20,
                        ),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({required IconData icon, required VoidCallback onTap, bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: AppTheme.navyBlue.withValues(alpha: enabled ? 0.1 : 0.04),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: AppTheme.navyText.withValues(alpha: enabled ? 0.6 : 0.25)),
      ),
    );
  }

  Widget _buildSettings(VoidCallback flipBack) {
    return _settingsBackPanel(
      onDone: flipBack,
      title: 'Browse Sounds',
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(fontSize: 13, color: AppTheme.navyText),
                decoration: InputDecoration(
                  hintText: 'Search Freesound...',
                  hintStyle: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.4)),
                  prefixIcon: Icon(Icons.search, size: 16, color: AppTheme.navyText.withValues(alpha: 0.4)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.royalPurple.withValues(alpha: 0.2))),
                  contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  isDense: true,
                ),
                onSubmitted: _searchTracks,
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _searchTracks(_searchCtrl.text),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.brightNavy, AppTheme.royalPurple]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.search, size: 16, color: SojornColors.basicWhite),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_settingsLoading)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ))
        else if (_searchResults.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _searchCtrl.text.isEmpty ? 'Type to search sounds, or tap to load ambient tracks' : 'No results — try a different search',
              style: TextStyle(fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.4)),
            ),
          )
        else
          ..._searchResults.map((track) {
            final title = (track['title'] as String?) ?? 'Unknown';
            final artist = (track['artist'] as String?) ?? '';
            final durSec = ((track['duration'] as num?) ?? 0).toInt();
            final dur = '${durSec ~/ 60}:${(durSec % 60).toString().padLeft(2, '0')}';
            return InkWell(
              onTap: () { _selectTrack(track); flipBack(); },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.music_note, size: 14, color: AppTheme.royalPurple.withValues(alpha: 0.6)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 12, color: AppTheme.navyText, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (artist.isNotEmpty || dur != '0:00')
                            Text('${artist.isNotEmpty ? artist : 'Freesound'}  ·  $dur', style: TextStyle(fontSize: 10, color: AppTheme.navyText.withValues(alpha: 0.45)), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Icon(Icons.play_arrow, size: 14, color: AppTheme.royalPurple.withValues(alpha: 0.5)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _FlipCard(
      front: const SizedBox.shrink(),
      back: _buildSettings,
      frontBuilder: _buildFront,
    );
  }
}

class _AnimatedWaveformPainter extends CustomPainter {
  final Color color;
  final double progress; // 0..1 drives bar height oscillation

  _AnimatedWaveformPainter({required this.color, required this.progress});

  static const _baseBars = [0.3, 0.6, 0.9, 0.5, 0.8, 0.4, 0.7, 0.35, 0.65, 0.5, 0.75, 0.45];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: progress > 0 ? 0.55 : 0.3)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / _baseBars.length;
    for (int i = 0; i < _baseBars.length; i++) {
      final oscillation = progress > 0 ? (0.15 * (i.isEven ? progress : (1 - progress))) : 0.0;
      final h = ((_baseBars[i] + oscillation).clamp(0.15, 1.0)) * size.height;
      final x = i * barWidth + barWidth / 2;
      final top = (size.height - h) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(_AnimatedWaveformPainter old) => old.progress != progress;
}

// ─── Shared gear button builder ─────────────────────────────────────────────

Widget _gearButton(VoidCallback? onTap) {
  if (onTap == null) return const SizedBox.shrink();
  return Positioned(
    top: 0, right: 0,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: AppTheme.royalPurple.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.2)),
        ),
        child: Icon(Icons.tune, size: 14, color: AppTheme.royalPurple.withValues(alpha: 0.7)),
      ),
    ),
  );
}

// ─── Quote Widget ────────────────────────────────────────────────────────────

class QuoteWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final VoidCallback? onSettingsTap;

  const QuoteWidget({super.key, this.config = const {}, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final quote = config['quote'] as String? ?? '';
    final author = config['author'] as String? ?? '';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.format_quote, color: AppTheme.royalPurple.withValues(alpha: 0.3), size: 24),
              const SizedBox(height: 8),
              Text(
                quote.isNotEmpty ? quote : 'Tap \u2699 to add your quote',
                style: TextStyle(
                  color: quote.isNotEmpty ? AppTheme.navyText : AppTheme.navyText.withValues(alpha: 0.35),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
              if (author.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '\u2014 $author',
                    style: TextStyle(
                      color: AppTheme.royalPurple.withValues(alpha: 0.7),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          _gearButton(onSettingsTap),
        ],
      ),
    );
  }
}

// ─── Custom Text Widget ──────────────────────────────────────────────────────

class CustomTextWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final VoidCallback? onSettingsTap;

  const CustomTextWidget({super.key, this.config = const {}, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final title = config['title'] as String? ?? '';
    final text = config['text'] as String? ?? '';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty) ...[
                Text(title, style: TextStyle(color: AppTheme.navyText, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
              ],
              Text(
                text.isNotEmpty ? text : 'Tap \u2699 to add your content',
                style: TextStyle(
                  color: text.isNotEmpty ? AppTheme.navyText.withValues(alpha: 0.75) : AppTheme.navyText.withValues(alpha: 0.35),
                  fontSize: 12,
                  fontStyle: text.isEmpty ? FontStyle.italic : FontStyle.normal,
                  height: 1.5,
                ),
              ),
            ],
          ),
          _gearButton(onSettingsTap),
        ],
      ),
    );
  }
}

// ─── Photo Frame Widget ──────────────────────────────────────────────────────

class PhotoFrameWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final VoidCallback? onSettingsTap;

  const PhotoFrameWidget({super.key, this.config = const {}, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final url = config['url'] as String? ?? '';
    final caption = config['caption'] as String? ?? '';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (url.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _photoPlaceholder()),
                ),
                if (caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(caption, style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.65), fontSize: 12, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                  ),
              ],
            )
          else
            _photoPlaceholder(),
          if (onSettingsTap != null)
            Positioned(
              top: 10, right: 10,
              child: GestureDetector(
                onTap: onSettingsTap,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: SojornColors.basicBlack.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.tune, size: 14, color: SojornColors.basicWhite),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Widget _photoPlaceholder() {
    return Container(
      height: 120,
      color: AppTheme.royalPurple.withValues(alpha: 0.06),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 36, color: AppTheme.royalPurple.withValues(alpha: 0.35)),
          const SizedBox(height: 6),
          Text('Tap \u2699 to add a photo URL', style: TextStyle(fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.35))),
        ],
      ),
    );
  }
}

// ─── Group Events Widget (compact list, no calendar) ─────────────────────────

class GroupEventsWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>>? onConfigChange;

  const GroupEventsWidget({super.key, this.config = const {}, this.onConfigChange});

  @override
  State<GroupEventsWidget> createState() => _GroupEventsWidgetState();
}

class _GroupEventsWidgetState extends State<GroupEventsWidget> {
  List<GroupEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await ApiService.instance.fetchUpcomingEvents(limit: 10);
      if (!mounted) return;
      setState(() { _events = raw.map((e) => GroupEvent.fromJson(e)).toList(); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month, size: 15, color: AppTheme.royalPurple),
              const SizedBox(width: 6),
              Text('Group Events', style: TextStyle(color: AppTheme.navyText, fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_events.isEmpty)
            Text('No upcoming events', style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.4), fontSize: 12))
          else
            ..._events.take(widget.config['max_items'] as int? ?? 5).map((e) => _buildRow(e)),
        ],
      ),
    );
  }

  Widget _buildRow(GroupEvent event) {
    final fmt = DateFormat('MMM d  h:mm a');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(SojornRadii.sm),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EventDetailScreen(
            groupId: event.groupId,
            eventId: event.id,
            initialEvent: event,
          ),
        )),
        child: Row(
        children: [
          Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.brightNavy, AppTheme.royalPurple]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${event.startsAt.toLocal().day}', style: const TextStyle(color: SojornColors.basicWhite, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: TextStyle(color: AppTheme.navyText, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(fmt.format(event.startsAt.toLocal()), style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.45), fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Friend Activity Widget ──────────────────────────────────────────────────

class FriendActivityWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>>? onConfigChange;
  /// Full following list — passed from home_shell for the friend filter picker.
  final List<Map<String, dynamic>> allFriends;

  const FriendActivityWidget({
    super.key,
    this.config = const {},
    this.onConfigChange,
    this.allFriends = const [],
  });

  @override
  State<FriendActivityWidget> createState() => _FriendActivityWidgetState();
}

class _FriendActivityWidgetState extends State<FriendActivityWidget> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _settingsExpanded = false;

  List<String> get _filterIds =>
      (widget.config['filter_friend_ids'] as List?)?.cast<String>() ?? [];
  int get _maxItems => widget.config['max_items'] as int? ?? 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FriendActivityWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload if filter config changed
    if (oldWidget.config['filter_friend_ids'] != widget.config['filter_friend_ids']) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final queryParams = <String, String>{'limit': '10', 'offset': '0'};
      final ids = _filterIds;
      if (ids.isNotEmpty) queryParams['author_ids'] = ids.join(',');
      final data = await ApiService.instance.callGoApi(
          '/feed/personal', method: 'GET', queryParams: queryParams);
      final posts =
          (data['posts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (!mounted) return;
      setState(() {
        _items = posts;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleFriendFilter(String id) {
    final current = List<String>.from(_filterIds);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    final cfg = Map<String, dynamic>.from(widget.config)
      ..['filter_friend_ids'] = current;
    widget.onConfigChange?.call(cfg);
  }

  void _setMaxItems(int value) {
    final cfg = Map<String, dynamic>.from(widget.config)
      ..['max_items'] = value;
    widget.onConfigChange?.call(cfg);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [
          BoxShadow(
              color: AppTheme.royalPurple.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with settings toggle
          Row(
            children: [
              Icon(Icons.rss_feed, size: 15, color: AppTheme.royalPurple),
              const SizedBox(width: 6),
              Text('Friend Activity',
                  style: TextStyle(
                      color: AppTheme.navyText,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              if (widget.onConfigChange != null)
                Semantics(
                  button: true,
                  label: _settingsExpanded ? 'Collapse settings' : 'Expand settings',
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _settingsExpanded = !_settingsExpanded),
                    child: Icon(
                      _settingsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.tune_outlined,
                      size: 16,
                      color: _settingsExpanded
                          ? AppTheme.royalPurple
                          : AppTheme.navyText.withValues(alpha: 0.35),
                    ),
                  ),
                ),
            ],
          ),
          // Expandable settings panel
          if (_settingsExpanded) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.royalPurple.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Max items stepper
                  Row(
                    children: [
                      Text('Show items:',
                          style: TextStyle(
                              color: AppTheme.navyText.withValues(alpha: 0.6),
                              fontSize: 12)),
                      const Spacer(),
                      _FAStepperButton(
                        icon: Icons.remove,
                        onPressed:
                            _maxItems > 1 ? () => _setMaxItems(_maxItems - 1) : null,
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 24,
                        child: Text('$_maxItems',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppTheme.navyText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      _FAStepperButton(
                        icon: Icons.add,
                        onPressed:
                            _maxItems < 20 ? () => _setMaxItems(_maxItems + 1) : null,
                      ),
                    ],
                  ),
                  if (widget.allFriends.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Filter by friends:',
                            style: TextStyle(
                                color: AppTheme.navyText.withValues(alpha: 0.6),
                                fontSize: 12)),
                        if (_filterIds.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              final cfg =
                                  Map<String, dynamic>.from(widget.config)
                                    ..['filter_friend_ids'] = <String>[];
                              widget.onConfigChange?.call(cfg);
                            },
                            child: Text('Clear',
                                style: TextStyle(
                                    color: AppTheme.royalPurple,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: widget.allFriends.length,
                        itemBuilder: (context, i) {
                          final f = widget.allFriends[i];
                          final id = f['id'] as String? ??
                              f['user_id'] as String? ??
                              '';
                          final name = f['display_name'] as String? ??
                              f['handle'] as String? ??
                              '?';
                          final avatar = f['avatar_url'] as String?;
                          final isSelected = _filterIds.contains(id);
                          return InkWell(
                            onTap: () =>
                                setState(() => _toggleFriendFilter(id)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  SojornAvatar(
                                      displayName: name,
                                      avatarUrl: avatar,
                                      size: 22),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(name,
                                        style: TextStyle(
                                            color: AppTheme.navyText,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (_) => setState(
                                        () => _toggleFriendFilter(id)),
                                    activeColor: AppTheme.royalPurple,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_loading)
            const Center(
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_items.isEmpty)
            Text('No recent activity',
                style: TextStyle(
                    color: AppTheme.navyText.withValues(alpha: 0.4),
                    fontSize: 12))
          else
            ..._items.take(_maxItems).map((item) => _buildItem(item)),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> post) {
    final author = post['author'] as Map<String, dynamic>?;
    final name = author?['display_name'] as String? ??
        author?['handle'] as String? ??
        'Someone';
    final handle = author?['handle'] as String? ?? '';
    final avatarUrl = author?['avatar_url'] as String?;
    final body = post['body'] as String? ?? post['content'] as String? ?? '';
    final createdAt =
        post['created_at'] as String? ?? post['createdAt'] as String?;
    final ago = _timeAgo(createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SojornAvatar(displayName: name, avatarUrl: avatarUrl, size: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(name,
                            style: TextStyle(
                                color: AppTheme.navyText,
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    if (ago.isNotEmpty)
                      Text(ago,
                          style: TextStyle(
                              color: AppTheme.navyText.withValues(alpha: 0.35),
                              fontSize: 10)),
                  ],
                ),
                if (body.isNotEmpty)
                  Text(body,
                      style: TextStyle(
                          color: AppTheme.navyText.withValues(alpha: 0.6),
                          fontSize: 11,
                          height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                if (handle.isNotEmpty)
                  Text('@$handle posted',
                      style: TextStyle(
                          color: AppTheme.royalPurple.withValues(alpha: 0.5),
                          fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

class _FAStepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _FAStepperButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: onPressed != null
              ? AppTheme.royalPurple.withValues(alpha: 0.1)
              : AppTheme.royalPurple.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 12,
            color: onPressed != null
                ? AppTheme.royalPurple
                : AppTheme.royalPurple.withValues(alpha: 0.3)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Discover-specific sidebar widgets
// ═══════════════════════════════════════════════════════════════════════════

/// Suggested users to follow — fetches from /users/suggested API.
class DesktopSuggestedUsersCard extends StatefulWidget {
  const DesktopSuggestedUsersCard({super.key});

  @override
  State<DesktopSuggestedUsersCard> createState() =>
      _DesktopSuggestedUsersCardState();
}

class _DesktopSuggestedUsersCardState extends State<DesktopSuggestedUsersCard> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.instance.getSuggestedUsers(limit: 8);
      if (mounted) setState(() { _suggestions = data; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_add_outlined, size: 14, color: AppTheme.royalPurple),
              const SizedBox(width: 6),
              Text('People to Follow',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
            ],
          ),
          const SizedBox(height: 12),
          ..._suggestions.take(6).map((u) {
            final displayName = u['display_name'] as String? ?? u['handle'] as String? ?? '';
            final handle = u['handle'] as String? ?? '';
            final avatarUrl = u['avatar_url'] as String?;
            final userId = u['user_id'] as String? ?? u['id'] as String? ?? '';
            final reason = u['reason'] as String?;
            return _SuggestedUserRow(
              displayName: displayName,
              handle: handle,
              avatarUrl: avatarUrl,
              userId: userId,
              reason: reason,
              onFollowed: () {
                setState(() => _suggestions.removeWhere(
                    (s) => (s['user_id'] ?? s['id']) == userId));
              },
            );
          }),
        ],
      ),
    );
  }
}

class _SuggestedUserRow extends StatefulWidget {
  final String displayName;
  final String handle;
  final String? avatarUrl;
  final String userId;
  final String? reason;
  final VoidCallback onFollowed;

  const _SuggestedUserRow({
    required this.displayName,
    required this.handle,
    this.avatarUrl,
    required this.userId,
    this.reason,
    required this.onFollowed,
  });

  @override
  State<_SuggestedUserRow> createState() => _SuggestedUserRowState();
}

class _SuggestedUserRowState extends State<_SuggestedUserRow> {
  bool _isFollowing = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SojornAvatar(
            displayName: widget.displayName,
            avatarUrl: widget.avatarUrl,
            size: 32,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.displayName,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.navyText),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('@${widget.handle}',
                    style: TextStyle(fontSize: 10, color: AppTheme.textDisabled),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (widget.reason != null)
                  Text(widget.reason!,
                      style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: AppTheme.navyText.withValues(alpha: 0.4)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 26,
            child: FilledButton(
              onPressed: _isFollowing ? null : () async {
                setState(() => _isFollowing = true);
                try {
                  await ApiService.instance.followUser(widget.userId);
                  widget.onFollowed();
                } catch (_) {
                  if (mounted) setState(() => _isFollowing = false);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brightNavy,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              ),
              child: Text(_isFollowing ? 'Following' : 'Follow'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trending hashtags — fetches from /discover API.
class DesktopTrendingHashtagsCard extends StatefulWidget {
  const DesktopTrendingHashtagsCard({super.key});

  @override
  State<DesktopTrendingHashtagsCard> createState() =>
      _DesktopTrendingHashtagsCardState();
}

class _DesktopTrendingHashtagsCardState
    extends State<DesktopTrendingHashtagsCard> {
  List<Map<String, dynamic>> _tags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final apiService = ApiService.instance;
      final response = await apiService.get('/discover');
      final tags = (response['top_tags'] as List?) ?? [];
      if (mounted) {
        setState(() {
          _tags = tags.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_tags.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up, size: 14, color: AppTheme.royalPurple),
              const SizedBox(width: 6),
              Text('Trending',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _tags.take(10).map((tag) {
              final name = tag['display_name'] as String? ?? tag['name'] as String? ?? '';
              final count = tag['use_count'] as int? ?? 0;
              return GestureDetector(
                onTap: () {
                  // Navigate to discover with tag search
                  // TODO: wire up tag navigation
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.royalPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('#$name',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.royalPurple)),
                      if (count > 0) ...[
                        const SizedBox(width: 4),
                        Text('$count',
                            style: TextStyle(fontSize: 9, color: AppTheme.textDisabled)),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Popular groups — fetches from /groups API.
class DesktopPopularGroupsCard extends StatefulWidget {
  const DesktopPopularGroupsCard({super.key});

  @override
  State<DesktopPopularGroupsCard> createState() =>
      _DesktopPopularGroupsCardState();
}

class _DesktopPopularGroupsCardState extends State<DesktopPopularGroupsCard> {
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.instance.callGoApi(
        '/groups', method: 'GET', queryParams: {'limit': '5'},
      );
      final groups = (data['groups'] as List?) ?? [];
      if (mounted) {
        setState(() {
          _groups = groups.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_groups.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.groups_outlined, size: 14, color: AppTheme.royalPurple),
              const SizedBox(width: 6),
              Text('Popular Groups',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
            ],
          ),
          const SizedBox(height: 12),
          ..._groups.take(5).map((g) {
            final name = g['name'] as String? ?? '';
            final memberCount = g['member_count'] as int? ?? 0;
            final avatarUrl = g['avatar_url'] as String?;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SojornAvatar(
                    displayName: name,
                    avatarUrl: avatarUrl,
                    size: 32,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.navyText),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('$memberCount members',
                            style: TextStyle(fontSize: 10, color: AppTheme.textDisabled)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── Mood / Status Widget ──────────────────────────────────────────────────

class MoodStatusWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final VoidCallback? onSettingsTap;

  const MoodStatusWidget({super.key, this.config = const {}, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final emoji = config['emoji'] as String? ?? '';
    final text = config['text'] as String? ?? '';
    final hasContent = emoji.isNotEmpty || text.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MOOD',
                style: TextStyle(
                  color: AppTheme.royalPurple,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              if (hasContent) ...[
                Row(
                  children: [
                    if (emoji.isNotEmpty) ...[
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [AppTheme.brightNavy.withValues(alpha: 0.08), AppTheme.royalPurple.withValues(alpha: 0.12)]),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(emoji, style: const TextStyle(fontSize: 24)),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (text.isNotEmpty)
                      Expanded(
                        child: Text(
                          text,
                          style: TextStyle(
                            color: AppTheme.navyText,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ] else
                Text(
                  'Tap \u2699 to set your mood',
                  style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.35), fontSize: 13, fontStyle: FontStyle.italic),
                ),
            ],
          ),
          _gearButton(onSettingsTap),
        ],
      ),
    );
  }
}


// ─── Favorite Media Widget ─────────────────────────────────────────────────

IconData favoriteCategoryIcon(String cat) {
  switch (cat) {
    case 'music': return Icons.album;
    case 'movie': return Icons.movie;
    case 'book': return Icons.menu_book;
    case 'game': return Icons.sports_esports;
    case 'show': return Icons.tv;
    default: return Icons.star;
  }
}

class FavoriteMediaWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final VoidCallback? onSettingsTap;

  const FavoriteMediaWidget({super.key, this.config = const {}, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final raw = config['items'] as List? ?? [];
    final items = raw.map((e) {
      final m = e as Map<String, dynamic>;
      return {
        'title': m['title']?.toString() ?? '',
        'subtitle': m['subtitle']?.toString() ?? '',
        'category': m['category']?.toString() ?? 'music',
      };
    }).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FAVORITES',
                style: TextStyle(
                  color: AppTheme.royalPurple,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                Text('Tap \u2699 to add your favorites', style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.35), fontSize: 13, fontStyle: FontStyle.italic))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.0,
                  ),
                  itemCount: items.length.clamp(0, 4),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final cat = item['category'] ?? 'music';
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.royalPurple.withValues(alpha: 0.06), AppTheme.brightNavy.withValues(alpha: 0.04)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.08)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(favoriteCategoryIcon(cat), size: 18, color: AppTheme.royalPurple.withValues(alpha: 0.6)),
                          const SizedBox(height: 4),
                          Text(
                            item['title'] ?? '',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.navyText),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          if ((item['subtitle'] ?? '').isNotEmpty)
                            Text(
                              item['subtitle']!,
                              style: TextStyle(fontSize: 9, color: AppTheme.navyText.withValues(alpha: 0.5)),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
          _gearButton(onSettingsTap),
        ],
      ),
    );
  }
}


// ─── Countdown Widget ──────────────────────────────────────────────────────

class CountdownWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final VoidCallback? onSettingsTap;

  const CountdownWidget({super.key, this.config = const {}, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final label = config['label'] as String? ?? '';
    final dateStr = config['target_date'] as String?;
    final targetDate = dateStr != null ? DateTime.tryParse(dateStr) : null;
    final hasContent = targetDate != null;
    int days = 0;
    if (targetDate != null) {
      final diff = targetDate.difference(DateTime.now()).inDays;
      days = diff < 0 ? 0 : diff;
    }
    final isUrgent = days <= 7 && hasContent;
    final accentColor = isUrgent ? const Color(0xFFFF6B6B) : AppTheme.brightNavy;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'COUNTDOWN',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              if (hasContent) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isUrgent
                            ? [const Color(0xFFFF6B6B).withValues(alpha: 0.15), const Color(0xFFFF8E53).withValues(alpha: 0.10)]
                            : [AppTheme.brightNavy.withValues(alpha: 0.10), AppTheme.royalPurple.withValues(alpha: 0.08)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$days',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: accentColor,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            days == 1 ? 'day remaining' : 'days remaining',
                            style: TextStyle(fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.5), fontWeight: FontWeight.w500),
                          ),
                          if (label.isNotEmpty)
                            Text(
                              label,
                              style: TextStyle(fontSize: 13, color: AppTheme.navyText, fontWeight: FontWeight.w700),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else
                Text(
                  'Tap \u2699 to set a countdown',
                  style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.35), fontSize: 13, fontStyle: FontStyle.italic),
                ),
            ],
          ),
          _gearButton(onSettingsTap),
        ],
      ),
    );
  }
}


// ─── Social Links Widget ───────────────────────────────────────────────────

Color socialPlatformColor(String p) {
  switch (p) {
    case 'twitter': return const Color(0xFF1DA1F2);
    case 'bluesky': return const Color(0xFF0085FF);
    case 'instagram': return const Color(0xFFE1306C);
    case 'github': return const Color(0xFF333333);
    case 'linkedin': return const Color(0xFF0077B5);
    case 'youtube': return const Color(0xFFFF0000);
    case 'tiktok': return const Color(0xFF010101);
    case 'website': return const Color(0xFF6366F1);
    default: return Colors.grey;
  }
}

IconData socialPlatformIcon(String p) {
  switch (p) {
    case 'twitter': return Icons.alternate_email;
    case 'bluesky': return Icons.cloud;
    case 'instagram': return Icons.camera_alt;
    case 'github': return Icons.code;
    case 'linkedin': return Icons.work;
    case 'youtube': return Icons.play_circle;
    case 'tiktok': return Icons.music_video;
    case 'website': return Icons.language;
    default: return Icons.link;
  }
}

const socialPlatforms = ['twitter', 'bluesky', 'instagram', 'github', 'linkedin', 'youtube', 'tiktok', 'website'];
const favoriteCategories = ['music', 'movie', 'book', 'game', 'show'];
const moodEmojis = [
  '😊', '😎', '🔥', '💭', '🎨', '🎵', '📚', '💻', '🌙', '☕',
  '😴', '🤔', '🥳', '💪', '🌈', '❤️', '✨', '🎯', '🧠', '🍕',
];

class SocialLinksWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final VoidCallback? onSettingsTap;

  const SocialLinksWidget({super.key, this.config = const {}, this.onSettingsTap});

  @override
  Widget build(BuildContext context) {
    final raw = config['links'] as List? ?? [];
    final links = raw.map((e) {
      final m = e as Map<String, dynamic>;
      return {
        'platform': m['platform']?.toString() ?? 'website',
        'url': m['url']?.toString() ?? '',
        'label': m['label']?.toString() ?? '',
      };
    }).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LINKS',
                style: TextStyle(
                  color: AppTheme.royalPurple,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              if (links.isEmpty)
                Text('Tap \u2699 to add your links', style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.35), fontSize: 13, fontStyle: FontStyle.italic))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: links.map((link) {
                    final platform = link['platform'] ?? 'website';
                    final label = link['label'] ?? platform;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: socialPlatformColor(platform).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: socialPlatformColor(platform).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(socialPlatformIcon(platform), color: socialPlatformColor(platform), size: 14),
                          const SizedBox(width: 5),
                          Text(label.isNotEmpty ? label : platform, style: TextStyle(color: socialPlatformColor(platform), fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
          _gearButton(onSettingsTap),
        ],
      ),
    );
  }
}


// ─── Widget Settings Panel (center column) ─────────────────────────────────

class WidgetSettingsPanel extends StatefulWidget {
  final DashboardWidget widgetData;
  final void Function(Map<String, dynamic>) onSave;
  final VoidCallback onCancel;

  const WidgetSettingsPanel({
    super.key,
    required this.widgetData,
    required this.onSave,
    required this.onCancel,
  });

  @override
  State<WidgetSettingsPanel> createState() => _WidgetSettingsPanelState();
}

class _WidgetSettingsPanelState extends State<WidgetSettingsPanel> {
  // Quote / Custom Text
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;

  // Mood
  String _moodEmoji = '';
  late TextEditingController _moodTextCtrl;

  // Countdown
  late TextEditingController _countdownLabelCtrl;
  DateTime? _countdownDate;

  // Photo Frame
  late TextEditingController _photoUrlCtrl;
  late TextEditingController _photoCaptionCtrl;

  // Favorites
  List<Map<String, String>> _favItems = [];
  List<TextEditingController> _favTitleCtrls = [];
  List<TextEditingController> _favSubCtrls = [];

  // Social Links
  List<Map<String, String>> _socialLinks = [];
  List<TextEditingController> _socialLabelCtrls = [];
  List<TextEditingController> _socialUrlCtrls = [];

  @override
  void initState() {
    super.initState();
    final cfg = widget.widgetData.config;
    switch (widget.widgetData.type) {
      case DashboardWidgetType.quote:
        _titleCtrl = TextEditingController(text: cfg['author'] as String? ?? '');
        _bodyCtrl = TextEditingController(text: cfg['quote'] as String? ?? '');
      case DashboardWidgetType.customText:
        _titleCtrl = TextEditingController(text: cfg['title'] as String? ?? '');
        _bodyCtrl = TextEditingController(text: cfg['text'] as String? ?? '');
      case DashboardWidgetType.moodStatus:
        _moodEmoji = cfg['emoji'] as String? ?? '';
        _moodTextCtrl = TextEditingController(text: cfg['text'] as String? ?? '');
        _titleCtrl = TextEditingController();
        _bodyCtrl = TextEditingController();
      case DashboardWidgetType.countdown:
        _countdownLabelCtrl = TextEditingController(text: cfg['label'] as String? ?? '');
        final dateStr = cfg['target_date'] as String?;
        _countdownDate = dateStr != null ? DateTime.tryParse(dateStr) : null;
        _titleCtrl = TextEditingController();
        _bodyCtrl = TextEditingController();
      case DashboardWidgetType.photoFrame:
        _photoUrlCtrl = TextEditingController(text: cfg['url'] as String? ?? '');
        _photoCaptionCtrl = TextEditingController(text: cfg['caption'] as String? ?? '');
        _titleCtrl = TextEditingController();
        _bodyCtrl = TextEditingController();
      case DashboardWidgetType.favoriteMedia:
        final raw = cfg['items'] as List? ?? [];
        _favItems = raw.map((e) {
          final m = e as Map<String, dynamic>;
          return {'title': m['title']?.toString() ?? '', 'subtitle': m['subtitle']?.toString() ?? '', 'category': m['category']?.toString() ?? 'music'};
        }).toList();
        _favTitleCtrls = _favItems.map((e) => TextEditingController(text: e['title'])).toList();
        _favSubCtrls = _favItems.map((e) => TextEditingController(text: e['subtitle'])).toList();
        _titleCtrl = TextEditingController();
        _bodyCtrl = TextEditingController();
      case DashboardWidgetType.socialLinks:
        final raw = cfg['links'] as List? ?? [];
        _socialLinks = raw.map((e) {
          final m = e as Map<String, dynamic>;
          return {'platform': m['platform']?.toString() ?? 'website', 'url': m['url']?.toString() ?? '', 'label': m['label']?.toString() ?? ''};
        }).toList();
        _socialLabelCtrls = _socialLinks.map((e) => TextEditingController(text: e['label'])).toList();
        _socialUrlCtrls = _socialLinks.map((e) => TextEditingController(text: e['url'])).toList();
        _titleCtrl = TextEditingController();
        _bodyCtrl = TextEditingController();
      default:
        _titleCtrl = TextEditingController();
        _bodyCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    if (widget.widgetData.type == DashboardWidgetType.moodStatus) _moodTextCtrl.dispose();
    if (widget.widgetData.type == DashboardWidgetType.countdown) _countdownLabelCtrl.dispose();
    if (widget.widgetData.type == DashboardWidgetType.photoFrame) {
      _photoUrlCtrl.dispose();
      _photoCaptionCtrl.dispose();
    }
    for (final c in _favTitleCtrls) { c.dispose(); }
    for (final c in _favSubCtrls) { c.dispose(); }
    for (final c in _socialLabelCtrls) { c.dispose(); }
    for (final c in _socialUrlCtrls) { c.dispose(); }
    super.dispose();
  }

  void _handleSave() {
    switch (widget.widgetData.type) {
      case DashboardWidgetType.quote:
        widget.onSave({'quote': _bodyCtrl.text.trim(), 'author': _titleCtrl.text.trim()});
      case DashboardWidgetType.customText:
        widget.onSave({'title': _titleCtrl.text.trim(), 'text': _bodyCtrl.text.trim()});
      case DashboardWidgetType.moodStatus:
        widget.onSave({'emoji': _moodEmoji, 'text': _moodTextCtrl.text.trim()});
      case DashboardWidgetType.countdown:
        widget.onSave({'label': _countdownLabelCtrl.text.trim(), 'target_date': _countdownDate?.toIso8601String()});
      case DashboardWidgetType.photoFrame:
        widget.onSave({'url': _photoUrlCtrl.text.trim(), 'caption': _photoCaptionCtrl.text.trim()});
      case DashboardWidgetType.favoriteMedia:
        for (int i = 0; i < _favItems.length; i++) {
          _favItems[i] = {..._favItems[i], 'title': _favTitleCtrls[i].text, 'subtitle': _favSubCtrls[i].text};
        }
        widget.onSave({'items': _favItems, 'maxItems': 4});
      case DashboardWidgetType.socialLinks:
        for (int i = 0; i < _socialLinks.length; i++) {
          _socialLinks[i] = {..._socialLinks[i], 'label': _socialLabelCtrls[i].text, 'url': _socialUrlCtrls[i].text};
        }
        widget.onSave({'links': _socialLinks});
      default:
        widget.onCancel();
    }
  }

  String get _panelTitle {
    switch (widget.widgetData.type) {
      case DashboardWidgetType.quote: return 'Edit Quote';
      case DashboardWidgetType.customText: return 'Edit Custom Text';
      case DashboardWidgetType.moodStatus: return 'Set Mood';
      case DashboardWidgetType.countdown: return 'Set Countdown';
      case DashboardWidgetType.photoFrame: return 'Edit Photo Frame';
      case DashboardWidgetType.favoriteMedia: return 'Edit Favorites';
      case DashboardWidgetType.socialLinks: return 'Edit Links';
      default: return 'Settings';
    }
  }

  IconData get _panelIcon {
    switch (widget.widgetData.type) {
      case DashboardWidgetType.quote: return Icons.format_quote;
      case DashboardWidgetType.customText: return Icons.text_fields;
      case DashboardWidgetType.moodStatus: return Icons.emoji_emotions;
      case DashboardWidgetType.countdown: return Icons.timer;
      case DashboardWidgetType.photoFrame: return Icons.photo;
      case DashboardWidgetType.favoriteMedia: return Icons.star;
      case DashboardWidgetType.socialLinks: return Icons.link;
      default: return Icons.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        margin: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(SojornRadii.card),
          boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.royalPurple.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: [
                  Icon(_panelIcon, size: 20, color: AppTheme.royalPurple),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _panelTitle,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyText),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onCancel,
                    child: Text('Cancel', style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.5), fontSize: 13)),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _handleSave,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [AppTheme.brightNavy, AppTheme.royalPurple]),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Padding(
              padding: const EdgeInsets.all(20),
              child: _buildForm(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    switch (widget.widgetData.type) {
      case DashboardWidgetType.quote:
        return _buildQuoteForm();
      case DashboardWidgetType.customText:
        return _buildCustomTextForm();
      case DashboardWidgetType.moodStatus:
        return _buildMoodForm();
      case DashboardWidgetType.countdown:
        return _buildCountdownForm();
      case DashboardWidgetType.photoFrame:
        return _buildPhotoForm();
      case DashboardWidgetType.favoriteMedia:
        return _buildFavoritesForm();
      case DashboardWidgetType.socialLinks:
        return _buildLinksForm();
      default:
        return const Text('No settings available for this widget.');
    }
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(fontSize: 13, color: AppTheme.navyText.withValues(alpha: 0.5)),
      hintStyle: TextStyle(fontSize: 13, color: AppTheme.navyText.withValues(alpha: 0.3)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      isDense: true,
    );
  }

  TextStyle get _fieldStyle => TextStyle(fontSize: 14, color: AppTheme.navyText);

  Widget _buildQuoteForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _bodyCtrl,
          maxLines: 4,
          maxLength: 300,
          style: _fieldStyle,
          decoration: _fieldDecoration('Quote text', hint: 'Enter your quote...'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _titleCtrl,
          maxLength: 80,
          style: _fieldStyle,
          decoration: _fieldDecoration('Author', hint: '— Someone wise'),
        ),
      ],
    );
  }

  Widget _buildCustomTextForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleCtrl,
          maxLength: 80,
          style: _fieldStyle,
          decoration: _fieldDecoration('Title', hint: 'Widget title...'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _bodyCtrl,
          maxLines: 5,
          maxLength: 500,
          style: _fieldStyle,
          decoration: _fieldDecoration('Body', hint: 'Write something...'),
        ),
      ],
    );
  }

  Widget _buildMoodForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick an emoji:', style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: moodEmojis.map((e) {
            final isSelected = _moodEmoji == e;
            return GestureDetector(
              onTap: () => setState(() => _moodEmoji = isSelected ? '' : e),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.royalPurple.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? Border.all(color: AppTheme.royalPurple, width: 2) : Border.all(color: AppTheme.navyText.withValues(alpha: 0.08)),
                ),
                alignment: Alignment.center,
                child: Text(e, style: const TextStyle(fontSize: 22)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _moodTextCtrl,
          maxLength: 80,
          style: _fieldStyle,
          decoration: _fieldDecoration('Status text', hint: 'feeling creative...'),
        ),
      ],
    );
  }

  Widget _buildCountdownForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _countdownLabelCtrl,
          maxLength: 60,
          style: _fieldStyle,
          decoration: _fieldDecoration('Event name', hint: 'Album Drop, Birthday, Launch...'),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _countdownDate ?? DateTime.now().add(const Duration(days: 7)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
            );
            if (picked != null) setState(() => _countdownDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: AppTheme.royalPurple),
                const SizedBox(width: 10),
                Text(
                  _countdownDate != null
                    ? '${_countdownDate!.month}/${_countdownDate!.day}/${_countdownDate!.year}'
                    : 'Pick a date',
                  style: TextStyle(fontSize: 14, color: _countdownDate != null ? AppTheme.navyText : AppTheme.navyText.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _photoUrlCtrl,
          style: _fieldStyle,
          decoration: _fieldDecoration('Image URL', hint: 'https://example.com/photo.jpg'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _photoCaptionCtrl,
          maxLength: 120,
          style: _fieldStyle,
          decoration: _fieldDecoration('Caption', hint: 'A lovely day...'),
        ),
      ],
    );
  }

  Widget _buildFavoritesForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._favItems.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.royalPurple.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Category dropdown
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.15)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: item['category'] ?? 'music',
                            isDense: true,
                            style: TextStyle(fontSize: 12, color: AppTheme.navyText),
                            items: favoriteCategories.map((c) => DropdownMenuItem(
                              value: c,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(favoriteCategoryIcon(c), size: 16, color: AppTheme.royalPurple.withValues(alpha: 0.6)),
                                  const SizedBox(width: 6),
                                  Text(c[0].toUpperCase() + c.substring(1), style: TextStyle(fontSize: 12, color: AppTheme.navyText)),
                                ],
                              ),
                            )).toList(),
                            onChanged: (v) => setState(() => _favItems[i] = {..._favItems[i], 'category': v ?? 'music'}),
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() {
                          _favItems.removeAt(i);
                          _favTitleCtrls[i].dispose();
                          _favSubCtrls[i].dispose();
                          _favTitleCtrls.removeAt(i);
                          _favSubCtrls.removeAt(i);
                        }),
                        child: Icon(Icons.close, size: 18, color: AppTheme.navyText.withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _favTitleCtrls[i],
                    style: _fieldStyle,
                    decoration: _fieldDecoration('Title', hint: 'e.g. Dark Side of the Moon'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _favSubCtrls[i],
                    style: _fieldStyle,
                    decoration: _fieldDecoration('Artist / Author', hint: 'e.g. Pink Floyd'),
                  ),
                ],
              ),
            ),
          );
        }),
        if (_favItems.length < 4)
          GestureDetector(
            onTap: () => setState(() {
              _favItems.add({'title': '', 'subtitle': '', 'category': 'music'});
              _favTitleCtrls.add(TextEditingController());
              _favSubCtrls.add(TextEditingController());
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.15), style: BorderStyle.solid),
              ),
              child: Text('+ Add favorite', style: TextStyle(color: AppTheme.royalPurple, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  Widget _buildLinksForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._socialLinks.asMap().entries.map((entry) {
          final i = entry.key;
          final link = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.royalPurple.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.15)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: link['platform'] ?? 'website',
                            isDense: true,
                            style: TextStyle(fontSize: 12, color: AppTheme.navyText),
                            items: socialPlatforms.map((p) => DropdownMenuItem(
                              value: p,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(socialPlatformIcon(p), size: 16, color: socialPlatformColor(p)),
                                  const SizedBox(width: 6),
                                  Text(p[0].toUpperCase() + p.substring(1), style: TextStyle(fontSize: 12, color: AppTheme.navyText)),
                                ],
                              ),
                            )).toList(),
                            onChanged: (v) => setState(() => _socialLinks[i] = {..._socialLinks[i], 'platform': v ?? 'website'}),
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() {
                          _socialLinks.removeAt(i);
                          _socialLabelCtrls[i].dispose();
                          _socialUrlCtrls[i].dispose();
                          _socialLabelCtrls.removeAt(i);
                          _socialUrlCtrls.removeAt(i);
                        }),
                        child: Icon(Icons.close, size: 18, color: AppTheme.navyText.withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _socialLabelCtrls[i],
                    style: _fieldStyle,
                    decoration: _fieldDecoration('@handle / Label', hint: '@yourname'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _socialUrlCtrls[i],
                    style: _fieldStyle,
                    decoration: _fieldDecoration('URL', hint: 'https://twitter.com/yourname'),
                  ),
                ],
              ),
            ),
          );
        }),
        if (_socialLinks.length < 8)
          GestureDetector(
            onTap: () => setState(() {
              _socialLinks.add({'platform': 'website', 'url': '', 'label': ''});
              _socialLabelCtrls.add(TextEditingController());
              _socialUrlCtrls.add(TextEditingController());
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.15), style: BorderStyle.solid),
              ),
              child: Text('+ Add link', style: TextStyle(color: AppTheme.royalPurple, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}


/// Shared card decoration for discover sidebar widgets.
BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppTheme.cardSurface,
    borderRadius: BorderRadius.circular(SojornRadii.card),
    boxShadow: [
      BoxShadow(
        color: AppTheme.royalPurple.withValues(alpha: 0.08),
        blurRadius: 12,
        offset: const Offset(0, 2),
      ),
    ],
  );
}
