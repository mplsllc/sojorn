// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:equatable/equatable.dart';
import 'cluster.dart' show GroupCategory;
export 'cluster.dart' show GroupCategory;

enum GroupRole {
  owner('Owner'),
  admin('Admin'),
  moderator('Moderator'),
  member('Member');

  const GroupRole(this.displayName);
  final String displayName;

  static GroupRole fromString(String value) {
    return GroupRole.values.firstWhere(
      (role) => role.name.toLowerCase() == value.toLowerCase(),
      orElse: () => GroupRole.member,
    );
  }
}

enum JoinRequestStatus {
  pending('Pending'),
  approved('Approved'),
  rejected('Rejected');

  const JoinRequestStatus(this.displayName);
  final String displayName;

  static JoinRequestStatus fromString(String value) {
    return JoinRequestStatus.values.firstWhere(
      (status) => status.name.toLowerCase() == value.toLowerCase(),
      orElse: () => JoinRequestStatus.pending,
    );
  }
}

class Group extends Equatable {
  final String id;
  final String name;
  final String description;
  final GroupCategory category;
  final String? avatarUrl;
  final String? bannerUrl;
  final bool isPrivate;
  final String createdBy;
  final int memberCount;
  final int postCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final GroupRole? userRole;
  final bool isMember;
  final bool hasPendingRequest;

  const Group({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.avatarUrl,
    this.bannerUrl,
    required this.isPrivate,
    required this.createdBy,
    required this.memberCount,
    required this.postCount,
    required this.createdAt,
    required this.updatedAt,
    this.userRole,
    this.isMember = false,
    this.hasPendingRequest = false,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      category: GroupCategory.fromString(json['category'] as String),
      avatarUrl: json['avatar_url'] as String?,
      bannerUrl: json['banner_url'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      createdBy: json['created_by'] as String,
      memberCount: json['member_count'] as int? ?? 0,
      postCount: json['post_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      userRole: json['user_role'] != null 
          ? GroupRole.fromString(json['user_role'] as String)
          : null,
      isMember: json['is_member'] as bool? ?? false,
      hasPendingRequest: json['has_pending_request'] as bool? ?? false,
    );
  }

  Group copyWith({
    String? id,
    String? name,
    String? description,
    GroupCategory? category,
    String? avatarUrl,
    String? bannerUrl,
    bool? isPrivate,
    String? createdBy,
    int? memberCount,
    int? postCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    GroupRole? userRole,
    bool? isMember,
    bool? hasPendingRequest,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      isPrivate: isPrivate ?? this.isPrivate,
      createdBy: createdBy ?? this.createdBy,
      memberCount: memberCount ?? this.memberCount,
      postCount: postCount ?? this.postCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userRole: userRole ?? this.userRole,
      isMember: isMember ?? this.isMember,
      hasPendingRequest: hasPendingRequest ?? this.hasPendingRequest,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        category,
        avatarUrl,
        bannerUrl,
        isPrivate,
        createdBy,
        memberCount,
        postCount,
        createdAt,
        updatedAt,
        userRole,
        isMember,
        hasPendingRequest,
      ];

  String get memberCountText {
    if (memberCount >= 1000000) {
      return '${(memberCount / 1000000).toStringAsFixed(1)}M members';
    } else if (memberCount >= 1000) {
      return '${(memberCount / 1000).toStringAsFixed(1)}K members';
    }
    return '$memberCount members';
  }

  String get postCountText {
    if (postCount >= 1000) {
      return '${(postCount / 1000).toStringAsFixed(1)}K posts';
    }
    return '$postCount posts';
  }
}

class GroupMember extends Equatable {
  final String id;
  final String groupId;
  final String userId;
  final GroupRole role;
  final DateTime joinedAt;
  final String? username;
  final String? avatarUrl;

  const GroupMember({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.username,
    this.avatarUrl,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      role: GroupRole.fromString(json['role'] as String),
      joinedAt: DateTime.parse(json['joined_at'] as String),
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        userId,
        role,
        joinedAt,
        username,
        avatarUrl,
      ];
}

class JoinRequest extends Equatable {
  final String id;
  final String groupId;
  final String userId;
  final JoinRequestStatus status;
  final String? message;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? username;
  final String? avatarUrl;

  const JoinRequest({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.status,
    this.message,
    required this.createdAt,
    this.reviewedAt,
    this.reviewedBy,
    this.username,
    this.avatarUrl,
  });

  factory JoinRequest.fromJson(Map<String, dynamic> json) {
    return JoinRequest(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      userId: json['user_id'] as String,
      status: JoinRequestStatus.fromString(json['status'] as String),
      message: json['message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: json['reviewed_at'] != null 
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      reviewedBy: json['reviewed_by'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        groupId,
        userId,
        status,
        message,
        createdAt,
        reviewedAt,
        reviewedBy,
        username,
        avatarUrl,
      ];
}

class SuggestedGroup extends Equatable {
  final Group group;
  final String reason;

  const SuggestedGroup({
    required this.group,
    required this.reason,
  });

  factory SuggestedGroup.fromJson(Map<String, dynamic> json) {
    return SuggestedGroup(
      group: Group.fromJson(json),
      reason: json['reason'] as String? ?? 'Suggested for you',
    );
  }

  @override
  List<Object?> get props => [group, reason];
}
