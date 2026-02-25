// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'profile.dart';
import 'beacon.dart';

enum PostStatus {
  active('active'),
  flagged('flagged'),
  removed('removed');

  final String value;
  const PostStatus(this.value);

  static PostStatus fromString(String value) {
    return PostStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => PostStatus.active,
    );
  }
}

enum ToneLabel {
  positive('positive'),
  neutral('neutral'),
  mixed('mixed'),
  negative('negative'),
  hostile('hostile');

  final String value;
  const ToneLabel(this.value);

  static ToneLabel fromString(String value) {
    return ToneLabel.values.firstWhere(
      (label) => label.value == value,
      orElse: () => ToneLabel.neutral,
    );
  }
}

class Post {
  final String id;
  final String authorId;
  final String? categoryId;
  final String body;
  final PostStatus status;
  final ToneLabel detectedTone;
  final double contentIntegrityScore;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? expiresAt;
  final bool isEdited;
  final bool allowChain;
  final String? chainParentId;
  final PostPreview? chainParent;
  final String visibility;
  final DateTime? pinnedAt;

  final Profile? author;
  final int? likeCount;
  final int? saveCount;
  final int? commentCount;
  final int? viewCount;

  final bool? isLiked;
  final bool? isSaved;
  final String? imageUrl;
  final String? videoUrl;
  final String? thumbnailUrl;
  final int? durationMs;
  final bool? hasVideoContent;
  final String? bodyFormat;
  final String? backgroundId;
  final List<String>? tags;
  final Map<String, int>? reactions;
  final List<String>? myReactions;
  final Map<String, List<String>>? reactionUsers;
  
  final bool? isBeacon;
  final BeaconType? beaconType;
  final double? confidenceScore;
  final bool? isActiveBeacon;
  final bool? isPriority;
  final String? beaconStatusColor;
  final String? severity;
  final String? incidentStatus;
  final int? radius;
  final int? verificationCount;
  final int? vouchCount;
  final int? reportCount;
  // "vouch", "report", or null — the current user's vote on this beacon.
  final String? myVote;

  // Official/government source fields
  final bool? isOfficial;
  final String? officialSource;
  // Title field — used by external beacon sources (211 resources, weather stations)
  // where title != body. Null for user-created posts.
  final String? title;

  final double? latitude;
  final double? longitude;
  final double? distanceMeters;

  // Group / Neighborhood context
  final String? groupId;
  final String? groupName;

  final bool isSponsored;
  final String? advertiserName;
  final String? ctaLink;
  final String? ctaText;

  final bool isNsfw;
  final String? nsfwReason;

  // Audio overlay — background music track URL attached to this post
  final String? audioOverlayUrl;

  // Link preview (OG metadata)
  final String? linkPreviewUrl;
  final String? linkPreviewTitle;
  final String? linkPreviewDescription;
  final String? linkPreviewImageUrl;
  final String? linkPreviewSiteName;

  bool get hasLinkPreview => linkPreviewUrl != null && linkPreviewUrl!.isNotEmpty;

  Post({
    required this.id,
    required this.authorId,
    this.categoryId,
    required this.body,
    required this.status,
    required this.detectedTone,
    required this.contentIntegrityScore,
    required this.createdAt,
    this.editedAt,
    this.expiresAt,
    this.isEdited = false,
    this.allowChain = true,
    this.chainParentId,
    this.chainParent,
    this.visibility = 'public',
    this.pinnedAt,
    this.author,
    this.likeCount,
    this.saveCount,
    this.commentCount,
    this.viewCount,
    this.isLiked,
    this.isSaved,
    this.imageUrl,
    this.videoUrl,
    this.thumbnailUrl,
    this.durationMs,
    this.hasVideoContent,
    this.bodyFormat,
    this.backgroundId,
    this.tags,
    this.reactions,
    this.myReactions,
    this.reactionUsers,
    this.isBeacon = false,
    this.beaconType,
    this.confidenceScore,
    this.isActiveBeacon,
    this.isPriority,
    this.beaconStatusColor,
    this.severity,
    this.incidentStatus,
    this.radius,
    this.verificationCount,
    this.vouchCount,
    this.reportCount,
    this.myVote,
    this.isOfficial,
    this.officialSource,
    this.title,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.groupId,
    this.groupName,
    this.isSponsored = false,
    this.advertiserName,
    this.ctaLink,
    this.ctaText,
    this.isNsfw = false,
    this.nsfwReason,
    this.audioOverlayUrl,
    this.linkPreviewUrl,
    this.linkPreviewTitle,
    this.linkPreviewDescription,
    this.linkPreviewImageUrl,
    this.linkPreviewSiteName,
  });

