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
import '../../widgets/group_card.dart';
import '../../widgets/group_creation_modal.dart';

/// ClustersScreen — Discovery-first groups page.
/// Shows "Your Groups" at top, then "Discover Communities" with category filtering.
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
  List<Cluster> _myGroups = [];
  List<Cluster> _myCapsules = [];
  List<Map<String, dynamic>> _discoverGroups = [];
  Map<String, String> _encryptedKeys = {};
  String _selectedCategory = 'all';
  
  // Groups system state
  List<group_models.Group> _myUserGroups = [];
  List<group_models.SuggestedGroup> _suggestedGroups = [];
  bool _isGroupsLoading = false;
  bool _isSuggestedLoading = false;

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
          _myGroups = allClusters.where((c) => !c.isCapsule).toList();
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
      );
      if (mounted) setState(() => _discoverGroups = groups);
    } catch (e) {
      if (kDebugMode) print('[Clusters] Discover error: $e');
    }
    if (mounted) setState(() => _isDiscoverLoading = false);
  }

  Future<void> _joinGroup(String groupId) async {
    try {
      await ApiService.instance.joinGroup(groupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined group!'), backgroundColor: Color(0xFF4CAF50)),
        );
      }
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _navigateToCluster(Cluster cluster) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GroupScreen(
        group: cluster,
        encryptedGroupKey: _encryptedKeys[cluster.id],
      ),
    ));
  }

  // Groups system methods
  Future<void> _loadUserGroups() async {
    setState(() => _isGroupsLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final groups = await api.getMyGroups();
      if (mounted) setState(() => _myUserGroups = groups);
    } catch (e) {
      if (kDebugMode) print('[Groups] Load user groups error: $e');
    }
    if (mounted) setState(() => _isGroupsLoading = false);
  }

  Future<void> _loadSuggestedGroups() async {
    setState(() => _isSuggestedLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final suggestions = await api.getSuggestedGroups();
      if (mounted) setState(() => _suggestedGroups = suggestions);
    } catch (e) {
      if (kDebugMode) print('[Groups] Load suggestions error: $e');
    }
    if (mounted) setState(() => _isSuggestedLoading = false);
  }

  void _navigateToGroup(group_models.Group group) {
    // TODO: Navigate to group detail screen
    if (kDebugMode) print('Navigate to group: ${group.name}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Communities', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: AppTheme.scaffoldBg,
        surfaceTintColor: SojornColors.transparent,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.navyBlue,
          labelColor: AppTheme.navyBlue,
          unselectedLabelColor: SojornColors.textDisabled,
          tabs: const [
            Tab(text: 'Groups'),
            Tab(text: 'Encrypted'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateSheet(context),
            tooltip: 'Create Group',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGroupsTab(),
          _buildCapsuleTab(),
        ],
      ),
    );
  }

  // ── Groups Tab (Your Groups + Discover) ──────────────────────────────
  Widget _buildGroupsTab() {
    if (_isLoading) return const SingleChildScrollView(child: SkeletonGroupList(count: 6));
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        children: [
          // ── Your Groups ──
          if (_myUserGroups.isNotEmpty) ...[
            _SectionHeader(title: 'Your Groups', count: _myUserGroups.length),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _myUserGroups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final group = _myUserGroups[i];
                  return CompactGroupCard(
                    group: group,
                    onTap: () => _navigateToGroup(group),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Discover Communities ──
          _SectionHeader(title: 'Discover Communities'),
          const SizedBox(height: 10),

          // Category chips (horizontal scroll)
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
                      Icon(icon, size: 14, color: selected ? Colors.white : AppTheme.navyBlue),
                      const SizedBox(width: 5),
                      Text(label, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppTheme.navyBlue,
                      )),
                    ],
                  ),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedCategory = value);
                    _loadSuggestedGroups();
                  },
                  selectedColor: AppTheme.navyBlue,
                  backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.06),
                  side: BorderSide(color: selected ? AppTheme.navyBlue : AppTheme.navyBlue.withValues(alpha: 0.15)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Discover results
          if (_isSuggestedLoading)
            const SkeletonGroupList(count: 4)
          else if (_suggestedGroups.isEmpty)
            _EmptyDiscoverState(
              onCreateGroup: () => _showCreateSheet(context),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                ..._suggestedGroups.map((suggested) {
                  return GroupCard(
                    group: suggested.group,
                    onTap: () => _navigateToGroup(suggested.group),
                    showReason: true,
                    reason: suggested.reason,
                  );
                }),
                const SizedBox(height: 20),
              ],
            ),

          // Create group CTA at bottom
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => _showCreateSheet(context),
              icon: Icon(Icons.add_circle_outline, size: 18, color: AppTheme.navyBlue),
              label: Text('Create a Group', style: TextStyle(
                color: AppTheme.navyBlue, fontWeight: FontWeight.w600,
              )),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Capsules Tab ─────────────────────────────────────────────────────
  Widget _buildCapsuleTab() {
    if (_isLoading) return const SingleChildScrollView(child: SkeletonGroupList(count: 4));
    if (_myCapsules.isEmpty) return _EmptyState(
      icon: Icons.lock,
      title: 'No Capsules Yet',
      subtitle: 'Create an encrypted capsule or join one via invite code.',
      actionLabel: 'Create Capsule',
      onAction: () => _showCreateSheet(context, capsule: true),
    );
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
      // Keep existing capsule creation
      showModalBottomSheet(
        context: context,
        backgroundColor: AppTheme.cardSurface,
        isScrollControlled: true,
        builder: (ctx) => _CreateCapsuleForm(onCreated: () { Navigator.pop(ctx); _loadAll(); }),
      );
    } else {
      // Use new GroupCreationModal
      showDialog(
        context: context,
        builder: (ctx) => GroupCreationModal(),
      ).then((_) {
        // Refresh data after modal is closed
        _loadAll();
      });
    }
  }
}

