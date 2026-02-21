// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:convert';
import 'package:flutter/material.dart';

enum GroupCategory {
  general('general', 'General', Icons.grid_view, Color(0xFF607D8B)),
  hobby('hobby', 'Hobby', Icons.palette, Color(0xFF9C27B0)),
  sports('sports', 'Sports', Icons.sports, Color(0xFF4CAF50)),
  professional('professional', 'Professional', Icons.business_center, Color(0xFF2196F3)),
  localBusiness('local_business', 'Local Business', Icons.storefront, Color(0xFFFF9800)),
  support('support', 'Support', Icons.favorite, Color(0xFFE91E63)),
  education('education', 'Education', Icons.school, Color(0xFF3F51B5));

  final String value;
  final String displayName;
  final IconData icon;
  final Color color;
  const GroupCategory(this.value, this.displayName, this.icon, this.color);

  static GroupCategory fromString(String s) {
    return GroupCategory.values.firstWhere((c) => c.value == s, orElse: () => GroupCategory.general);
  }
}

/// Represents a Sojorn Cluster — either a public geo-cluster or a private capsule.
class Cluster {
  final String id;
  final String name;
  final String description;
  final String type; // 'geo', 'public_geo', 'private_capsule'
  final String privacy;
  final double? lat;
  final double? lng;
  final int radiusMeters;
  final String? avatarUrl;
  final int memberCount;
  final bool isEncrypted;
  final ClusterSettings settings;
  final GroupCategory category;
  final int keyVersion;
  final DateTime createdAt;
  final bool isMember;

  Cluster({
    required this.id,
    required this.name,
    this.description = '',
    required this.type,
    this.privacy = 'public',
    this.lat,
    this.lng,
    this.radiusMeters = 5000,
    this.avatarUrl,
    this.memberCount = 0,
    this.isEncrypted = false,
    this.settings = const ClusterSettings(),
    this.category = GroupCategory.general,
    this.keyVersion = 1,
    required this.createdAt,
    this.isMember = true,
  });

  bool get isPublic => type == 'geo' || type == 'public_geo';
  bool get isCapsule => type == 'private_capsule' && isEncrypted;

  factory Cluster.fromJson(Map<String, dynamic> json) {
    ClusterSettings settings = const ClusterSettings();
    if (json['settings'] != null) {
      final raw = json['settings'];
      if (raw is String) {
        settings = ClusterSettings.fromJson(jsonDecode(raw));
      } else if (raw is Map<String, dynamic>) {
        settings = ClusterSettings.fromJson(raw);
      }
    }

    return Cluster(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'geo',
      privacy: json['privacy'] as String? ?? 'public',
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['long'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble(),
      radiusMeters: json['radius_meters'] as int? ?? 5000,
      avatarUrl: json['avatar_url'] as String?,
      memberCount: json['member_count'] as int? ?? 0,
      isEncrypted: json['is_encrypted'] as bool? ?? false,
      settings: settings,
      category: GroupCategory.fromString(json['category'] as String? ?? 'general'),
      keyVersion: json['key_version'] as int? ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String),
      isMember: json['is_member'] as bool? ?? true,
    );
  }
}

/// Feature flags for a cluster
class ClusterSettings {
  final bool chat;
  final bool forum;
  final bool files;

  const ClusterSettings({this.chat = true, this.forum = true, this.files = false});

  factory ClusterSettings.fromJson(Map<String, dynamic> json) => ClusterSettings(
    chat: json['chat'] as bool? ?? true,
    forum: json['forum'] as bool? ?? true,
    files: json['files'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {'chat': chat, 'forum': forum, 'files': files};
}

/// A decrypted capsule entry (after client-side decryption)
class DecryptedCapsuleEntry {
  final String id;
  final String groupId;
  final String authorId;
  final String authorHandle;
  final String authorDisplayName;
  final String authorAvatarUrl;
  final String dataType; // chat, forum_post, document, image
  final String? replyToId;
  final DateTime createdAt;

  // Decrypted content
  final String? title;
  final String? body;
  final String? imageUrl;

  DecryptedCapsuleEntry({
    required this.id,
    required this.groupId,
    required this.authorId,
    this.authorHandle = '',
    this.authorDisplayName = '',
    this.authorAvatarUrl = '',
    required this.dataType,
    this.replyToId,
    required this.createdAt,
    this.title,
    this.body,
    this.imageUrl,
  });
}
