// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'profile.dart';

/// Comment status enum
enum CommentStatus {
  active('active'),
  flagged('flagged'),
  removed('removed');

  final String value;
  const CommentStatus(this.value);

  static CommentStatus fromString(String value) {
    return CommentStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => CommentStatus.active,
    );
  }
}

/// Comment model matching backend comments table
class Comment {
  final String id;
  final String postId;
  final String authorId;
  final String body;
  final CommentStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Relations
  final Profile? author;
  final int? voteCount;

  Comment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.body,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.author,
    this.voteCount,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      authorId: json['author_id'] as String,
      body: json['body'] as String,
      status: CommentStatus.fromString(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      author: json['author'] != null
          ? Profile.fromJson(json['author'] as Map<String, dynamic>)
          : null,
      voteCount: json['vote_count'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'post_id': postId,
      'author_id': authorId,
      'body': body,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'author': author?.toJson(),
      'vote_count': voteCount,
    };
  }
}
