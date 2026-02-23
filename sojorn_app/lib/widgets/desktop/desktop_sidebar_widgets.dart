// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../../config/api_config.dart';
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
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

  const DesktopProfileCard({
    super.key,
    required this.profile,
    required this.stats,
    this.onProfileTap,
    this.onEditTap,
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
                  Row(
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
                            displayName: name, avatarUrl: avatar, size: 26),
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
                        (constraints.maxWidth * 0.78).clamp(28.0, 42.0);
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
                  size: 32,
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

// ─── Quote Widget ────────────────────────────────────────────────────────────

class QuoteWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final void Function(Map<String, dynamic>)? onConfigChange;

  const QuoteWidget({super.key, this.config = const {}, this.onConfigChange});

  @override
  State<QuoteWidget> createState() => _QuoteWidgetState();
}

class _QuoteWidgetState extends State<QuoteWidget> {
  late String _quote;
  late String _author;
  late final TextEditingController _quoteCtrl;
  late final TextEditingController _authorCtrl;

  @override
  void initState() {
    super.initState();
    _quote = widget.config['quote'] as String? ?? '';
    _author = widget.config['author'] as String? ?? '';
    _quoteCtrl = TextEditingController(text: _quote);
    _authorCtrl = TextEditingController(text: _author);
  }

  @override
  void dispose() {
    _quoteCtrl.dispose();
    _authorCtrl.dispose();
    super.dispose();
  }

  void _save(VoidCallback flipBack) {
    setState(() {
      _quote = _quoteCtrl.text.trim();
      _author = _authorCtrl.text.trim();
    });
    widget.onConfigChange?.call({'quote': _quote, 'author': _author});
    flipBack();
  }

  Widget _buildFront(VoidCallback onFlip) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.royalPurple.withValues(alpha: 0.08), AppTheme.brightNavy.withValues(alpha: 0.04)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.format_quote, color: AppTheme.royalPurple.withValues(alpha: 0.4), size: 28),
              const SizedBox(height: 6),
              Text(
                _quote.isNotEmpty ? _quote : 'Tap ⚙ to add your quote',
                style: TextStyle(
                  color: _quote.isNotEmpty ? AppTheme.navyText : AppTheme.navyText.withValues(alpha: 0.35),
                  fontSize: 13,
                  fontStyle: _quote.isEmpty ? FontStyle.italic : FontStyle.normal,
                  height: 1.5,
                ),
              ),
              if (_author.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '— $_author',
                  style: TextStyle(
                    color: AppTheme.royalPurple.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          Positioned(
            top: 0, right: 0,
            child: GestureDetector(
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
          ),
        ],
      ),
    );
  }

  Widget _buildSettings(VoidCallback flipBack) {
    return _settingsBackPanel(
      onDone: () => _save(flipBack),
      title: 'Edit Quote',
      children: [
        TextField(
          controller: _quoteCtrl,
          maxLines: 3,
          style: TextStyle(fontSize: 13, color: AppTheme.navyText),
          decoration: InputDecoration(
            labelText: 'Quote text',
            labelStyle: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(10),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _authorCtrl,
          style: TextStyle(fontSize: 13, color: AppTheme.navyText),
          decoration: InputDecoration(
            labelText: 'Author (optional)',
            labelStyle: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _FlipCard(frontBuilder: _buildFront, back: _buildSettings, front: const SizedBox.shrink());
}

// ─── Custom Text Widget ──────────────────────────────────────────────────────

class CustomTextWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final void Function(Map<String, dynamic>)? onConfigChange;

  const CustomTextWidget({super.key, this.config = const {}, this.onConfigChange});

  @override
  State<CustomTextWidget> createState() => _CustomTextWidgetState();
}

class _CustomTextWidgetState extends State<CustomTextWidget> {
  late String _title;
  late String _text;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    _title = widget.config['title'] as String? ?? '';
    _text = widget.config['text'] as String? ?? '';
    _titleCtrl = TextEditingController(text: _title);
    _textCtrl = TextEditingController(text: _text);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _save(VoidCallback flipBack) {
    setState(() {
      _title = _titleCtrl.text.trim();
      _text = _textCtrl.text.trim();
    });
    widget.onConfigChange?.call({'title': _title, 'text': _text});
    flipBack();
  }

  Widget _buildFront(VoidCallback onFlip) {
    return Container(
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
              if (_title.isNotEmpty) ...[
                Text(_title, style: TextStyle(color: AppTheme.navyText, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
              ],
              Text(
                _text.isNotEmpty ? _text : 'Tap ⚙ to add your content',
                style: TextStyle(
                  color: _text.isNotEmpty ? AppTheme.navyText.withValues(alpha: 0.75) : AppTheme.navyText.withValues(alpha: 0.35),
                  fontSize: 12,
                  fontStyle: _text.isEmpty ? FontStyle.italic : FontStyle.normal,
                  height: 1.5,
                ),
              ),
            ],
          ),
          Positioned(
            top: 0, right: 0,
            child: GestureDetector(
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
          ),
        ],
      ),
    );
  }

  Widget _buildSettings(VoidCallback flipBack) {
    return _settingsBackPanel(
      onDone: () => _save(flipBack),
      title: 'Edit Content',
      children: [
        TextField(
          controller: _titleCtrl,
          style: TextStyle(fontSize: 13, color: AppTheme.navyText),
          decoration: InputDecoration(
            labelText: 'Title (optional)',
            labelStyle: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _textCtrl,
          maxLines: 5,
          style: TextStyle(fontSize: 13, color: AppTheme.navyText),
          decoration: InputDecoration(
            labelText: 'Content',
            labelStyle: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.all(10),
            isDense: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _FlipCard(frontBuilder: _buildFront, back: _buildSettings, front: const SizedBox.shrink());
}

// ─── Photo Frame Widget ──────────────────────────────────────────────────────

class PhotoFrameWidget extends StatefulWidget {
  final Map<String, dynamic> config;
  final void Function(Map<String, dynamic>)? onConfigChange;

  const PhotoFrameWidget({super.key, this.config = const {}, this.onConfigChange});

  @override
  State<PhotoFrameWidget> createState() => _PhotoFrameWidgetState();
}

class _PhotoFrameWidgetState extends State<PhotoFrameWidget> {
  late String _url;
  late String _caption;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _captionCtrl;

  @override
  void initState() {
    super.initState();
    _url = widget.config['url'] as String? ?? '';
    _caption = widget.config['caption'] as String? ?? '';
    _urlCtrl = TextEditingController(text: _url);
    _captionCtrl = TextEditingController(text: _caption);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _captionCtrl.dispose();
    super.dispose();
  }

  void _save(VoidCallback flipBack) {
    setState(() {
      _url = _urlCtrl.text.trim();
      _caption = _captionCtrl.text.trim();
    });
    widget.onConfigChange?.call({'url': _url, 'caption': _caption});
    flipBack();
  }

  Widget _buildFront(VoidCallback onFlip) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        boxShadow: [BoxShadow(color: AppTheme.royalPurple.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (_url.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(_url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder()),
                ),
                if (_caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(_caption, style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.65), fontSize: 12, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
                  ),
              ],
            )
          else
            _placeholder(),
          Positioned(
            top: 10, right: 10,
            child: GestureDetector(
              onTap: onFlip,
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

  Widget _placeholder() {
    return Container(
      height: 120,
      color: AppTheme.royalPurple.withValues(alpha: 0.06),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 36, color: AppTheme.royalPurple.withValues(alpha: 0.35)),
          const SizedBox(height: 6),
          Text('Tap ⚙ to add a photo URL', style: TextStyle(fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.35))),
        ],
      ),
    );
  }

  Widget _buildSettings(VoidCallback flipBack) {
    return _settingsBackPanel(
      onDone: () => _save(flipBack),
      title: 'Photo Frame',
      children: [
        TextField(
          controller: _urlCtrl,
          style: TextStyle(fontSize: 12, color: AppTheme.navyText),
          decoration: InputDecoration(
            labelText: 'Image URL',
            labelStyle: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
            hintText: 'https://...',
            hintStyle: TextStyle(fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.3)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _captionCtrl,
          style: TextStyle(fontSize: 13, color: AppTheme.navyText),
          decoration: InputDecoration(
            labelText: 'Caption (optional)',
            labelStyle: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            isDense: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => _FlipCard(frontBuilder: _buildFront, back: _buildSettings, front: const SizedBox.shrink());
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
                GestureDetector(
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
          SojornAvatar(displayName: name, avatarUrl: avatarUrl, size: 28),
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
