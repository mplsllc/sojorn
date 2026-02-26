// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../models/cluster.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media/sojorn_avatar.dart';

class GroupMembersTab extends StatefulWidget {
  final String groupId;
  final Cluster group;
  final bool isEncrypted;

  const GroupMembersTab({
    super.key,
    required this.groupId,
    required this.group,
    this.isEncrypted = false,
  });

  @override
  State<GroupMembersTab> createState() => _GroupMembersTabState();
}

class _GroupMembersTabState extends State<GroupMembersTab> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  String? _currentUserId;
  String? _myRole;

  @override
  void initState() {
    super.initState();
    _currentUserId = AuthService.instance.currentUser?.id;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    try {
      _members = await ApiService.instance.fetchGroupMembers(widget.groupId);
      // Find my role
      for (final m in _members) {
        if (m['user_id']?.toString() == _currentUserId) {
          _myRole = m['role'] as String?;
          break;
        }
      }
    } catch (e) {
      debugPrint('[GroupMembers] Error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get canManage => _myRole == 'owner' || _myRole == 'admin';

  void _showInviteSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => _InviteSheet(groupId: widget.groupId, onInvited: _loadMembers),
    );
  }

  void _showMemberActions(Map<String, dynamic> member) {
    final memberId = member['user_id']?.toString() ?? '';
    final memberRole = member['role'] as String? ?? 'member';
    final handle = member['handle'] as String? ?? '';

    if (memberId == _currentUserId) return; // Can't act on yourself
    if (memberRole == 'owner') return; // Can't act on owner

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text('@$handle', style: TextStyle(color: AppTheme.navyBlue, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              if (_myRole == 'owner') ...[
                if (memberRole != 'admin')
                  _ActionTile(
                    icon: Icons.arrow_upward,
                    label: 'Promote to Admin',
                    color: AppTheme.brightNavy,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ApiService.instance.updateMemberRole(widget.groupId, memberId, role: 'admin');
                      _loadMembers();
                    },
                  ),
                if (memberRole == 'admin')
                  _ActionTile(
                    icon: Icons.arrow_downward,
                    label: 'Demote to Member',
                    color: AppTheme.brightNavy,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ApiService.instance.updateMemberRole(widget.groupId, memberId, role: 'member');
                      _loadMembers();
                    },
                  ),
                const SizedBox(height: 4),
              ],
              _ActionTile(
                icon: Icons.person_remove,
                label: 'Remove from Group',
                color: SojornColors.destructive,
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Remove Member'),
                      content: Text('Remove @$handle from this group?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text('Remove', style: TextStyle(color: SojornColors.destructive)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    try {
                      await ApiService.instance.removeGroupMember(widget.groupId, memberId);
                      _loadMembers();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                      }
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'owner': return const Color(0xFFFFA726);
      case 'admin': return AppTheme.brightNavy;
      case 'moderator': return const Color(0xFF4CAF50);
      default: return SojornColors.textDisabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _members.isEmpty
                ? Center(child: Text('No members', style: TextStyle(color: SojornColors.textDisabled)))
                : RefreshIndicator(
                    onRefresh: _loadMembers,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      itemCount: _members.length,
                      itemBuilder: (_, i) {
                        final m = _members[i];
                        final handle = m['handle'] as String? ?? '';
                        final displayName = m['display_name'] as String? ?? handle;
                        final avatarUrl = m['avatar_url'] as String? ?? '';
                        final role = m['role'] as String? ?? 'member';
                        final isMe = m['user_id']?.toString() == _currentUserId;
                        final isOnline = m['is_online'] as bool? ?? false;

                        return ListTile(
                          onLongPress: canManage && !isMe ? () => _showMemberActions(m) : null,
                          onTap: canManage && !isMe ? () => _showMemberActions(m) : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              SojornAvatar(
                                displayName: displayName.isNotEmpty ? displayName : handle,
                                avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                                size: 40,
                              ),
                              // Online indicator dot
                              if (isOnline)
                                Positioned(
                                  right: -1,
                                  bottom: -1,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppTheme.cardSurface, width: 2),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  displayName.isNotEmpty ? displayName : handle,
                                  style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 6),
                                Text('(you)', style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                              ],
                              if (role == 'admin' || role == 'owner') ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _roleColor(role).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    role == 'owner' ? 'OWNER' : 'ADMIN',
                                    style: TextStyle(color: _roleColor(role), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text('@$handle', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
                        );
                      },
                    ),
                  ),
        if (canManage)
          Positioned(
            bottom: 16, right: 16,
            child: FloatingActionButton.small(
              heroTag: 'invite_member',
              onPressed: _showInviteSheet,
              backgroundColor: widget.isEncrypted ? const Color(0xFF4CAF50) : AppTheme.brightNavy,
              child: const Icon(Icons.person_add, color: SojornColors.basicWhite, size: 20),
            ),
          ),
      ],
    );
  }
}

// ── Invite Sheet ─────────────────────────────────────────────────────────
class _InviteSheet extends StatefulWidget {
  final String groupId;
  final VoidCallback onInvited;
  const _InviteSheet({required this.groupId, required this.onInvited});

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  String? _invitingId;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      _results = await ApiService.instance.searchUsersForInvite(widget.groupId, query);
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _invite(String userId) async {
    setState(() => _invitingId = userId);
    try {
      await ApiService.instance.inviteToGroup(widget.groupId, userId: userId);
      widget.onInvited();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invited!')));
        // Remove from results
        setState(() => _results.removeWhere((u) => u['id']?.toString() == userId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
    if (mounted) setState(() => _invitingId = null);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          Text('Invite Members', style: TextStyle(color: AppTheme.navyBlue, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            style: TextStyle(color: SojornColors.postContent, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by handle or name…',
              hintStyle: TextStyle(color: SojornColors.textDisabled),
              prefixIcon: Icon(Icons.search, color: SojornColors.textDisabled, size: 20),
              filled: true, fillColor: AppTheme.scaffoldBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 8),
          if (_searching)
            const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final u = _results[i];
                  final uid = u['id']?.toString() ?? '';
                  final handle = u['handle'] as String? ?? '';
                  final displayName = u['display_name'] as String? ?? handle;
                  final avatarUrl = u['avatar_url'] as String? ?? '';
                  final isInviting = _invitingId == uid;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SojornAvatar(
                      displayName: displayName.isNotEmpty ? displayName : handle,
                      avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                      size: 36,
                    ),
                    title: Text(displayName, style: TextStyle(color: AppTheme.navyBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('@$handle', style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                    trailing: isInviting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(
                            onPressed: () => _invite(uid),
                            child: Text('Invite', style: TextStyle(color: AppTheme.brightNavy, fontWeight: FontWeight.w600)),
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
    );
  }
}
