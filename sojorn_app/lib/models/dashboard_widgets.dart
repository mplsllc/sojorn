// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';

/// All widget types available on the dashboard home page.
enum DashboardWidgetType {
  profileCard('profile_card', 'Profile Card', Icons.person),
  top8Friends('top8_friends', 'Top 8 Friends', Icons.people),
  upcomingEvents('upcoming_events', 'Upcoming Shows', Icons.event),
  whosOnline('whos_online', "Who's Online", Icons.circle),
  nowPlaying('now_playing', 'Now Playing', Icons.music_note),
  pinnedPost('pinned_post', 'Pinned Post', Icons.push_pin),
  friendActivity('friend_activity', 'Friend Activity', Icons.rss_feed),
  groupEvents('group_events', 'Group Events', Icons.calendar_month),
  quote('quote', 'Quote', Icons.format_quote),
  customText('custom_text', 'Custom Text', Icons.text_fields),
  photoFrame('photo_frame', 'Photo Frame', Icons.photo),
  musicPlayer('music_player', 'Music Player', Icons.headphones);

  const DashboardWidgetType(this.value, this.displayName, this.icon);
  final String value;
  final String displayName;
  final IconData icon;

  static DashboardWidgetType fromString(String value) {
    return DashboardWidgetType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => DashboardWidgetType.customText,
    );
  }
}

/// A single widget entry in a dashboard layout slot.
class DashboardWidget {
  final String? id;
  final DashboardWidgetType type;
  final Map<String, dynamic> config;
  final int order;
  final bool isEnabled;

  const DashboardWidget({
    this.id,
    required this.type,
    this.config = const {},
    required this.order,
    this.isEnabled = true,
  });

  factory DashboardWidget.fromJson(Map<String, dynamic> json) {
    return DashboardWidget(
      id: json['id'] as String?,
      type: DashboardWidgetType.fromString(json['type'] as String? ?? 'custom_text'),
      config: (json['config'] as Map<String, dynamic>?) ?? {},
      order: json['order'] as int? ?? 0,
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'type': type.value,
        'config': config,
        'order': order,
        'is_enabled': isEnabled,
      };

  DashboardWidget copyWith({
    int? order,
    bool? isEnabled,
    Map<String, dynamic>? config,
  }) {
    return DashboardWidget(
      id: id,
      type: type,
      config: config ?? this.config,
      order: order ?? this.order,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

/// Full dashboard layout with three slots.
class DashboardLayout {
  final List<DashboardWidget> leftSidebar;
  final List<DashboardWidget> rightSidebar;
  final List<DashboardWidget> feedTopbar;
  final DateTime? updatedAt;

  const DashboardLayout({
    this.leftSidebar = const [],
    this.rightSidebar = const [],
    this.feedTopbar = const [],
    this.updatedAt,
  });

  factory DashboardLayout.fromJson(Map<String, dynamic> json) {
    return DashboardLayout(
      leftSidebar: _parseWidgetList(json['left_sidebar']),
      rightSidebar: _parseWidgetList(json['right_sidebar']),
      feedTopbar: _parseWidgetList(json['feed_topbar']),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'left_sidebar': leftSidebar.map((w) => w.toJson()).toList(),
        'right_sidebar': rightSidebar.map((w) => w.toJson()).toList(),
        'feed_topbar': feedTopbar.map((w) => w.toJson()).toList(),
      };

  static List<DashboardWidget> _parseWidgetList(dynamic data) {
    if (data == null) return [];
    if (data is! List) return [];
    return data
        .whereType<Map<String, dynamic>>()
        .map((w) => DashboardWidget.fromJson(w))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  /// Default layout matching the server default.
  static const DashboardLayout defaultLayout = DashboardLayout(
    leftSidebar: [
      DashboardWidget(type: DashboardWidgetType.profileCard, order: 0),
      DashboardWidget(type: DashboardWidgetType.top8Friends, order: 1),
    ],
    rightSidebar: [
      DashboardWidget(type: DashboardWidgetType.upcomingEvents, order: 0),
      DashboardWidget(type: DashboardWidgetType.whosOnline, order: 1),
    ],
  );
}
