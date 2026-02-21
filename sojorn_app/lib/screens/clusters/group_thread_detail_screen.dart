// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import '../../services/api_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/composer/composer_bar.dart';

/// Thread detail screen with replies — works for both public and encrypted groups.
/// For encrypted groups, thread detail isn't supported via the standard API yet,
/// so we show a placeholder until capsule_entries reply support is wired.
class GroupThreadDetailScreen extends StatefulWidget {
  final String groupId;
  final String threadId;
  final bool isEncrypted;
  final SecretKey? capsuleKey;
  final String threadTitle;

  const GroupThreadDetailScreen({
    super.key,
    required this.groupId,
    required this.threadId,
    this.isEncrypted = false,
    this.capsuleKey,
    required this.threadTitle,
  });

  @override
  State<GroupThreadDetailScreen> createState() => _GroupThreadDetailScreenState();
}

class _GroupThreadDetailScreenState extends State<GroupThreadDetailScreen> {
  Map<String, dynamic>? _thread;
  List<Map<String, dynamic>> _replies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThread();
  }

  Future<void> _loadThread() async {
    setState(() => _loading = true);
    try {
      if (widget.isEncrypted) {
        // For encrypted groups, we don't have a thread detail endpoint yet
        // Show the thread title and a message
        _thread = {'title': widget.threadTitle, 'body': '', 'author_handle': ''};
        _replies = [];
      } else {
        final data = await ApiService.instance.fetchGroupThread(widget.groupId, widget.threadId);
        _thread = data['thread'] as Map<String, dynamic>?;
        _replies = (data['replies'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (e) {
      debugPrint('[ThreadDetail] Error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _sendReply(String text, String? _) async {
    await ApiService.instance.createGroupThreadReply(widget.groupId, widget.threadId, body: text);
    await _loadThread();
  }

  int _uniqueParticipants() {
    final authors = <String>{};
    if (_thread != null) {
      final a = _thread!['author_id']?.toString() ?? _thread!['author_handle']?.toString() ?? '';
      if (a.isNotEmpty) authors.add(a);
    }
    for (final r in _replies) {
      final a = r['author_id']?.toString() ?? r['author_handle']?.toString() ?? '';
      if (a.isNotEmpty) authors.add(a);
    }
    return authors.length;
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
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppTheme.cardSurface,
        foregroundColor: AppTheme.navyBlue,
        surfaceTintColor: SojornColors.transparent,
        title: Text(widget.threadTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Original post (highlighted)
                      if (_thread != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.cardSurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.brightNavy.withValues(alpha: 0.25), width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _thread!['title'] as String? ?? '',
                                style: TextStyle(color: AppTheme.navyBlue, fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    _thread!['author_display_name'] as String? ??
                                        _thread!['author_handle'] as String? ?? '',
                                    style: TextStyle(color: AppTheme.brightNavy, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _timeAgo(_thread!['created_at']?.toString()),
                                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
                                  ),
                                ],
                              ),
                              if ((_thread!['body'] as String? ?? '').isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  _thread!['body'] as String,
                                  style: TextStyle(color: SojornColors.postContent, fontSize: 14, height: 1.5),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Chain metadata
                        Row(
                          children: [
                            Icon(Icons.forum_outlined, size: 14, color: AppTheme.navyBlue.withValues(alpha: 0.5)),
                            const SizedBox(width: 6),
                            Text(
                              '${_replies.length} ${_replies.length == 1 ? 'reply' : 'replies'}',
                              style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.people_outline, size: 14, color: AppTheme.navyBlue.withValues(alpha: 0.5)),
                            const SizedBox(width: 4),
                            Text(
                              '${_uniqueParticipants()} participants',
                              style: TextStyle(color: SojornColors.textDisabled, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.isEncrypted && _replies.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'Encrypted thread replies coming soon',
                              style: TextStyle(color: SojornColors.textDisabled, fontSize: 13),
                            ),
                          ),
                        ),
                      // Replies with thread connector
                      for (int i = 0; i < _replies.length; i++)
                        _ReplyCard(
                          reply: _replies[i],
                          timeAgo: _timeAgo(_replies[i]['created_at']?.toString()),
                          showConnector: i < _replies.length - 1,
                        ),
                    ],
                  ),
                ),
                // Reply composer
                if (!widget.isEncrypted)
                  Container(
                    padding: EdgeInsets.fromLTRB(12, 8, 8, MediaQuery.of(context).padding.bottom + 8),
                    decoration: BoxDecoration(
                      color: AppTheme.cardSurface,
                      border: Border(top: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.08))),
                    ),
                    child: ComposerBar(
                      config: ComposerConfig.threadReply,
                      onSend: _sendReply,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  final Map<String, dynamic> reply;
  final String timeAgo;
  final bool showConnector;
  const _ReplyCard({required this.reply, required this.timeAgo, this.showConnector = false});

  @override
  Widget build(BuildContext context) {
    final handle = reply['author_handle'] as String? ?? '';
    final displayName = reply['author_display_name'] as String? ?? handle;
    final avatarUrl = reply['author_avatar_url'] as String? ?? '';
    final body = reply['body'] as String? ?? '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thread connector line
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 2, height: 8,
                  color: AppTheme.navyBlue.withValues(alpha: 0.12),
                ),
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.navyBlue.withValues(alpha: 0.15),
                  ),
                ),
                if (showConnector)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppTheme.navyBlue.withValues(alpha: 0.12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Reply content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SojornAvatar(
                        displayName: displayName.isNotEmpty ? displayName : handle,
                        avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Text(displayName.isNotEmpty ? displayName : handle,
                          style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(timeAgo, style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(body, style: TextStyle(color: SojornColors.postContent, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
