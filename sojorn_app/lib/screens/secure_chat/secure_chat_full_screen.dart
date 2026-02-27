// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

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
import '../../widgets/media/sojorn_avatar.dart';
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

  // Search + filter state
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _filterUnread = false;

  // Desktop split-pane state
  SecureConversation? _selectedConversation;

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
    _searchCtrl.dispose();
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
      builder: (ctx) => NewConversationSheet(
        onConversationStarted: (conversation) {
          Navigator.pop(ctx);
          _openConversation(conversation);
        },
      ),
    );
  }

  void _openConversation(SecureConversation conversation) {
    // On desktop, show in the right pane instead of pushing a route
    final width = MediaQuery.of(context).size.width;
    if (width >= SojornBreakpoints.desktop) {
      setState(() => _selectedConversation = conversation);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SecureChatScreen(conversation: conversation),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= SojornBreakpoints.desktop;
          if (!isDesktop) return _buildBody();

          // Desktop: split-pane — conversation list left, active chat right
          return Row(
            children: [
              // Left pane: conversation list
              SizedBox(
                width: SojornBreakpoints.sidebarWidth,
                child: _buildBody(),
              ),
              VerticalDivider(width: 1, color: AppTheme.border),
              // Right pane: active chat or placeholder
              Expanded(
                child: _selectedConversation != null
                    ? SecureChatScreen(
                        key: ValueKey(_selectedConversation!.id),
                        conversation: _selectedConversation!,
                        embeddedMode: true,
                      )
                    : _buildChatPlaceholder(),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'secure_chat_new_conversation',
        onPressed: _showNewConversationSheet,
        backgroundColor: AppTheme.brightNavy,
        tooltip: 'New conversation',
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
    );
  }

  Widget _buildChatPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64,
            color: AppTheme.brightNavy.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text(
            'Select a conversation',
            style: GoogleFonts.literata(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.navyBlue.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose from your messages on the left',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textDisabled,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: SojornColors.destructive),
              const SizedBox(height: 16),
              Text('Something went wrong',
                style: GoogleFonts.literata(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.navyBlue)),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadConversations,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.brightNavy,
                  foregroundColor: SojornColors.basicWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    // Apply search + unread filter
    final visible = _conversations.where((c) {
      if (_filterUnread && (c.unreadCount == null || c.unreadCount! == 0)) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final name = (c.otherUserDisplayName ?? '').toLowerCase();
        final handle = (c.otherUserHandle ?? '').toLowerCase();
        if (!name.contains(q) && !handle.contains(q)) return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // ── Search bar ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v.trim()),
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.navyBlue),
            decoration: InputDecoration(
              hintText: 'Search conversations…',
              hintStyle: GoogleFonts.inter(color: AppTheme.textDisabled, fontSize: 14),
              prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.textDisabled),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 16, color: AppTheme.textDisabled),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              filled: true,
              fillColor: AppTheme.cardSurface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.brightNavy, width: 1.5),
              ),
            ),
          ),
        ),

        // ── Filter chips ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              _filterChip('All', !_filterUnread, () => setState(() => _filterUnread = false)),
              const SizedBox(width: 8),
              _filterChip(
                'Unread${_conversations.any((c) => (c.unreadCount ?? 0) > 0) ? ' (${_conversations.where((c) => (c.unreadCount ?? 0) > 0).length})' : ''}',
                _filterUnread,
                () => setState(() => _filterUnread = true),
              ),
            ],
          ),
        ),

        // ── List ─────────────────────────────────────────────────────
        Expanded(
          child: _conversations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock, size: 56, color: AppTheme.brightNavy.withValues(alpha: 0.2)),
                        const SizedBox(height: 16),
                        Text('No messages yet',
                          style: GoogleFonts.literata(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.navyBlue)),
                        const SizedBox(height: 8),
                        Text('Start a secure conversation with someone',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary)),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _showNewConversationSheet,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.brightNavy,
                            foregroundColor: SojornColors.basicWhite,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: const Text('Start Conversation'),
                        ),
                      ],
                    ),
                  ),
                )
              : visible.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isNotEmpty ? 'No matches for "$_searchQuery"' : 'No unread conversations',
                        style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadConversations,
                      color: AppTheme.brightNavy,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final conv = visible[index];
                          return _ConversationTile(
                            conversation: conv,
                            onTap: () => _openConversation(conv),
                            onDelete: () => _confirmDeleteConversation(conv),
                            isSelected: _selectedConversation?.id == conv.id,
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brightNavy : AppTheme.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.brightNavy : AppTheme.border,
          ),
        ),
        child: Text(label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppTheme.textSecondary,
          )),
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
  final bool isSelected;
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onDelete,
    this.isSelected = false,
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
            color: widget.isSelected
                ? AppTheme.brightNavy.withValues(alpha: 0.08)
                : AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? AppTheme.brightNavy.withValues(alpha: 0.3)
                  : AppTheme.navyBlue.withValues(alpha: 0.1),
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
                    // Avatar — rounded square per design system
                    SojornAvatar(
                      displayName: widget.conversation.otherUserDisplayName ??
                          '@${widget.conversation.otherUserHandle ?? 'Unknown'}',
                      avatarUrl: widget.conversation.otherUserAvatarUrl,
                      size: 52,
                    ),
                    const SizedBox(width: 14),
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
                                    fontSize: 15,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                timeago.format(widget.conversation.lastMessageAt),
                                style: GoogleFonts.inter(color: AppTheme.textDisabled, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.lock, size: 11,
                                color: AppTheme.brightNavy.withValues(alpha: 0.4)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Encrypted message',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
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
                          icon: Icon(
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
