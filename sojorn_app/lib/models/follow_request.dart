// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

class FollowRequest {
  final String followerId;
  final String handle;
  final String displayName;
  final String? avatarUrl;
  final DateTime? requestedAt;

  const FollowRequest({
    required this.followerId,
    required this.handle,
    required this.displayName,
    this.avatarUrl,
    this.requestedAt,
  });

  factory FollowRequest.fromJson(Map<String, dynamic> json) {
    final requestedAtValue = json['requested_at'] as String?;
    return FollowRequest(
      followerId: json['follower_id'] as String? ?? '',
      handle: json['handle'] as String? ?? 'unknown',
      displayName: json['display_name'] as String? ?? 'Anonymous',
      avatarUrl: json['avatar_url'] as String?,
      requestedAt: requestedAtValue != null
          ? DateTime.parse(requestedAtValue)
          : null,
    );
  }
}
