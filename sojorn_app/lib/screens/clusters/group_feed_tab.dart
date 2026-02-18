import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/capsule_security_service.dart';
import '../../services/image_upload_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gif/gif_picker.dart';

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
  final TextEditingController _postCtrl = TextEditingController();
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _posting = false;

  // Image / GIF attachment (public groups only)
  File? _pickedImage;
  String? _pendingImageUrl; // already-uploaded URL (from GIF or uploaded file)
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  @override
  void dispose() {
    _postCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(source: ImageSource.gallery);
    if (xf == null) return;
    setState(() { _pickedImage = File(xf.path); _pendingImageUrl = null; });
  }

  void _attachGif(String gifUrl) {
    setState(() { _pickedImage = null; _pendingImageUrl = gifUrl; });
  }

  void _clearAttachment() {
    setState(() { _pickedImage = null; _pendingImageUrl = null; });
  }

  Future<String?> _resolveImageUrl() async {
    if (_pendingImageUrl != null) return _pendingImageUrl;
    if (_pickedImage != null) {
      setState(() => _uploading = true);
      try {
        final url = await ImageUploadService().uploadImage(_pickedImage!);
        return url;
      } finally {
        if (mounted) setState(() => _uploading = false);
      }
    }
    return null;
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

  Future<void> _createPost() async {
    final text = _postCtrl.text.trim();
    final hasAttachment = _pickedImage != null || _pendingImageUrl != null;
    if ((text.isEmpty && !hasAttachment) || _posting) return;
    setState(() => _posting = true);
    try {
      if (widget.isEncrypted && widget.capsuleKey != null) {
        final encrypted = await CapsuleSecurityService.encryptPayload(
          payload: {'text': text, 'ts': DateTime.now().toIso8601String()},
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
        final imageUrl = await _resolveImageUrl();
        await ApiService.instance.createGroupPost(
          widget.groupId,
          body: text,
          imageUrl: imageUrl,
        );
      }
      _postCtrl.clear();
      _clearAttachment();
      await _loadPosts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
      }
    }
    if (mounted) setState(() => _posting = false);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.brightNavy.withValues(alpha: 0.1),
                    child: Icon(Icons.person, size: 18, color: AppTheme.brightNavy),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _postCtrl,
                      style: TextStyle(color: SojornColors.postContent, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: widget.isEncrypted ? 'Write an encrypted post…' : 'Write something…',
                        hintStyle: TextStyle(color: SojornColors.textDisabled),
                        filled: true,
                        fillColor: AppTheme.scaffoldBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                      textInputAction: TextInputAction.newline,
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: (_posting || _uploading) ? null : _createPost,
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_posting || _uploading)
                            ? AppTheme.brightNavy.withValues(alpha: 0.5)
                            : AppTheme.brightNavy,
                      ),
                      child: (_posting || _uploading)
                          ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                          : const Icon(Icons.send, color: SojornColors.basicWhite, size: 16),
                    ),
                  ),
                ],
              ),
              // Attachment buttons (public groups only) + preview
              if (!widget.isEncrypted) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MediaBtn(
                      icon: Icons.image_outlined,
                      label: 'Photo',
                      onTap: _pickImage,
                    ),
                    const SizedBox(width: 8),
                    _MediaBtn(
                      icon: Icons.gif_outlined,
                      label: 'GIF',
                      onTap: () => showGifPicker(context, onSelected: _attachGif),
                    ),
                    if (_pickedImage != null || _pendingImageUrl != null) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: _clearAttachment,
                        child: Icon(Icons.cancel, size: 18, color: AppTheme.textSecondary),
                      ),
                    ],
                  ],
                ),
                // Attachment preview
                if (_pickedImage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(_pickedImage!, height: 120, fit: BoxFit.cover),
                    ),
                  ),
                if (_pendingImageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        ApiConfig.needsProxy(_pendingImageUrl!)
                            ? ApiConfig.proxyImageUrl(_pendingImageUrl!)
                            : _pendingImageUrl!,
                        height: 120, fit: BoxFit.cover),
                    ),
                  ),
              ],
            ],
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
                          Text('No posts yet', style: TextStyle(color: SojornColors.postContentLight, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text('Be the first to post!', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
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
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.brightNavy.withValues(alpha: 0.1),
                backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty ? Icon(Icons.person, size: 16, color: AppTheme.brightNavy) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName.isNotEmpty ? displayName : handle,
                        style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('@$handle · $timeAgo',
                        style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                  ],
                ),
              ),
              if (isEncrypted)
                Icon(Icons.lock, size: 12, color: const Color(0xFF4CAF50).withValues(alpha: 0.4)),
            ],
          ),
          const SizedBox(height: 10),
          // Body
          Text(body, style: TextStyle(color: SojornColors.postContent, fontSize: 14, height: 1.4)),
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
                          size: 18, color: likedByMe ? SojornColors.destructive : SojornColors.textDisabled),
                      const SizedBox(width: 4),
                      Text('$likeCount', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  onTap: onComment,
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 16, color: SojornColors.textDisabled),
                      const SizedBox(width: 4),
                      Text('$commentCount', style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
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
  final _commentCtrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() { _commentCtrl.dispose(); super.dispose(); }

  Future<void> _loadComments() async {
    setState(() => _loading = true);
    try {
      _comments = await ApiService.instance.fetchGroupPostComments(widget.groupId, widget.postId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ApiService.instance.createGroupPostComment(widget.groupId, widget.postId, body: text);
      _commentCtrl.clear();
      await _loadComments();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
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
                    ? Center(child: Text('No comments yet', style: TextStyle(color: SojornColors.textDisabled)))
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
                                      Text(c['body'] ?? '', style: TextStyle(color: SojornColors.postContent, fontSize: 13)),
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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  style: TextStyle(color: SojornColors.postContent, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Write a comment…',
                    hintStyle: TextStyle(color: SojornColors.textDisabled),
                    filled: true, fillColor: AppTheme.scaffoldBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _sendComment(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sendComment,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.brightNavy),
                  child: _sending
                      ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                      : const Icon(Icons.send, color: SojornColors.basicWhite, size: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MediaBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MediaBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.navyBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
