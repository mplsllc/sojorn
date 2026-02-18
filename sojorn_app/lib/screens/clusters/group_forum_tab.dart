import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import '../../services/api_service.dart';
import '../../services/capsule_security_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import 'group_thread_detail_screen.dart';

class GroupForumTab extends StatefulWidget {
  final String groupId;
  final bool isEncrypted;
  final SecretKey? capsuleKey;

  const GroupForumTab({
    super.key,
    required this.groupId,
    this.isEncrypted = false,
    this.capsuleKey,
  });

  @override
  State<GroupForumTab> createState() => _GroupForumTabState();
}

class _GroupForumTabState extends State<GroupForumTab> {
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  String? _activeSubforum;

  static const _subforums = ['General', 'Events', 'Information', 'Safety', 'Recommendations', 'Marketplace'];

  static const _subforumDescriptions = {
    'General': 'Open public discussion',
    'Events': 'Plans, meetups, and happenings',
    'Information': 'Updates, notices, and resources',
    'Safety': 'Alerts and local safety conversations',
    'Recommendations': 'Trusted local picks and referrals',
    'Marketplace': 'Buy, sell, and trade nearby',
  };

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    setState(() => _loading = true);
    try {
      if (widget.isEncrypted) {
        await _loadEncryptedThreads();
      } else {
        // Non-encrypted public forums support sub-forums via category.
        final queryParams = <String, String>{
          'limit': _activeSubforum == null ? '120' : '30',
        };
        if (_activeSubforum != null) {
          queryParams['category'] = _activeSubforum!;
        }
        final data = await ApiService.instance.callGoApi(
          '/capsules/${widget.groupId}/threads',
          method: 'GET',
          queryParams: queryParams,
        );
        _threads = (data['threads'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (e) {
      debugPrint('[GroupForum] Error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadEncryptedThreads() async {
    if (widget.capsuleKey == null) return;
    final data = await ApiService.instance.callGoApi(
      '/capsules/${widget.groupId}/entries',
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
          'id': entry['id'],
          'author_id': entry['author_id'],
          'author_handle': entry['author_handle'] ?? '',
          'author_display_name': entry['author_display_name'] ?? '',
          'author_avatar_url': entry['author_avatar_url'] ?? '',
          'created_at': entry['created_at'],
          'title': payload['title'] ?? 'Untitled',
          'body': payload['body'] ?? '',
          'reply_count': 0,
        });
      } catch (_) {
        decrypted.add({
          'id': entry['id'],
          'author_handle': entry['author_handle'] ?? '',
          'created_at': entry['created_at'],
          'title': '[Decryption failed]',
          'body': '',
          'reply_count': 0,
        });
      }
    }
    _threads = decrypted;
  }

  void _showCreateThread() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => _NewThreadSheet(
        isEncrypted: widget.isEncrypted,
        initialCategory: widget.isEncrypted ? null : (_activeSubforum ?? 'General'),
        lockCategory: !widget.isEncrypted && _activeSubforum != null,
      ),
    );
    if (result == null) return;
    try {
      if (widget.isEncrypted && widget.capsuleKey != null) {
        // Encryption doesn't support categories in payload yet, strictly speaking, 
        // but we could add it to payload map if needed. user only asked for neighborhoods (public).
        final encrypted = await CapsuleSecurityService.encryptPayload(
          payload: {'title': result['title'], 'body': result['body'], 'ts': DateTime.now().toIso8601String()},
          capsuleKey: widget.capsuleKey!,
        );
        await ApiService.instance.callGoApi(
          '/capsules/${widget.groupId}/entries',
          method: 'POST',
          body: {
            'iv': encrypted.iv,
            'encrypted_payload': encrypted.encryptedPayload,
            'data_type': 'forum',
            'key_version': 1,
          },
        );
      } else {
        await ApiService.instance.callGoApi(
          '/capsules/${widget.groupId}/threads',
          method: 'POST',
          body: {
            'title': result['title'],
            'body': result['body'] ?? '',
            'category': result['category'] ?? 'General',
          },
        );
      }
      await _loadThreads();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create thread: $e')));
      }
    }
  }

  void _openThread(Map<String, dynamic> thread) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => GroupThreadDetailScreen(
        groupId: widget.groupId,
        threadId: thread['id'].toString(),
        isEncrypted: widget.isEncrypted,
        capsuleKey: widget.capsuleKey,
        threadTitle: thread['title'] as String? ?? 'Thread',
      ),
    )).then((_) => _loadThreads());
  }

  String _timeAgo(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      final diff = DateTime.now().toUtc().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 30) return '${diff.inDays}d ago';
      return '${(diff.inDays / 30).floor()}mo ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSubforumDirectory = !widget.isEncrypted && _activeSubforum == null;

    return Column(
      children: [
        if (showSubforumDirectory)
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildSubforumDirectory(),
          )
        else ...[
          if (!widget.isEncrypted)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              color: AppTheme.cardSurface,
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() => _activeSubforum = null);
                      _loadThreads();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back, size: 15, color: SojornColors.textDisabled),
                          const SizedBox(width: 6),
                          Text(
                            'Subforums',
                            style: TextStyle(
                              color: SojornColors.textDisabled,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.brightNavy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _activeSubforum ?? 'General',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.brightNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _threads.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.forum, size: 48, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                                const SizedBox(height: 12),
                                Text('No discussions yet', style: TextStyle(color: SojornColors.postContentLight, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('Start a thread to get the conversation going',
                                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadThreads,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                              itemCount: _threads.length,
                              separatorBuilder: (_, __) => Divider(color: AppTheme.navyBlue.withValues(alpha: 0.06), height: 1),
                              itemBuilder: (_, i) {
                                final thread = _threads[i];
                                final title = thread['title'] as String? ?? 'Untitled';
                                final body = thread['body'] as String? ?? '';
                                final category = thread['category'] as String? ?? '';
                                final handle = thread['author_handle'] as String? ?? '';
                                final displayName = thread['author_display_name'] as String? ?? handle;
                                final replyCount = thread['reply_count'] as int? ?? 0;
                                final createdAt = thread['created_at']?.toString() ?? thread['last_activity_at']?.toString();

                                return ListTile(
                                  onTap: () => _openThread(thread),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  title: Row(
                                    children: [
                                      if (category.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppTheme.brightNavy.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(category, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.brightNavy)),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(child: Text(title, style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 14))),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (body.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis,
                                              style: TextStyle(color: SojornColors.postContentLight, fontSize: 12)),
                                        ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Text(displayName.isNotEmpty ? displayName : handle,
                                              style: TextStyle(color: AppTheme.brightNavy, fontSize: 11, fontWeight: FontWeight.w500)),
                                          const SizedBox(width: 8),
                                          Icon(Icons.chat_bubble_outline, size: 12, color: SojornColors.textDisabled),
                                          const SizedBox(width: 3),
                                          Text('$replyCount', style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                                          const SizedBox(width: 8),
                                          Text(_timeAgo(createdAt), style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: Icon(Icons.chevron_right, size: 18, color: SojornColors.textDisabled),
                                );
                              },
                            ),
                          ),
                Positioned(
                  bottom: 16, right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'new_thread',
                    onPressed: _showCreateThread,
                    backgroundColor: widget.isEncrypted ? const Color(0xFF4CAF50) : AppTheme.brightNavy,
                    child: const Icon(Icons.add, color: SojornColors.basicWhite),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSubforumDirectory() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: _subforums.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final subforum = _subforums[i];
        final count = _threads.where((t) => (t['category'] as String? ?? 'General') == subforum).length;
        final description = _subforumDescriptions[subforum] ?? '';

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _activeSubforum = subforum);
            _loadThreads();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.brightNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.forum, size: 18, color: AppTheme.brightNavy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subforum,
                        style: TextStyle(
                          color: AppTheme.navyBlue,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: SojornColors.textDisabled,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    color: AppTheme.brightNavy,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: SojornColors.textDisabled),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── New Thread Sheet ─────────────────────────────────────────────────────
class _NewThreadSheet extends StatefulWidget {
  final bool isEncrypted;
  final String? initialCategory;
  final bool lockCategory;
  const _NewThreadSheet({
    this.isEncrypted = false,
    this.initialCategory,
    this.lockCategory = false,
  });

  @override
  State<_NewThreadSheet> createState() => _NewThreadSheetState();
}

class _NewThreadSheetState extends State<_NewThreadSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _selectedCategory = 'General';

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _selectedCategory = widget.initialCategory!;
    }
  }

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
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.navyBlue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('New Thread', style: TextStyle(color: AppTheme.navyBlue, fontSize: 16, fontWeight: FontWeight.w700)),
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
          const SizedBox(height: 16),
          // Category Selector
          if (!widget.isEncrypted && !widget.lockCategory) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['General', 'Events', 'Information', 'Safety', 'Recommendations', 'Marketplace'].map((c) {
                  final isSelected = _selectedCategory == c;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c, style: TextStyle(
                        fontSize: 12, 
                        color: isSelected ? SojornColors.basicWhite : AppTheme.navyBlue
                      )),
                      selected: isSelected,
                      selectedColor: AppTheme.brightNavy,
                      backgroundColor: AppTheme.scaffoldBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = c);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ] else if (!widget.isEncrypted && widget.lockCategory) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.brightNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Posting in $_selectedCategory',
                style: TextStyle(
                  color: AppTheme.brightNavy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
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
                Navigator.pop(context, {
                  'title': _titleCtrl.text.trim(),
                  'body': _bodyCtrl.text.trim(),
                  'category': _selectedCategory,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brightNavy, foregroundColor: SojornColors.basicWhite,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Create Thread', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
