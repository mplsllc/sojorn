// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cluster.dart';
import '../../models/group.dart' as group_models;
import '../../providers/api_provider.dart';
import '../../services/api_service.dart';
import '../../services/capsule_security_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import 'group_screen.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/group_creation_modal.dart';
import '../../widgets/desktop/desktop_dialog_helper.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/media/signed_media_image.dart';

/// ClustersScreen — HumHub-inspired groups directory.
class ClustersScreen extends ConsumerStatefulWidget {
  const ClustersScreen({super.key});

  @override
  ConsumerState<ClustersScreen> createState() => _ClustersScreenState();
}

class _ClustersScreenState extends ConsumerState<ClustersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isDiscoverLoading = false;
  List<Cluster> _myCapsules = [];
  List<Map<String, dynamic>> _discoverGroups = [];
  Map<String, String> _encryptedKeys = {};
  String _selectedCategory = 'all';
  String _searchQuery = '';
  Timer? _searchDebounce;

  // Groups system state
  List<group_models.Group> _myUserGroups = [];
  List<group_models.SuggestedGroup> _suggestedGroups = [];

  final _searchController = TextEditingController();

  static const _categories = [
    ('all', 'All', Icons.grid_view),
    ('general', 'General', Icons.chat_bubble_outline),
    ('hobby', 'Hobby', Icons.palette),
    ('sports', 'Sports', Icons.sports),
    ('professional', 'Professional', Icons.business_center),
    ('local_business', 'Local', Icons.storefront),
    ('support', 'Support', Icons.favorite),
    ('education', 'Education', Icons.school),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadMyGroups(),
      _loadDiscover(),
      _loadUserGroups(),
      _loadSuggestedGroups(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMyGroups() async {
    try {
      final groups = await ApiService.instance.fetchMyGroups();
      final allClusters = groups.map((g) => Cluster.fromJson(g)).toList();
      if (mounted) {
        setState(() {
          _myCapsules = allClusters.where((c) => c.isCapsule).toList();
          _encryptedKeys = {
            for (final g in groups)
              if ((g['encrypted_group_key'] as String?)?.isNotEmpty == true)
                g['id'] as String: g['encrypted_group_key'] as String,
          };
        });
      }
    } catch (e) {
      if (kDebugMode) print('[Clusters] Load error: $e');
    }
  }

  Future<void> _loadDiscover() async {
    setState(() => _isDiscoverLoading = true);
    try {
      final groups = await ApiService.instance.discoverGroups(
        category: _selectedCategory == 'all' ? null : _selectedCategory,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (mounted) setState(() => _discoverGroups = groups);
    } catch (e) {
      if (kDebugMode) print('[Clusters] Discover error: $e');
    }
    if (mounted) setState(() => _isDiscoverLoading = false);
  }

  Future<void> _loadUserGroups() async {
    try {
      final api = ref.read(apiServiceProvider);
      final groups = await api.getMyGroups();
      if (mounted) setState(() => _myUserGroups = groups);
    } catch (e) {
      if (kDebugMode) print('[Groups] Load user groups error: $e');
    }
  }

  Future<void> _loadSuggestedGroups() async {
    try {
      final api = ref.read(apiServiceProvider);
      final suggestions = await api.getSuggestedGroups();
      if (mounted) setState(() => _suggestedGroups = suggestions);
    } catch (e) {
      if (kDebugMode) print('[Groups] Load suggestions error: $e');
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _searchQuery = value.trim());
      _loadDiscover();
    });
  }

  void _navigateToCluster(Cluster cluster) {
    openDesktopDialog(
      context,
      width: 800,
      child: GroupScreen(
        group: cluster,
        encryptedGroupKey: _encryptedKeys[cluster.id],
      ),
    );
  }

  void _navigateToGroup(group_models.Group group) {
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    final tabBar = TabBar(
      controller: _tabController,
      indicatorColor: AppTheme.brightNavy,
      labelColor: AppTheme.navyText,
      unselectedLabelColor: AppTheme.navyText.withValues(alpha: 0.4),
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      tabs: const [
        Tab(text: 'Groups'),
        Tab(text: 'Encrypted'),
      ],
    );

    final body = TabBarView(
      controller: _tabController,
      children: [
        _buildGroupsTab(),
        _buildCapsuleTab(),
      ],
    );

    if (isDesktop) {
      return Column(
        children: [
          Container(
            color: AppTheme.scaffoldBg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Communities',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
                const Spacer(),
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: () => _showCreateSheet(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Create', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brightNavy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SojornRadii.md)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          tabBar,
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Communities',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: AppTheme.scaffoldBg,
        surfaceTintColor: Colors.transparent,
        bottom: tabBar,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateSheet(context),
            tooltip: 'Create Group',
          ),
        ],
      ),
      body: body,
    );
  }

  // ── Groups Tab ────────────────────────────────────────────────────────
  Widget _buildGroupsTab() {
    if (_isLoading) {
      return const SingleChildScrollView(child: SkeletonGroupList(count: 6));
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── Search Bar ──
          _buildSearchBar(),
          const SizedBox(height: 16),

          // ── Your Groups ──
          if (_myUserGroups.isNotEmpty && _searchQuery.isEmpty) ...[
            _SectionHeader(title: 'Your Groups', count: _myUserGroups.length),
            const SizedBox(height: 10),
            SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _myUserGroups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final group = _myUserGroups[i];
                  return _MyGroupCard(
                    group: group,
                    onTap: () => _navigateToGroup(group),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Suggested for You ──
          if (_suggestedGroups.isNotEmpty && _searchQuery.isEmpty) ...[
            const _SectionHeader(title: 'Suggested for You'),
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _suggestedGroups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final sg = _suggestedGroups[i];
                  return _SuggestedGroupCard(
                    group: sg.group,
                    reason: sg.reason,
                    onTap: () => _navigateToGroup(sg.group),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Browse / Search Results ──
          _SectionHeader(
            title: _searchQuery.isNotEmpty ? 'Search Results' : 'Browse Communities',
            count: _discoverGroups.isNotEmpty ? _discoverGroups.length : null,
          ),
          const SizedBox(height: 10),

          // Category chips
          if (_searchQuery.isEmpty) ...[
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final (value, label, icon) = _categories[i];
                  final selected = _selectedCategory == value;
                  return FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14,
                            color: selected ? Colors.white : AppTheme.brightNavy),
                        const SizedBox(width: 5),
                        Text(label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : AppTheme.brightNavy,
                            )),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedCategory = value);
                      _loadDiscover();
                    },
                    selectedColor: AppTheme.brightNavy,
                    backgroundColor: AppTheme.brightNavy.withValues(alpha: 0.06),
                    side: BorderSide(
                        color: selected
                            ? AppTheme.brightNavy
                            : AppTheme.brightNavy.withValues(alpha: 0.15)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Results
          if (_isDiscoverLoading)
            const SkeletonGroupList(count: 4)
          else if (_discoverGroups.isEmpty)
            _EmptyDiscoverState(
              isSearch: _searchQuery.isNotEmpty,
              onCreateGroup: () => _showCreateSheet(context),
            )
          else
            ..._discoverGroups.map((g) {
              final group = group_models.Group.fromJson(g);
              return _BrowseGroupCard(
                group: group,
                onTap: () => _navigateToGroup(group),
              );
            }),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.lg),
        border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(fontSize: 14, color: AppTheme.navyText),
        decoration: InputDecoration(
          hintText: 'Search communities...',
          hintStyle: TextStyle(
              color: AppTheme.navyText.withValues(alpha: 0.35), fontSize: 14),
          prefixIcon:
              Icon(Icons.search, color: AppTheme.navyText.withValues(alpha: 0.3), size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close,
                      size: 18, color: AppTheme.navyText.withValues(alpha: 0.4)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _loadDiscover();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  // ── Capsules Tab ──────────────────────────────────────────────────────
  Widget _buildCapsuleTab() {
    if (_isLoading) {
      return const SingleChildScrollView(child: SkeletonGroupList(count: 4));
    }
    if (_myCapsules.isEmpty) {
      return _EmptyState(
        icon: Icons.lock,
        title: 'No Capsules Yet',
        subtitle:
            'Create an encrypted capsule or join one via invite code.',
        actionLabel: 'Create Capsule',
        onAction: () => _showCreateSheet(context, capsule: true),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _myCapsules.length,
        itemBuilder: (_, i) => _CapsuleCard(
          capsule: _myCapsules[i],
          onTap: () => _navigateToCluster(_myCapsules[i]),
        ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context, {bool capsule = false}) {
    if (capsule) {
      showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.cardSurface,
        isScrollControlled: true,
        builder: (ctx) => _CreateCapsuleForm(
            onCreated: () {
              Navigator.pop(ctx);
              _loadAll();
            }),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => GroupCreationModal(),
      ).then((_) => _loadAll());
    }
  }
}

// ─── My Group Card (horizontal scroll) ──────────────────────────────────────

class _MyGroupCard extends StatelessWidget {
  final group_models.Group group;
  final VoidCallback onTap;
  const _MyGroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(SojornRadii.card),
          border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Banner or gradient strip
            Container(
              height: 48,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SojornRadii.md),
                gradient: LinearGradient(
                  colors: [
                    group.category.color.withValues(alpha: 0.3),
                    group.category.color.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: group.bannerUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(SojornRadii.md),
                      child: SignedMediaImage(
                          url: group.bannerUrl!, fit: BoxFit.cover),
                    )
                  : Center(
                      child: Icon(group.category.icon,
                          size: 20, color: group.category.color)),
            ),
            const SizedBox(height: 10),
            SojornAvatar(
              displayName: group.name,
              avatarUrl: group.avatarUrl,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              group.name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navyText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 3),
            Text(
              group.memberCountText,
              style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.navyText.withValues(alpha: 0.4)),
            ),
            if (group.userRole != null) ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.brightNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  group.userRole!.displayName,
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.brightNavy),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Suggested Group Card (horizontal scroll) ───────────────────────────────

class _SuggestedGroupCard extends ConsumerStatefulWidget {
  final group_models.Group group;
  final String reason;
  final VoidCallback onTap;
  const _SuggestedGroupCard(
      {required this.group, required this.reason, required this.onTap});

  @override
  ConsumerState<_SuggestedGroupCard> createState() =>
      _SuggestedGroupCardState();
}

class _SuggestedGroupCardState extends ConsumerState<_SuggestedGroupCard> {
  bool _joining = false;

  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.joinGroup(widget.group.id);
    } catch (_) {}
    if (mounted) setState(() => _joining = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(SojornRadii.card),
          border:
              Border.all(color: AppTheme.navyText.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SojornAvatar(
                  displayName: widget.group.name,
                  avatarUrl: widget.group.avatarUrl,
                  size: 44,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.group.name,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.navyText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: widget.group.category.color
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.group.category.displayName,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: widget.group.category.color),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.group.description.isNotEmpty)
              Text(
                widget.group.description,
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.navyText.withValues(alpha: 0.6),
                    height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const Spacer(),
            // Reason chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.royalPurple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome,
                      size: 12, color: AppTheme.royalPurple),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      widget.reason,
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.royalPurple,
                          fontStyle: FontStyle.italic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Stats + Join
            Row(
              children: [
                Text(
                  widget.group.memberCountText,
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.navyText.withValues(alpha: 0.4)),
                ),
                const Spacer(),
                if (widget.group.isMember)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('Joined',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.green)),
                  )
                else
                  SizedBox(
                    height: 30,
                    child: ElevatedButton(
                      onPressed: _joining ? null : _join,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.brightNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        elevation: 0,
                      ),
                      child: _joining
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Join',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Browse Group Card (vertical list, rich) ────────────────────────────────

class _BrowseGroupCard extends ConsumerStatefulWidget {
  final group_models.Group group;
  final VoidCallback onTap;
  const _BrowseGroupCard({required this.group, required this.onTap});

  @override
  ConsumerState<_BrowseGroupCard> createState() => _BrowseGroupCardState();
}

class _BrowseGroupCardState extends ConsumerState<_BrowseGroupCard> {
  bool _joining = false;

  Future<void> _join() async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.joinGroup(widget.group.id);
    } catch (_) {}
    if (mounted) setState(() => _joining = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(SojornRadii.card),
          border: Border.all(color: AppTheme.navyText.withValues(alpha: 0.06)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner / gradient header
            Container(
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    g.category.color.withValues(alpha: 0.25),
                    g.category.color.withValues(alpha: 0.08),
                  ],
                ),
              ),
              child: g.bannerUrl != null
                  ? SignedMediaImage(
                      url: g.bannerUrl!, fit: BoxFit.cover, width: double.infinity)
                  : null,
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar overlapping banner
                  Transform.translate(
                    offset: const Offset(0, -28),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.cardSurface, width: 3),
                      ),
                      child: SojornAvatar(
                        displayName: g.name,
                        avatarUrl: g.avatarUrl,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(g.name,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.navyText),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (g.isPrivate)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(Icons.lock,
                                    size: 14,
                                    color:
                                        AppTheme.navyText.withValues(alpha: 0.3)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (g.description.isNotEmpty) ...[
                          Text(g.description,
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      AppTheme.navyText.withValues(alpha: 0.55),
                                  height: 1.3),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                        ],
                        // Stats row
                        Row(
                          children: [
                            Icon(Icons.people_outline,
                                size: 13,
                                color:
                                    AppTheme.navyText.withValues(alpha: 0.35)),
                            const SizedBox(width: 3),
                            Text(g.memberCountText,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.navyText
                                        .withValues(alpha: 0.4))),
                            const SizedBox(width: 10),
                            Text('${g.postCount} posts',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.navyText
                                        .withValues(alpha: 0.4))),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: g.category.color
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(g.category.displayName,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: g.category.color)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Join button
                  if (g.isMember)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text('Joined',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green)),
                    )
                  else if (g.hasPendingRequest)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text('Pending',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.deepOrange)),
                    )
                  else
                    SizedBox(
                      height: 32,
                      child: ElevatedButton(
                        onPressed: _joining ? null : _join,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.brightNavy,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          elevation: 0,
                        ),
                        child: _joining
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Text(g.isPrivate ? 'Request' : 'Join',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  const _SectionHeader({required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.navyText,
            )),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.brightNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.brightNavy,
                )),
          ),
        ],
      ],
    );
  }
}

