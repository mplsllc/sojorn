/// Sponsored Post model for First-Party Contextual Ads
/// Matches the sponsored_posts table schema
class SponsoredPost {
  final String id;
  final DateTime createdAt;
  final String advertiserName;
  final String body;
  final String? imageUrl;
  final String ctaLink;
  final String ctaText;
  final List<String> targetCategories;
  final bool active;
  final int impressionGoal;
  final int currentImpressions;

  SponsoredPost({
    required this.id,
    required this.createdAt,
    required this.advertiserName,
    required this.body,
    this.imageUrl,
    required this.ctaLink,
    this.ctaText = 'Learn More',
    required this.targetCategories,
    this.active = true,
    this.impressionGoal = 1000,
    this.currentImpressions = 0,
  });

  factory SponsoredPost.fromJson(Map<String, dynamic> json) {
    return SponsoredPost(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      advertiserName: json['advertiser_name'] as String,
      body: json['body'] as String,
      imageUrl: json['image_url'] as String?,
      ctaLink: json['cta_link'] as String,
      ctaText: json['cta_text'] as String? ?? 'Learn More',
      targetCategories: _parseCategories(json['target_categories']),
      active: json['active'] as bool? ?? true,
      impressionGoal: json['impression_goal'] as int? ?? 1000,
      currentImpressions: json['current_impressions'] as int? ?? 0,
    );
  }

  static List<String> _parseCategories(dynamic value) {
    if (value == null) return [];
    if (value is List<dynamic>) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String) {
      // Handle Postgres array string format: {cat1,cat2}
      return value
          .replaceAll('{', '')
          .replaceAll('}', '')
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Check if this ad matches a given category
  bool matchesCategory(String categoryId) {
    return targetCategories.contains('*') || targetCategories.contains(categoryId);
  }

  /// Check if the ad has reached its impression goal
  bool get hasReachedGoal => currentImpressions >= impressionGoal;

  /// Get remaining impressions until goal
  int get remainingImpressions {
    final remaining = impressionGoal - currentImpressions;
    return remaining < 0 ? 0 : remaining;
  }

  /// Get impression progress as a percentage (0.0 to 1.0)
  double get impressionProgress {
    if (impressionGoal == 0) return 0.0;
    return (currentImpressions / impressionGoal).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'advertiser_name': advertiserName,
      'body': body,
      'image_url': imageUrl,
      'cta_link': ctaLink,
      'cta_text': ctaText,
      'target_categories': targetCategories,
      'active': active,
      'impression_goal': impressionGoal,
      'current_impressions': currentImpressions,
    };
  }
}
