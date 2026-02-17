import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/secure_chat.dart';
import '../../services/api_service.dart';
import '../../services/secure_chat_service.dart';
import '../../services/local_message_store.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../services/notification_service.dart';
import '../../widgets/media/signed_media_image.dart';
import '../../widgets/secure_chat/chat_bubble_widget.dart';
import '../../widgets/secure_chat/composer_widget.dart';

/// Secure chat conversation screen with local-first, optimistic UI.
class SecureChatScreen extends StatefulWidget {
  final SecureConversation conversation;
  final bool isModal;
  final ScrollController? scrollController;

  const SecureChatScreen({
    super.key,
    required this.conversation,
    this.isModal = false,
    this.scrollController,
  });

  @override
  State<SecureChatScreen> createState() => _SecureChatScreenState();
}

class _SecureChatScreenState extends State<SecureChatScreen>
    with WidgetsBindingObserver {
  final SecureChatService _chatService = SecureChatService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final GlobalKey _listViewportKey = GlobalKey();
  final Set<String> _deletedMessageIds = {};

  late final Stream<List<LocalMessageRecord>> _messageStream;
  final List<_PendingMessage> _pendingMessages = [];

  bool _isSending = false;
  String _activeDateLabel = '';
  _ReplyPreview? _replyPreview;
  String? _currentUserAvatarUrl;
  String? _currentUserInitial;
  String? _otherUserAvatarUrl;
  String? _otherUserInitial;

  String get _currentUserId => _chatService.currentUserId ?? '';
  String get _recipientId => widget.conversation.getOtherId(_currentUserId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messageStream = _chatService.getMessagesStream(widget.conversation.id);
    NotificationService.instance.activeConversationId = widget.conversation.id;
    _markAsRead();
    _hydrateAvatars();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.activeConversationId = null;
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markAsRead();
    }
  }

  Future<void> _markAsRead() async {
    await _chatService.markAsRead(widget.conversation.id);
  }

  Future<void> _hydrateAvatars() async {
    setState(() {
      _otherUserAvatarUrl = widget.conversation.otherUserAvatarUrl;
      _otherUserInitial = _initialFor(
        widget.conversation.otherUserDisplayName ??
            widget.conversation.otherUserHandle ??
            '',
      );
    });

    final userId = _currentUserId;
    if (userId.isEmpty) return;

    try {
      final data = await ApiService.instance.getProfileById(userId);
      final profile = data['profile'];
      if (!mounted) return;
      if (profile != null) {
        setState(() {
          _currentUserAvatarUrl = profile.avatarUrl;
          _currentUserInitial = _initialFor(
            profile.displayName.isNotEmpty
                ? profile.displayName
                : profile.handle,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final rawText = _messageController.text.trim();
    if (rawText.isEmpty) return;

    final composedText = _replyPreview != null
        ? 'Replying to ${_replyPreview!.label}\n$rawText'
        : rawText;

    final pendingId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final pending = _PendingMessage(
      id: pendingId,
      text: composedText,
      createdAt: DateTime.now(),
    );

    setState(() {
      _isSending = true;
      _pendingMessages.add(pending);
      _replyPreview = null;
    });

    _messageController.clear();

    try {
      final message = await _chatService.sendMessage(
        widget.conversation.id,
        _recipientId,
        composedText,
      );

      if (!mounted) return;

      setState(() {
        _isSending = false;
        if (message != null) {
          _pendingMessages.removeWhere((p) => p.id == pendingId);
        } else {
          _flagPendingAsFailed(pendingId);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _flagPendingAsFailed(pendingId);
      });
      
      String errorMessage = 'Failed to send message';
      if (e.toString().contains('signed_prekey') || e.toString().contains('key bundle')) {
        errorMessage = 'Recipient\'s security keys are invalid. They must open the app to fix this.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _flagPendingAsFailed(String pendingId) {
    final index =
        _pendingMessages.indexWhere((element) => element.id == pendingId);
    if (index == -1) return;
    final updated = _pendingMessages[index].copyWith(failed: true);
    _pendingMessages[index] = updated;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.scrollController ?? _scrollController;

    if (widget.isModal) {
      return Column(
        children: [
          Expanded(child: _buildMessageStream(controller)),
          _buildInputArea(),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMessageStream(controller)),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.scaffoldBg,
      elevation: 0,
      surfaceTintColor: SojornColors.transparent,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: Icon(Icons.arrow_back, color: AppTheme.navyBlue),
      ),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.queenPink.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: widget.conversation.otherUserAvatarUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SignedMediaImage(
                      url: widget.conversation.otherUserAvatarUrl!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: Text(
                      (widget.conversation.otherUserHandle?.isNotEmpty ??
                              false)
                          ? widget.conversation.otherUserHandle![0].toUpperCase()
                          : '?',
                      style: GoogleFonts.inter(
                        color: AppTheme.navyBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.conversation.otherUserDisplayName ??
                      '@${widget.conversation.otherUserHandle ?? 'Unknown'}',
                  style: GoogleFonts.literata(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.navyBlue,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Encrypted with Signal',
                  style: GoogleFonts.inter(
                    color: AppTheme.textDisabled,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Key upload removed - available in main chat list
      ],
    );
  }

  Widget _buildMessageStream(ScrollController controller) {
    return StreamBuilder<List<LocalMessageRecord>>(
      stream: _messageStream,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];
        _reconcilePending(messages);

        if (snapshot.connectionState == ConnectionState.waiting &&
            messages.isEmpty &&
            _pendingMessages.isEmpty) {
          return _buildSoftLoader();
        }

        final items = _buildListItems(messages);
        if (items.isEmpty) {
          return _buildEmptyState();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _markAsRead();
          _refreshActiveHeader(items);
          _updateStickyDateLabel();
          _maybeScrollToBottom();
        });

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification ||
                notification is OverscrollNotification) {
              _updateStickyDateLabel();
            }
            return false;
          },
          child: Stack(
            children: [
              Container(
                key: _listViewportKey,
                color: SojornColors.transparent,
                child: ListView.builder(
                  reverse: true,
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final displayIndex = items.length - 1 - index;
                    final current = items[displayIndex];
                    final previous =
                        displayIndex > 0 ? items[displayIndex - 1] : null;
                    final next = displayIndex < items.length - 1
                        ? items[displayIndex + 1]
                        : null;

                    final showDateHeader = previous == null ||
                        !_isSameDay(previous.timestamp, current.timestamp);
                    final startsCluster =
                        previous == null || !_canCluster(previous, current);
                    final endsCluster =
                        next == null || !_canCluster(current, next);
                    final dateLabel = _labelForDate(current.timestamp);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDateHeader)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6, top: 12),
                            child: _DatePill(
                              key: ValueKey('date-header-$dateLabel'),
                              label: dateLabel,
                            ),
                          ),
                        Dismissible(
                          key: ValueKey('swipe-${current.id}-${current.isPending}'),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (direction) async {
                            if (current.isPending) {
                              _removePending(current.id);
                            } else {
                              _confirmDeleteMessage(current.id, forEveryone: false);
                            }
                            return false; // Let confirmation dialog handle it
                          },
                          background: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            child: Icon(
                              Icons.delete_outline,
                              color: AppTheme.error,
                              size: 24,
                            ),
                          ),
                          child: ChatBubbleWidget(
                            key: ValueKey('${current.id}-${current.isPending}'),
                            message: current.text,
                            isMe: current.isMe,
                            timestamp: current.timestamp,
                            isSending: current.isPending && !current.sendFailed,
                            sendFailed: current.sendFailed,
                            isDelivered: current.isDelivered,
                            isRead: current.isRead,
                            decryptionFailed: current.decryptionFailed,
                            isFirstInCluster: startsCluster,
                            isLastInCluster: endsCluster,
                            showAvatar: true,
                            avatarUrl: current.isMe
                                ? _currentUserAvatarUrl
                                : _otherUserAvatarUrl,
                            avatarInitial: current.isMe
                                ? _currentUserInitial
                                : _otherUserInitial,
                            onLongPress: current.isPending
                                ? null
                                : () => _showMessageOptions(current),
                            onDelete: current.isPending
                                ? () => _removePending(current.id)
                                : () => _confirmDeleteMessage(
                                      current.id,
                                      forEveryone: false,
                                    ),
                            onReply: () => _startReply(current),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              _buildStickyDateBanner(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSoftLoader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 140,
            height: 18,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Container(
            width: double.infinity,
            height: 18,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Container(
            width: 220,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  List<_ChatListItem> _buildListItems(List<LocalMessageRecord> messages) {
    final items = <_ChatListItem>[];

    for (final msg in messages) {
      if (_deletedMessageIds.contains(msg.messageId)) continue;
      final content = msg.plaintext;
      final failed = content.startsWith('?? Decryption');
      items.add(
        _ChatListItem(
          id: msg.messageId,
          text: content,
          isMe: msg.senderId == _currentUserId,
          timestamp: msg.createdAt,
          isDelivered: msg.deliveredAt != null,
          isRead: msg.readAt != null,
          decryptionFailed: failed,
          isPending: false,
          sendFailed: false,
        ),
      );
    }

    for (final pending in _pendingMessages) {
      items.add(
        _ChatListItem(
          id: pending.id,
          text: pending.text,
          isMe: true,
          timestamp: pending.createdAt,
          isDelivered: false,
          isRead: false,
          decryptionFailed: false,
          isPending: true,
          sendFailed: pending.failed,
        ),
      );
    }

    items.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return items;
  }

  void _reconcilePending(List<LocalMessageRecord> messages) {
    if (_pendingMessages.isEmpty) return;
    final myMessages = messages.where((m) => m.senderId == _currentUserId);

    final resolvedIds = <String>{};
    for (final pending in _pendingMessages) {
      final match = myMessages.any(
        (m) =>
            m.plaintext == pending.text &&
            (m.createdAt.difference(pending.createdAt).inSeconds).abs() < 3,
      );
      if (match) resolvedIds.add(pending.id);
    }

    if (resolvedIds.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _pendingMessages.removeWhere((p) => resolvedIds.contains(p.id));
        });
      });
    }
  }

  void _refreshActiveHeader(List<_ChatListItem> items) {
    if (items.isEmpty) return;
    final latestLabel = _labelForDate(items.last.timestamp);
    if (_activeDateLabel != latestLabel && mounted) {
      setState(() {
        _activeDateLabel = latestLabel;
      });
    }
  }

  Widget _buildStickyDateBanner() {
    if (_activeDateLabel.isEmpty) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Container(
              key: ValueKey(_activeDateLabel),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.cardSurface.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _activeDateLabel,
                style: GoogleFonts.inter(
                  color: AppTheme.navyBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateStickyDateLabel() {
    // Sticky label is now driven by _refreshActiveHeader which uses
    // message timestamps instead of GlobalKey render-object positions.
  }

  void _maybeScrollToBottom() {
    final controller = widget.scrollController ?? _scrollController;
    if (!controller.hasClients) return;
    final atBottom = controller.position.pixels <= 20;
    if (atBottom) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.queenPink.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 40,
                color: AppTheme.brightNavy,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Start a secure conversation',
              style: GoogleFonts.literata(
                color: AppTheme.navyBlue,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your messages are encrypted end-to-end',
              style: GoogleFonts.inter(
                color: AppTheme.textDisabled,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _startReply(_ChatListItem item) {
    setState(() {
      _replyPreview = _ReplyPreview(
        label: item.isMe
            ? 'You'
            : widget.conversation.otherUserDisplayName ??
                widget.conversation.otherUserHandle ??
                'Contact',
        text: item.text,
      );
    });
    _focusNode.requestFocus();
  }

  void _clearReply() {
    setState(() {
      _replyPreview = null;
    });
  }

  void _removePending(String id) {
    setState(() {
      _pendingMessages.removeWhere((p) => p.id == id);
    });
  }

  void _showMessageOptions(_ChatListItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (item.isMe) ...[
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.navyBlue),
                title: Text(
                  'Delete for me',
                  style: GoogleFonts.inter(color: AppTheme.navyBlue),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteMessage(item.id, forEveryone: false);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_forever, color: AppTheme.error),
                title: Text(
                  'Delete for everyone',
                  style: GoogleFonts.inter(color: AppTheme.error),
                ),
                subtitle: Text(
                  'Message will be removed from both devices',
                  style: GoogleFonts.inter(
                    color: AppTheme.textDisabled,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteMessage(item.id, forEveryone: true);
                },
              ),
            ] else
              ListTile(
                leading: Icon(Icons.delete_outline, color: AppTheme.error),
                title: Text(
                  'Delete for me',
                  style: GoogleFonts.inter(color: AppTheme.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessageLocally(item.id);
                },
              ),
            ListTile(
              leading: Icon(Icons.copy, color: AppTheme.navyBlue),
              title: Text(
                'Copy text',
                style: GoogleFonts.inter(color: AppTheme.navyBlue),
              ),
                onTap: () {
                  Navigator.pop(context);
                  if (item.text.isNotEmpty &&
                      item.text != '[Unable to decrypt]') {
                    Clipboard.setData(ClipboardData(text: item.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Copied to clipboard',
                          style: GoogleFonts.inter(),
                      ),
                      backgroundColor: AppTheme.brightNavy,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showResetSessionDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        title: Text(
          'Reset Encryption Session?',
          style: GoogleFonts.literata(
            color: AppTheme.navyBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This will reset the encryption keys for both you and the recipient. '
          'Use this if messages are failing to decrypt. '
          'Both users will need to establish a new secure session.',
          style: GoogleFonts.inter(color: AppTheme.navyText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppTheme.egyptianBlue),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Reset for Both',
              style: GoogleFonts.inter(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _chatService.resetSession(_recipientId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Encryption session reset - send a new message to re-establish',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: AppTheme.brightNavy,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to reset session: $e',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDeleteConversationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'PERMANENT DELETION',
                style: GoogleFonts.literata(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will PERMANENTLY delete:',
              style: GoogleFonts.inter(
                color: AppTheme.navyText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _buildWarningItem('All encrypted messages on the server'),
            _buildWarningItem('All messages on your device'),
            _buildWarningItem('The entire conversation record'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                '⚠️ THIS ACTION CANNOT BE UNDONE\n\nBoth you and the other person will lose all messages permanently.',
                style: GoogleFonts.inter(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: AppTheme.egyptianBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: SojornColors.basicWhite,
            ),
            child: Text(
              'DELETE PERMANENTLY',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final result = await _chatService.deleteConversation(
        widget.conversation.id,
        fullDelete: true,
      );
      
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Conversation permanently deleted'),
              backgroundColor: AppTheme.success,
            ),
          );
          Navigator.of(context).pop(); // Close chat screen
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to delete chat'),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteMessage(
    String messageId, {
    required bool forEveryone,
  }) async {
    final title = forEveryone ? 'Delete for Everyone?' : 'Delete Message?';
    final content = forEveryone
        ? "This message will be permanently deleted from both your device and the recipient's device."
        : "This message will be deleted from your device only.";

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        title: Text(
          title,
          style: GoogleFonts.literata(
            color: AppTheme.navyBlue,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          content,
          style: GoogleFonts.inter(color: AppTheme.navyText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppTheme.egyptianBlue),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (forEveryone) {
        await _deleteMessageForEveryone(messageId);
      } else {
        await _deleteMessageForMe(messageId);
      }
    }
  }

  Future<void> _deleteMessageForMe(String messageId) async {
    setState(() {
      _deletedMessageIds.add(messageId);
    });
    final result = await _chatService.deleteMessage(
      messageId,
      forEveryone: false,
    );

    if (!result.success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to delete message'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _deleteMessageForEveryone(String messageId) async {
    setState(() {
      _deletedMessageIds.add(messageId);
    });
    final result = await _chatService.deleteMessage(
      messageId,
      forEveryone: true,
      conversationId: widget.conversation.id,
      recipientId: _recipientId,
    );

    if (mounted) {
      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Failed to delete message'),
            backgroundColor: AppTheme.error,
          ),
        );
      } else if (result.remoteWipeFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Message deleted, but recipient may still see it',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
    }
  }

  void _deleteMessageLocally(String messageId) {
    setState(() {
      _deletedMessageIds.add(messageId);
    });
    _chatService.markMessageLocallyDeleted(messageId);
  }

  Widget _buildInputArea() {
    return ComposerWidget(
      controller: _messageController,
      focusNode: _focusNode,
      onSend: _sendMessage,
      isSending: _isSending,
      replyingLabel: _replyPreview?.label,
      replyingSnippet: _replyPreview?.text,
      onCancelReply: _clearReply,
    );
  }

  String _labelForDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target == today) return 'Today';
    if (target == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    return DateFormat('EEE, MMM d').format(date);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _initialFor(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  bool _canCluster(_ChatListItem a, _ChatListItem b) {
    if (!_isSameDay(a.timestamp, b.timestamp)) return false;
    return a.isMe == b.isMe;
  }

  Widget _buildWarningItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.close, color: AppTheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: AppTheme.navyText,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatListItem {
  _ChatListItem({
    required this.id,
    required this.text,
    required this.isMe,
    required this.timestamp,
    required this.isDelivered,
    required this.isRead,
    required this.decryptionFailed,
    required this.isPending,
    required this.sendFailed,
  });

  final String id;
  final String text;
  final bool isMe;
  final DateTime timestamp;
  final bool isDelivered;
  final bool isRead;
  final bool decryptionFailed;
  final bool isPending;
  final bool sendFailed;
}

class _PendingMessage {
  const _PendingMessage({
    required this.id,
    required this.text,
    required this.createdAt,
    this.failed = false,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final bool failed;

  _PendingMessage copyWith({bool? failed}) {
    return _PendingMessage(
      id: id,
      text: text,
      createdAt: createdAt,
      failed: failed ?? this.failed,
    );
  }
}

class _ReplyPreview {
  const _ReplyPreview({required this.label, required this.text});
  final String label;
  final String text;
}

class _DatePill extends StatelessWidget {
  const _DatePill({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: AppTheme.navyBlue,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