// ─── Empty States ───────────────────────────────────────────────────────────

class _EmptyDiscoverState extends StatelessWidget {
  final bool isSearch;
  final VoidCallback onCreateGroup;
  const _EmptyDiscoverState(
      {this.isSearch = false, required this.onCreateGroup});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
              isSearch ? Icons.search_off : Icons.explore_outlined,
              size: 48,
              color: AppTheme.navyText.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            isSearch
                ? 'No groups match your search'
                : 'No groups found in this category',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.navyText.withValues(alpha: 0.5)),
          ),
          if (!isSearch) ...[
            const SizedBox(height: 4),
            Text('Be the first to create one!',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.navyText.withValues(alpha: 0.35))),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onCreateGroup,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Create Group'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: AppTheme.brightNavy.withValues(alpha: 0.3)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 56, color: AppTheme.navyText.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navyText.withValues(alpha: 0.6))),
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.navyText.withValues(alpha: 0.4)),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: AppTheme.navyText.withValues(alpha: 0.3)),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Capsule Card ───────────────────────────────────────────────────────────

class _CapsuleCard extends StatelessWidget {
  final Cluster capsule;
  final VoidCallback onTap;
  const _CapsuleCard({required this.capsule, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F8F0),
          borderRadius: BorderRadius.circular(SojornRadii.card),
          border: Border.all(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.lock,
                  color: Color(0xFF4CAF50), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(capsule.name,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.navyText)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.shield,
                          size: 12,
                          color: const Color(0xFF4CAF50)
                              .withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text('E2E Encrypted',
                          style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFF4CAF50)
                                  .withValues(alpha: 0.7))),
                      const SizedBox(width: 10),
                      Icon(Icons.people,
                          size: 12,
                          color: AppTheme.navyText.withValues(alpha: 0.35)),
                      const SizedBox(width: 4),
                      Text('${capsule.memberCount}',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.navyText
                                  .withValues(alpha: 0.4))),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppTheme.navyText.withValues(alpha: 0.3), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Create Capsule Form ────────────────────────────────────────────────────

