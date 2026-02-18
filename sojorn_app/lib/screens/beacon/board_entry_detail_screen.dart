import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/board_entry.dart';
import '../../services/api_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/composer/composer_bar.dart';

class BoardEntryDetailScreen extends ConsumerStatefulWidget {
  final BoardEntry entry;

  const BoardEntryDetailScreen({super.key, required this.entry});

  @override
  ConsumerState<BoardEntryDetailScreen> createState() => _BoardEntryDetailScreenState();
}

class _BoardEntryDetailScreenState extends ConsumerState<BoardEntryDetailScreen> {
  late BoardEntry _entry;
  List<BoardReply> _replies = [];
  bool _isLoading = true;
  bool _isNeighborhoodAdmin = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _loadDetail();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final data = await ApiService.instance.getBoardEntry(_entry.id);
      if (mounted) {
        final entryJson = data['entry'] as Map<String, dynamic>;
        final repliesJson = data['replies'] as List? ?? [];
        setState(() {
          _entry = BoardEntry.fromJson(entryJson);
          _replies = repliesJson.map((r) => BoardReply.fromJson(r as Map<String, dynamic>)).toList();
          _isNeighborhoodAdmin = data['is_neighborhood_admin'] == true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) print('[Board] Detail load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendReply(String text, String? _) async {
    final data = await ApiService.instance.createBoardReply(
      entryId: _entry.id,
      body: text,
    );
    if (mounted) {
      final reply = BoardReply.fromJson(data['reply'] as Map<String, dynamic>);
      setState(() {
        _replies.add(reply);
        _entry = BoardEntry(
          id: _entry.id, body: _entry.body, imageUrl: _entry.imageUrl, topic: _entry.topic,
          lat: _entry.lat, long: _entry.long, upvotes: _entry.upvotes,
          replyCount: _entry.replyCount + 1, isPinned: _entry.isPinned, createdAt: _entry.createdAt,
          authorHandle: _entry.authorHandle, authorDisplayName: _entry.authorDisplayName,
          authorAvatarUrl: _entry.authorAvatarUrl, hasVoted: _entry.hasVoted,
        );
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _toggleEntryVote() async {
    try {
      final result = await ApiService.instance.toggleBoardVote(entryId: _entry.id);
      final voted = result['voted'] as bool? ?? false;
      if (mounted) {
        setState(() {
          _entry = BoardEntry(
            id: _entry.id, body: _entry.body, imageUrl: _entry.imageUrl, topic: _entry.topic,
            lat: _entry.lat, long: _entry.long,
            upvotes: voted ? _entry.upvotes + 1 : _entry.upvotes - 1,
            replyCount: _entry.replyCount, isPinned: _entry.isPinned, createdAt: _entry.createdAt,
            authorHandle: _entry.authorHandle, authorDisplayName: _entry.authorDisplayName,
            authorAvatarUrl: _entry.authorAvatarUrl, hasVoted: voted,
          );
        });
      }
    } catch (e) {
      if (kDebugMode) print('[Board] Vote error: $e');
    }
  }

  Future<void> _toggleReplyVote(int index) async {
    final reply = _replies[index];
    try {
      final result = await ApiService.instance.toggleBoardVote(replyId: reply.id);
      final voted = result['voted'] as bool? ?? false;
      if (mounted) {
        setState(() {
          _replies[index] = BoardReply(
            id: reply.id, body: reply.body,
            upvotes: voted ? reply.upvotes + 1 : reply.upvotes - 1,
            createdAt: reply.createdAt,
            authorHandle: reply.authorHandle, authorDisplayName: reply.authorDisplayName,
            authorAvatarUrl: reply.authorAvatarUrl, hasVoted: voted,
          );
        });
      }
    } catch (e) {
      if (kDebugMode) print('[Board] Reply vote error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final topicColor = _entry.topic.color;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppTheme.cardSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.navyBlue),
          onPressed: () => Navigator.of(context).pop(_entry),
        ),
        title: Row(
          children: [
            Icon(_entry.topic.icon, size: 18, color: topicColor),
            const SizedBox(width: 8),
            Text(_entry.topic.displayName,
              style: TextStyle(color: AppTheme.navyBlue, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Scrollable content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadDetail,
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Entry card
                        _buildEntryHeader(),
                        const SizedBox(height: 16),
                        // Replies section
                        if (_replies.isNotEmpty) ...[
                          Text('Replies (${_replies.length})',
                            style: TextStyle(color: AppTheme.navyBlue, fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          ...List.generate(_replies.length, (i) => _buildReplyCard(i)),
                        ] else ...[
                          const SizedBox(height: 40),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 36, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                                const SizedBox(height: 8),
                                Text('No replies yet — be the first!',
                                  style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          // Reply composer
          _buildReplyComposer(),
        ],
      ),
    );
  }

  Widget _buildEntryHeader() {
    final topicColor = _entry.topic.color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Topic + time
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: topicColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_entry.topic.icon, size: 13, color: topicColor),
                  const SizedBox(width: 4),
                  Text(_entry.topic.displayName,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: topicColor)),
                ]),
              ),
              if (_entry.isPinned) ...[
                const SizedBox(width: 6),
                Icon(Icons.push_pin, size: 13, color: AppTheme.brightNavy),
              ],
              const Spacer(),
              Text(_entry.getTimeAgo(), style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
              const Spacer(),
              if (_isNeighborhoodAdmin)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz, size: 16, color: SojornColors.textDisabled),
                  onSelected: (val) {
                    if (val == 'remove') _removeEntry();
                    if (val == 'flag') _flagEntry();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'flag', child: Text('Flag Content')),
                    const PopupMenuItem(value: 'remove', child: Text('Remove (Admin)', style: TextStyle(color: SojornColors.destructive))),
                  ],
                )
              else
                IconButton(
                  icon: Icon(Icons.flag_outlined, size: 16, color: SojornColors.textDisabled),
                  onPressed: _flagEntry,
                  tooltip: 'Report Content',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Author
          Row(
            children: [
              SojornAvatar(
                displayName: _entry.authorDisplayName.isNotEmpty ? _entry.authorDisplayName : _entry.authorHandle,
                avatarUrl: _entry.authorAvatarUrl.isNotEmpty ? _entry.authorAvatarUrl : null,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                _entry.authorDisplayName.isNotEmpty ? _entry.authorDisplayName : _entry.authorHandle,
                style: TextStyle(color: AppTheme.navyBlue, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Body
          Text(_entry.body,
            style: TextStyle(color: SojornColors.postContent, fontSize: 15, height: 1.5)),
          // Image
          if (_entry.imageUrl != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(_entry.imageUrl!, width: double.infinity, fit: BoxFit.cover),
            ),
          ],
          const SizedBox(height: 14),
          // Actions
          Row(
            children: [
              // Upvote
              GestureDetector(
                onTap: _toggleEntryVote,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _entry.hasVoted ? AppTheme.brightNavy.withValues(alpha: 0.1) : AppTheme.scaffoldBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _entry.hasVoted ? AppTheme.brightNavy.withValues(alpha: 0.3) : AppTheme.navyBlue.withValues(alpha: 0.1)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.arrow_upward, size: 15,
                      color: _entry.hasVoted ? AppTheme.brightNavy : SojornColors.textDisabled),
                    const SizedBox(width: 4),
                    Text('${_entry.upvotes}', style: TextStyle(
                      color: _entry.hasVoted ? AppTheme.brightNavy : SojornColors.textDisabled,
                      fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              // Reply count
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.scaffoldBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline, size: 14, color: SojornColors.textDisabled),
                  const SizedBox(width: 4),
                  Text('${_entry.replyCount}', style: TextStyle(
                    color: SojornColors.textDisabled, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReplyCard(int index) {
    final reply = _replies[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author + time
            Row(
              children: [
                SojornAvatar(
                  displayName: reply.authorDisplayName.isNotEmpty ? reply.authorDisplayName : reply.authorHandle,
                  avatarUrl: reply.authorAvatarUrl.isNotEmpty ? reply.authorAvatarUrl : null,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reply.authorDisplayName.isNotEmpty ? reply.authorDisplayName : reply.authorHandle,
                    style: TextStyle(color: AppTheme.navyBlue, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                Text(reply.getTimeAgo(), style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                const Spacer(),
                GestureDetector(
                  onTap: () => _flagReply(reply.id),
                  child: Icon(Icons.flag_outlined, size: 14, color: SojornColors.textDisabled.withValues(alpha: 0.5)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Body
            Text(reply.body,
              style: TextStyle(color: SojornColors.postContentLight, fontSize: 14, height: 1.4)),
            const SizedBox(height: 8),
            // Upvote
            GestureDetector(
              onTap: () => _toggleReplyVote(index),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(reply.hasVoted ? Icons.arrow_upward : Icons.arrow_upward_outlined,
                  size: 13, color: reply.hasVoted ? AppTheme.brightNavy : SojornColors.textDisabled),
                const SizedBox(width: 3),
                Text('${reply.upvotes}', style: TextStyle(
                  color: reply.hasVoted ? AppTheme.brightNavy : SojornColors.textDisabled, fontSize: 12)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyComposer() {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 8, MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border(top: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.08))),
      ),
      child: ComposerBar(
        config: const ComposerConfig(hintText: 'Write a reply…'),
        onSend: _sendReply,
      ),
    );
  }

  Future<void> _removeEntry() async {
    final confirmed = await _confirmAction('Remove Entry', 'Are you sure you want to remove this post?');
    if (confirmed == true) {
      final reason = await _promptReason('Reason for removal');
      if (reason != null) {
        try {
          await ApiService.instance.removeBoardEntry(_entry.id, reason);
          if (mounted) {
            Navigator.of(context).pop(); // Go back
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry removed')));
          }
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }



  Future<void> _flagEntry() async {
    final reason = await _promptReason('Report Reason');
    if (reason != null) {
      try {
        await ApiService.instance.flagBoardEntry(_entry.id, reason);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _flagReply(String replyId) async {
    final reason = await _promptReason('Report Reason');
    if (reason != null) {
      try {
        await ApiService.instance.flagBoardEntry(_entry.id, reason, replyId: replyId);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<bool?> _confirmAction(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm', style: TextStyle(color: SojornColors.destructive))),
        ],
      ),
    );
  }

  Future<String?> _promptReason(String label) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(controller: controller, decoration: InputDecoration(hintText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    return confirmed == true && controller.text.isNotEmpty ? controller.text : null;
  }
}
