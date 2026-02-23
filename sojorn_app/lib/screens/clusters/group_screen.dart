// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import '../../models/cluster.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/capsule_security_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import 'group_feed_tab.dart';
import 'group_chat_tab.dart';
import 'group_forum_tab.dart';
import 'group_events_tab.dart';
import 'group_members_tab.dart';

/// Shared GroupScreen for both public groups and private capsules.
/// For encrypted capsules, all content is encrypted/decrypted client-side.
class GroupScreen extends ConsumerStatefulWidget {
  final Cluster group;
  final String? encryptedGroupKey;

  const GroupScreen({
    super.key,
    required this.group,
    this.encryptedGroupKey,
  });

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  SecretKey? _capsuleKey;
  bool _isUnlocking = false;
  String? _unlockError;
  String? _currentUserId;
  late bool _isMember;
  bool _isJoining = false;

  bool get isEncrypted => widget.group.isEncrypted;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _currentUserId = AuthService.instance.currentUser?.id;
    _isMember = widget.group.isMember;
    if (isEncrypted) {
      _unlockCapsule();
    }
  }

  Future<void> _joinGroup() async {
    setState(() => _isJoining = true);
    try {
      await ApiService.instance.joinGroup(widget.group.id);
      if (mounted) setState(() { _isMember = true; _isJoining = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isJoining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _unlockCapsule() async {
    setState(() { _isUnlocking = true; _unlockError = null; });
    try {
      var key = await CapsuleSecurityService.getCachedCapsuleKey(widget.group.id);
      if (key == null && widget.encryptedGroupKey != null) {
        key = await CapsuleSecurityService.decryptCapsuleKey(
          encryptedGroupKeyJson: widget.encryptedGroupKey!,
        );
        await CapsuleSecurityService.cacheCapsuleKey(widget.group.id, key);
      }
      if (mounted) setState(() { _capsuleKey = key; _isUnlocking = false; });
    } catch (e) {
      if (mounted) setState(() { _unlockError = 'Failed to unlock capsule'; _isUnlocking = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    if (isEncrypted && _isUnlocking) return _buildUnlockingScreen();
    if (isEncrypted && _unlockError != null) return _buildErrorScreen();

    final tabBarWidget = TabBar(
      controller: _tabController,
      indicatorColor: isEncrypted ? const Color(0xFF4CAF50) : AppTheme.brightNavy,
      labelColor: AppTheme.navyBlue,
      unselectedLabelColor: SojornColors.textDisabled,
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      tabs: const [
        Tab(icon: Icon(Icons.dynamic_feed, size: 18), text: 'Feed'),
        Tab(icon: Icon(Icons.chat_bubble, size: 18), text: 'Chat'),
        Tab(icon: Icon(Icons.forum, size: 18), text: 'Forum'),
        Tab(icon: Icon(Icons.event, size: 18), text: 'Events'),
        Tab(icon: Icon(Icons.people, size: 18), text: 'Members'),
      ],
    );

    final tabBody = TabBarView(
      controller: _tabController,
      children: [
        GroupFeedTab(
          groupId: widget.group.id,
          isEncrypted: isEncrypted,
          capsuleKey: _capsuleKey,
          currentUserId: _currentUserId,
        ),
        GroupChatTab(
          groupId: widget.group.id,
          isEncrypted: isEncrypted,
          capsuleKey: _capsuleKey,
          currentUserId: _currentUserId,
        ),
        GroupForumTab(
          groupId: widget.group.id,
          isEncrypted: isEncrypted,
          capsuleKey: _capsuleKey,
        ),
        GroupEventsTab(
          groupId: widget.group.id,
        ),
        GroupMembersTab(
          groupId: widget.group.id,
          group: widget.group,
          isEncrypted: isEncrypted,
        ),
      ],
    );

    if (isDesktop) {
      return Column(
        children: [
          // Compact header
          _buildCompactHeader(context),
          if (_isMember) tabBarWidget,
          Expanded(child: _isMember ? tabBody : _buildJoinPrompt()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildHeader(context),
          if (_isMember) _buildTabBar(),
        ],
        body: _isMember ? tabBody : _buildJoinPrompt(),
      ),
    );
  }

  /// Compact header for desktop dialog layout (replaces SliverAppBar).
  Widget _buildCompactHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(bottom: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          if (isEncrypted) ...[
            const Icon(Icons.lock, size: 16, color: Color(0xFF4CAF50)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.group.name,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.navyBlue),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _GroupBadge(isEncrypted: isEncrypted),
                    const SizedBox(width: 10),
                    Icon(Icons.people, size: 13, color: SojornColors.textDisabled),
                    const SizedBox(width: 4),
                    Text('${widget.group.memberCount}',
                        style: TextStyle(color: SojornColors.postContentLight, fontSize: 12)),
                    if (widget.group.description.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          widget.group.description,
                          style: TextStyle(color: SojornColors.textDisabled, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: AppTheme.navyBlue),
            onSelected: (val) {
              if (val == 'settings') _showSettings();
              if (val == 'leave') _confirmLeave();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'settings', child: Text('Group Settings')),
              const PopupMenuItem(value: 'leave', child: Text('Leave Group')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      backgroundColor: AppTheme.cardSurface,
      foregroundColor: AppTheme.navyBlue,
      flexibleSpace: FlexibleSpaceBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEncrypted) ...[
              const Icon(Icons.lock, size: 14, color: Color(0xFF4CAF50)),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                widget.group.name,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.navyBlue),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isEncrypted
                  ? [const Color(0xFFF0F8F0), AppTheme.scaffoldBg]
                  : [AppTheme.brightNavy.withValues(alpha: 0.08), AppTheme.scaffoldBg],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 50),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _GroupBadge(isEncrypted: isEncrypted),
                      const Spacer(),
                      Icon(Icons.people, size: 14, color: SojornColors.textDisabled),
                      const SizedBox(width: 4),
                      Text('${widget.group.memberCount}',
                          style: TextStyle(color: SojornColors.postContentLight, fontSize: 13)),
                      if (isEncrypted) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.vpn_key, size: 14, color: SojornColors.textDisabled),
                        const SizedBox(width: 4),
                        Text('v${widget.group.keyVersion}',
                            style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                      ],
                    ],
                  ),
                  if (widget.group.description.isNotEmpty) ...[
                    const Spacer(),
                    Text(
                      widget.group.description,
                      style: TextStyle(color: SojornColors.postContentLight, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: AppTheme.navyBlue),
          onSelected: (val) {
            if (val == 'settings') _showSettings();
            if (val == 'leave') _confirmLeave();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'settings', child: Text('Group Settings')),
            const PopupMenuItem(value: 'leave', child: Text('Leave Group')),
          ],
        ),
      ],
    );
  }

  SliverPersistentHeader _buildTabBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TabBarDelegate(
        TabBar(
          controller: _tabController,
          indicatorColor: isEncrypted ? const Color(0xFF4CAF50) : AppTheme.brightNavy,
          labelColor: AppTheme.navyBlue,
          unselectedLabelColor: SojornColors.textDisabled,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.dynamic_feed, size: 18), text: 'Feed'),
            Tab(icon: Icon(Icons.chat_bubble, size: 18), text: 'Chat'),
            Tab(icon: Icon(Icons.forum, size: 18), text: 'Forum'),
            Tab(icon: Icon(Icons.event, size: 18), text: 'Events'),
            Tab(icon: Icon(Icons.people, size: 18), text: 'Members'),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    // TODO: Full settings sheet
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Group settings coming soon')),
    );
  }

  void _confirmLeave() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Are you sure you want to leave ${widget.group.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiService.instance.leaveGroup(widget.group.id);
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to leave: $e')),
                  );
                }
              }
            },
            child: Text('Leave', style: TextStyle(color: SojornColors.destructive)),
          ),
        ],
      ),
    );
  }

  Widget _buildUnlockingScreen() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 48, color: Color(0xFF4CAF50)),
            const SizedBox(height: 20),
            Text('Decrypting…', style: TextStyle(color: SojornColors.textDisabled, fontSize: 14)),
            const SizedBox(height: 8),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_add, size: 56, color: AppTheme.brightNavy.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text(widget.group.name,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.navyBlue),
              textAlign: TextAlign.center),
            if (widget.group.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(widget.group.description,
                style: TextStyle(fontSize: 13, color: SojornColors.textDisabled),
                textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, size: 14, color: SojornColors.textDisabled),
                const SizedBox(width: 4),
                Text('${widget.group.memberCount} members',
                  style: TextStyle(fontSize: 12, color: SojornColors.textDisabled)),
                if (widget.group.category != GroupCategory.general) ...[
                  const SizedBox(width: 12),
                  Icon(widget.group.category.icon, size: 14, color: widget.group.category.color),
                  const SizedBox(width: 4),
                  Text(widget.group.category.displayName,
                    style: TextStyle(fontSize: 12, color: widget.group.category.color)),
                ],
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              height: 44,
              child: ElevatedButton(
                onPressed: _isJoining ? null : _joinGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isJoining
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                    : const Text('Join Group', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(backgroundColor: AppTheme.scaffoldBg, foregroundColor: AppTheme.navyBlue),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 48, color: SojornColors.destructive),
            const SizedBox(height: 16),
            Text(_unlockError!, style: const TextStyle(color: SojornColors.destructive, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _unlockCapsule,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brightNavy, foregroundColor: SojornColors.basicWhite),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────
class _GroupBadge extends StatelessWidget {
  final bool isEncrypted;
  const _GroupBadge({required this.isEncrypted});

  @override
  Widget build(BuildContext context) {
    final color = isEncrypted ? const Color(0xFF4CAF50) : AppTheme.brightNavy;
    final label = isEncrypted ? 'E2E ENCRYPTED' : 'GROUP';
    final icon = isEncrypted ? Icons.shield : Icons.public;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color.withValues(alpha: 0.9), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ],
      ),
    );
  }
}

// ── Tab Bar Delegate ──────────────────────────────────────────────────────
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);
  @override double get minExtent => tabBar.preferredSize.height;
  @override double get maxExtent => tabBar.preferredSize.height;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppTheme.cardSurface, child: tabBar);
  }
  @override bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}
