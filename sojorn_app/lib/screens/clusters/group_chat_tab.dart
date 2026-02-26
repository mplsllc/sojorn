// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/capsule_security_service.dart';
import '../../services/content_guard_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/composer/composer_bar.dart';

class GroupChatTab extends StatefulWidget {
  final String groupId;
  final bool isEncrypted;
  final SecretKey? capsuleKey;
  final String? currentUserId;

  const GroupChatTab({
    super.key,
    required this.groupId,
    this.isEncrypted = false,
    this.capsuleKey,
    this.currentUserId,
  });

  @override
  State<GroupChatTab> createState() => _GroupChatTabState();
}

class _GroupChatTabState extends State<GroupChatTab> {
  final ScrollController _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      if (widget.isEncrypted) {
        await _loadEncryptedMessages();
      } else {
        final msgs = await ApiService.instance.fetchGroupMessages(widget.groupId);
        // Detect GIF URLs stored as body text (from sendGroupMessage fallback)
        _messages = msgs.reversed.map((msg) {
          final body = msg['body'] as String? ?? '';
          if (msg['gif_url'] == null && body.isNotEmpty && ApiConfig.needsProxy(body)) {
            return Map<String, dynamic>.from(msg)
              ..['gif_url'] = body
              ..['body'] = '';
          }
          return msg;
        }).toList();
      }
    } catch (e) {
      debugPrint('[GroupChat] Error: $e');
    }
    if (mounted) setState(() => _loading = false);
    _scrollToBottom();
  }

  Future<void> _loadEncryptedMessages() async {
    if (widget.capsuleKey == null) return;
    final data = await ApiService.instance.callGoApi(
      '/capsules/${widget.groupId}/entries',
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
          'author_display_name': entry['author_display_name'] ?? '',
          'author_avatar_url': entry['author_avatar_url'] ?? '',
          'created_at': entry['created_at'],
          'body': payload['text'] ?? '',
          'gif_url': payload['gif_url'],
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
    _messages = decrypted.reversed.toList();
  }

  Future<void> _onChatSend(String text, String? gifUrl) async {
    if (text.isNotEmpty) {
      // Local content guard — block before encryption
      final guardReason = ContentGuardService.instance.check(text);
      if (guardReason != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(guardReason), backgroundColor: Colors.red),
          );
        }
        throw Exception('blocked'); // prevents ComposerBar from clearing
      }

      // Server-side AI moderation — stateless, nothing stored
      final aiReason = await ApiService.instance.moderateContent(text: text, context: 'group');
      if (aiReason != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(aiReason), backgroundColor: Colors.red),
          );
        }
        throw Exception('blocked');
      }
    }

    final payload = {
      'text': text,
      'ts': DateTime.now().toIso8601String(),
      if (gifUrl != null) 'gif_url': gifUrl,
    };

    if (widget.isEncrypted && widget.capsuleKey != null) {
      final encrypted = await CapsuleSecurityService.encryptPayload(
        payload: payload,
        capsuleKey: widget.capsuleKey!,
      );
      await ApiService.instance.callGoApi(
        '/capsules/${widget.groupId}/entries',
        method: 'POST',
        body: {
          'iv': encrypted.iv,
          'encrypted_payload': encrypted.encryptedPayload,
          'data_type': 'chat',
          'key_version': 1,
        },
      );
    } else {
      await ApiService.instance.sendGroupMessage(
          widget.groupId, body: text.isNotEmpty ? text : gifUrl ?? '');
    }
    if (mounted) await _loadMessages();
  }

  void _reportMessage(Map<String, dynamic> msg) {
    final entryId = msg['id']?.toString() ?? '';
    final body = msg['body'] as String? ?? '';
    if (entryId.isEmpty) return;

    String? selectedReason;
    const reasons = ['Harassment', 'Hate speech', 'Threats', 'Spam', 'Illegal content', 'Other'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setBS) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report Message',
                  style: TextStyle(
                      color: AppTheme.navyBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Why are you reporting this message?',
                  style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
              const SizedBox(height: 16),
              ...reasons.map((r) => RadioListTile<String>(
                    dense: true,
                    title: Text(r,
                        style: TextStyle(color: SojornColors.postContent, fontSize: 14)),
                    value: r,
                    groupValue: selectedReason,
                    activeColor: AppTheme.brightNavy,
                    onChanged: (v) => setBS(() => selectedReason = v),
                  )),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brightNavy,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: selectedReason == null
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          await _submitReport(entryId, selectedReason!, body);
                        },
                  child: const Text('Submit Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport(String entryId, String reason, String sample) async {
    try {
      if (widget.isEncrypted) {
        // Encrypted capsule: use capsule entry report endpoint (includes decrypted_sample)
        await ApiService.instance.callGoApi(
          '/capsules/${widget.groupId}/entries/$entryId/report',
          method: 'POST',
          body: {
            'reason': reason,
            if (sample.isNotEmpty && sample != '[Decryption failed]')
              'decrypted_sample': sample,
          },
        );
      } else {
        // Regular group: use message report endpoint
        await ApiService.instance.callGoApi(
          '/capsules/${widget.groupId}/messages/$entryId/report',
          method: 'POST',
          body: {
            'reason': reason,
            'description': sample.length > 200 ? sample.substring(0, 200) : sample,
          },
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Could not submit report. Please try again.')),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _timeStr(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:${dt.minute.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return '';
    }
  }

  /// Interleaves date-separator sentinels into the message list.
  ///
  /// Returns a flat list of either [Map<String, dynamic>] (message) or
  /// [DateTime] (date separator label). The ListView renders each type
  /// differently so users can see "Today", "Yesterday", or "Mar 15" headers
  /// between groups of messages from different days.
  List<dynamic> _buildChatItems() {
    final items = <dynamic>[];
    DateTime? lastDate;
    for (final msg in _messages) {
      final rawDate = msg['created_at']?.toString();
      DateTime? msgDate;
      if (rawDate != null) {
        try {
          final local = DateTime.parse(rawDate).toLocal();
          msgDate = DateTime(local.year, local.month, local.day);
        } catch (_) {}
      }
      if (msgDate != null && msgDate != lastDate) {
        items.add(msgDate); // date separator sentinel
        lastDate = msgDate;
      }
      items.add(msg);
    }
    return items;
  }

  /// Human-readable date label for a chat separator.
  String _dateSeparatorLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (date == today) return 'Today';
    if (date == yesterday) return 'Yesterday';
    // e.g. "Feb 21"
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[date.month - 1]} ${date.day}${date.year != today.year ? ', ${date.year}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 40, color: AppTheme.navyBlue.withValues(alpha: 0.15)),
                          const SizedBox(height: 12),
                          Text('No messages yet', style: TextStyle(color: SojornColors.postContentLight, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(widget.isEncrypted ? 'Messages are end-to-end encrypted' : 'Start the conversation!',
                              style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMessages,
                      child: Builder(
                        builder: (_) {
                          final items = _buildChatItems();
                          return ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final item = items[i];
                              // Date separator sentinel
                              if (item is DateTime) {
                                return _DateSeparator(label: _dateSeparatorLabel(item));
                              }
                              final msg = item as Map<String, dynamic>;
                              final isMine = msg['author_id']?.toString() == widget.currentUserId;
                              return _ChatBubble(
                                message: msg,
                                isMine: isMine,
                                isEncrypted: widget.isEncrypted,
                                timeStr: _timeStr(msg['created_at']?.toString()),
                                gifUrl: msg['gif_url'] as String?,
                                onReport: !isMine
                                    ? () => _reportMessage(msg)
                                    : null,
                              );
                            },
                          );
                        },
                      ),
                    ),
        ),
        // Compose bar
        Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 12),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(top: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.08))),
          ),
          child: SafeArea(
            top: false,
            child: ComposerBar(
              config: widget.isEncrypted
                  ? const ComposerConfig(allowGifs: true, hintText: 'Encrypted message…')
                  : ComposerConfig.chat,
              onSend: _onChatSend,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Chat Bubble ──────────────────────────────────────────────────────────
class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final bool isEncrypted;
  final String timeStr;
  final String? gifUrl;
  final VoidCallback? onReport;

  const _ChatBubble({
    required this.message,
    required this.isMine,
    required this.isEncrypted,
    required this.timeStr,
    this.gifUrl,
    this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final body = message['body'] as String? ?? '';
    final handle = message['author_handle'] as String? ?? '';
    final displayName = message['author_display_name'] as String? ?? handle;
    final avatarUrl = message['author_avatar_url'] as String?;

    // Color scheme: mine = brand indigo + white text / others = slate-100 + dark text.
    final bubbleBg = isMine
        ? (isEncrypted ? const Color(0xFF2E7D32) : AppTheme.brightNavy)
        : const Color(0xFFF1F5F9);
    final textColor = isMine ? Colors.white : SojornColors.postContent;

    final isDesktop = MediaQuery.of(context).size.width >= 900;

    Widget bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (isDesktop ? 0.5 : 0.72)),
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 13, vertical: isDesktop ? 11 : 9),
      decoration: BoxDecoration(
        color: bubbleBg,
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
          // Sender name (other users only)
          if (!isMine) ...[
            Text(
              displayName.isNotEmpty ? displayName : handle,
              style: TextStyle(
                color: AppTheme.navyBlue,
                fontSize: isDesktop ? 13 : 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
          ],
          if (body.isNotEmpty)
            Text(body, style: TextStyle(color: textColor, fontSize: isDesktop ? 15 : 14, height: 1.4)),
          if (gifUrl != null) ...[
            if (body.isNotEmpty) const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: ApiConfig.needsProxy(gifUrl!)
                    ? ApiConfig.proxyImageUrl(gifUrl!)
                    : gifUrl!,
                width: 200,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 200, height: 120,
                  color: AppTheme.navyBlue.withValues(alpha: 0.05),
                  child: Icon(Icons.gif_outlined, color: AppTheme.textSecondary, size: 32),
                ),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );

    return GestureDetector(
      onLongPress: onReport,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMine ? 48 : 0,
          right: isMine ? 0 : 48,
          top: 2, bottom: 2,
        ),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                // Avatar for other users' messages
                if (!isMine) ...[
                  _MiniAvatar(handle: handle, avatarUrl: avatarUrl),
                  const SizedBox(width: 6),
                ],
                Flexible(child: bubble),
              ],
            ),
            // Timestamp below the bubble
            Padding(
              padding: EdgeInsets.only(
                left: isMine ? 0 : 34,
                right: isMine ? 4 : 0,
                top: 2,
              ),
              child: Text(
                timeStr,
                style: TextStyle(
                  color: SojornColors.textDisabled.withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded-square avatar for chat bubbles (responsive: 28px mobile, 36px desktop).
class _MiniAvatar extends StatelessWidget {
  final String handle;
  final String? avatarUrl;
  const _MiniAvatar({required this.handle, this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final size = isDesktop ? 36.0 : 28.0;
    final radius = isDesktop ? 10.0 : 8.0;
    final fontSize = isDesktop ? 14.0 : 12.0;
    final initial = handle.isNotEmpty ? handle[0].toUpperCase() : '?';
    final hue = (handle.hashCode % 360).toDouble();
    final bg = HSLColor.fromAHSL(1.0, hue, 0.45, 0.55).toColor();
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: avatarUrl != null && avatarUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: CachedNetworkImage(
                imageUrl: avatarUrl!,
                width: size, height: size,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Center(
                  child: Text(initial,
                      style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w700)),
                ),
              ),
            )
          : Center(
              child: Text(initial,
                  style: TextStyle(color: Colors.white, fontSize: fontSize, fontWeight: FontWeight.w700)),
            ),
    );
  }
}

/// Horizontal date separator — "Today", "Yesterday", or "Mar 15".
class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppTheme.navyBlue.withValues(alpha: 0.1), thickness: 1)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.scaffoldBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.navyText.withValues(alpha: 0.45),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: AppTheme.navyBlue.withValues(alpha: 0.1), thickness: 1)),
        ],
      ),
    );
  }
}
