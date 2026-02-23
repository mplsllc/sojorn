// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../models/group.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/media/sojorn_avatar.dart';

/// Standalone desktop screen for browsing and managing Groups.
///
/// Desktop: 3-column layout (joined groups sidebar | discovery center | group preview).
/// Mobile: single tab showing joined groups + discovery.
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  List<Group> _myGroups = [];
  List<Group> _suggestedGroups = [];
  bool _isLoading = true;
  GroupCategory? _categoryFilter;
  Group? _previewGroup;
  final _searchController = TextEditingController();
  List<Group> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getMyGroups(),
        ApiService.instance.getSuggestedGroups(limit: 20),
      ]);
      if (mounted) {
        setState(() {
          _myGroups = results[0] as List<Group>;
          final suggested = results[1] as List<SuggestedGroup>;
          _suggestedGroups = suggested.map((s) => s.group).toList();
          // Default preview to first joined group
          if (_previewGroup == null && _myGroups.isNotEmpty) {
            _previewGroup = _myGroups.first;
          }
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[GROUPS] Load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _searchGroups(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await ApiService.instance.listGroups(
        category: _categoryFilter?.name,
        limit: 50,
      );
      final lower = q.trim().toLowerCase();
      final filtered = results.where((g) =>
        g.name.toLowerCase().contains(lower) ||
        g.description.toLowerCase().contains(lower)).toList();
      if (mounted) setState(() { _searchResults = filtered; _isSearching = false; });
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _joinGroup(Group group) async {
    try {
      await ApiService.instance.joinGroup(group.id);
      await _loadGroups();
    } catch (e) {
      if (kDebugMode) debugPrint('[GROUPS] Join failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = SojornBreakpoints.isDesktop(width);

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (isDesktop) return _buildDesktopLayout();
    return _buildMobileLayout();
  }

  // ── Desktop 3-column ───────────────────────────────────────────────────────

  Widget _buildDesktopLayout() {
    return Container(
      color: AppTheme.scaffoldBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left sidebar: joined groups ────────────────────
          SizedBox(width: 260, child: _buildJoinedGroupsSidebar()),
          // ── Center: discovery browser ──────────────────────
          Expanded(child: _buildDiscoveryCenter()),
          // ── Right sidebar: group preview ───────────────────
          SizedBox(width: 280, child: _buildGroupPreviewSidebar()),
        ],
      ),
    );
  }

  Widget _buildJoinedGroupsSidebar() {
    final filtered = _categoryFilter == null
        ? _myGroups
        : _myGroups.where((g) => g.category == _categoryFilter).toList();

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(
              bottom: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.group, color: AppTheme.brightNavy, size: 18),
              const SizedBox(width: 8),
              const Text('My Groups',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.add, size: 18, color: AppTheme.brightNavy),
                tooltip: 'Create Group',
                onPressed: () => context.push('/clusters'),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
        // Category filter chips (compact)
        _buildSidebarCategoryChips(),
        // Group list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_add_outlined,
                          size: 36, color: AppTheme.navyText.withValues(alpha: 0.2)),
                      const SizedBox(height: 8),
                      Text('No groups yet',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.navyText.withValues(alpha: 0.4))),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _buildMyGroupTile(filtered[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildSidebarCategoryChips() {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _buildCatChip(null, 'All'),
          ...GroupCategory.values.map((c) => _buildCatChip(c, c.displayName)),
        ],
      ),
    );
  }

  Widget _buildCatChip(GroupCategory? cat, String label) {
    final isSelected = _categoryFilter == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
        selected: isSelected,
        onSelected: (_) => setState(() => _categoryFilter = cat),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _buildMyGroupTile(Group group) {
    final isSelected = _previewGroup?.id == group.id;
    return InkWell(
      onTap: () => setState(() => _previewGroup = group),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: isSelected ? AppTheme.royalPurple.withValues(alpha: 0.08) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SojornAvatar(
              displayName: group.name,
              avatarUrl: group.avatarUrl,
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? AppTheme.royalPurple : AppTheme.navyText)),
                  Row(
                    children: [
                      Icon(group.category.icon, size: 10, color: group.category.color),
                      const SizedBox(width: 4),
                      Text(group.category.displayName,
                          style: TextStyle(fontSize: 10, color: SojornColors.textDisabled)),
                      const SizedBox(width: 6),
                      Text('${group.memberCount}',
                          style: TextStyle(fontSize: 10, color: SojornColors.textDisabled)),
                      Icon(Icons.person, size: 9, color: SojornColors.textDisabled),
                    ],
                  ),
                ],
              ),
            ),
            if (group.isPrivate)
              Icon(Icons.lock, size: 12, color: SojornColors.textDisabled),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryCenter() {
    final displayList = _searchController.text.isNotEmpty ? _searchResults : _suggestedGroups;
    final filtered = _categoryFilter == null
        ? displayList
        : displayList.where((g) => g.category == _categoryFilter).toList();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search groups...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchResults = []);
                      })
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onSubmitted: _searchGroups,
            onChanged: (q) {
              setState(() {});
              if (q.trim().isEmpty) setState(() => _searchResults = []);
            },
          ),
        ),
        // Section heading
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Text(
                _searchController.text.isNotEmpty ? 'Search Results' : 'Suggested for You',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navyText.withValues(alpha: 0.6)),
              ),
              const Spacer(),
              if (_isSearching)
                SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.royalPurple)),
            ],
          ),
        ),
        // Group grid
        Expanded(
          child: filtered.isEmpty && !_isSearching
              ? Center(
                  child: Text('No groups found',
                      style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.4))),
                )
              : RefreshIndicator(
                  onRefresh: _loadGroups,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.5,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) => _buildGroupCard(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildGroupCard(Group group) {
    final isMember = group.isMember || _myGroups.any((g) => g.id == group.id);
    return GestureDetector(
      onTap: () => setState(() => _previewGroup = group),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(SojornRadii.card),
          border: Border.all(
            color: _previewGroup?.id == group.id
                ? AppTheme.royalPurple.withValues(alpha: 0.4)
                : AppTheme.navyBlue.withValues(alpha: 0.08),
            width: _previewGroup?.id == group.id ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SojornAvatar(displayName: group.name, avatarUrl: group.avatarUrl, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                if (group.isPrivate)
                  Icon(Icons.lock, size: 12, color: SojornColors.textDisabled),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(group.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.6), height: 1.3)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(group.category.icon, size: 11, color: group.category.color),
                const SizedBox(width: 4),
                Text('${group.memberCount}',
                    style: TextStyle(fontSize: 10, color: SojornColors.textDisabled)),
                const Icon(Icons.person, size: 10),
                const Spacer(),
                if (!isMember && !group.hasPendingRequest)
                  GestureDetector(
                    onTap: () => _joinGroup(group),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.royalPurple,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Join',
                          style: TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  )
                else if (group.hasPendingRequest)
                  Text('Pending',
                      style: TextStyle(fontSize: 10, color: SojornColors.textDisabled))
                else
                  Icon(Icons.check_circle, size: 14, color: AppTheme.brightNavy),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupPreviewSidebar() {
    final group = _previewGroup;
    if (group == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined,
                size: 36, color: AppTheme.navyText.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            Text('Select a group to preview',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.4))),
          ],
        ),
      );
    }
    final isMember = group.isMember || _myGroups.any((g) => g.id == group.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner/avatar
          if (group.bannerUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(SojornRadii.card),
              child: Image.network(group.bannerUrl!,
                  height: 90, width: double.infinity, fit: BoxFit.cover),
            )
          else
            Container(
              height: 70,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [group.category.color.withValues(alpha: 0.3), group.category.color.withValues(alpha: 0.1)],
                ),
                borderRadius: BorderRadius.circular(SojornRadii.card),
              ),
              child: Center(
                  child: Icon(group.category.icon, size: 30, color: group.category.color)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              SojornAvatar(displayName: group.name, avatarUrl: group.avatarUrl, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        Icon(group.category.icon, size: 11, color: group.category.color),
                        const SizedBox(width: 4),
                        Text(group.category.displayName,
                            style: TextStyle(fontSize: 11, color: group.category.color,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Description
          if (group.description.isNotEmpty)
            Text(group.description,
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.navyText.withValues(alpha: 0.7),
                    height: 1.4)),
          const SizedBox(height: 12),
          // Stats row
          Row(
            children: [
              _buildPreviewStat('${group.memberCount}', 'Members'),
              const SizedBox(width: 16),
              _buildPreviewStat('${group.postCount}', 'Posts'),
              if (group.isPrivate) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 10, color: SojornColors.textDisabled),
                      const SizedBox(width: 3),
                      Text('Private',
                          style: TextStyle(fontSize: 10, color: SojornColors.textDisabled)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: isMember
                      ? () => context.push('/clusters')
                      : (group.hasPendingRequest ? null : () => _joinGroup(group)),
                  style: FilledButton.styleFrom(
                    backgroundColor: isMember ? AppTheme.brightNavy : AppTheme.royalPurple,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    isMember
                        ? 'Open'
                        : group.hasPendingRequest
                            ? 'Pending'
                            : 'Join',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (isMember) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 14, color: AppTheme.navyBlue),
                    const SizedBox(width: 6),
                    const Text('Group Chat', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyText)),
        Text(label,
            style: TextStyle(fontSize: 10, color: AppTheme.navyText.withValues(alpha: 0.5))),
      ],
    );
  }

  // ── Mobile single-column ──────────────────────────────────────────────────

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Groups'),
          bottom: const TabBar(
            tabs: [Tab(text: 'My Groups'), Tab(text: 'Discover')],
          ),
        ),
        body: TabBarView(
          children: [
            // My groups list
            _myGroups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group_add, size: 48,
                            color: AppTheme.navyText.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text('No groups yet',
                            style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.4))),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadGroups,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _myGroups.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                      itemBuilder: (context, i) => _buildMyGroupListTile(_myGroups[i]),
                    ),
                  ),
            // Discover
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search groups...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    onSubmitted: _searchGroups,
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadGroups,
                    child: ListView.separated(
                      itemCount: _suggestedGroups.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                      itemBuilder: (context, i) => _buildDiscoverListTile(_suggestedGroups[i]),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyGroupListTile(Group group) {
    return ListTile(
      leading: SojornAvatar(displayName: group.name, avatarUrl: group.avatarUrl, size: 40),
      title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${group.memberCount} members · ${group.category.displayName}',
          style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => context.push('/clusters'),
    );
  }

  Widget _buildDiscoverListTile(Group group) {
    final isMember = _myGroups.any((g) => g.id == group.id);
    return ListTile(
      leading: SojornAvatar(displayName: group.name, avatarUrl: group.avatarUrl, size: 40),
      title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${group.memberCount} members · ${group.category.displayName}',
          style: const TextStyle(fontSize: 12)),
      trailing: isMember
          ? Icon(Icons.check_circle, color: AppTheme.brightNavy)
          : FilledButton(
              onPressed: () => _joinGroup(group),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.royalPurple,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                minimumSize: const Size(0, 32),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Join', style: TextStyle(fontSize: 12)),
            ),
      onTap: () => context.push('/clusters'),
    );
  }
}
