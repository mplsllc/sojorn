import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import '../../models/cluster.dart';
import '../../providers/api_provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/capsule_security_service.dart';
import '../../services/content_guard_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

/// PrivateCapsuleScreen — E2EE private groups with a subtle green-tinted
/// light theme. Lock badges, tabbed interface: Chat / Forum / Vault.
/// All content is decrypted client-side using the Capsule Key.
class PrivateCapsuleScreen extends ConsumerStatefulWidget {
  final Cluster capsule;
  final String? encryptedGroupKey; // from group_members

  const PrivateCapsuleScreen({
    super.key,
    required this.capsule,
    this.encryptedGroupKey,
  });

  @override
  ConsumerState<PrivateCapsuleScreen> createState() => _PrivateCapsuleScreenState();
}

class _PrivateCapsuleScreenState extends ConsumerState<PrivateCapsuleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  SecretKey? _capsuleKey;
  bool _isUnlocking = true;
  String? _unlockError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _unlockCapsule();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _unlockCapsule() async {
    setState(() { _isUnlocking = true; _unlockError = null; });
    try {
      // Try cached key first
      var key = await CapsuleSecurityService.getCachedCapsuleKey(widget.capsule.id);
      if (key == null && widget.encryptedGroupKey != null) {
        key = await CapsuleSecurityService.decryptCapsuleKey(
          encryptedGroupKeyJson: widget.encryptedGroupKey!,
        );
        await CapsuleSecurityService.cacheCapsuleKey(widget.capsule.id, key);
      }
      if (mounted) setState(() { _capsuleKey = key; _isUnlocking = false; });

      // Silent self-healing: rotate keys if the server flagged it
      if (key != null) _checkAndRotateKeysIfNeeded();
    } catch (e) {
      if (mounted) setState(() { _unlockError = 'Failed to unlock capsule'; _isUnlocking = false; });
    }
  }

  /// Silently check if key rotation is needed and perform it automatically.
  Future<void> _checkAndRotateKeysIfNeeded() async {
    try {
      final api = ref.read(apiServiceProvider);
      final status = await api.callGoApi('/groups/${widget.capsule.id}/key-status', method: 'GET');
      final rotationNeeded = status['key_rotation_needed'] as bool? ?? false;
      if (!rotationNeeded || !mounted) return;
      // Perform rotation silently — user sees nothing
      await _performKeyRotation(api, silent: true);
    } catch (_) {
      // Non-fatal: rotation will be retried on next open
    }
  }

  /// Full key rotation: fetch member public keys, generate new AES key,
  /// encrypt for each member, push to server.
  Future<void> _performKeyRotation(ApiService api, {bool silent = false}) async {
    // Fetch member public keys
    final keysData = await api.callGoApi(
      '/groups/${widget.capsule.id}/members/public-keys',
      method: 'GET',
    );
    final memberKeys = (keysData['keys'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (memberKeys.isEmpty) return;

    final pubKeys = memberKeys.map((m) => m['public_key'] as String).toList();
    final userIds = memberKeys.map((m) => m['user_id'] as String).toList();

    final result = await CapsuleSecurityService.rotateKeys(
      memberPublicKeysB64: pubKeys,
      memberUserIds: userIds,
    );

    // Determine next key version
    final status = await api.callGoApi('/groups/${widget.capsule.id}/key-status', method: 'GET');
    final currentVersion = status['key_version'] as int? ?? 1;
    final nextVersion = currentVersion + 1;

    final payload = result.memberKeys.entries.map((e) => {
      'user_id': e.key,
      'encrypted_key': e.value,
      'key_version': nextVersion,
    }).toList();

    await api.callGoApi('/groups/${widget.capsule.id}/keys', method: 'POST', body: {'keys': payload});

    // Update local cache with new key
    await CapsuleSecurityService.cacheCapsuleKey(widget.capsule.id, result.newCapsuleKey);
    if (mounted) setState(() => _capsuleKey = result.newCapsuleKey);

    if (!silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keys rotated successfully')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: _isUnlocking
          ? _buildUnlockingScreen()
          : _unlockError != null
              ? _buildErrorScreen()
              : _buildCapsuleContent(),
    );
  }

  Widget _buildUnlockingScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PulsingLockIcon(),
          const SizedBox(height: 20),
          Text(
            'Decrypting…',
            style: TextStyle(color: SojornColors.textDisabled, fontSize: 14),
          ),
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
    );
  }

  Widget _buildErrorScreen() {
    return Center(
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
    );
  }

  Widget _buildCapsuleContent() {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        // ── Capsule header ────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 160,
          pinned: true,
          backgroundColor: AppTheme.cardSurface,
          foregroundColor: AppTheme.navyBlue,
          flexibleSpace: FlexibleSpaceBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, size: 14, color: Color(0xFF4CAF50)),
                const SizedBox(width: 6),
                Text(
                  widget.capsule.name,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.navyBlue),
                ),
              ],
            ),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFFF0F8F0), AppTheme.scaffoldBg],
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
                          _SecureBadge(),
                          const Spacer(),
                          Icon(Icons.people, size: 14, color: SojornColors.textDisabled),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.capsule.memberCount}',
                            style: TextStyle(color: SojornColors.postContentLight, fontSize: 13),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.vpn_key, size: 14, color: SojornColors.textDisabled),
                          const SizedBox(width: 4),
                          Text(
                            'v${widget.capsule.keyVersion}',
                            style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
                          ),
                        ],
                      ),
                      if (widget.capsule.description.isNotEmpty) ...[
                        const Spacer(),
                        Text(
                          widget.capsule.description,
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
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, size: 20),
              onPressed: () => _showAdminPanel(context),
              tooltip: 'Admin',
            ),
          ],
        ),

        // ── Tabs ──────────────────────────────────────────────────
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF4CAF50),
              labelColor: AppTheme.navyBlue,
              unselectedLabelColor: SojornColors.textDisabled,
              tabs: const [
                Tab(icon: Icon(Icons.chat_bubble, size: 18), text: 'Chat'),
                Tab(icon: Icon(Icons.forum, size: 18), text: 'Forum'),
                Tab(icon: Icon(Icons.folder_special, size: 18), text: 'Vault'),
              ],
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [
          _CapsuleChatTab(capsuleId: widget.capsule.id, capsuleKey: _capsuleKey),
          _CapsuleForumTab(capsuleId: widget.capsule.id, capsuleKey: _capsuleKey),
          _CapsuleVaultTab(capsuleId: widget.capsule.id, capsuleKey: _capsuleKey),
        ],
      ),
    );
  }

  void _showAdminPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => _CapsuleAdminPanel(
        capsule: widget.capsule,
        capsuleKey: _capsuleKey,
        onRotateKeys: () => _performKeyRotation(ref.read(apiServiceProvider)),
      ),
    );
  }
}

