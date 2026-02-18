import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/secure_chat.dart';
import '../../services/secure_chat_service.dart';
import '../security/encryption_hub_screen.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/media/signed_media_image.dart';
import '../home/full_screen_shell.dart';
import 'secure_chat_screen.dart';
import 'new_conversation_sheet.dart';

/// Full-screen secure chat with proper navigation bars
/// Replaces the modal sheet for a native app experience
class SecureChatFullScreen extends StatefulWidget {
  const SecureChatFullScreen({super.key});

  @override
  State<SecureChatFullScreen> createState() => _SecureChatFullScreenState();
}

class _SecureChatFullScreenState extends State<SecureChatFullScreen>
    with WidgetsBindingObserver {
  final SecureChatService _chatService = SecureChatService();

  List<SecureConversation> _conversations = [];
  bool _isLoading = true;
  bool _isInitializing = false;
  String? _error;

  Timer? _pollTimer;
  StreamSubscription? _changesSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Poll every 30 s — paused when app is backgrounded
    _startPolling();

    // Re-load only when the list actually changed (push notification, send, etc.)
    _changesSub = _chatService.conversationListChanges.listen((_) {
      if (mounted) _loadConversations();
    });

    _initialize();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadConversations();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopPolling();
    } else if (state == AppLifecycleState.resumed) {
      _startPolling();
      // Refresh immediately on resume to catch any missed updates
      _loadConversations();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _isInitializing = true;
    });

    try {
      
      // Initialize chat service with key generation if needed
      await _chatService.initialize(generateIfMissing: true);
      
      // Load conversations
      await _loadConversations();
      
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isInitializing = false;
      });
    }
  }

  Future<void> _loadConversations() async {
    try {
      final conversations = await _chatService.getConversations();
      if (!mounted) return;

      // Skip rebuild if conversation IDs haven't changed
      final newIds = conversations.map((c) => c.id).toList();
      final oldIds = _conversations.map((c) => c.id).toList();
      if (listEquals(newIds, oldIds)) return;

      setState(() {
        _conversations = conversations;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  void _showNewConversationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SojornColors.transparent,
      builder: (context) => NewConversationSheet(
        onConversationStarted: (conversation) {
          Navigator.pop(context); // Close new conversation sheet
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SecureChatScreen(conversation: conversation),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FullScreenShell(
      title: Row(
        children: [
          Flexible(
            child: Text(
              'Messages',
              style: GoogleFonts.literata(
                fontWeight: FontWeight.w600,
                color: AppTheme.navyBlue,
                fontSize: 20,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.brightNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'End-to-end encrypted',
              style: GoogleFonts.inter(
                color: AppTheme.brightNavy,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      showSearch: false,
      showMessages: false,
      leadingActions: [
        PopupMenuButton<_ChatMenuAction>(
          icon: Icon(Icons.more_vert, color: AppTheme.navyBlue),
          tooltip: 'More options',
          onSelected: (action) async {
            switch (action) {
              case _ChatMenuAction.refresh:
                await _loadConversations();
              case _ChatMenuAction.uploadKeys:
                try {
                  await _chatService.uploadKeysManually();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Keys uploaded successfully'),
                        backgroundColor: Color(0xFF4CAF50),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to upload keys: $e'),
                        backgroundColor: SojornColors.destructive,
                      ),
                    );
                  }
                }
              case _ChatMenuAction.backup:
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EncryptionHubScreen(),
                  ),
                );
              case _ChatMenuAction.devices:
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Device management coming soon')),
                );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _ChatMenuAction.refresh,
              child: Row(children: [
                Icon(Icons.refresh, size: 18, color: AppTheme.navyBlue),
                const SizedBox(width: 12),
                const Text('Refresh'),
              ]),
            ),
            PopupMenuItem(
              value: _ChatMenuAction.uploadKeys,
              child: Row(children: [
                Icon(Icons.key, size: 18, color: AppTheme.navyBlue),
                const SizedBox(width: 12),
                const Text('Upload keys'),
              ]),
            ),
            PopupMenuItem(
              value: _ChatMenuAction.backup,
              child: Row(children: [
                Icon(Icons.backup, size: 18, color: AppTheme.navyBlue),
                const SizedBox(width: 12),
                const Text('Backup & Recovery'),
              ]),
            ),
            PopupMenuItem(
              value: _ChatMenuAction.devices,
              child: Row(children: [
                Icon(Icons.devices, size: 18, color: AppTheme.navyBlue),
                const SizedBox(width: 12),
                const Text('Device Management'),
              ]),
            ),
          ],
        ),
      ],
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewConversationSheet,
        backgroundColor: AppTheme.brightNavy,
        tooltip: 'New conversation',
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _conversations.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.brightNavy),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: SojornColors.destructive,
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: GoogleFonts.literata(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadConversations,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock,
                size: 64,
                color: AppTheme.brightNavy.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No messages yet',
                style: GoogleFonts.literata(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.navyBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start a secure conversation with someone',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _showNewConversationSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text('Start Conversation'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      color: AppTheme.brightNavy,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final conversation = _conversations[index];
          return _ConversationTile(
            conversation: conversation,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SecureChatScreen(conversation: conversation),
                ),
              );
            },
            onDelete: () => _confirmDeleteConversation(conversation),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteConversation(SecureConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        title: Text(
          'Delete Conversation?',
          style: GoogleFonts.literata(
            fontWeight: FontWeight.w600,
            color: AppTheme.navyBlue,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this conversation with ${conversation.otherUserDisplayName ?? conversation.otherUserHandle}? This will remove all messages for everyone.',
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
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: SojornColors.basicWhite,
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _chatService.deleteConversation(conversation.id, fullDelete: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Conversation deleted'),
              backgroundColor: const Color(0xFF4CAF50),
            ),
          );
          _loadConversations();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: SojornColors.destructive,
            ),
          );
        }
      }
    }
  }
}

enum _ChatMenuAction { refresh, uploadKeys, backup, devices }

class _ConversationTile extends StatefulWidget {
  final SecureConversation conversation;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Dismissible(
        key: Key('conv_${widget.conversation.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (direction) async {
          widget.onDelete();
          return false; // Let the full screen state handle the actual removal
        },
        background: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.error,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Icon(
            Icons.delete_outline,
            color: SojornColors.basicWhite,
            size: 28,
          ),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.navyBlue.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Material(
            color: SojornColors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.brightNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: widget.conversation.otherUserAvatarUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: SignedMediaImage(
                                url: widget.conversation.otherUserAvatarUrl!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              ),
                            )
                          : Center(
                              child: Text(
                                (widget.conversation.otherUserDisplayName ??
                                            '@${widget.conversation.otherUserHandle ?? 'Unknown'}')
                                        .isNotEmpty
                                    ? (widget.conversation.otherUserDisplayName ??
                                            '@${widget.conversation.otherUserHandle ?? 'Unknown'}')[0]
                                        .toUpperCase()
                                    : '?',
                                style: GoogleFonts.inter(
                                  color: AppTheme.navyBlue,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 16),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.conversation.otherUserDisplayName ??
                                      '@${widget.conversation.otherUserHandle ?? 'Unknown'}',
                                  style: GoogleFonts.literata(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.navyBlue,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.conversation.lastMessageAt != null)
                                Text(
                                  timeago.format(widget.conversation.lastMessageAt!),
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textDisabled,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.lock,
                                size: 12,
                                color: AppTheme.brightNavy.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                  child: Text(
                                    widget.conversation.lastMessageAt != null
                                        ? 'Encrypted message'
                                        : 'Start a conversation',
                                    style: GoogleFonts.inter(
                                      color: widget.conversation.lastMessageAt != null
                                          ? AppTheme.textSecondary
                                          : AppTheme.textDisabled,
                                      fontSize: 13,
                                      fontStyle: widget.conversation.lastMessageAt != null
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Unread badge
                      if (widget.conversation.unreadCount != null && widget.conversation.unreadCount! > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.brightNavy,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.conversation.unreadCount.toString(),
                            style: GoogleFonts.inter(
                              color: SojornColors.basicWhite,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      // Hover delete button for web/desktop
                    if (_isHovered)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IconButton(
                          onPressed: widget.onDelete,
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppTheme.error,
                            size: 20,
                          ),
                          tooltip: 'Delete conversation',
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.error.withValues(alpha: 0.1),
                            padding: const EdgeInsets.all(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
