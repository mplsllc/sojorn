// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';

enum BeaconCategory {
  safetyAlert('Safety Alert', Icons.warning_amber, Colors.red),
  communityNeed('Community Need', Icons.volunteer_activism, Colors.green),
  lostFound('Lost & Found', Icons.search, Colors.blue),
  event('Event', Icons.event, Colors.purple),
  mutualAid('Mutual Aid', Icons.handshake, Colors.orange);

  const BeaconCategory(this.displayName, this.icon, this.color);
  
  final String displayName;
  final IconData icon;
  final Color color;

  static BeaconCategory fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'safety_alert':
      case 'safety':
        return BeaconCategory.safetyAlert;
      case 'community_need':
      case 'community':
        return BeaconCategory.communityNeed;
      case 'lost_found':
      case 'lost':
        return BeaconCategory.lostFound;
      case 'event':
        return BeaconCategory.event;
      case 'mutual_aid':
      case 'mutual':
        return BeaconCategory.mutualAid;
      default:
        return BeaconCategory.safetyAlert;
    }
  }
}

enum BeaconStatus {
  active('Active', Colors.green),
  resolved('Resolved', Colors.grey),
  archived('Archived', Colors.grey);

  const BeaconStatus(this.displayName, this.color);
  
  final String displayName;
  final Color color;

  static BeaconStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'active':
        return BeaconStatus.active;
      case 'resolved':
        return BeaconStatus.resolved;
      case 'archived':
        return BeaconStatus.archived;
      default:
        return BeaconStatus.active;
    }
  }
}

class EnhancedBeacon {
  final String id;
  final String title;
  final String description;
  final BeaconCategory category;
  final BeaconStatus status;
  final double lat;
  final double lng;
  final String authorId;
  final String authorHandle;
  final String? authorAvatar;
  final bool isVerified;
  final bool isOfficialSource;
  final String? organizationName;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int vouchCount;
  final int reportCount;
  final double confidenceScore;
  final String? imageUrl;
  final List<String> actionItems;
  final String? neighborhood;
  final double? radiusMeters;

  EnhancedBeacon({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.status,
    required this.lat,
    required this.lng,
    required this.authorId,
    required this.authorHandle,
    this.authorAvatar,
    this.isVerified = false,
    this.isOfficialSource = false,
    this.organizationName,
    required this.createdAt,
    this.expiresAt,
    this.vouchCount = 0,
    this.reportCount = 0,
    this.confidenceScore = 0.0,
    this.imageUrl,
    this.actionItems = const [],
    this.neighborhood,
    this.radiusMeters,
  });

  factory EnhancedBeacon.fromJson(Map<String, dynamic> json) {
    return EnhancedBeacon(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['body'] ?? json['description'] ?? '',
      category: BeaconCategory.fromString(json['category']),
      status: BeaconStatus.fromString(json['status']),
      lat: (json['lat'] ?? json['beacon_lat'])?.toDouble() ?? 0.0,
      lng: (json['lng'] ?? json['beacon_long'])?.toDouble() ?? 0.0,
      authorId: json['author_id'] ?? '',
      authorHandle: json['author_handle'] ?? '',
      authorAvatar: json['author_avatar'],
      isVerified: json['is_verified'] ?? false,
      isOfficialSource: json['is_official_source'] ?? false,
      organizationName: json['organization_name'],
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      vouchCount: json['vouch_count'] ?? 0,
      reportCount: json['report_count'] ?? 0,
      confidenceScore: (json['confidence_score'] ?? 0.0).toDouble(),
      imageUrl: json['image_url'],
      actionItems: (json['action_items'] as List<dynamic>?)?.cast<String>() ?? [],
      neighborhood: json['neighborhood'],
      radiusMeters: json['radius_meters']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'category': category.name,
      'status': status.name,
      'lat': lat,
      'lng': lng,
      'author_id': authorId,
      'author_handle': authorHandle,
      'author_avatar': authorAvatar,
      'is_verified': isVerified,
      'is_official_source': isOfficialSource,
      'organization_name': organizationName,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'vouch_count': vouchCount,
      'report_count': reportCount,
      "confidence_score": confidenceScore,
      'image_url': imageUrl,
      'action_items': actionItems,
      'neighborhood': neighborhood,
      'radius_meters': radiusMeters,
    };
  }

