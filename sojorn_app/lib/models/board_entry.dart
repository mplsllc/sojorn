import 'package:flutter/material.dart';

/// Standalone neighborhood board entry — completely separate from Post/Beacon.
class BoardEntry {
  final String id;
  final String body;
  final String? imageUrl;
  final BoardTopic topic;
  final double lat;
  final double long;
  final int upvotes;
  final int replyCount;
  final bool isPinned;
  final DateTime createdAt;
  final String authorHandle;
  final String authorDisplayName;
  final String authorAvatarUrl;
  final bool hasVoted;

  const BoardEntry({
    required this.id,
    required this.body,
    this.imageUrl,
    required this.topic,
    required this.lat,
    required this.long,
    this.upvotes = 0,
    this.replyCount = 0,
    this.isPinned = false,
    required this.createdAt,
    this.authorHandle = '',
    this.authorDisplayName = '',
    this.authorAvatarUrl = '',
    this.hasVoted = false,
  });

  factory BoardEntry.fromJson(Map<String, dynamic> json) {
    return BoardEntry(
      id: json['id'] ?? '',
      body: json['body'] ?? '',
      imageUrl: (json['image_url'] != null && json['image_url'] != '') ? json['image_url'] : null,
      topic: BoardTopic.fromString(json['topic'] ?? 'community'),
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      long: (json['long'] as num?)?.toDouble() ?? 0,
      upvotes: json['upvotes'] ?? 0,
      replyCount: json['reply_count'] ?? 0,
      isPinned: json['is_pinned'] ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      authorHandle: json['author_handle'] ?? '',
      authorDisplayName: json['author_display_name'] ?? '',
      authorAvatarUrl: json['author_avatar_url'] ?? '',
      hasVoted: json['has_voted'] ?? false,
    );
  }

  String getTimeAgo() {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

class BoardReply {
  final String id;
  final String body;
  final int upvotes;
  final DateTime createdAt;
  final String authorHandle;
  final String authorDisplayName;
  final String authorAvatarUrl;
  final bool hasVoted;

  const BoardReply({
    required this.id,
    required this.body,
    this.upvotes = 0,
    required this.createdAt,
    this.authorHandle = '',
    this.authorDisplayName = '',
    this.authorAvatarUrl = '',
    this.hasVoted = false,
  });

  factory BoardReply.fromJson(Map<String, dynamic> json) {
    return BoardReply(
      id: json['id'] ?? '',
      body: json['body'] ?? '',
      upvotes: json['upvotes'] ?? 0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      authorHandle: json['author_handle'] ?? '',
      authorDisplayName: json['author_display_name'] ?? '',
      authorAvatarUrl: json['author_avatar_url'] ?? '',
      hasVoted: json['has_voted'] ?? false,
    );
  }

  String getTimeAgo() {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

enum BoardTopic {
  community('community', 'Community', Icons.people, Color(0xFF4CAF50)),
  question('question', 'Question', Icons.help_outline, Color(0xFF2196F3)),
  event('event', 'Event', Icons.event, Color(0xFF9C27B0)),
  lostPet('lost_pet', 'Lost Pet', Icons.pets, Color(0xFFFF9800)),
  resource('resource', 'Resource', Icons.handshake, Color(0xFF009688)),
  recommendation('recommendation', 'Recommend', Icons.thumb_up, Color(0xFF3F51B5)),
  warning('warning', 'Warning', Icons.warning_amber, Color(0xFFFF5252));

  final String value;
  final String displayName;
  final IconData icon;
  final Color color;
  const BoardTopic(this.value, this.displayName, this.icon, this.color);

  static BoardTopic fromString(String s) {
    return BoardTopic.values.firstWhere((t) => t.value == s, orElse: () => BoardTopic.community);
  }
}
