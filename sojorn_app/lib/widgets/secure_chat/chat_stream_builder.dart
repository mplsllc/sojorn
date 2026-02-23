// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../services/secure_chat_service.dart';
import '../../services/local_message_store.dart';
import 'chat_bubble_widget.dart';

class ChatStreamBuilder extends StatefulWidget {
  final String conversationId;
  final String currentUserId;
  final ScrollController? scrollController;
  final Widget? loadingState;
  final Widget? emptyState;
  final String? pendingMessageText;
  final void Function(LocalMessageRecord message, bool isMe)? onMessageLongPress;

  const ChatStreamBuilder({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    this.scrollController,
    this.loadingState,
    this.emptyState,
    this.pendingMessageText,
    this.onMessageLongPress,
  });

  @override
  State<ChatStreamBuilder> createState() => _ChatStreamBuilderState();
}

class _ChatStreamBuilderState extends State<ChatStreamBuilder> {
  final SecureChatService _chatService = SecureChatService();
  late Stream<List<LocalMessageRecord>> _messageStream;

  @override
  void initState() {
    super.initState();
    _messageStream = _chatService.watchConversation(widget.conversationId);
  }

  @override
  void didUpdateWidget(covariant ChatStreamBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _messageStream = _chatService.watchConversation(widget.conversationId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LocalMessageRecord>>(
      stream: _messageStream,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const [];
        final isWaiting = snapshot.connectionState == ConnectionState.waiting;
        final hasPending = widget.pendingMessageText?.isNotEmpty ?? false;

        if (isWaiting && messages.isEmpty) {
          return widget.loadingState ?? const SizedBox.shrink();
        }

        if (messages.isEmpty && !hasPending) {
          return widget.emptyState ?? const SizedBox.shrink();
        }

        if (messages.isNotEmpty) {
          _chatService.markAsRead(widget.conversationId);
        }

        _scheduleScrollToBottom();

        return ListView.builder(
          controller: widget.scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: messages.length + (hasPending ? 1 : 0),
          itemBuilder: (context, index) {
            if (hasPending && index == messages.length) {
              return ChatBubbleWidget(
                message: widget.pendingMessageText ?? '',
                isMe: true,
                isSending: true,
                timestamp: DateTime.now(),
              );
            }

            final message = messages[index];
            final isMe = message.senderId == widget.currentUserId;
            final failed = message.plaintext.startsWith('?? Decryption');

            return ChatBubbleWidget(
              message: message.plaintext,
              isMe: isMe,
              timestamp: message.createdAt,
              isDelivered: message.deliveredAt != null,
              isRead: message.readAt != null,
              decryptionFailed: failed,
              onLongPress: widget.onMessageLongPress == null
                  ? null
                  : () => widget.onMessageLongPress!(message, isMe),
            );
          },
        );
      },
    );
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = widget.scrollController;
      if (controller == null || !controller.hasClients) return;
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }
}
