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
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final bool isRead;
  final DateTime? archivedAt;

  const AppNotification({
    required this.id,
    required this.type,
    this.actor,
    this.postId,
    this.postBody,
    this.metadata,
    required this.createdAt,
    this.isRead = false,
    this.archivedAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final metadataValue = json['metadata'];
    Map<String, dynamic>? metadata;
    if (metadataValue is Map) {
      metadata = Map<String, dynamic>.from(metadataValue);
    }

    // Extract post body from nested post object or direct field
    String? postBody = json['post_body'] as String?;
    if (postBody == null && json['post'] is Map) {
      postBody = (json['post'] as Map)['body'] as String?;
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
      metadata: metadata,
      createdAt: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool? ?? false,
      archivedAt: json['archived_at'] != null
          ? DateTime.parse(json['archived_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'actor': actor?.toJson(),
      'post_id': postId,
      'post_body': postBody,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'is_read': isRead,
      'archived_at': archivedAt?.toIso8601String(),
    };
  }

  AppNotification copyWith({
    String? id,
    NotificationType? type,
    Profile? actor,
    String? postId,
    String? postBody,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    bool? isRead,
    DateTime? archivedAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      actor: actor ?? this.actor,
      postId: postId ?? this.postId,
      postBody: postBody ?? this.postBody,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      archivedAt: archivedAt ?? this.archivedAt,
    );
  }

  String? get followerIdFromMetadata {
    final value = metadata?['follower_id'];
    return value is String ? value : null;
  }

  String get message {
    final actorName = actor?.displayName ?? 'Someone';
    switch (type) {
      case NotificationType.like:
        return '$actorName liked your post';
      case NotificationType.reply:
        return '$actorName replied to your post';
      case NotificationType.follow:
        return '$actorName started following you';
      case NotificationType.follow_request:
        return '$actorName requested to follow you';
      case NotificationType.follow_accepted:
        return '$actorName accepted your follow request';
      case NotificationType.comment:
        return '$actorName commented on your post';
      case NotificationType.mention:
        return '$actorName mentioned you';
      case NotificationType.message:
        return '$actorName sent you a message';
      case NotificationType.save:
        return '$actorName saved your post';
      case NotificationType.beacon_vouch:
        return '$actorName vouched for your beacon';
      case NotificationType.beacon_report:
        return '$actorName reported your beacon';
      case NotificationType.share:
        return '$actorName shared your post';
      case NotificationType.quip_reaction:
        return '$actorName reacted to your quip';
    }
  }
}