  // Helper methods for UI
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  
  bool get isHighConfidence => confidenceScore >= 0.7;
  
  bool get isLowConfidence => confidenceScore < 0.3;
  
  String get confidenceLabel {
    if (isHighConfidence) return 'High Confidence';
    if (isLowConfidence) return 'Low Confidence';
    return 'Medium Confidence';
  }

  Color get confidenceColor {
    if (isHighConfidence) return Colors.green;
    if (isLowConfidence) return Colors.red;
    return Colors.orange;
  }

  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  bool get hasActionItems => actionItems.isNotEmpty;
}

class BeaconCluster {
  final List<EnhancedBeacon> beacons;
  final double lat;
  final double lng;
  final int count;

  BeaconCluster({
    required this.beacons,
    required this.lat,
    required this.lng,
  }) : count = beacons.length;

  // Get the most common category in the cluster
  BeaconCategory get dominantCategory {
    final categoryCount = <BeaconCategory, int>{};
    for (final beacon in beacons) {
      categoryCount[beacon.category] = (categoryCount[beacon.category] ?? 0) + 1;
    }
    
    BeaconCategory? dominant;
    int maxCount = 0;
    
    categoryCount.forEach((category, count) {
      if (count > maxCount) {
        maxCount = count;
        dominant = category;
      }
    });
    
    return dominant ?? BeaconCategory.safetyAlert;
  }

  // Check if cluster has any official sources
  bool get hasOfficialSource {
    return beacons.any((b) => b.isOfficialSource);
  }

  // Get highest priority beacon
  EnhancedBeacon get priorityBeacon {
    // Priority: Official > High Confidence > Most Recent
    final officialBeacons = beacons.where((b) => b.isOfficialSource).toList();
    if (officialBeacons.isNotEmpty) {
      return officialBeacons.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
    }
    
    final highConfidenceBeacons = beacons.where((b) => b.isHighConfidence).toList();
    if (highConfidenceBeacons.isNotEmpty) {
      return highConfidenceBeacons.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
    }
    
    return beacons.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
  }
}

class BeaconFilter {
  final Set<BeaconCategory> categories;
  final Set<BeaconStatus> statuses;
  final bool onlyOfficial;
  final double? radiusKm;
  final String? neighborhood;

  const BeaconFilter({
    this.categories = const {},
    this.statuses = const {},
    this.onlyOfficial = false,
    this.radiusKm,
    this.neighborhood,
  });

  BeaconFilter copyWith({
    Set<BeaconCategory>? categories,
    Set<BeaconStatus>? statuses,
    bool? onlyOfficial,
    double? radiusKm,
    String? neighborhood,
  }) {
    return BeaconFilter(
      categories: categories ?? this.categories,
      statuses: statuses ?? this.statuses,
      onlyOfficial: onlyOfficial ?? this.onlyOfficial,
      radiusKm: radiusKm ?? this.radiusKm,
      neighborhood: neighborhood ?? this.neighborhood,
    );
  }

  bool matches(EnhancedBeacon beacon) {
    // Category filter
    if (categories.isNotEmpty && !categories.contains(beacon.category)) {
      return false;
    }
    
    // Status filter
    if (statuses.isNotEmpty && !statuses.contains(beacon.status)) {
      return false;
    }
    
    // Official filter
    if (onlyOfficial && !beacon.isOfficialSource) {
      return false;
    }
    
    // Neighborhood filter
    if (neighborhood != null && beacon.neighborhood != neighborhood) {
      return false;
    }
    
    return true;
  }
}