  static int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static double _parseDouble(dynamic value, {double fallback = 0.0}) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return fallback;
  }

  static List<String>? _parseTags(dynamic value) {
    if (value == null) return null;
    if (value is List<dynamic>) {
      return value.map((e) => e.toString()).toList();
    }
    return null;
  }

  static Map<String, int>? _parseReactions(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) {
      return value.map((key, val) => MapEntry(key, _parseInt(val) ?? 0));
    }
    return null;
  }

  static List<String>? _parseReactionsList(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return null;
  }

  static Map<String, List<String>>? _parseReactionUsers(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) {
      return value.map((key, val) {
        if (val is List) {
          return MapEntry(key, val.map((item) => item.toString()).toList());
        }
        return MapEntry(key, <String>[]);
      });
    }
    return null;
  }

  static double _defaultCis(String tone) {
    switch (tone) {
      case 'positive':
        return 0.9;
      case 'neutral':
        return 0.8;
      case 'mixed':
        return 0.7;
      case 'negative':
        return 0.5;
      default:
        return 0.8;
    }
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    final authorJson = json['author'] as Map<String, dynamic>?;
    final categoryJson = json['category'] as Map<String, dynamic>?;
    final metricsJson = json['metrics'] as Map<String, dynamic>?;
    final chainParentJson = json['chain_parent'] == null || json['chain_parent'] is! Map<String, dynamic>
        ? null
        : json['chain_parent'] as Map<String, dynamic>;
    final statusValue = json['status'] as String? ?? 'active';
    final toneValue =
        json['detected_tone'] as String? ?? json['tone_label'] as String? ?? 'neutral';
    final cisValue =
        json['content_integrity_score'] ?? json['cis_score'] ?? _defaultCis(toneValue);
    final editedAtValue = json['edited_at'] ?? json['updated_at'];

    return Post(
      id: json['id'] as String,
      authorId: json['author_id'] as String? ?? authorJson?['id'] as String? ?? '',
      categoryId: json['category_id'] as String? ?? categoryJson?['id'] as String?,
      body: json['body'] as String,
      status: PostStatus.fromString(statusValue),
      detectedTone: ToneLabel.fromString(toneValue),
      contentIntegrityScore: _parseDouble(cisValue, fallback: _defaultCis(toneValue)),
      createdAt: DateTime.parse(json['created_at'] as String),
      editedAt: editedAtValue != null
          ? DateTime.parse(editedAtValue as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      isEdited: json['is_edited'] as bool? ?? false,
      allowChain: json['allow_chain'] as bool? ?? true,
      chainParentId: json['chain_parent_id'] as String?,
      chainParent:
          chainParentJson != null ? PostPreview.fromJson(chainParentJson) : null,
      visibility: json['visibility'] as String? ?? 'public',
      pinnedAt: json['pinned_at'] != null
          ? DateTime.parse(json['pinned_at'] as String)
          : null,
      author: authorJson != null ? Profile.fromJson(authorJson) : null,
      likeCount: _parseInt(metricsJson?['like_count'] ?? json['like_count']),
      saveCount: _parseInt(metricsJson?['save_count'] ?? json['save_count']),
      commentCount: _parseInt(json['comment_count']),
      viewCount: _parseInt(metricsJson?['view_count'] ?? json['view_count']),
      isLiked: json['is_liked'] as bool? ?? json['user_liked'] as bool?,
      isSaved: json['is_saved'] as bool? ?? json['user_saved'] as bool?,
      imageUrl: json['image_url'] as String?,
      videoUrl: json['video_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      durationMs: _parseInt(json['duration_ms']),
      hasVideoContent: json['has_video_content'] as bool? ?? 
          ((json['video_url'] as String?)?.isNotEmpty == true || 
           (json['image_url'] as String?)?.toLowerCase().endsWith('.mp4') == true),
      bodyFormat: json['body_format'] as String?,

      backgroundId: json['background_id'] as String?,
      tags: _parseTags(json['tags']),
      reactions: _parseReactions(
          json['reactions'] ?? json['reaction_counts'] ?? json['reaction_map']),
      myReactions: _parseReactionsList(
          json['my_reactions'] ?? json['myReactions']),
      reactionUsers: _parseReactionUsers(
          json['reaction_users'] ?? json['reaction_users_preview']),
      isBeacon: json['is_beacon'] as bool?,
      beaconType: json['beacon_type'] != null ? BeaconType.fromString(json['beacon_type'] as String) : null,
      confidenceScore: _parseDouble(json['confidence_score']),
      isActiveBeacon: json['is_active_beacon'] as bool?,
      isPriority: json['is_priority'] as bool?,
      beaconStatusColor: json['status_color'] as String?,
      severity: json['severity'] as String?,
      incidentStatus: json['incident_status'] as String?,
      radius: _parseInt(json['radius']),
      verificationCount: _parseInt(json['verification_count']),
      vouchCount: _parseInt(json['vouch_count']),
      reportCount: _parseInt(json['report_count']),
      myVote: json['my_vote'] as String?,
      isOfficial: json['is_official'] as bool?,
      officialSource: json['official_source'] as String?,
      title: json['title'] as String?,
      latitude: _parseLatitude(json),
      longitude: _parseLongitude(json),
      distanceMeters: _parseDouble(json['distance_meters']),
      groupId: json['group_id'] as String?,
      groupName: json['group_name'] as String?,
      isSponsored: json['is_sponsored'] as bool? ?? false,
      advertiserName: json['advertiser_name'] as String?,
      ctaLink: json['advertiser_cta_link'] as String?,
      ctaText: json['advertiser_cta_text'] as String?,
      isNsfw: json['is_nsfw'] as bool? ?? false,
      nsfwReason: json['nsfw_reason'] as String?,
      audioOverlayUrl: json['audio_overlay_url'] as String?,
      linkPreviewUrl: json['link_preview_url'] as String?,
      linkPreviewTitle: json['link_preview_title'] as String?,
      linkPreviewDescription: json['link_preview_description'] as String?,
      linkPreviewImageUrl: json['link_preview_image_url'] as String?,
      linkPreviewSiteName: json['link_preview_site_name'] as String?,
    );
  }

  static double? _parseLatitude(Map<String, dynamic> json) {
    final value = json['latitude'] ?? json['lat'] ?? json['beacon_lat'];
    if (value == null) return null;
    return _parseDouble(value);
  }

  static double? _parseLongitude(Map<String, dynamic> json) {
    final value = json['longitude'] ?? json['long'] ?? json['beacon_long'];
    if (value == null) return null;
    return _parseDouble(value);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author_id': authorId,
      'category_id': categoryId,
      'body': body,
      'status': status.value,
      'detected_tone': detectedTone.value,
      'content_integrity_score': contentIntegrityScore,
      'created_at': createdAt.toIso8601String(),
      'edited_at': editedAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'allow_chain': allowChain,
      'chain_parent_id': chainParentId,
      'chain_parent': chainParent?.toJson(),
      'visibility': visibility,
      'pinned_at': pinnedAt?.toIso8601String(),
      'author': author?.toJson(),
      'like_count': likeCount,
      'save_count': saveCount,
      'comment_count': commentCount,
      'view_count': viewCount,
      'is_liked': isLiked,
      'is_saved': isSaved,
      'image_url': imageUrl,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'duration_ms': durationMs,
      'has_video_content': hasVideoContent,
      'tags': tags,
      'reactions': reactions,
      'my_reactions': myReactions,
      'reaction_users': reactionUsers,
      'is_nsfw': isNsfw,
      'nsfw_reason': nsfwReason,
      'audio_overlay_url': audioOverlayUrl,
      'link_preview_url': linkPreviewUrl,
      'link_preview_title': linkPreviewTitle,
      'link_preview_description': linkPreviewDescription,
      'link_preview_image_url': linkPreviewImageUrl,
      'link_preview_site_name': linkPreviewSiteName,
      if (title != null) 'title': title,
    };
  }
}

