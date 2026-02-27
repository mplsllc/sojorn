// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

/// A single violation record issued against the current user.
class UserViolation {
  final String id;
  final String userId;
  final String violationType; // "hard_violation" / "soft_violation"
  final String violationReason;
  final double severityScore;
  final bool isAppealable;
  final DateTime? appealDeadline;
  final String status; // active/appealed/upheld/overturned/expired
  final bool contentDeleted;
  final String? accountStatusChange;
  final DateTime createdAt;
  final String? flagReason;
  final String? postContent;
  final String? commentContent;
  final bool canAppeal;
  final UserAppeal? appeal;

  UserViolation({
    required this.id,
    required this.userId,
    required this.violationType,
    required this.violationReason,
    required this.severityScore,
    required this.isAppealable,
    this.appealDeadline,
    required this.status,
    required this.contentDeleted,
    this.accountStatusChange,
    required this.createdAt,
    this.flagReason,
    this.postContent,
    this.commentContent,
    required this.canAppeal,
    this.appeal,
  });

  factory UserViolation.fromJson(Map<String, dynamic> json) {
    return UserViolation(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      violationType: json['violation_type'] as String? ?? '',
      violationReason: json['violation_reason'] as String? ?? '',
      severityScore: (json['severity_score'] as num?)?.toDouble() ?? 0.0,
      isAppealable: json['is_appealable'] as bool? ?? false,
      appealDeadline: json['appeal_deadline'] != null
          ? DateTime.parse(json['appeal_deadline'] as String)
          : null,
      status: json['status'] as String? ?? 'active',
      contentDeleted: json['content_deleted'] as bool? ?? false,
      accountStatusChange: json['account_status_change'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      flagReason: json['flag_reason'] as String?,
      postContent: json['post_content'] as String?,
      commentContent: json['comment_content'] as String?,
      canAppeal: json['can_appeal'] as bool? ?? false,
      appeal: json['appeal'] != null
          ? UserAppeal.fromJson(json['appeal'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'violation_type': violationType,
      'violation_reason': violationReason,
      'severity_score': severityScore,
      'is_appealable': isAppealable,
      'appeal_deadline': appealDeadline?.toIso8601String(),
      'status': status,
      'content_deleted': contentDeleted,
      'account_status_change': accountStatusChange,
      'created_at': createdAt.toIso8601String(),
      'flag_reason': flagReason,
      'post_content': postContent,
      'comment_content': commentContent,
      'can_appeal': canAppeal,
      if (appeal != null) 'appeal': appeal!.toJson(),
    };
  }
}

/// An appeal submitted by the user against a violation.
class UserAppeal {
  final String id;
  final String userViolationId;
  final String appealReason;
  final String? appealContext;
  final List<String> evidenceUrls;
  final String status; // pending/reviewing/approved/rejected/withdrawn
  final String? reviewDecision;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  UserAppeal({
    required this.id,
    required this.userViolationId,
    required this.appealReason,
    this.appealContext,
    required this.evidenceUrls,
    required this.status,
    this.reviewDecision,
    this.reviewedAt,
    required this.createdAt,
  });

  factory UserAppeal.fromJson(Map<String, dynamic> json) {
    return UserAppeal(
      id: json['id'] as String? ?? '',
      userViolationId: json['user_violation_id'] as String? ?? '',
      appealReason: json['appeal_reason'] as String? ?? '',
      appealContext: json['appeal_context'] as String?,
      evidenceUrls: (json['evidence_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: json['status'] as String? ?? 'pending',
      reviewDecision: json['review_decision'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_violation_id': userViolationId,
      'appeal_reason': appealReason,
      'appeal_context': appealContext,
      'evidence_urls': evidenceUrls,
      'status': status,
      'review_decision': reviewDecision,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Summary of a user's violation history and current standing.
class ViolationSummary {
  final int totalViolations;
  final int hardViolations;
  final int softViolations;
  final int activeAppeals;
  final String currentStatus;
  final DateTime? banExpiry;
  final List<UserViolation> recentViolations;

  ViolationSummary({
    required this.totalViolations,
    required this.hardViolations,
    required this.softViolations,
    required this.activeAppeals,
    required this.currentStatus,
    this.banExpiry,
    required this.recentViolations,
  });

  factory ViolationSummary.fromJson(Map<String, dynamic> json) {
    return ViolationSummary(
      totalViolations: (json['total_violations'] as num?)?.toInt() ?? 0,
      hardViolations: (json['hard_violations'] as num?)?.toInt() ?? 0,
      softViolations: (json['soft_violations'] as num?)?.toInt() ?? 0,
      activeAppeals: (json['active_appeals'] as num?)?.toInt() ?? 0,
      currentStatus: json['current_status'] as String? ?? 'good_standing',
      banExpiry: json['ban_expiry'] != null
          ? DateTime.parse(json['ban_expiry'] as String)
          : null,
      recentViolations: (json['recent_violations'] as List<dynamic>?)
              ?.map((e) =>
                  UserViolation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_violations': totalViolations,
      'hard_violations': hardViolations,
      'soft_violations': softViolations,
      'active_appeals': activeAppeals,
      'current_status': currentStatus,
      'ban_expiry': banExpiry?.toIso8601String(),
      'recent_violations':
          recentViolations.map((v) => v.toJson()).toList(),
    };
  }
}
