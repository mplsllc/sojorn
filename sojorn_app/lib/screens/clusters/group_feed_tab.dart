// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/capsule_security_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/composer/composer_bar.dart';

class GroupFeedTab extends StatefulWidget {
  final String groupId;
  final bool isEncrypted;
  final SecretKey? capsuleKey;
  final String? currentUserId;

  const GroupFeedTab({
    super.key,
    required this.groupId,
    this.isEncrypted = false,
    this.capsuleKey,
    this.currentUserId,
  });

  @override
  State<GroupFeedTab> createState() => _GroupFeedTabState();
}

class _GroupFeedTabState extends State<GroupFeedTab> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() => _loading = true);
    try {
      if (widget.isEncrypted) {
        await _loadEncryptedPosts();
      } else {
        _posts = await ApiService.instance.fetchGroupPosts(widget.groupId);
      }
    } catch (e) {
      debugPrint('[GroupFeed] Error loading posts: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadEncryptedPosts() async {
    if (widget.capsuleKey == null) return;
    final data = await ApiService.instance.callGoApi(
      '/capsules/${widget.groupId}/entries',
      method: 'GET',
      queryParams: {'type': 'post', 'limit': '30'},
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
          'body': payload['text'] ?? payload['body'] ?? '',
          'image_url': payload['image_url'] ?? '',
          'like_count': 0,
          'comment_count': 0,
          'liked_by_me': false,
        });
      } catch (_) {
        decrypted.add({
          'id': entry['id'],
          'author_id': entry['author_id'],
          'author_handle': entry['author_handle'] ?? '',
          'created_at': entry['created_at'],
          'body': '[Decryption failed]',
        });
      }
    }
    _posts = decrypted;
  }

  Future<void> _onComposerSend(String text, String? mediaUrl) async {
    if (widget.isEncrypted && widget.capsuleKey != null) {
      final encrypted = await CapsuleSecurityService.encryptPayload(
        payload: {'text': text, 'ts': DateTime.now().toIso8601String(),
                 if (mediaUrl != null) 'image_url': mediaUrl},
        capsuleKey: widget.capsuleKey!,
      );
      await ApiService.instance.callGoApi(
        '/capsules/${widget.groupId}/entries',
        method: 'POST',
        body: {
          'iv': encrypted.iv,
          'encrypted_payload': encrypted.encryptedPayload,
          'data_type': 'post',
          'key_version': 1,
        },
      );
    } else {
      await ApiService.instance.createGroupPost(
        widget.groupId,
        body: text,
        imageUrl: mediaUrl,
      );
    }
    if (mounted) await _loadPosts();
  }

  Future<void> _toggleLike(String postId, int index) async {
    if (widget.isEncrypted) return; // likes not supported for encrypted yet
    try {
      final result = await ApiService.instance.toggleGroupPostLike(widget.groupId, postId);
      final liked = result['liked'] == true;
      setState(() {
        _posts[index]['liked_by_me'] = liked;
        _posts[index]['like_count'] = (_posts[index]['like_count'] as int? ?? 0) + (liked ? 1 : -1);
      });
    } catch (_) {}
  }

  String _timeAgo(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      final diff = DateTime.now().toUtc().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      if (diff.inDays < 30) return '${diff.inDays}d';
      return '${(diff.inDays / 30).floor()}mo';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Composer
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(bottom: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.06))),
          ),
          child: ComposerBar(
            config: widget.isEncrypted
                ? const ComposerConfig(allowGifs: true, hintText: 'Write an encrypted post…')
                : ComposerConfig.publicPost,
            onSend: _onComposerSend,
          ),
        ),
        // Posts list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _posts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dynamic_feed, size: 48, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                          const SizedBox(height: 12),
                          Text('No posts yet', style: TextStyle(color: AppTheme.postContentLight, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('Be the first to post!', style: TextStyle(color: AppTheme.textDisabled, fontSize: 12)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPosts,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _posts.length,
                        itemBuilder: (_, i) => _PostCard(
                          post: _posts[i],
                          isEncrypted: widget.isEncrypted,
                          timeAgo: _timeAgo(_posts[i]['created_at']?.toString()),
                          onLike: () => _toggleLike(_posts[i]['id'].toString(), i),
                          onComment: () => _showComments(_posts[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  void _showComments(Map<String, dynamic> post) {
    if (widget.isEncrypted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      isScrollControlled: true,
      builder: (ctx) => _CommentsSheet(
        groupId: widget.groupId,
        postId: post['id'].toString(),
      ),
    );
  }
}

// ── Post Card ────────────────────────────────────────────────────────────
class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final bool isEncrypted;
  final String timeAgo;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const _PostCard({
    required this.post,
    required this.isEncrypted,
    required this.timeAgo,
    required this.onLike,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    final handle = post['author_handle'] as String? ?? '';
    final displayName = post['author_display_name'] as String? ?? handle;
    final avatarUrl = post['author_avatar_url'] as String? ?? '';
    final body = post['body'] as String? ?? '';
    final imageUrl = post['image_url'] as String? ?? '';
    final likeCount = post['like_count'] as int? ?? 0;
    final commentCount = post['comment_count'] as int? ?? 0;
    final likedByMe = post['liked_by_me'] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author row
          Row(
            children: [
              SojornAvatar(
                displayName: displayName,
                avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName.isNotEmpty ? displayName : handle,
                        style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('@$handle · $timeAgo',
                        style: TextStyle(color: AppTheme.textDisabled, fontSize: 11)),
                  ],
                ),
              ),
              if (isEncrypted)
                Icon(Icons.lock, size: 12, color: const Color(0xFF4CAF50).withValues(alpha: 0.4)),
            ],
          ),
          const SizedBox(height: 10),
          // Body
          Text(body, style: TextStyle(color: AppTheme.postContent, fontSize: 14, height: 1.4)),
          // Image
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                ApiConfig.needsProxy(imageUrl)
                    ? ApiConfig.proxyImageUrl(imageUrl)
                    : imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ],
          // Actions
          if (!isEncrypted) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: onLike,
                  child: Row(
                    children: [
                      Icon(likedByMe ? Icons.favorite : Icons.favorite_border,
                          size: 18, color: likedByMe ? SojornColors.destructive : AppTheme.textDisabled),
                      const SizedBox(width: 4),
                      Text('$likeCount', style: TextStyle(color: AppTheme.textDisabled, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: onComment,
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 16, color: AppTheme.textDisabled),
                      const SizedBox(width: 4),
                      Text('$commentCount', style: TextStyle(color: AppTheme.textDisabled, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Comments Sheet ───────────────────────────────────────────────────────
class _CommentsSheet extends StatefulWidget {
  final String groupId;
  final String postId;
  const _CommentsSheet({required this.groupId, required this.postId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      _comments = await ApiService.instance.fetchGroupPostComments(widget.groupId, widget.postId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendComment(String text, String? _) async {
    await ApiService.instance.createGroupPostComment(widget.groupId, widget.postId, body: text);
    await _loadComments();
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
          Text('Comments', style: TextStyle(color: AppTheme.navyBlue, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Flexible(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? Center(child: Text('No comments yet', style: TextStyle(color: AppTheme.textDisabled)))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _comments.length,
                        itemBuilder: (_, i) {
                          final c = _comments[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(radius: 14, backgroundColor: AppTheme.brightNavy.withValues(alpha: 0.1),
                                    child: Icon(Icons.person, size: 14, color: AppTheme.brightNavy)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c['author_handle'] ?? '', style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 12)),
                                      const SizedBox(height: 2),
                                      Text(c['body'] ?? '', style: TextStyle(color: AppTheme.postContent, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 8),
          ComposerBar(
            config: ComposerConfig.comment,
            onSend: _sendComment,
          ),
        ],
      ),
    );
  }
}