class PostPreview {
  final String id;
  final String body;
  final DateTime createdAt;
  final Profile? author;
  final Map<String, int>? reactions;
  final List<String>? myReactions;

  const PostPreview({
    required this.id,
    required this.body,
    required this.createdAt,
    this.author,
    this.reactions,
    this.myReactions,
  });

  factory PostPreview.fromJson(Map<String, dynamic> json) {
    final authorJson = json['author'] as Map<String, dynamic>?;
    return PostPreview(
      id: json['id'] as String,
      body: json['body'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      author: authorJson != null ? Profile.fromJson(authorJson) : null,
      reactions: Post._parseReactions(json['reactions'] ?? json['reaction_counts']),
      myReactions: Post._parseReactionsList(json['my_reactions'] ?? json['myReactions']),
    );
  }

  factory PostPreview.fromPost(Post post) {
    return PostPreview(
      id: post.id,
      body: post.body,
      createdAt: post.createdAt,
      author: post.author,
      reactions: post.reactions,
      myReactions: post.myReactions,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'body': body,
      'created_at': createdAt.toIso8601String(),
      'author': author?.toJson(),
      'reactions': reactions,
      'my_reactions': myReactions,
    };
  }
}

class ToneAnalysis {
  final ToneLabel tone;
  final double cis;
  final bool shouldReject;
  final String? rejectReason;
  final List<String> flags;

