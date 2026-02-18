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
        : null,
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
    }
  }
}
