// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/event.dart';
import '../../models/profile.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../media/sojorn_avatar.dart';


// ─── Flip Card Widget (wraps sidebar widgets with settings flip) ─────────────

class _FlipCard extends StatefulWidget {
  final Widget front;
  final Widget Function(VoidCallback flipBack) back;

  const _FlipCard({required this.front, required this.back});

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
            // Gradient overlay — stronger at top for text legibility
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    SojornColors.basicBlack.withValues(alpha: 0.45),
                    SojornColors.basicBlack.withValues(alpha: 0.15),
                    SojornColors.basicBlack.withValues(alpha: 0.0),
                    SojornColors.basicBlack.withValues(alpha: 0.35),
                  ],
                  stops: const [0.0, 0.3, 0.55, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 12,
              child: Text(
                '$coverGreeting, ${profile.displayName.split(' ').first}',
                style: TextStyle(
                  color: SojornColors.basicWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
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
              ),
            ),
            Center(child: avatarWidget),
          ],
        ),
      );
    }

    // Default: vibrant gradient header with PFP centered + greeting
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
            top: 10,
            left: 12,
            child: Text(
              '$greeting, ${profile.displayName.split(' ').first}',
              style: TextStyle(
                color: SojornColors.basicWhite,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: SojornColors.basicBlack.withValues(alpha: 0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Center(child: avatarWidget),
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
  final VoidCallback? onViewAll;
  final void Function(String userId)? onFriendTap;

  const Top8FriendsGrid({
    super.key,
    required this.friends,
    this.onViewAll,
    this.onFriendTap,
  });

  @override
  State<Top8FriendsGrid> createState() => _Top8FriendsGridState();
}

class _Top8FriendsGridState extends State<Top8FriendsGrid> {
  int _maxCount = 8;

  Widget _buildSettings(VoidCallback flipBack) {
    return _settingsBackPanel(
      onDone: flipBack,
      title: 'Top Friends',
      children: [
        Text('Show how many?', style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.6), fontSize: 12)),
        const SizedBox(height: 8),
        Row(
          children: [4, 8].map((count) {
            final isSelected = _maxCount == count;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _maxCount = count),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.royalPurple : AppTheme.royalPurple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$count', style: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.royalPurple,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  )),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.friends.isEmpty) return const SizedBox.shrink();

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
            'Top 8',
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
              childAspectRatio: 0.72,
            ),
            itemCount: widget.friends.length.clamp(0, _maxCount),
            itemBuilder: (context, index) {
              final friend = widget.friends[index];
              final name = friend['display_name'] as String? ?? friend['handle'] as String? ?? '?';
              final avatar = friend['avatar_url'] as String?;
              final handle = friend['handle'] as String? ?? '';

              return GestureDetector(
                onTap: () => widget.onFriendTap?.call(handle),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate avatar size to fit within the cell, leaving room for text
                    final avatarSize = (constraints.maxWidth * 0.78).clamp(28.0, 42.0);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.royalPurple.withValues(alpha: 0.15),
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

  const WhosOnlineList({
    super.key,
    required this.onlineUsers,
    this.onUserTap,
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
            ...onlineUsers.take(10).map((user) => _buildOnlineUser(user)),
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
  const UpcomingEventsWidget({super.key});

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
      final raw = await ApiService.instance.fetchMyEvents(limit: 10);
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
            ..._events.take(3).map((e) => _buildEventCard(e)),
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