  ToneAnalysis({
    required this.tone,
    required this.cis,
    required this.shouldReject,
    this.rejectReason,
    required this.flags,
  });

  factory ToneAnalysis.fromJson(Map<String, dynamic> json) {
    return ToneAnalysis(
      tone: ToneLabel.fromString(json['tone'] as String),
      cis: (json['cis'] as num).toDouble(),
      shouldReject: json['should_reject'] as bool,
      rejectReason: json['reject_reason'] as String?,
      flags: (json['flags'] as List<dynamic>).cast<String>(),
    );
  }
}

extension PostBeaconExtension on Post {
  bool get isBeaconPost => isBeacon == true && beaconType != null;

  dynamic get beaconColor => beaconType?.color;

  dynamic get beaconIcon => beaconType?.icon;

  Beacon toBeacon() {
    if (!isBeaconPost) {
      throw Exception('Cannot convert non-beacon Post to Beacon');
    }

    final status = confidenceScore != null
        ? BeaconStatus.fromConfidence(confidenceScore!)
        : BeaconStatus.yellow;

    return Beacon(
      id: id,
      body: body,
      authorId: authorId,
      beaconType: beaconType!,
      confidenceScore: confidenceScore ?? 0.5,
      isActiveBeacon: isActiveBeacon ?? true,
      status: status,
      createdAt: createdAt,
      distanceMeters: distanceMeters ?? 0,
      imageUrl: imageUrl,
      beaconLat: latitude,
      beaconLong: longitude,
      authorHandle: author?.handle,
      authorDisplayName: author?.displayName,
      authorAvatarUrl: author?.avatarUrl,
      vouchCount: vouchCount,
      reportCount: reportCount,
      userVote: myVote,
      groupId: groupId,
      severity: BeaconSeverity.fromString(severity ?? 'medium'),
      incidentStatus: BeaconIncidentStatus.fromString(incidentStatus ?? 'active'),
      radius: radius ?? 500,
      verificationCount: verificationCount ?? 0,
      isOfficial: isOfficial ?? false,
      officialSource: officialSource,
      streamUrl: videoUrl,
    );
  }
}

/// FocusContext represents the minimal data needed for the Focus-Context view
class FocusContext {
  final Post targetPost;
  final Post? parentPost;
  final List<Post> children;
  final List<Post> parentChildren;

  const FocusContext({
    required this.targetPost,
    this.parentPost,
    required this.children,
    this.parentChildren = const [],
  });

  factory FocusContext.fromJson(Map<String, dynamic> json) {
    return FocusContext(
      targetPost: Post.fromJson(json['target_post']),
      parentPost: json['parent_post'] != null ? Post.fromJson(json['parent_post']) : null,
      children: (json['children'] as List?)
          ?.map((child) => Post.fromJson(child))
          .toList() ?? [],
      parentChildren: (json['parent_children'] as List?)
          ?.map((child) => Post.fromJson(child))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'target_post': targetPost.toJson(),
      'parent_post': parentPost?.toJson(),
      'children': children.map((child) => child.toJson()).toList(),
      'parent_children': parentChildren.map((child) => child.toJson()).toList(),
    };
  }
}
