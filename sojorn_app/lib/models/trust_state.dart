import 'trust_tier.dart';

/// Trust state model matching backend trust_state table
class TrustState {
  final String userId;
  final int harmonyScore;
  final TrustTier tier;
  final int postsToday;
  final DateTime? lastPostAt;
  final DateTime? lastHarmonyCalcAt;

  TrustState({
    required this.userId,
    required this.harmonyScore,
    required this.tier,
    required this.postsToday,
    this.lastPostAt,
    this.lastHarmonyCalcAt,
  });

  factory TrustState.fromJson(Map<String, dynamic> json) {
    final tierValue = json['tier'] as String? ?? TrustTier.new_user.value;
    final harmonyScoreValue =
        (json['harmony_score'] as num?)?.toInt() ?? 0;
    final postsTodayValue = (json['posts_today'] as num?)?.toInt() ?? 0;

    return TrustState(
      // FIX: Use 'as String?' and provide a default empty string if null
      userId: json['user_id'] as String? ?? '', 
      harmonyScore: harmonyScoreValue,
      tier: TrustTier.fromString(tierValue),
      postsToday: postsTodayValue,
      lastPostAt: json['last_post_at'] != null
          ? DateTime.parse(json['last_post_at'] as String)
          : null,
      lastHarmonyCalcAt: json['last_harmony_calc_at'] != null
          ? DateTime.parse(json['last_harmony_calc_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'harmony_score': harmonyScore,
      'tier': tier.value,
      'posts_today': postsToday,
      'last_post_at': lastPostAt?.toIso8601String(),
      'last_harmony_calc_at': lastHarmonyCalcAt?.toIso8601String(),
    };
  }

  bool canPost() {
    return postsToday < tier.postLimit;
  }

  int get remainingPosts {
    return tier.postLimit - postsToday;
  }
}
