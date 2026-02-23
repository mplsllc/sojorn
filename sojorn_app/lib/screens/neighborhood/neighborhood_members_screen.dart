// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media/sojorn_avatar.dart';

/// Full member list for a neighborhood, backed by the neighborhood's group.
/// Private users are filtered server-side.
class NeighborhoodMembersScreen extends StatefulWidget {
  final String groupId;
  final String neighborhoodName;
  final String? userRole; // 'admin', 'moderator', 'resident'

  const NeighborhoodMembersScreen({
    super.key,
    required this.groupId,
    required this.neighborhoodName,
    this.userRole,
  });

  @override
  State<NeighborhoodMembersScreen> createState() =>
      _NeighborhoodMembersScreenState();
}

class _NeighborhoodMembersScreenState
    extends State<NeighborhoodMembersScreen> {
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String? _currentUserId;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentUserId = AuthService.instance.currentUser?.id;
    _loadMembers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    try {
      _members =
          await ApiService.instance.fetchGroupMembers(widget.groupId);
      _applyFilter();
    } catch (e) {
      debugPrint('[NeighborhoodMembers] Error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = List.from(_members);
    } else {
      _filtered = _members.where((m) {
        final name =
            (m['display_name'] as String? ?? '').toLowerCase();
        final handle = (m['handle'] as String? ?? '').toLowerCase();
        return name.contains(q) || handle.contains(q);
      }).toList();
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'owner':
        return const Color(0xFFFFA726);
      case 'admin':
        return AppTheme.brightNavy;
      case 'moderator':
        return const Color(0xFF4CAF50);
      default:
        return SojornColors.textDisabled;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'ADMIN';
      case 'admin':
        return 'ADMIN';
      case 'moderator':
        return 'MOD';
      default:
        return 'MEMBER';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.neighborhoodName} Members'),
        backgroundColor: AppTheme.cardSurface,
        foregroundColor: AppTheme.navyText,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(SojornSpacing.md),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(
                  color: SojornColors.postContent, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search members...',
                hintStyle: TextStyle(color: SojornColors.textDisabled),
                prefixIcon: Icon(Icons.search,
                    color: SojornColors.textDisabled, size: 20),
                filled: true,
                fillColor: AppTheme.scaffoldBg,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (_) {
                setState(() => _applyFilter());
              },
            ),
          ),

          // Member count
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: SojornSpacing.md),
              child: Row(
                children: [
                  Text(
                    '${_filtered.length} member${_filtered.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: SojornColors.textDisabled,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 4),

          // Member list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text('No members found',
                            style: TextStyle(
                                color: SojornColors.textDisabled)))
                    : RefreshIndicator(
                        onRefresh: _loadMembers,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(
                              12, 4, 12, 80),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final m = _filtered[i];
                            final handle =
                                m['handle'] as String? ?? '';
                            final displayName =
                                m['display_name'] as String? ??
                                    handle;
                            final avatarUrl =
                                m['avatar_url'] as String? ?? '';
                            final role =
                                m['role'] as String? ?? 'member';
                            final isMe =
                                m['user_id']?.toString() ==
                                    _currentUserId;

                            return ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                              leading: SojornAvatar(
                                displayName:
                                    displayName.isNotEmpty
                                        ? displayName
                                        : handle,
                                avatarUrl: avatarUrl.isNotEmpty
                                    ? avatarUrl
                                    : null,
                                size: 40,
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayName.isNotEmpty
                                          ? displayName
                                          : handle,
                                      style: TextStyle(
                                          color: AppTheme.navyBlue,
                                          fontWeight:
                                              FontWeight.w600,
                                          fontSize: 14),
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 6),
                                    Text('(you)',
                                        style: TextStyle(
                                            color: SojornColors
                                                .textDisabled,
                                            fontSize: 11)),
                                  ],
                                ],
                              ),
                              subtitle: Text('@$handle',
                                  style: TextStyle(
                                      color: SojornColors
                                          .textDisabled,
                                      fontSize: 12)),
                              trailing: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3),
                                decoration: BoxDecoration(
                                  color: _roleColor(role)
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _roleLabel(role),
                                  style: TextStyle(
                                      color: _roleColor(role),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
