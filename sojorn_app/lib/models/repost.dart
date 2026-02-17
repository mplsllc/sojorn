import 'package:flutter/material.dart';

enum RepostType {
  standard('Repost', Icons.repeat),
  quote('Quote', Icons.format_quote),
  boost('Boost', Icons.rocket_launch),
  amplify('Amplify', Icons.trending_up);

  const RepostType(this.displayName, this.icon);
  
  final String displayName;
  final IconData icon;

  static RepostType fromString(String? value) {
    switch (value) {
      case 'standard':
        return RepostType.standard;
      case 'quote':
        return RepostType.quote;
      case 'boost':
        return RepostType.boost;
      case 'amplify':
        return RepostType.amplify;
      default:
        return RepostType.standard;
    }
  }
}

class Repost {
  final String id;
  final String originalPostId;
  final String authorId;
  final String authorHandle;
  final String? authorAvatar;
  final RepostType type;
  final String? comment;
  final DateTime createdAt;
  final int boostCount;
  final int amplificationScore;
  final bool isAmplified;
  final Map<String, dynamic>? metadata;

  Repost({
    required this.id,
    required this.originalPostId,
    required this.authorId,
    required this.authorHandle,
    this.authorAvatar,
    required this.type,
    this.comment,
    required this.createdAt,
    this.boostCount = 0,
    this.amplificationScore = 0,
    this.isAmplified = false,
    this.metadata,
  });

  factory Repost.fromJson(Map<String, dynamic> json) {
    return Repost(
      id: json['id'] ?? '',
      originalPostId: json['original_post_id'] ?? '',
      authorId: json['author_id'] ?? '',
      authorHandle: json['author_handle'] ?? '',
      authorAvatar: json['author_avatar'],
      type: RepostType.fromString(json['type']),
      comment: json['comment'],
      createdAt: DateTime.parse(json['created_at']),
      boostCount: json['boost_count'] ?? 0,
      amplificationScore: json['amplification_score'] ?? 0,
      isAmplified: json['is_amplified'] ?? false,
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'original_post_id': originalPostId,
      'author_id': authorId,
      'author_handle': authorHandle,
      'author_avatar': authorAvatar,
      'type': type.name,
      'comment': comment,
      'created_at': createdAt.toIso8601String(),
      'boost_count': boostCount,
      'amplification_score': amplificationScore,
      'is_amplified': isAmplified,
      'metadata': metadata,
    };
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
}

class AmplificationMetrics {
  final int totalReach;
  final int engagementCount;
  final double engagementRate;
  final int newFollowers;
  final int shares;
  final int comments;
  final int likes;
  final DateTime lastUpdated;

  AmplificationMetrics({
    required this.totalReach,
    required this.engagementCount,
    required this.engagementRate,
    required this.newFollowers,
    required this.shares,
    required this.comments,
    required this.likes,
    required this.lastUpdated,
  });

  factory AmplificationMetrics.fromJson(Map<String, dynamic> json) {
    return AmplificationMetrics(
      totalReach: json['total_reach'] ?? 0,
      engagementCount: json['engagement_count'] ?? 0,
      engagementRate: (json['engagement_rate'] ?? 0.0).toDouble(),
      newFollowers: json['new_followers'] ?? 0,
      shares: json['shares'] ?? 0,
      comments: json['comments'] ?? 0,
      likes: json['likes'] ?? 0,
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_reach': totalReach,
      'engagement_count': engagementCount,
      'engagement_rate': engagementRate,
      'new_followers': newFollowers,
      'shares': shares,
      'comments': comments,
      'likes': likes,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}

class FeedAmplificationRule {
  final String id;
  final String name;
  final String description;
  final RepostType type;
  final double weightMultiplier;
  final int minBoostScore;
  final int maxDailyBoosts;
  final bool isActive;
  final DateTime createdAt;

  FeedAmplificationRule({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.weightMultiplier,
    required this.minBoostScore,
    required this.maxDailyBoosts,
    required this.isActive,
    required this.createdAt,
  });

  factory FeedAmplificationRule.fromJson(Map<String, dynamic> json) {
    return FeedAmplificationRule(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      type: RepostType.fromString(json['type']),
      weightMultiplier: (json['weight_multiplier'] ?? 1.0).toDouble(),
      minBoostScore: json['min_boost_score'] ?? 0,
      maxDailyBoosts: json['max_daily_boosts'] ?? 5,
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'weight_multiplier': weightMultiplier,
      'min_boost_score': minBoostScore,
      'max_daily_boosts': maxDailyBoosts,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class AmplificationAnalytics {
  final String postId;
  final List<AmplificationMetrics> metrics;
  final List<Repost> reposts;
  final int totalAmplification;
  final double amplificationRate;
  final Map<RepostType, int> repostCounts;

  AmplificationAnalytics({
    required this.postId,
    required this.metrics,
    required this.reposts,
    required this.totalAmplification,
    required this.amplificationRate,
    required this.repostCounts,
  });

  factory AmplificationAnalytics.fromJson(Map<String, dynamic> json) {
    final repostCountsMap = <RepostType, int>{};
    final repostCountsJson = json['repost_counts'] as Map<String, dynamic>? ?? {};
    
    repostCountsJson.forEach((type, count) {
      final repostType = RepostType.fromString(type);
      repostCountsMap[repostType] = count as int;
    });

    return AmplificationAnalytics(
      postId: json['post_id'] ?? '',
      metrics: (json['metrics'] as List<dynamic>?)
          ?.map((m) => AmplificationMetrics.fromJson(m as Map<String, dynamic>))
          .toList() ?? [],
      reposts: (json['reposts'] as List<dynamic>?)
          ?.map((r) => Repost.fromJson(r as Map<String, dynamic>))
          .toList() ?? [],
      totalAmplification: json['total_amplification'] ?? 0,
      amplificationRate: (json['amplification_rate'] ?? 0.0).toDouble(),
      repostCounts: repostCountsMap,
    );
  }

  Map<String, dynamic> toJson() {
    final repostCountsJson = <String, int>{};
    repostCounts.forEach((type, count) {
      repostCountsJson[type.name] = count;
    });

    return {
      'post_id': postId,
      'metrics': metrics.map((m) => m.toJson()).toList(),
      'reposts': reposts.map((r) => r.toJson()).toList(),
      'total_amplification': totalAmplification,
      'amplification_rate': amplificationRate,
      'repost_counts': repostCountsJson,
    };
  }

  int get totalReposts => reposts.length;
  
  RepostType? get mostEffectiveType {
    if (repostCounts.isEmpty) return null;
    
    return repostCounts.entries.reduce((a, b) => 
      a.value > b.value ? a : b
    ).key;
  }

  double get averageEngagementRate {
    if (metrics.isEmpty) return 0.0;
    
    final totalRate = metrics.fold(0.0, (sum, metric) => sum + metric.engagementRate);
    return totalRate / metrics.length;
  }
}
