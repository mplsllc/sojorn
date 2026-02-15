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

  bool get isEncrypted => widget.group.isEncrypted;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _currentUserId = AuthService.instance.currentUser?.id;
    if (isEncrypted) {
      _unlockCapsule();
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
    if (isEncrypted && _isUnlocking) return _buildUnlockingScreen();
    if (isEncrypted && _unlockError != null) return _buildErrorScreen();

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildHeader(context),
          _buildTabBar(),
        ],
        body: TabBarView(
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
            GroupMembersTab(
              groupId: widget.group.id,
              group: widget.group,
              isEncrypted: isEncrypted,
            ),
          ],
        ),
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