// ── Secure Badge ──────────────────────────────────────────────────────────
class _SecureBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield, size: 12, color: Color(0xFF4CAF50)),
          const SizedBox(width: 4),
          Text(
            'E2E ENCRYPTED',
            style: TextStyle(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.9),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing Lock Icon ─────────────────────────────────────────────────────
class _PulsingLockIcon extends StatefulWidget {
  const _PulsingLockIcon();
  @override
  State<_PulsingLockIcon> createState() => _PulsingLockIconState();
}

class _PulsingLockIconState extends State<_PulsingLockIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Icon(
        Icons.lock,
        size: 48,
        color: Color.lerp(const Color(0xFF4CAF50).withValues(alpha: 0.3), const Color(0xFF4CAF50), _ctrl.value),
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

// ── Chat Tab — Real encrypted message flow ────────────────────────────────
class _CapsuleChatTab extends StatefulWidget {
  final String capsuleId;
  final SecretKey? capsuleKey;
  const _CapsuleChatTab({required this.capsuleId, this.capsuleKey});

  @override
  State<_CapsuleChatTab> createState() => _CapsuleChatTabState();
}

class _CapsuleChatTabState extends State<_CapsuleChatTab> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = AuthService.instance.currentUser?.id;
    _loadMessages();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (widget.capsuleKey == null) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService.instance.callGoApi(
        '/capsules/${widget.capsuleId}/entries',
        method: 'GET',
        queryParams: {'type': 'chat', 'limit': '50'},
      );
      final entries = (data['entries'] as List?) ?? [];
      final decrypted = <Map<String, dynamic>>[];
      for (final entry in entries) {
        try {
          final payload = await CapsuleSecurityService.decryptPayload(
            iv: entry['iv'] as String,
            encryptedPayload: entry['encrypted_payload'] as String,
            capsuleKey: widget.capsuleKey!,
          );
          decrypted.add({
            'id': entry['id'],
            'author_id': entry['author_id'],
            'author_handle': entry['author_handle'] ?? '',
            'author_avatar_url': entry['author_avatar_url'] ?? '',
            'created_at': entry['created_at'],
            'content': payload,
          });
        } catch (_) {
          decrypted.add({
            'id': entry['id'],
            'author_id': entry['author_id'],
            'author_handle': entry['author_handle'] ?? '',
            'created_at': entry['created_at'],
            'content': {'text': '[Decryption failed]'},
          });
        }
      }
      if (mounted) setState(() { _messages = decrypted.reversed.toList(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || widget.capsuleKey == null || _sending) return;

    // Local content guard — block before encryption
    final guardReason = ContentGuardService.instance.check(text);
    if (guardReason != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(guardReason), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Server-side AI moderation — stateless, nothing stored
    final aiReason = await ApiService.instance.moderateContent(text: text, context: 'group');
    if (aiReason != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(aiReason), backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() => _sending = true);
    try {
      final encrypted = await CapsuleSecurityService.encryptPayload(
        payload: {'text': text, 'ts': DateTime.now().toIso8601String()},
        capsuleKey: widget.capsuleKey!,
      );
      await ApiService.instance.callGoApi(
        '/capsules/${widget.capsuleId}/entries',
        method: 'POST',
        body: {
          'iv': encrypted.iv,
          'encrypted_payload': encrypted.encryptedPayload,
          'data_type': 'chat',
          'key_version': 1,
        },
      );
      _msgCtrl.clear();
      await _loadMessages();
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 60,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
              : _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 40, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                          const SizedBox(height: 12),
                          Text('No messages yet', style: TextStyle(color: SojornColors.postContentLight, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('Messages are end-to-end encrypted', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMessages,
                      color: const Color(0xFF4CAF50),
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _ChatBubble(
                          message: _messages[i],
                          isMine: _messages[i]['author_id'] == _currentUserId,
                        ),
                      ),
                    ),
        ),
        // Compose bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(top: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.08))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    style: TextStyle(color: SojornColors.postContent, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Encrypted message…',
                      hintStyle: TextStyle(color: SojornColors.textDisabled),
                      filled: true,
                      fillColor: AppTheme.scaffoldBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _sending ? const Color(0xFF4CAF50).withValues(alpha: 0.5) : const Color(0xFF4CAF50),
                    ),
                    child: _sending
                        ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                        : const Icon(Icons.send, color: SojornColors.basicWhite, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  const _ChatBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final content = message['content'] as Map<String, dynamic>? ?? {};
    final text = content['text'] as String? ?? '';
    final handle = message['author_handle'] as String? ?? '';

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine ? const Color(0xFFE8F5E9) : AppTheme.cardSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine && handle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(handle, style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            Text(text, style: TextStyle(color: SojornColors.postContent, fontSize: 14, height: 1.35)),
          ],
        ),
      ),
    );
  }
}

// ── Forum Tab — Encrypted threaded discussions ────────────────────────────
class _CapsuleForumTab extends StatefulWidget {
  final String capsuleId;
  final SecretKey? capsuleKey;
  const _CapsuleForumTab({required this.capsuleId, this.capsuleKey});

  @override
  State<_CapsuleForumTab> createState() => _CapsuleForumTabState();
}

class _CapsuleForumTabState extends State<_CapsuleForumTab> {
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    if (widget.capsuleKey == null) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService.instance.callGoApi(
        '/capsules/${widget.capsuleId}/entries',
        method: 'GET',
        queryParams: {'type': 'forum', 'limit': '30'},
      );
      final entries = (data['entries'] as List?) ?? [];
      final decrypted = <Map<String, dynamic>>[];
      for (final entry in entries) {
        try {
          final payload = await CapsuleSecurityService.decryptPayload(
            iv: entry['iv'] as String,
            encryptedPayload: entry['encrypted_payload'] as String,
            capsuleKey: widget.capsuleKey!,
          );
          decrypted.add({
            ...entry,
            'content': payload,
          });
        } catch (_) {
          decrypted.add({...entry, 'content': {'title': '[Decryption failed]', 'body': ''}});
        }
      }
      if (mounted) setState(() { _threads = decrypted; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showNewThreadSheet() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => _NewForumThreadSheet(),
    );
    if (result == null || widget.capsuleKey == null) return;
    try {
      final encrypted = await CapsuleSecurityService.encryptPayload(
        payload: {'title': result['title'], 'body': result['body'], 'ts': DateTime.now().toIso8601String()},
        capsuleKey: widget.capsuleKey!,
      );
      await ApiService.instance.callGoApi(
        '/capsules/${widget.capsuleId}/entries',
        method: 'POST',
        body: {
          'iv': encrypted.iv,
          'encrypted_payload': encrypted.encryptedPayload,
          'data_type': 'forum',
          'key_version': 1,
        },
      );
      await _loadThreads();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
            : _threads.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forum, size: 40, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text('No threads yet', style: TextStyle(color: SojornColors.postContentLight, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('Threaded discussions with E2E encryption', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadThreads,
                    color: const Color(0xFF4CAF50),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      itemCount: _threads.length,
                      separatorBuilder: (_, __) => Divider(color: AppTheme.navyBlue.withValues(alpha: 0.06), height: 1),
                      itemBuilder: (_, i) {
                        final thread = _threads[i];
                        final content = thread['content'] as Map<String, dynamic>? ?? {};
                        final title = content['title'] as String? ?? 'Untitled';
                        final body = content['body'] as String? ?? '';
                        final handle = thread['author_handle'] as String? ?? '';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          title: Text(title, style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (body.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: SojornColors.postContentLight, fontSize: 12)),
                                ),
                              const SizedBox(height: 6),
                              Text(handle, style: TextStyle(color: const Color(0xFF4CAF50).withValues(alpha: 0.7), fontSize: 11)),
                            ],
                          ),
                          trailing: Icon(Icons.lock, size: 14, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                        );
                      },
                    ),
                  ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.small(
            heroTag: 'new_forum_post',
            onPressed: _showNewThreadSheet,
            backgroundColor: const Color(0xFF4CAF50),
            child: const Icon(Icons.add, color: SojornColors.basicWhite),
          ),
        ),
      ],
    );
  }
}

