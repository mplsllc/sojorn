import 'package:flutter/material.dart';
import 'package:cryptography/cryptography.dart';
import '../../services/api_service.dart';
import '../../services/capsule_security_service.dart';
import '../../services/content_guard_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

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
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
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
        _messages = msgs.reversed.toList(); // API returns newest first, we want oldest first
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

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

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
            'data_type': 'chat',
            'key_version': 1,
          },
        );
      } else {
        await ApiService.instance.sendGroupMessage(widget.groupId, body: text);
      }
      _msgCtrl.clear();
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
    if (mounted) setState(() => _sending = false);
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
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final msg = _messages[i];
                          final isMine = msg['author_id']?.toString() == widget.currentUserId;
                          return _ChatBubble(
                            message: msg,
                            isMine: isMine,
                            isEncrypted: widget.isEncrypted,
                            timeStr: _timeStr(msg['created_at']?.toString()),
                          );
                        },
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
                      hintText: widget.isEncrypted ? 'Encrypted message…' : 'Type a message…',
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
                      color: _sending ? AppTheme.brightNavy.withValues(alpha: 0.5) : AppTheme.brightNavy,
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

// ── Chat Bubble ──────────────────────────────────────────────────────────
class _ChatBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final bool isEncrypted;
  final String timeStr;

  const _ChatBubble({
    required this.message,
    required this.isMine,
    required this.isEncrypted,
    required this.timeStr,
  });

  @override
  Widget build(BuildContext context) {
    final body = message['body'] as String? ?? '';
    final handle = message['author_handle'] as String? ?? '';
    final displayName = message['author_display_name'] as String? ?? handle;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMine
              ? (isEncrypted ? const Color(0xFFE8F5E9) : AppTheme.brightNavy.withValues(alpha: 0.08))
              : AppTheme.cardSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          border: isMine ? null : Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Always show sender name
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMine ? 'You' : (displayName.isNotEmpty ? displayName : handle),
                    style: TextStyle(
                      color: isMine
                          ? (isEncrypted ? const Color(0xFF4CAF50) : AppTheme.brightNavy)
                          : AppTheme.navyBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (handle.isNotEmpty && !isMine) ...[
                    const SizedBox(width: 4),
                    Text('@$handle', style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
                  ],
                  const SizedBox(width: 6),
                  Text(timeStr, style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
                ],
              ),
            ),
            Text(body, style: TextStyle(color: SojornColors.postContent, fontSize: 14, height: 1.35)),
          ],
        ),
      ),
    );
  }
}
