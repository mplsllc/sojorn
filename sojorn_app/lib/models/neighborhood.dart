// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

/// Typed model for the user's detected or home neighborhood.
class NeighborhoodInfo {
  final String? groupId;
  final String name;
  final String? city;
  final double? lat;
  final double? lng;
  final bool onboarded;
  final bool canChange;
  final String? nextChangeAllowedAt;

  const NeighborhoodInfo({
    this.groupId,
    this.name = '',
    this.city,
    this.lat,
    this.lng,
    this.onboarded = false,
    this.canChange = true,
    this.nextChangeAllowedAt,
  });

  String get displayName {
    if (name.isEmpty) return 'Commons';
    return (city != null && city!.isNotEmpty) ? '$name, $city' : name;
  }

  /// Parse the API response from /neighborhoods/mine or /neighborhoods/detect.
  factory NeighborhoodInfo.fromJson(Map<String, dynamic> json) {
    final hood = json['neighborhood'] as Map<String, dynamic>?;
    return NeighborhoodInfo(
      groupId: hood?['group_id'] as String? ?? json['group_id'] as String?,
      name: hood?['name'] as String? ?? json['name'] as String? ?? '',
      city: hood?['city'] as String? ?? json['city'] as String?,
      lat: (hood?['lat'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble(),
      lng: (hood?['lng'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble(),
      onboarded: json['onboarded'] as bool? ?? false,
      canChange: json['can_change'] as bool? ?? true,
      nextChangeAllowedAt: json['next_change_allowed_at'] as String?,
    );
  }
}
