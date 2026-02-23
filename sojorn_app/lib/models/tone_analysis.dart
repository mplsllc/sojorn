// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

/// Represents the tone analysis result from the AI moderation system.
///
/// The tone analysis uses intent-based detection rather than simple
/// keyword matching. This allows for authentic expression while
/// rejecting harmful content.
///
/// Note: This is used for real-time tone checking before posting.
/// See [ToneAnalysis] in post.dart for the stored post analysis.
class ToneCheckResult {
  /// Whether content is flagged by moderation
  final bool flagged;

  /// The flagged category when present
  final ModerationCategory? category;

  /// List of flags detected in the content
  final List<String> flags;

  /// User-facing explanation of the analysis
  final String reason;

  ToneCheckResult({
    required this.flagged,
    required this.category,
    required this.flags,
    required this.reason,
  });

  factory ToneCheckResult.fromJson(Map<String, dynamic> json) {
    return ToneCheckResult(
      flagged: json['flagged'] == true,
      category: ModerationCategory.fromString(json['category'] as String?),
      flags: (json['flags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      reason: json['reason'] ?? 'Analysis complete',
    );
  }

  /// Whether this content should be allowed
  bool get isAllowed {
    return !flagged;
  }

  String get categoryLabel {
    switch (category) {
      case ModerationCategory.bigotry:
        return 'Bigotry';
      case ModerationCategory.nsfw:
        return 'NSFW';
      case ModerationCategory.violence:
        return 'Violence';
      case null:
        return 'Sensitive';
    }
  }
}

/// Possible moderation categories for content analysis
enum ModerationCategory {
  bigotry,
  nsfw,
  violence;

  static ModerationCategory? fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'bigotry':
        return ModerationCategory.bigotry;
      case 'nsfw':
        return ModerationCategory.nsfw;
      case 'violence':
        return ModerationCategory.violence;
      default:
        return null;
    }
  }
}

/// Error thrown when tone analysis fails
class ToneCheckException implements Exception {
  final String message;
  final bool allowFallback;

  ToneCheckException(this.message, {this.allowFallback = true});

  @override
  String toString() => 'ToneCheckException: $message';
}
