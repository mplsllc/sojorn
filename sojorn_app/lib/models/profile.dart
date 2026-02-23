// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'trust_state.dart';
import 'trust_tier.dart';

/// User profile model matching backend profiles table
class Profile {
  final String id;
  final String handle;
  final String displayName;
  final String? bio;
  final bool isOfficial;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final TrustState? trustState;
  final String? location;
  final String? website;
  final List<String>? interests;
  final String? avatarUrl;
  final String? coverUrl;
  final String? originCountry;
  final String? identityKey;
  final int? registrationId;
  final String? encryptedPrivateKey;
  final bool hasCompletedOnboarding;
  final int birthMonth;
  final int birthYear;
  /// AIM-style presence line: "at the coffee shop", "working from home", etc.
  /// Null = no status. Max 80 chars enforced server-side.
  final String? statusText;
  final DateTime? statusUpdatedAt;
  /// Mastodon-style key-value metadata fields (max 8).
  /// Each entry: {"key": "Pronouns", "value": "they/them", "verified": false}
  final List<ProfileMetadataField> metadataFields;

  Profile({
    required this.id,
    required this.handle,
    required this.displayName,
    this.bio,
    this.isOfficial = false,
    this.isPrivate = false,
    required this.createdAt,
    this.updatedAt,
    this.trustState,
    this.location,
    this.website,
    this.interests,
    this.avatarUrl,
    this.coverUrl,
    this.originCountry,
    this.identityKey,
    this.registrationId,
    this.encryptedPrivateKey,
    this.hasCompletedOnboarding = false,
    this.birthMonth = 0,
    this.birthYear = 0,
    this.statusText,
    this.statusUpdatedAt,
    this.metadataFields = const [],
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    final createdAtValue = json['created_at'] as String?;
    final updatedAtValue = json['updated_at'] as String?;

    // Parse interests array
    List<String>? interests;
    if (json['interests'] != null) {
      final interestsJson = json['interests'];
      if (interestsJson is List) {
        interests = interestsJson.map((e) => e.toString()).toList();
      }
    }

    return Profile(
      id: json['id'] as String? ?? '',
      handle: json['handle'] as String? ?? 'unknown',
      displayName: json['display_name'] as String? ?? 'Anonymous',
      bio: json['bio'] as String?,
      isOfficial: json['is_official'] as bool? ?? false,
      isPrivate: json['is_private'] as bool? ?? false,
      createdAt: createdAtValue != null
          ? DateTime.parse(createdAtValue)
          : DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAtValue != null ? DateTime.parse(updatedAtValue) : null,
      // Full trust_state object (own profile API) → parse as-is.
      // Flat trust_tier string (author embedded in post/feed) → synthesise a
      // minimal TrustState so the Harmony badge can render without a full fetch.
      trustState: json['trust_state'] != null
          ? TrustState.fromJson(json['trust_state'] as Map<String, dynamic>)
          : json['trust_tier'] != null
              ? TrustState(
                  userId: json['id'] as String? ?? '',
                  tier: TrustTier.fromString(json['trust_tier'] as String),
                  harmonyScore: 0,
                  postsToday: 0,
                )
              : null,
      location: json['location'] as String?,
      website: json['website'] as String?,
      interests: interests,
      avatarUrl: json['avatar_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      originCountry: json['origin_country'] as String?,
      identityKey: json['identity_key'] as String?,
      registrationId: json['registration_id'] as int?,
      encryptedPrivateKey: json['encrypted_private_key'] as String?,
      hasCompletedOnboarding: json['has_completed_onboarding'] as bool? ?? false,
      birthMonth: json['birth_month'] as int? ?? 0,
      birthYear: json['birth_year'] as int? ?? 0,
      statusText: json['status_text'] as String?,
      statusUpdatedAt: json['status_updated_at'] != null
          ? DateTime.tryParse(json['status_updated_at'] as String)
          : null,
      metadataFields: (json['metadata_fields'] as List?)
          ?.map((e) => ProfileMetadataField.fromJson(e as Map<String, dynamic>))
          .toList() ?? const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'handle': handle,
      'display_name': displayName,
      'bio': bio,
      'is_official': isOfficial,
      'is_private': isPrivate,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'trust_state': trustState?.toJson(),
      'location': location,
      'website': website,
      'interests': interests,
      'avatar_url': avatarUrl,
      'cover_url': coverUrl,
      'origin_country': originCountry,
      'identity_key': identityKey,
      'registration_id': registrationId,
      'encrypted_private_key': encryptedPrivateKey,
      'has_completed_onboarding': hasCompletedOnboarding,
      'birth_month': birthMonth,
      'birth_year': birthYear,
      if (statusText != null) 'status_text': statusText,
      if (statusUpdatedAt != null) 'status_updated_at': statusUpdatedAt!.toIso8601String(),
    };
  }

  Profile copyWith({
    String? id,
    String? handle,
    String? displayName,
    String? bio,
    DateTime? createdAt,
    DateTime? updatedAt,
    TrustState? trustState,
    String? location,
    String? website,
    List<String>? interests,
    String? avatarUrl,
    String? coverUrl,
    String? originCountry,
    String? identityKey,
    int? registrationId,
    String? encryptedPrivateKey,
    bool? isPrivate,
    bool? isOfficial,
    bool? hasCompletedOnboarding,
    int? birthMonth,
    int? birthYear,
    String? statusText,
    DateTime? statusUpdatedAt,
    List<ProfileMetadataField>? metadataFields,
  }) {
    return Profile(
      id: id ?? this.id,
      handle: handle ?? this.handle,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      isOfficial: isOfficial ?? this.isOfficial,
      isPrivate: isPrivate ?? this.isPrivate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trustState: trustState ?? this.trustState,
      location: location ?? this.location,
      website: website ?? this.website,
      interests: interests ?? this.interests,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      originCountry: originCountry ?? this.originCountry,
      identityKey: identityKey ?? this.identityKey,
      registrationId: registrationId ?? this.registrationId,
      encryptedPrivateKey: encryptedPrivateKey ?? this.encryptedPrivateKey,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      birthMonth: birthMonth ?? this.birthMonth,
      birthYear: birthYear ?? this.birthYear,
      statusText: statusText ?? this.statusText,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      metadataFields: metadataFields ?? this.metadataFields,
    );
  }
}

/// Mastodon-style key-value metadata field.
class ProfileMetadataField {
  final String key;
  final String value;
  final bool verified;

  const ProfileMetadataField({
    required this.key,
    required this.value,
    this.verified = false,
  });

  factory ProfileMetadataField.fromJson(Map<String, dynamic> json) {
    return ProfileMetadataField(
      key: json['key'] as String? ?? '',
      value: json['value'] as String? ?? '',
      verified: json['verified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'verified': verified,
  };
}

/// Profile stats (returned separately from profile API)
class ProfileStats {
  final int posts;
  final int followers;
  final int following;

  ProfileStats({
    required this.posts,
    required this.followers,
    required this.following,
  });

  factory ProfileStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return ProfileStats(posts: 0, followers: 0, following: 0);
    }
    return ProfileStats(
      posts: (json['posts'] ?? json['post_count'] ?? 0) as int,
      followers: (json['followers'] ?? json['follower_count'] ?? 0) as int,
      following: (json['following'] ?? json['following_count'] ?? 0) as int,
    );
  }
}
