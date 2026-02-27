// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

/// A report previously submitted by the current user.
class UserReport {
  final String id;
  final String? targetHandle;
  final String? postId;
  final String? commentId;
  final String? groupName;
  final String? neighborhoodName;
  final String violationType;
  final String description;
  final String status; // pending/reviewed/actioned/dismissed
  final DateTime createdAt;

  UserReport({
    required this.id,
    this.targetHandle,
    this.postId,
    this.commentId,
    this.groupName,
    this.neighborhoodName,
    required this.violationType,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  factory UserReport.fromJson(Map<String, dynamic> json) {
    return UserReport(
      id: json['id'] as String? ?? '',
      targetHandle: json['target_handle'] as String?,
      postId: json['post_id'] as String?,
      commentId: json['comment_id'] as String?,
      groupName: json['group_name'] as String?,
      neighborhoodName: json['neighborhood_name'] as String?,
      violationType: json['violation_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'target_handle': targetHandle,
      'post_id': postId,
      'comment_id': commentId,
      'group_name': groupName,
      'neighborhood_name': neighborhoodName,
      'violation_type': violationType,
      'description': description,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
