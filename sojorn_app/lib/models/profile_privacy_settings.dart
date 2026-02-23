// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

class ProfilePrivacySettings {
  String userId;
  String profileVisibility;
  String postsVisibility;
  String savedVisibility;
  String followRequestPolicy;
  String defaultVisibility;
  bool isPrivate;
  bool allowChains;
  String whoCanMessage;
  String whoCanComment;
  bool showActivityStatus;
  bool showInSearch;
  bool showInSuggestions;

  ProfilePrivacySettings({
    this.userId = '',
    this.profileVisibility = 'public',
    this.postsVisibility = 'public',
    this.savedVisibility = 'private',
    this.followRequestPolicy = 'everyone',
    this.defaultVisibility = 'public',
    this.isPrivate = false,
    this.allowChains = true,
    this.whoCanMessage = 'everyone',
    this.whoCanComment = 'everyone',
    this.showActivityStatus = true,
    this.showInSearch = true,
    this.showInSuggestions = true,
  });

  factory ProfilePrivacySettings.fromJson(Map<String, dynamic> json) {
    return ProfilePrivacySettings(
      userId: json['user_id'] as String? ?? '',
      profileVisibility: json['profile_visibility'] as String? ?? 'public',
      postsVisibility: json['posts_visibility'] as String? ?? 'public',
      savedVisibility: json['saved_visibility'] as String? ?? 'private',
      followRequestPolicy: json['follow_request_policy'] as String? ?? 'everyone',
      defaultVisibility: json['default_post_visibility'] as String? ?? 
                         json['default_visibility'] as String? ?? 'public',
      isPrivate: json['is_private_profile'] as bool? ?? 
                 json['is_private'] as bool? ?? false,
      allowChains: json['allow_chains'] as bool? ?? true,
      whoCanMessage: json['who_can_message'] as String? ?? 'everyone',
      whoCanComment: json['who_can_comment'] as String? ?? 'everyone',
      showActivityStatus: json['show_activity_status'] as bool? ?? true,
      showInSearch: json['show_in_search'] as bool? ?? true,
      showInSuggestions: json['show_in_suggestions'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'profile_visibility': profileVisibility,
      'posts_visibility': postsVisibility,
      'saved_visibility': savedVisibility,
      'follow_request_policy': followRequestPolicy,
      'default_post_visibility': defaultVisibility,
      'is_private_profile': isPrivate,
      'allow_chains': allowChains,
      'who_can_message': whoCanMessage,
      'who_can_comment': whoCanComment,
      'show_activity_status': showActivityStatus,
      'show_in_search': showInSearch,
      'show_in_suggestions': showInSuggestions,
    };
  }

  ProfilePrivacySettings copyWith({
    String? profileVisibility,
    String? postsVisibility,
    String? savedVisibility,
    String? followRequestPolicy,
    String? defaultVisibility,
    bool? isPrivate,
    bool? allowChains,
    String? whoCanMessage,
    String? whoCanComment,
    bool? showActivityStatus,
    bool? showInSearch,
    bool? showInSuggestions,
  }) {
    return ProfilePrivacySettings(
      userId: userId,
      profileVisibility: profileVisibility ?? this.profileVisibility,
      postsVisibility: postsVisibility ?? this.postsVisibility,
      savedVisibility: savedVisibility ?? this.savedVisibility,
      followRequestPolicy: followRequestPolicy ?? this.followRequestPolicy,
      defaultVisibility: defaultVisibility ?? this.defaultVisibility,
      isPrivate: isPrivate ?? this.isPrivate,
      allowChains: allowChains ?? this.allowChains,
      whoCanMessage: whoCanMessage ?? this.whoCanMessage,
      whoCanComment: whoCanComment ?? this.whoCanComment,
      showActivityStatus: showActivityStatus ?? this.showActivityStatus,
      showInSearch: showInSearch ?? this.showInSearch,
      showInSuggestions: showInSuggestions ?? this.showInSuggestions,
    );
  }

  static ProfilePrivacySettings defaults(String userId) {
    return ProfilePrivacySettings(
      userId: userId,
      profileVisibility: 'public',
      postsVisibility: 'public',
      savedVisibility: 'private',
      followRequestPolicy: 'everyone',
      defaultVisibility: 'public',
      isPrivate: false,
      allowChains: true,
      whoCanMessage: 'everyone',
      whoCanComment: 'everyone',
      showActivityStatus: true,
      showInSearch: true,
      showInSuggestions: true,
    );
  }

  // Legacy getters for backwards compatibility
  String get defaultPostVisibility => defaultVisibility;
  bool get isPrivateProfile => isPrivate;
}
