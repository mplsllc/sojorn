// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

class UserSettings {
  final String userId;
  final String theme;
  final String language;
  final bool notificationsEnabled;
  final bool emailNotifications;
  final bool pushNotifications;
  final String contentFilterLevel;
  final bool autoPlayVideos;
  final bool dataSaverMode;
  final int? defaultPostTtl;
  final bool nsfwEnabled;
  final bool nsfwBlurEnabled;

  const UserSettings({
    required this.userId,
    this.theme = 'system',
    this.language = 'en',
    this.notificationsEnabled = true,
    this.emailNotifications = true,
    this.pushNotifications = true,
    this.contentFilterLevel = 'medium',
    this.autoPlayVideos = true,
    this.dataSaverMode = false,
    this.defaultPostTtl,
    this.nsfwEnabled = false,
    this.nsfwBlurEnabled = true,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      userId: json['user_id'] as String,
      theme: json['theme'] as String? ?? 'system',
      language: json['language'] as String? ?? 'en',
      notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      emailNotifications: json['email_notifications'] as bool? ?? true,
      pushNotifications: json['push_notifications'] as bool? ?? true,
      contentFilterLevel: json['content_filter_level'] as String? ?? 'medium',
      autoPlayVideos: json['auto_play_videos'] as bool? ?? true,
      dataSaverMode: json['data_saver_mode'] as bool? ?? false,
      defaultPostTtl: _parseIntervalHours(json['default_post_ttl']),
      nsfwEnabled: json['nsfw_enabled'] as bool? ?? false,
      nsfwBlurEnabled: json['nsfw_blur_enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'theme': theme,
      'language': language,
      'notifications_enabled': notificationsEnabled,
      'email_notifications': emailNotifications,
      'push_notifications': pushNotifications,
      'content_filter_level': contentFilterLevel,
      'auto_play_videos': autoPlayVideos,
      'data_saver_mode': dataSaverMode,
      'default_post_ttl': defaultPostTtl,
      'nsfw_enabled': nsfwEnabled,
      'nsfw_blur_enabled': nsfwBlurEnabled,
    };
  }

  UserSettings copyWith({
    String? theme,
    String? language,
    bool? notificationsEnabled,
    bool? emailNotifications,
    bool? pushNotifications,
    String? contentFilterLevel,
    bool? autoPlayVideos,
    bool? dataSaverMode,
    int? defaultPostTtl,
    bool? nsfwEnabled,
    bool? nsfwBlurEnabled,
  }) {
    return UserSettings(
      userId: userId,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      pushNotifications: pushNotifications ?? this.pushNotifications,
      contentFilterLevel: contentFilterLevel ?? this.contentFilterLevel,
      autoPlayVideos: autoPlayVideos ?? this.autoPlayVideos,
      dataSaverMode: dataSaverMode ?? this.dataSaverMode,
      defaultPostTtl: defaultPostTtl ?? this.defaultPostTtl,
      nsfwEnabled: nsfwEnabled ?? this.nsfwEnabled,
      nsfwBlurEnabled: nsfwBlurEnabled ?? this.nsfwBlurEnabled,
    );
  }

  static int? _parseIntervalHours(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;

      final dayMatch = RegExp(r'(\d+)\s+day').firstMatch(trimmed);
      final hourMatch = RegExp(r'(\d+)\s+hour').firstMatch(trimmed);
      final timeMatch = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})').firstMatch(trimmed);

      var totalHours = 0;
      if (dayMatch != null) {
        totalHours += (int.tryParse(dayMatch.group(1) ?? '') ?? 0) * 24;
      }
      if (timeMatch != null) {
        totalHours += int.tryParse(timeMatch.group(1) ?? '') ?? 0;
      } else if (hourMatch != null) {
        totalHours += int.tryParse(hourMatch.group(1) ?? '') ?? 0;
      }

      return totalHours == 0 ? null : totalHours;
    }
    return null;
  }
}