// ── Section Header ────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final int? count;
  const _SectionHeader({required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.navyBlue,
        )),
        if (count != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.navyBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.navyBlue,
            )),
          ),
        ],
      ],
    );
  }
}

// ── Empty Discover State ──────────────────────────────────────────────────
class _EmptyDiscoverState extends StatelessWidget {
  final VoidCallback onCreateGroup;
  const _EmptyDiscoverState({required this.onCreateGroup});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.explore_outlined, size: 48, color: AppTheme.navyBlue.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text('No groups found in this category', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600,
            color: AppTheme.navyBlue.withValues(alpha: 0.5),
          )),
          const SizedBox(height: 4),
          Text('Be the first to create one!', style: TextStyle(
            fontSize: 12, color: AppTheme.navyBlue.withValues(alpha: 0.35),
          )),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onCreateGroup,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Create Group'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.3)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty State (for capsules) ────────────────────────────────────────────
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
            Icon(icon, size: 56, color: AppTheme.navyBlue.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700,
              color: AppTheme.navyBlue.withValues(alpha: 0.6),
            )),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(
              fontSize: 13, color: AppTheme.navyBlue.withValues(alpha: 0.4),
            ), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: onAction,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.3)),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Group Card (user's own groups) ────────────────────────────────────────
class _GroupCard extends StatelessWidget {
  final Cluster cluster;
  final VoidCallback onTap;
  const _GroupCard({required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat = cluster.category;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.brightNavy.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(cat.icon, color: cat.color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cluster.name, style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                  )),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.people, size: 12, color: SojornColors.textDisabled),
                      const SizedBox(width: 4),
                      Text('${cluster.memberCount} members', style: TextStyle(fontSize: 11, color: SojornColors.textDisabled)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: SojornColors.textDisabled, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Discover Group Card (with Join button) ────────────────────────────────
class _DiscoverGroupCard extends StatelessWidget {
  final String name;
  final String description;
  final int memberCount;
  final GroupCategory category;
  final bool isMember;
  final VoidCallback? onJoin;
  final VoidCallback? onTap;

  const _DiscoverGroupCard({
    required this.name,
    required this.description,
    required this.memberCount,
    required this.category,
    required this.isMember,
    this.onJoin,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.brightNavy.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: category.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(category.icon, color: category.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                  ), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(description, style: TextStyle(
                      fontSize: 12, color: SojornColors.textDisabled,
                    ), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.people_outline, size: 12, color: SojornColors.textDisabled),
                      const SizedBox(width: 3),
                      Text('$memberCount', style: TextStyle(fontSize: 11, color: SojornColors.textDisabled)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: category.color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(category.displayName, style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600, color: category.color,
                        )),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isMember)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Joined', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4CAF50),
                )),
              )
            else
              SizedBox(
                height: 32,
                child: ElevatedButton(
                  onPressed: onJoin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.navyBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: const Text('Join', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Private Capsule Card ──────────────────────────────────────────────────
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
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.lock, color: Color(0xFF4CAF50), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(capsule.name, style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.navyBlue,
                  )),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.shield, size: 12, color: Color(0xFF4CAF50)),
                      const SizedBox(width: 4),
                      Text('E2E Encrypted', style: TextStyle(fontSize: 11, color: const Color(0xFF4CAF50).withValues(alpha: 0.7))),
                      const SizedBox(width: 10),
                      Icon(Icons.people, size: 12, color: SojornColors.textDisabled),
                      const SizedBox(width: 4),
                      Text('${capsule.memberCount}', style: TextStyle(fontSize: 11, color: SojornColors.postContentLight)),
                      const SizedBox(width: 10),
                      Icon(Icons.vpn_key, size: 11, color: SojornColors.textDisabled),
                      const SizedBox(width: 3),
                      Text('v${capsule.keyVersion}', style: TextStyle(fontSize: 10, color: SojornColors.textDisabled)),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: SojornColors.textDisabled, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Create Group Form (non-encrypted, public/private) ─────────────────
class _CreateGroupForm extends StatefulWidget {
  final VoidCallback onCreated;
  const _CreateGroupForm({required this.onCreated});

  @override
  State<_CreateGroupForm> createState() => _CreateGroupFormState();
}

class _CreateGroupFormState extends State<_CreateGroupForm> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _privacy = false;
  bool _submitting = false;

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.createGroup(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: group_models.GroupCategory.general,
        isPrivate: _privacy,
      );
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: SojornColors.basicBlack.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          const Text('Create Group', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Anyone can create a group. Automatic geo-groups are official.',
            style: TextStyle(fontSize: 12, color: SojornColors.basicBlack.withValues(alpha: 0.45))),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: 'Group name',
              filled: true,
              fillColor: SojornColors.basicBlack.withValues(alpha: 0.04),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: SojornColors.basicBlack.withValues(alpha: 0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: SojornColors.basicBlack.withValues(alpha: 0.1))),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              filled: true,
              fillColor: SojornColors.basicBlack.withValues(alpha: 0.04),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: SojornColors.basicBlack.withValues(alpha: 0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: SojornColors.basicBlack.withValues(alpha: 0.1))),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Visibility:', style: TextStyle(fontSize: 13, color: SojornColors.basicBlack.withValues(alpha: 0.6))),
              const SizedBox(width: 12),
              ChoiceChip(
                label: const Text('Public'),
                selected: _privacy == 'public',
                onSelected: (_) => setState(() => _privacy = 'public'),
                selectedColor: AppTheme.brightNavy.withValues(alpha: 0.15),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Private'),
                selected: _privacy == 'private',
                onSelected: (_) => setState(() => _privacy = 'private'),
                selectedColor: AppTheme.brightNavy.withValues(alpha: 0.15),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navyBlue,
                foregroundColor: SojornColors.basicWhite,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                  : const Text('Create Group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Create Capsule Form (E2EE, generates keys automatically) ──────────
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
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() { _submitting = true; _statusMsg = 'Generating encryption keys…'; });
    try {
      // 1. Generate capsule AES key
      final capsuleKey = await CapsuleSecurityService.generateCapsuleKey();

      // 2. Get (or create) user's X25519 key pair
      final publicKeyB64 = await CapsuleSecurityService.getUserPublicKeyB64();

      setState(() => _statusMsg = 'Encrypting group key…');

      // 3. Encrypt capsule key for the creator (box it to themselves)
      final encryptedGroupKey = await CapsuleSecurityService.encryptCapsuleKeyForUser(
        capsuleKey: capsuleKey,
        recipientPublicKeyB64: publicKeyB64,
      );

      setState(() => _statusMsg = 'Creating capsule…');

      // 4. POST to backend
      final result = await ApiService.instance.createCapsule(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        publicKey: publicKeyB64,
        encryptedGroupKey: encryptedGroupKey,
      );

      // 5. Cache the capsule key locally for instant access
      final capsuleId = (result['capsule'] as Map<String, dynamic>?)?['id']?.toString();
      if (capsuleId != null) {
        await CapsuleSecurityService.cacheCapsuleKey(capsuleId, capsuleKey);
      }

      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create capsule: $e')),
        );
      }
    }
    if (mounted) setState(() { _submitting = false; _statusMsg = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.lock, color: Color(0xFF4CAF50), size: 20),
              const SizedBox(width: 8),
              Text('Create Private Capsule', style: TextStyle(color: AppTheme.navyBlue, fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text('End-to-end encrypted. The server never sees your content.',
            style: TextStyle(fontSize: 12, color: SojornColors.textDisabled)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: SojornColors.postContent),
            decoration: InputDecoration(
              labelText: 'Capsule name',
              labelStyle: TextStyle(color: SojornColors.textDisabled),
              filled: true,
              fillColor: AppTheme.scaffoldBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            style: TextStyle(color: SojornColors.postContent),
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              labelStyle: TextStyle(color: SojornColors.textDisabled),
              filled: true,
              fillColor: AppTheme.scaffoldBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield, size: 14, color: const Color(0xFF4CAF50).withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Keys are generated on your device. Only invited members can decrypt content.',
                  style: TextStyle(fontSize: 11, color: SojornColors.postContentLight),
                )),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: SojornColors.basicWhite,
                disabledBackgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite)),
                      const SizedBox(width: 10),
                      Text(_statusMsg ?? 'Creating…', style: const TextStyle(fontSize: 13)),
                    ])
                  : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.lock, size: 16),
                      SizedBox(width: 8),
                      Text('Generate Keys & Create', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
            ),
          ),
        ],
      ),
    );
  }
}