class _NewForumThreadSheet extends StatefulWidget {
  @override
  State<_NewForumThreadSheet> createState() => _NewForumThreadSheetState();
}

class _NewForumThreadSheetState extends State<_NewForumThreadSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  @override
  void dispose() { _titleCtrl.dispose(); _bodyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('New Encrypted Thread', style: TextStyle(color: AppTheme.navyBlue, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            style: TextStyle(color: SojornColors.postContent, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Thread title',
              hintStyle: TextStyle(color: SojornColors.textDisabled),
              filled: true, fillColor: AppTheme.scaffoldBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bodyCtrl,
            style: TextStyle(color: SojornColors.postContent, fontSize: 14),
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'What do you want to discuss?',
              hintStyle: TextStyle(color: SojornColors.textDisabled),
              filled: true, fillColor: AppTheme.scaffoldBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {'title': _titleCtrl.text.trim(), 'body': _bodyCtrl.text.trim()});
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: SojornColors.basicWhite, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock, size: 14), SizedBox(width: 6), Text('Post Encrypted Thread')]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Vault Tab — Encrypted shared documents ────────────────────────────────
class _CapsuleVaultTab extends StatefulWidget {
  final String capsuleId;
  final SecretKey? capsuleKey;
  const _CapsuleVaultTab({required this.capsuleId, this.capsuleKey});

  @override
  State<_CapsuleVaultTab> createState() => _CapsuleVaultTabState();
}

class _CapsuleVaultTabState extends State<_CapsuleVaultTab> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    if (widget.capsuleKey == null) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService.instance.callGoApi(
        '/capsules/${widget.capsuleId}/entries',
        method: 'GET',
        queryParams: {'type': 'vault', 'limit': '50'},
      );
      final entries = (data['entries'] as List?) ?? [];
      final decrypted = <Map<String, dynamic>>[];
      for (final entry in entries) {
        try {
          final payload = await CapsuleSecurityService.decryptPayload(
            iv: entry['iv'] as String,
            encryptedPayload: entry['encrypted_payload'] as String,
            capsuleKey: widget.capsuleKey!,
          );
          decrypted.add({...entry, 'content': payload});
        } catch (_) {
          decrypted.add({...entry, 'content': {'name': '[Decryption failed]', 'type': 'unknown'}});
        }
      }
      if (mounted) setState(() { _docs = decrypted; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showAddNoteSheet() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => _NewVaultNoteSheet(),
    );
    if (result == null || widget.capsuleKey == null) return;
    try {
      final encrypted = await CapsuleSecurityService.encryptPayload(
        payload: {
          'name': result['name'],
          'type': 'note',
          'body': result['body'],
          'ts': DateTime.now().toIso8601String(),
        },
        capsuleKey: widget.capsuleKey!,
      );
      await ApiService.instance.callGoApi(
        '/capsules/${widget.capsuleId}/entries',
        method: 'POST',
        body: {
          'iv': encrypted.iv,
          'encrypted_payload': encrypted.encryptedPayload,
          'data_type': 'vault',
          'key_version': 1,
        },
      );
      await _loadDocs();
    } catch (_) {}
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'note': return Icons.description;
      case 'image': return Icons.image;
      case 'link': return Icons.link;
      default: return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
            : _docs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_special, size: 40, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                        const SizedBox(height: 12),
                        Text('Vault is empty', style: TextStyle(color: SojornColors.postContentLight, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('Shared encrypted notes and files', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadDocs,
                    color: const Color(0xFF4CAF50),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                      itemCount: _docs.length,
                      itemBuilder: (_, i) {
                        final doc = _docs[i];
                        final content = doc['content'] as Map<String, dynamic>? ?? {};
                        final name = content['name'] as String? ?? 'Untitled';
                        final type = content['type'] as String? ?? 'file';
                        final handle = doc['author_handle'] as String? ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.cardSurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_iconForType(type), color: const Color(0xFF4CAF50), size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 13)),
                                    const SizedBox(height: 3),
                                    Text('by $handle', style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Icon(Icons.lock, size: 12, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
        Positioned(
          bottom: 16, right: 16,
          child: FloatingActionButton.small(
            heroTag: 'new_vault_item',
            onPressed: _showAddNoteSheet,
            backgroundColor: const Color(0xFF4CAF50),
            child: const Icon(Icons.note_add, color: SojornColors.basicWhite),
          ),
        ),
      ],
    );
  }
}

class _NewVaultNoteSheet extends StatefulWidget {
  @override
  State<_NewVaultNoteSheet> createState() => _NewVaultNoteSheetState();
}

class _NewVaultNoteSheetState extends State<_NewVaultNoteSheet> {
  final _nameCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  @override
  void dispose() { _nameCtrl.dispose(); _bodyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('New Encrypted Note', style: TextStyle(color: AppTheme.navyBlue, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            style: TextStyle(color: SojornColors.postContent, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Note title',
              hintStyle: TextStyle(color: SojornColors.textDisabled),
              filled: true, fillColor: AppTheme.scaffoldBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _bodyCtrl,
            style: TextStyle(color: SojornColors.postContent, fontSize: 14),
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Note content…',
              hintStyle: TextStyle(color: SojornColors.textDisabled),
              filled: true, fillColor: AppTheme.scaffoldBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(context, {'name': _nameCtrl.text.trim(), 'body': _bodyCtrl.text.trim()});
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: SojornColors.basicWhite, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock, size: 14), SizedBox(width: 6), Text('Save Encrypted Note')]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Admin Panel ───────────────────────────────────────────────────────────
class _CapsuleAdminPanel extends ConsumerStatefulWidget {
  final Cluster capsule;
  final SecretKey? capsuleKey;
  final Future<void> Function() onRotateKeys;

  const _CapsuleAdminPanel({
    required this.capsule,
    required this.capsuleKey,
    required this.onRotateKeys,
  });

  @override
  ConsumerState<_CapsuleAdminPanel> createState() => _CapsuleAdminPanelState();
}

class _CapsuleAdminPanelState extends ConsumerState<_CapsuleAdminPanel> {
  bool _busy = false;

  Future<void> _rotateKeys() async {
    setState(() => _busy = true);
    try {
      await widget.onRotateKeys();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rotation failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteMember() async {
    final handle = await showDialog<String>(
      context: context,
      builder: (ctx) => _TextInputDialog(
        title: 'Invite Member',
        label: 'Username or @handle',
        action: 'Invite',
      ),
    );
    if (handle == null || handle.isEmpty) return;

    setState(() => _busy = true);
    try {
      final api = ref.read(apiServiceProvider);

      // Look up user by handle
      final userData = await api.callGoApi(
        '/users/by-handle/${handle.replaceFirst('@', '')}',
        method: 'GET',
      );
      final userId = userData['id'] as String?;
      final recipientPubKey = userData['public_key'] as String?;

      if (userId == null) throw 'User not found';
      if (recipientPubKey == null || recipientPubKey.isEmpty) throw 'User has no public key registered';
      if (widget.capsuleKey == null) throw 'Capsule not unlocked';

      // Encrypt the current group key for the new member
      final encryptedKey = await CapsuleSecurityService.encryptCapsuleKeyForUser(
        capsuleKey: widget.capsuleKey!,
        recipientPublicKeyB64: recipientPubKey,
      );

      await api.callGoApi('/groups/${widget.capsule.id}/invite-member', method: 'POST', body: {
        'user_id': userId,
        'encrypted_key': encryptedKey,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${handle.replaceFirst('@', '')} invited')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invite failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMember() async {
    final api = ref.read(apiServiceProvider);

    // Load member list
    final data = await api.callGoApi('/groups/${widget.capsule.id}/members', method: 'GET');
    final members = (data['members'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (!mounted) return;

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _MemberPickerDialog(members: members),
    );
    if (selected == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${selected['username']}? This will trigger key rotation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: SojornColors.destructive),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await api.callGoApi(
        '/groups/${widget.capsule.id}/members/${selected['user_id']}',
        method: 'DELETE',
      );
      // Rotate keys after removal — server already flagged it; do it now
      await widget.onRotateKeys();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    Navigator.pop(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _CapsuleSettingsDialog(capsule: widget.capsule),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Capsule Admin',
              style: TextStyle(color: AppTheme.navyBlue, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          if (_busy)
            const Center(child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(),
            ))
          else ...[
            _AdminAction(
              icon: Icons.vpn_key,
              label: 'Rotate Encryption Keys',
              subtitle: 'Generate new keys and re-encrypt for all members',
              color: const Color(0xFFFFA726),
              onTap: _rotateKeys,
            ),
            const SizedBox(height: 8),
            _AdminAction(
              icon: Icons.person_add,
              label: 'Invite Member',
              subtitle: 'Encrypt the capsule key for a new member',
              color: const Color(0xFF4CAF50),
              onTap: _inviteMember,
            ),
            const SizedBox(height: 8),
            _AdminAction(
              icon: Icons.person_remove,
              label: 'Remove Member',
              subtitle: 'Revoke access and rotate keys automatically',
              color: SojornColors.destructive,
              onTap: _removeMember,
            ),
            const SizedBox(height: 8),
            _AdminAction(
              icon: Icons.settings,
              label: 'Capsule Settings',
              subtitle: 'Toggle chat, forum, and vault features',
              color: SojornColors.basicBrightNavy,
              onTap: _openSettings,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Helper dialogs ─────────────────────────────────────────────────────────

class _TextInputDialog extends StatefulWidget {
  final String title;
  final String label;
  final String action;
  const _TextInputDialog({required this.title, required this.label, required this.action});
  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final _ctrl = TextEditingController();
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        decoration: InputDecoration(labelText: widget.label),
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _MemberPickerDialog extends StatelessWidget {
  final List<Map<String, dynamic>> members;
  const _MemberPickerDialog({required this.members});
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Member to Remove'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: members.length,
          itemBuilder: (ctx, i) {
            final m = members[i];
            return ListTile(
              title: Text(m['username'] as String? ?? m['user_id'] as String? ?? ''),
              subtitle: Text(m['role'] as String? ?? ''),
              onTap: () => Navigator.pop(context, m),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}

class _CapsuleSettingsDialog extends ConsumerStatefulWidget {
  final Cluster capsule;
  const _CapsuleSettingsDialog({required this.capsule});
  @override
  ConsumerState<_CapsuleSettingsDialog> createState() => _CapsuleSettingsDialogState();
}

class _CapsuleSettingsDialogState extends ConsumerState<_CapsuleSettingsDialog> {
  bool _chat = true;
  bool _forum = true;
  bool _vault = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _chat = widget.capsule.settings.chat;
    _forum = widget.capsule.settings.forum;
    _vault = widget.capsule.settings.files;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.callGoApi('/groups/${widget.capsule.id}/settings', method: 'PATCH', body: {
        'chat_enabled': _chat,
        'forum_enabled': _forum,
        'vault_enabled': _vault,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Capsule Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(title: const Text('Chat'), value: _chat, onChanged: (v) => setState(() => _chat = v)),
          SwitchListTile(title: const Text('Forum'), value: _forum, onChanged: (v) => setState(() => _forum = v)),
          SwitchListTile(title: const Text('Vault'), value: _vault, onChanged: (v) => setState(() => _vault = v)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
        ),
      ],
    );
  }
}

class _AdminAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AdminAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: SojornColors.postContent, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: SojornColors.textDisabled, size: 18),
          ],
        ),
      ),
    );
  }
}
