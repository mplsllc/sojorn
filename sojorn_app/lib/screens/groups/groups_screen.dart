// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/group.dart';
import '../../models/cluster.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/group_discover_card.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/group_creation_modal.dart';
import '../../widgets/desktop/desktop_dialog_helper.dart';
import '../clusters/group_screen.dart';

/// Standalone Groups page — browse, discover, and manage groups.
///
/// Desktop: 2-column (260px sidebar + scrollable main content).
/// Mobile: 2-tab (My Groups / Discover).
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  List<Group> _myGroups = [];
  List<SuggestedGroup> _suggestedGroups = [];
  List<Group> _discoverGroups = [];
  bool _isLoading = true;
  bool _isDiscoverLoading = false;

  GroupCategory? _categoryFilter;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getMyGroups(),
        ApiService.instance.getSuggestedGroups(limit: 6),
        ApiService.instance.listGroups(limit: 50),
      ]);
      if (mounted) {
        setState(() {
          _myGroups = results[0] as List<Group>;
          _suggestedGroups = results[1] as List<SuggestedGroup>;
          _discoverGroups = results[2] as List<Group>;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[GROUPS] Load failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDiscoverGroups() async {
    setState(() => _isDiscoverLoading = true);
    try {
      final groups = await ApiService.instance.listGroups(
        category: _categoryFilter?.value,
        limit: 50,
      );
      if (mounted) setState(() => _discoverGroups = groups);
    } catch (e) {
      if (kDebugMode) debugPrint('[GROUPS] Discover load failed: $e');
    } finally {
      if (mounted) setState(() => _isDiscoverLoading = false);
    }
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = q.trim().toLowerCase());
    });
  }

  List<Group> get _filteredDiscoverGroups {
    var list = _discoverGroups;
    if (_categoryFilter != null) {
      list = list.where((g) => g.category == _categoryFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((g) =>
              g.name.toLowerCase().contains(_searchQuery) ||
              g.description.toLowerCase().contains(_searchQuery))
          .toList();
    }
    return list;
  }

  void _navigateToGroup(Group group) {
    final cluster = Cluster(
      id: group.id,
      name: group.name,
      description: group.description,
      type: group.isPrivate ? 'private_capsule' : 'geo',
      privacy: group.isPrivate ? 'private' : 'public',
      avatarUrl: group.avatarUrl,
      memberCount: group.memberCount,
      isEncrypted: false,
      category: group.category,
      createdAt: group.createdAt,
    );
    openDesktopDialog(
      context,
      width: 800,
      child: GroupScreen(group: cluster),
    );
  }

  void _showCreateGroupModal() {
    showDialog(
      context: context,
      builder: (_) => const Dialog(
        child: GroupCreationModal(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = SojornBreakpoints.isDesktop(width);

    if (isDesktop) return _buildDesktopLayout();
    return _buildMobileLayout();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DESKTOP — 2-column: 260px sidebar + scrollable main
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildDesktopLayout() {
    return Container(
      color: AppTheme.scaffoldBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 260, child: _buildSidebar()),
          Expanded(child: _buildMainContent()),
        ],
      ),
    );
  }

  // ── Sidebar ──────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(
          right: BorderSide(
              color: AppTheme.navyBlue.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Text(
                  'Groups',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navyText,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _showCreateGroupModal,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.royalPurple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(SojornRadii.md)),
                  ),
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.scaffoldBg,
                borderRadius: BorderRadius.circular(SojornRadii.md),
                border: Border.all(
                    color: AppTheme.navyBlue.withValues(alpha: 0.08)),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(fontSize: 14, color: AppTheme.navyText),
                decoration: InputDecoration(
                  hintText: 'Search groups...',
                  hintStyle: TextStyle(
                    color: AppTheme.navyText.withValues(alpha: 0.35),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.search,
                      size: 18,
                      color:
                          AppTheme.navyText.withValues(alpha: 0.35)),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          ),

          // Scrollable body
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMyGroupsSection(),
                const SizedBox(height: 8),
                _buildCategoriesSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyGroupsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'MY GROUPS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: SojornColors.textDisabled,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (_isLoading)
          ...List.generate(3, (_) => _buildSkeletonGroupRow())
        else if (_myGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              children: [
                Icon(Icons.group_add_outlined,
                    size: 32,
                    color: AppTheme.navyText.withValues(alpha: 0.15)),
                const SizedBox(height: 8),
                Text(
                  'Join groups to see them here',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.navyText.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          )
        else
          ..._myGroups.map(_buildMyGroupRow),
      ],
    );
  }

  Widget _buildMyGroupRow(Group group) {
    return InkWell(
      onTap: () => _navigateToGroup(group),
      hoverColor: AppTheme.royalPurple.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SojornAvatar(
              displayName: group.name,
              avatarUrl: group.avatarUrl,
              size: 40,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.navyText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${group.memberCount} members · ${group.userRole?.displayName ?? 'Member'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: SojornColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
            if (group.isPrivate)
              Icon(Icons.lock,
                  size: 14, color: SojornColors.textDisabled),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonGroupRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.navyBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(SojornRadii.card),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: AppTheme.navyBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 11,
                  width: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.navyBlue.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'CATEGORIES',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: SojornColors.textDisabled,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...GroupCategory.values.map((cat) {
          final count = _discoverGroups
              .where((g) => g.category == cat)
              .length;
          final isActive = _categoryFilter == cat;

          return InkWell(
            onTap: () {
              setState(() {
                _categoryFilter = isActive ? null : cat;
              });
              _loadDiscoverGroups();
            },
            hoverColor: AppTheme.royalPurple.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  Icon(cat.icon,
                      size: 18,
                      color: isActive
                          ? AppTheme.royalPurple
                          : cat.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cat.displayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? AppTheme.royalPurple
                            : AppTheme.navyText,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        color: SojornColors.textDisabled,
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Main Content ─────────────────────────────────────────────────────────

  Widget _buildMainContent() {
    if (_isLoading) {
      return const SkeletonGroupList(count: 8);
    }

    final filtered = _filteredDiscoverGroups;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Suggested for You ──
          if (_searchQuery.isEmpty && _categoryFilter == null && _suggestedGroups.isNotEmpty) ...[
            Text(
              'Suggested for you',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.navyText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Groups based on your interests',
              style: TextStyle(
                fontSize: 13,
                color: SojornColors.textDisabled,
              ),
            ),
            const SizedBox(height: 16),
            _buildGroupGrid(
              _suggestedGroups.map((s) => s.group).toList(),
              reasons: {
                for (var s in _suggestedGroups) s.group.id: s.reason,
              },
            ),
            const SizedBox(height: 32),
          ],

          // ── Filter pills ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterPill(null, 'All'),
              ...GroupCategory.values
                  .map((c) => _buildFilterPill(c, c.displayName)),
            ],
          ),
          const SizedBox(height: 20),

          // ── Discover Groups ──
          Text(
            _searchQuery.isNotEmpty
                ? 'Search Results'
                : 'Discover Groups',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.navyText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _searchQuery.isNotEmpty
                ? '${filtered.length} groups found'
                : 'Popular and active groups',
            style: TextStyle(
              fontSize: 13,
              color: SojornColors.textDisabled,
            ),
          ),
          const SizedBox(height: 16),

          if (_isDiscoverLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            _buildEmptyDiscover()
          else
            _buildGroupGrid(filtered),
        ],
      ),
    );
  }

  Widget _buildFilterPill(GroupCategory? cat, String label) {
    final isActive = _categoryFilter == cat;

    return GestureDetector(
      onTap: () {
        setState(() => _categoryFilter = cat);
        if (cat != null) {
          _loadDiscoverGroups();
        } else {
          // "All" — reload without filter
          _loadDiscoverGroups();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.royalPurple : AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: isActive
              ? null
              : Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isActive ? Colors.white : AppTheme.navyText,
          ),
        ),
      ),
    );
  }

  Widget _buildGroupGrid(List<Group> groups,
      {Map<String, String>? reasons}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        const crossAxisCount = 3;
        final cardWidth =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: groups.map((group) {
            return SizedBox(
              width: cardWidth,
              child: GroupDiscoverCard(
                group: group,
                reason: reasons?[group.id],
                onTap: () => _navigateToGroup(group),
                onJoined: _loadInitialData,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEmptyDiscover() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 48,
                color: AppTheme.navyText.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No groups match your search'
                  : _categoryFilter != null
                      ? 'No groups in this category'
                      : 'No groups found',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.navyText.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MOBILE — 2-tab layout
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMobileLayout() {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Groups'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Create Group',
              onPressed: _showCreateGroupModal,
            ),
          ],
          bottom: const TabBar(
            tabs: [Tab(text: 'My Groups'), Tab(text: 'Discover')],
          ),
        ),
        body: TabBarView(
          children: [
            _buildMobileMyGroups(),
            _buildMobileDiscover(),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileMyGroups() {
    if (_isLoading) {
      return const SkeletonGroupList(count: 5);
    }
    if (_myGroups.isEmpty) {
      // Show discover groups inline so the first view isn't empty
      return RefreshIndicator(
        onRefresh: _loadInitialData,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          children: [
            // Small header
            Center(
              child: Column(
                children: [
                  Icon(Icons.group_add_outlined,
                      size: 40,
                      color: AppTheme.navyText.withValues(alpha: 0.15)),
                  const SizedBox(height: 8),
                  Text(
                    'You haven\'t joined any groups yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.navyText.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Suggested groups
            if (_suggestedGroups.isNotEmpty) ...[
              Text(
                'Suggested for you',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navyText,
                ),
              ),
              const SizedBox(height: 12),
              ..._suggestedGroups.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GroupDiscoverCard(
                  group: s.group,
                  reason: s.reason,
                  onTap: () => _navigateToGroup(s.group),
                  onJoined: _loadInitialData,
                ),
              )),
              const SizedBox(height: 8),
            ],
            // Discover groups
            if (_discoverGroups.isNotEmpty) ...[
              Text(
                'Discover Groups',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navyText,
                ),
              ),
              const SizedBox(height: 12),
              ..._discoverGroups.take(10).map((group) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GroupDiscoverCard(
                  group: group,
                  onTap: () => _navigateToGroup(group),
                  onJoined: _loadInitialData,
                ),
              )),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _myGroups.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 64),
        itemBuilder: (_, i) {
          final group = _myGroups[i];
          return ListTile(
            leading: SojornAvatar(
              displayName: group.name,
              avatarUrl: group.avatarUrl,
              size: 40,
            ),
            title: Text(group.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '${group.memberCount} members · ${group.category.displayName}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: group.isPrivate
                ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                : const Icon(Icons.chevron_right, size: 18),
            onTap: () => _navigateToGroup(group),
          );
        },
      ),
    );
  }

  Widget _buildMobileDiscover() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search groups...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
            ),
          ),
        ),

        // Category chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _buildMobileCategoryChip(null, 'All'),
              ...GroupCategory.values
                  .map((c) => _buildMobileCategoryChip(c, c.displayName)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Group cards
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadInitialData,
            child: _filteredDiscoverGroups.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 60),
                      _buildEmptyDiscover(),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: _filteredDiscoverGroups.length,
                    itemBuilder: (_, i) {
                      final group = _filteredDiscoverGroups[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GroupDiscoverCard(
                          group: group,
                          onTap: () => _navigateToGroup(group),
                          onJoined: _loadInitialData,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCategoryChip(GroupCategory? cat, String label) {
    final isActive = _categoryFilter == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? Colors.white : AppTheme.navyText,
          ),
        ),
        selected: isActive,
        selectedColor: AppTheme.royalPurple,
        checkmarkColor: Colors.white,
        onSelected: (_) {
          setState(() => _categoryFilter = isActive ? null : cat);
          _loadDiscoverGroups();
        },
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
