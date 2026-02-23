// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

// Models for Secure E2EE Chat
import 'dart:convert';
import 'dart:typed_data';

/// Encrypted conversation metadata
class SecureConversation {
  final String id;
  final String participantA;
  final String participantB;
  final DateTime createdAt;
  final DateTime lastMessageAt;

  // Resolved participant info (loaded separately)
  final String? otherUserHandle;
  final String? otherUserDisplayName;
  final String? otherUserAvatarUrl;
  final int? unreadCount;

  SecureConversation({
    required this.id,
    required this.participantA,
    required this.participantB,
    required this.createdAt,
    required this.lastMessageAt,
    this.otherUserHandle,
    this.otherUserDisplayName,
    this.otherUserAvatarUrl,
    this.unreadCount,
  });

  factory SecureConversation.fromJson(
      Map<String, dynamic> json, String currentUserId) {
    final participantA = json['participant_a'] as String;
    final participantB = json['participant_b'] as String;
    final isParticipantA = currentUserId == participantA;

    // Get the other participant's info if included
    final otherProfile = isParticipantA
        ? json['participant_b_profile']
        : json['participant_a_profile'];

    return SecureConversation(
      id: json['id'] as String,
      participantA: participantA,
      participantB: participantB,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastMessageAt: DateTime.parse(json['last_message_at'] as String),
      otherUserHandle: otherProfile?['handle'] as String?,
      otherUserDisplayName: otherProfile?['display_name'] as String?,
      otherUserAvatarUrl: otherProfile?['avatar_url'] as String?,
      unreadCount: json['unread_count'] as int?,
    );
  }

  String getOtherId(String currentUserId) {
    return currentUserId == participantA ? participantB : participantA;
  }
}

/// Encrypted message (what the server stores and returns)
class EncryptedMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String ciphertext;
  final String iv;
  final Object messageHeader;
  final int messageType;
  final String? replyToId;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? expiresAt;
  final List<MessageReaction> reactions;

  // Decrypted content (populated client-side)
  String? decryptedContent;

  EncryptedMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.ciphertext,
    required this.iv,
    required this.messageHeader,
    required this.messageType,
    this.replyToId,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.expiresAt,
    this.decryptedContent,
    this.reactions = const [],
  });

  factory EncryptedMessage.fromJson(Map<String, dynamic> json) {
    final cipher = json['ciphertext'];
    final ciphertext = cipher is String
        ? cipher
        : cipher is List
            ? base64Encode(Uint8List.fromList(cipher.cast<int>()))
            : '';
    final iv = json['iv'] as String? ?? '';
    final rawType = json['message_type'];
    final parsedType = rawType is int
        ? rawType
        : rawType is num
            ? rawType.toInt()
            : int.tryParse(rawType?.toString() ?? '');
    final header = json['message_header'];
    final messageHeader = header is Map<String, dynamic>
        ? header
        : header is String
            ? header
            : '';

    final reactionsJson = json['reactions'] as List?;
    final reactions = reactionsJson
        ?.map((r) => MessageReaction.fromJson(r as Map<String, dynamic>))
        .toList() ?? [];

    return EncryptedMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      ciphertext: ciphertext,
      iv: iv,
      messageHeader: messageHeader,
      messageType: parsedType ?? MessageType.standardMessage,
      replyToId: json['reply_to_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      readAt: json['read_at'] != null
          ? DateTime.parse(json['read_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      reactions: reactions,
    );
  }

  bool get isRead => readAt != null;
  bool get isDelivered => deliveredAt != null;
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

/// Reaction on a message (plaintext metadata — not encrypted)
class MessageReaction {
  final String id;
  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;

  const MessageReaction({
    required this.id,
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      id: json['id'] as String? ?? '',
      messageId: json['message_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// Message type constants
class MessageType {
  static const int standardMessage = 1; // Normal user message
  static const int commandMessage = 2; // System command (delete, etc.)
}

/// Command types for E2EE system commands
class CommandType {
  static const String deleteMessage = 'command_delete_message';
  static const String deleteConversation = 'command_delete_conversation';
  static const String resyncRequest = 'command_resync_request';
  static const String resyncPayload = 'command_resync_payload';
}

/// System command payload for E2EE commands
class E2EECommand {
  final String type;
  final Map<String, dynamic> payload;

  E2EECommand({
    required this.type,
    required this.payload,
  });

  factory E2EECommand.deleteMessage(String targetMessageId) {
    return E2EECommand(
      type: CommandType.deleteMessage,
      payload: {'target_message_id': targetMessageId},
    );
  }

  factory E2EECommand.deleteConversation(String targetConversationId) {
    return E2EECommand(
      type: CommandType.deleteConversation,
      payload: {'target_conversation_id': targetConversationId},
    );
  }

  factory E2EECommand.resyncRequest(String conversationId, {int? limit}) {
    return E2EECommand(
      type: CommandType.resyncRequest,
      payload: {
        'conversation_id': conversationId,
        if (limit != null) 'limit': limit,
      },
    );
  }

  factory E2EECommand.resyncPayload(
    String conversationId,
    List<Map<String, String>> messages,
  ) {
    return E2EECommand(
      type: CommandType.resyncPayload,
      payload: {
        'conversation_id': conversationId,
        'messages': messages,
      },
    );
  }

  factory E2EECommand.fromJson(Map<String, dynamic> json) {
    return E2EECommand(
      type: json['type'] as String,
      payload: Map<String, dynamic>.from(json['payload'] as Map),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'payload': payload,
  };

  String toJsonString() => jsonEncode(toJson());

  static E2EECommand? tryParse(String content) {
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (json.containsKey('type') && json.containsKey('payload')) {
        return E2EECommand.fromJson(json);
      }
    } catch (_) {}
    return null;
  }
}

/// Result of a delete operation
class DeleteResult {
  final bool success;
  final String? error;
  final bool remoteWipeFailed;

  DeleteResult({
    required this.success,
    this.error,
    this.remoteWipeFailed = false,
  });
}