class _CreateCapsuleForm extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateCapsuleForm({required this.onCreated});

  @override
  State<_CreateCapsuleForm> createState() => _CreateCapsuleFormState();
}

class _CreateCapsuleFormState extends State<_CreateCapsuleForm> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _submitting = false;
  String? _statusMsg;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() {
      _submitting = true;
      _statusMsg = 'Generating encryption keys...';
    });
    try {
      final capsuleKey =
          await CapsuleSecurityService.generateCapsuleKey();
      final publicKeyB64 =
          await CapsuleSecurityService.getUserPublicKeyB64();

      setState(() => _statusMsg = 'Encrypting group key...');

      final encryptedGroupKey =
          await CapsuleSecurityService.encryptCapsuleKeyForUser(
        capsuleKey: capsuleKey,
        recipientPublicKeyB64: publicKeyB64,
      );

      setState(() => _statusMsg = 'Creating capsule...');

      final result = await ApiService.instance.createCapsule(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        publicKey: publicKeyB64,
        encryptedGroupKey: encryptedGroupKey,
      );

      final capsuleId =
          (result['capsule'] as Map<String, dynamic>?)?['id']?.toString();
      if (capsuleId != null) {
        await CapsuleSecurityService.cacheCapsuleKey(
            capsuleId, capsuleKey);
      }

      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create capsule: $e')),
        );
      }
    }
    if (mounted) {
      setState(() {
        _submitting = false;
        _statusMsg = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.navyText.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.lock, color: Color(0xFF4CAF50), size: 20),
              const SizedBox(width: 8),
              Text('Create Private Capsule',
                  style: TextStyle(
                      color: AppTheme.navyText,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              'End-to-end encrypted. The server never sees your content.',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.navyText.withValues(alpha: 0.4))),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: AppTheme.navyText),
            decoration: InputDecoration(
              labelText: 'Capsule name',
              labelStyle: TextStyle(
                  color: AppTheme.navyText.withValues(alpha: 0.4)),
              filled: true,
              fillColor: AppTheme.scaffoldBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            style: TextStyle(color: AppTheme.navyText),
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              labelStyle: TextStyle(
                  color: AppTheme.navyText.withValues(alpha: 0.4)),
              filled: true,
              fillColor: AppTheme.scaffoldBg,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield,
                    size: 14,
                    color:
                        const Color(0xFF4CAF50).withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                  'Keys are generated on your device. Only invited members can decrypt content.',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.navyText.withValues(alpha: 0.5)),
                )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFF4CAF50).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 10),
                          Text(_statusMsg ?? 'Creating...',
                              style: const TextStyle(fontSize: 13)),
                        ])
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          Icon(Icons.lock, size: 16),
                          SizedBox(width: 8),
                          Text('Generate Keys & Create',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ]),
            ),
          ),
        ],
      ),
    );
  }
}
