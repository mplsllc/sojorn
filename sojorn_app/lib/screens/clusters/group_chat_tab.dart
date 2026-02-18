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
      await ApiService.instance.callGoApi(
        '/capsules/${widget.groupId}/entries/$entryId/report',
        method: 'POST',
        body: {
          'reason': reason,
          if (sample.isNotEmpty && sample != '[Decryption failed]')
            'decrypted_sample': sample,
        },
      );
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
                            gifUrl: msg['gif_url'] as String?,
                            onReport: (!isMine && widget.isEncrypted)
                                ? () => _reportMessage(msg)
                                : null,
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

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onReport,
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
            if (body.isNotEmpty)
              Text(body, style: TextStyle(color: SojornColors.postContent, fontSize: 14, height: 1.35)),
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
        ),
      ),
    );
  }
}
