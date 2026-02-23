// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'profile.dart';

/// Types of notifications
enum NotificationType {
  like,             // Someone liked your post
  comment,          // Someone commented on your post
  reply,            // Someone replied to your post (chained)
  mention,          // Someone mentioned you
  follow,           // Someone followed you
  follow_request,    // Someone requested to follow you
  follow_accepted,   // Someone accepted your follow request
  message,          // New chat message (if shown in notifications)
  save,             // Someone saved your post
  beacon_vouch,     // Someone vouched for your beacon
  beacon_report,    // Someone reported your beacon
  share,            // Someone shared your post
  quip_reaction,    // Someone reacted to your quip
  // Group / Capsule notifications
  group_post,       // Someone posted in your group
  group_comment,    // Someone commented on your group post
  group_like,       // Someone liked your group post
  group_invite,     // You were added to a group
  group_thread,     // Someone started a forum thread in your group
  group_reply,      // Someone replied to your forum thread
  // System / moderation
  nsfw_warning,     // Your post was labeled NSFW
  content_removed,  // Your content was removed
}

/// Notification model
class AppNotification {
  final String id;
  final NotificationType type;
  final Profile? actor; // User who performed the action
  final String? postId;
  final String? postBody;
  final String? postImageUrl; // Thumbnail for the related post
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? archivedAt;
  /// How many additional people performed the same action (for aggregation).
  final int otherCount;

  const AppNotification({
    required this.id,
    required this.type,
    this.actor,
    this.postId,
    this.postBody,
    this.postImageUrl,
    this.metadata,
    required this.createdAt,
    this.isRead = false,
    this.archivedAt,
    this.otherCount = 0,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final metadataValue = json['metadata'];
    Map<String, dynamic>? metadata;
    if (metadataValue is Map) {
      metadata = Map<String, dynamic>.from(metadataValue);
    }

    // Extract post body and image from nested post object or direct fields
    String? postBody = json['post_body'] as String?;
    String? postImageUrl = json['post_image_url'] as String?;
    if (json['post'] is Map) {
      final postMap = json['post'] as Map;
      postBody ??= postMap['body'] as String?;
      postImageUrl ??= postMap['image_url'] as String?;
    }

    return AppNotification(
      id: json['id'] as String,
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.like,
      ),
      actor: json['actor'] != null
        ? Profile.fromJson(json['actor'] as Map<String, dynamic>)
        : (json['actor_id'] != null
            ? Profile.fromJson({
                'id': json['actor_id'],
                'handle': json['actor_handle'] ?? '',
                'display_name': json['actor_display_name'] ?? '',
                'avatar_url': json['actor_avatar_url'] ?? '',
              })
            : null),
      postId: json['post_id'] as String?,
      postBody: postBody,
      postImageUrl: postImageUrl,
      metadata: metadata,
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
      archivedAt: json['archived_at'] != null
          ? DateTime.parse(json['archived_at'] as String)
          : null,
      otherCount: json['other_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'actor': actor?.toJson(),
      'post_id': postId,
      'post_body': postBody,
      'post_image_url': postImageUrl,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'archived_at': archivedAt?.toIso8601String(),
      'other_count': otherCount,
    };
  }

  AppNotification copyWith({
    String? id,
    NotificationType? type,
    Profile? actor,
    String? postId,
    String? postBody,
    String? postImageUrl,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    bool? isRead,
    DateTime? archivedAt,
    int? otherCount,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      actor: actor ?? this.actor,
      postId: postId ?? this.postId,
      postBody: postBody ?? this.postBody,
      postImageUrl: postImageUrl ?? this.postImageUrl,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      archivedAt: archivedAt ?? this.archivedAt,
      otherCount: otherCount ?? this.otherCount,
    );
  }

  String? get followerIdFromMetadata {
    final value = metadata?['follower_id'];
    return value is String ? value : null;
  }

  String get message {
    final actorName = actor?.displayName ?? 'Someone';
    final others = otherCount > 0 ? ' and $otherCount other${otherCount == 1 ? '' : 's'}' : '';
    switch (type) {
      case NotificationType.like:
        return '$actorName$others liked your post';
      case NotificationType.reply:
        return '$actorName$others replied to your post';
      case NotificationType.follow:
        return '$actorName started following you';
      case NotificationType.follow_request:
        return '$actorName requested to follow you';
      case NotificationType.follow_accepted:
        return '$actorName accepted your follow request';
      case NotificationType.comment:
        return '$actorName$others commented on your post';
      case NotificationType.mention:
        return '$actorName mentioned you';
      case NotificationType.message:
        return '$actorName sent you a message';
      case NotificationType.save:
        return '$actorName$others saved your post';
      case NotificationType.beacon_vouch:
        return '$actorName$others vouched for your beacon';
      case NotificationType.beacon_report:
        return '$actorName reported your beacon';
      case NotificationType.share:
        return '$actorName$others shared your post';
      case NotificationType.quip_reaction:
        return '$actorName$others reacted to your quip';
      case NotificationType.group_post:
        final groupName = metadata?['group_name'] as String?;
        return groupName != null
            ? '$actorName posted in $groupName'
            : '$actorName posted in your group';
      case NotificationType.group_comment:
        final groupName = metadata?['group_name'] as String?;
        return groupName != null
            ? '$actorName commented on your post in $groupName'
            : '$actorName commented on your group post';
      case NotificationType.group_like:
        final groupName = metadata?['group_name'] as String?;
        return groupName != null
            ? '$actorName$others liked your post in $groupName'
            : '$actorName$others liked your group post';
      case NotificationType.group_invite:
        final groupName = metadata?['group_name'] as String?;
        return groupName != null
            ? '$actorName added you to $groupName'
            : '$actorName added you to a group';
      case NotificationType.group_thread:
        final groupName = metadata?['group_name'] as String?;
        return groupName != null
            ? '$actorName started a discussion in $groupName'
            : '$actorName started a new discussion in your group';
      case NotificationType.group_reply:
        final groupName = metadata?['group_name'] as String?;
        return groupName != null
            ? '$actorName replied to your thread in $groupName'
            : '$actorName replied to your forum thread';
      case NotificationType.nsfw_warning:
        return 'Your post was labeled as sensitive content';
      case NotificationType.content_removed:
        return 'Your post was removed for violating community guidelines';
    }
  }

  /// Group ID from metadata (for group notification navigation)
  String? get groupIdFromMetadata {
    final value = metadata?['group_id'];
    return value is String ? value : null;
  }

  /// Whether this notification is group-related
  bool get isGroupNotification => type == NotificationType.group_post ||
      type == NotificationType.group_comment ||
      type == NotificationType.group_like ||
      type == NotificationType.group_invite ||
      type == NotificationType.group_thread ||
      type == NotificationType.group_reply;
}
