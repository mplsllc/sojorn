import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cluster.dart';
import '../../services/api_service.dart';
import '../../services/capsule_security_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import 'group_screen.dart';

/// ClustersScreen — Discovery and listing of all clusters the user belongs to.
/// Split into two sections: Public Clusters (geo) and Private Capsules (E2EE).
class ClustersScreen extends ConsumerStatefulWidget {
  const ClustersScreen({super.key});

  @override
  ConsumerState<ClustersScreen> createState() => _ClustersScreenState();
}

class _ClustersScreenState extends ConsumerState<ClustersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Cluster> _publicClusters = [];
  List<Cluster> _privateCapsules = [];
  Map<String, String> _encryptedKeys = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadClusters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadClusters() async {
    setState(() => _isLoading = true);
    try {
      final groups = await ApiService.instance.fetchMyGroups();
      final allClusters = groups.map((g) => Cluster.fromJson(g)).toList();
      if (mounted) {
        setState(() {
          _publicClusters = allClusters.where((c) => !c.isCapsule).toList();
          _privateCapsules = allClusters.where((c) => c.isCapsule).toList();
          // Store encrypted keys for quick access when navigating
          _encryptedKeys = {
            for (final g in groups)
              if ((g['encrypted_group_key'] as String?)?.isNotEmpty == true)
                g['id'] as String: g['encrypted_group_key'] as String,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[Clusters] Load error: $e');
      if (mounted) setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        title: const Text('Groups', style: TextStyle(fontWeight: FontWeight.w800)),
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
          _buildPublicTab(),
          _buildCapsuleTab(),
        ],
      ),
    );
  }

  Widget _buildPublicTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_publicClusters.isEmpty) return _EmptyState(
      icon: Icons.location_on,
      title: 'No Neighborhoods Yet',
      subtitle: 'Public clusters based on your location will appear here.',
      actionLabel: 'Discover Nearby',
      onAction: _loadClusters,
    );
    return RefreshIndicator(
      onRefresh: _loadClusters,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _publicClusters.length,
        itemBuilder: (_, i) => _PublicClusterCard(
          cluster: _publicClusters[i],
          onTap: () => _navigateToCluster(_publicClusters[i]),
        ),
      ),
    );
  }

  Widget _buildCapsuleTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_privateCapsules.isEmpty) return _EmptyState(
      icon: Icons.lock,
      title: 'No Capsules Yet',
      subtitle: 'Create an encrypted capsule or join one via invite code.',
      actionLabel: 'Create Capsule',
      onAction: () => _showCreateSheet(context, capsule: true),
    );
    return RefreshIndicator(
      onRefresh: _loadClusters,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _privateCapsules.length,
        itemBuilder: (_, i) => _CapsuleCard(
          capsule: _privateCapsules[i],
          onTap: () => _navigateToCluster(_privateCapsules[i]),
        ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context, {bool capsule = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => capsule
          ? _CreateCapsuleForm(onCreated: () { Navigator.pop(ctx); _loadClusters(); })
          : _CreateGroupForm(onCreated: () { Navigator.pop(ctx); _loadClusters(); }),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────
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

// ── Public Cluster Card ───────────────────────────────────────────────────
class _PublicClusterCard extends StatelessWidget {
  final Cluster cluster;
  final VoidCallback onTap;
  const _PublicClusterCard({required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
            // Avatar / location icon
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppTheme.brightNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.location_on, color: AppTheme.brightNavy, size: 24),
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
                      Icon(Icons.public, size: 12, color: SojornColors.textDisabled),
                      const SizedBox(width: 4),
                      Text('Public', style: TextStyle(fontSize: 11, color: SojornColors.textDisabled)),
                      const SizedBox(width: 10),
                      Icon(Icons.people, size: 12, color: SojornColors.textDisabled),
                      const SizedBox(width: 4),
                      Text('${cluster.memberCount}', style: TextStyle(fontSize: 11, color: SojornColors.textDisabled)),
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
            // Lock avatar
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
  String _privacy = 'public';
  bool _submitting = false;

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ApiService.instance.createGroup(
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        privacy: _privacy,
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
