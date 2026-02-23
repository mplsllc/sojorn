// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'dashboard_widgets.dart';

enum ProfileWidgetType {
  pinnedPosts('Pinned Posts', Icons.push_pin),
  musicWidget('Music Player', Icons.music_note),
  photoGrid('Photo Grid', Icons.photo_library),
  socialLinks('Social Links', Icons.link),
  bio('Bio', Icons.person),
  stats('Stats', Icons.bar_chart),
  quote('Quote', Icons.format_quote),
  beaconActivity('Beacon Activity', Icons.location_on),
  customText('Custom Text', Icons.text_fields),
  featuredFriends('Featured Friends', Icons.people),
  featuredGroups('Featured Groups', Icons.groups);

  const ProfileWidgetType(this.displayName, this.icon);

  final String displayName;
  final IconData icon;

  static ProfileWidgetType fromString(String? value) {
    switch (value) {
      case 'pinnedPosts':
        return ProfileWidgetType.pinnedPosts;
      case 'musicWidget':
        return ProfileWidgetType.musicWidget;
      case 'photoGrid':
        return ProfileWidgetType.photoGrid;
      case 'socialLinks':
        return ProfileWidgetType.socialLinks;
      case 'bio':
        return ProfileWidgetType.bio;
      case 'stats':
        return ProfileWidgetType.stats;
      case 'quote':
        return ProfileWidgetType.quote;
      case 'beaconActivity':
        return ProfileWidgetType.beaconActivity;
      case 'customText':
        return ProfileWidgetType.customText;
      case 'featuredFriends':
        return ProfileWidgetType.featuredFriends;
      case 'featuredGroups':
        return ProfileWidgetType.featuredGroups;
      default:
        return ProfileWidgetType.bio;
    }
  }
}

class ProfileWidget {
  final String id;
  final ProfileWidgetType type;
  final Map<String, dynamic> config;
  final int order;
  final bool isEnabled;

  ProfileWidget({
    required this.id,
    required this.type,
    required this.config,
    required this.order,
    this.isEnabled = true,
  });

  factory ProfileWidget.fromJson(Map<String, dynamic> json) {
    return ProfileWidget(
      id: json['id'] ?? '',
      type: ProfileWidgetType.fromString(json['type']),
      config: Map<String, dynamic>.from(json['config'] ?? {}),
      order: json['order'] ?? 0,
      isEnabled: json['is_enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'config': config,
      'order': order,
      'is_enabled': isEnabled,
    };
  }

  ProfileWidget copyWith({
    String? id,
    ProfileWidgetType? type,
    Map<String, dynamic>? config,
    int? order,
    bool? isEnabled,
  }) {
    return ProfileWidget(
      id: id ?? this.id,
      type: type ?? this.type,
      config: config ?? this.config,
      order: order ?? this.order,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}

class ProfileLayout {
  final List<ProfileWidget> widgets;
  final String theme;
  final Color? accentColor;
  final String? bannerImageUrl;
  final DateTime updatedAt;
  final List<DashboardWidget> desktopLeftSidebar;
  final List<DashboardWidget> desktopRightSidebar;

  ProfileLayout({
    required this.widgets,
    this.theme = 'default',
    this.accentColor,
    this.bannerImageUrl,
    required this.updatedAt,
    List<DashboardWidget>? desktopLeftSidebar,
    List<DashboardWidget>? desktopRightSidebar,
  })  : desktopLeftSidebar = desktopLeftSidebar ?? _defaultLeftSidebar,
        desktopRightSidebar = desktopRightSidebar ?? _defaultRightSidebar;

  static final List<DashboardWidget> _defaultLeftSidebar = [
    DashboardWidget(type: DashboardWidgetType.top8Friends, order: 0),
    DashboardWidget(type: DashboardWidgetType.quote, order: 1),
  ];

  static final List<DashboardWidget> _defaultRightSidebar = [
    DashboardWidget(type: DashboardWidgetType.friendActivity, order: 0),
    DashboardWidget(type: DashboardWidgetType.upcomingEvents, order: 1),
  ];

  factory ProfileLayout.fromJson(Map<String, dynamic> json) {
    List<DashboardWidget> parseSidebar(dynamic raw) {
      if (raw is! List || raw.isEmpty) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map((w) => DashboardWidget.fromJson(w))
          .toList();
    }

    final left = parseSidebar(json['desktop_left_sidebar']);
    final right = parseSidebar(json['desktop_right_sidebar']);

    return ProfileLayout(
      widgets: (json['widgets'] as List<dynamic>?)
          ?.map((w) => ProfileWidget.fromJson(w as Map<String, dynamic>))
          .toList() ?? [],
      theme: json['theme'] ?? 'default',
      accentColor: json['accent_color'] != null
          ? Color(int.parse(json['accent_color'].replaceFirst('#', '0xFF')))
          : null,
      bannerImageUrl: json['banner_image_url'],
      updatedAt: DateTime.parse(json['updated_at']),
      desktopLeftSidebar: left.isEmpty ? null : left,
      desktopRightSidebar: right.isEmpty ? null : right,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'widgets': widgets.map((w) => w.toJson()).toList(),
      'theme': theme,
      'accent_color': accentColor != null ? '#${accentColor!.toARGB32().toRadixString(16).padLeft(8, '0')}' : null,
      'banner_image_url': bannerImageUrl,
      'updated_at': updatedAt.toIso8601String(),
      'desktop_left_sidebar': desktopLeftSidebar.map((w) => w.toJson()).toList(),
      'desktop_right_sidebar': desktopRightSidebar.map((w) => w.toJson()).toList(),
    };
  }

  ProfileLayout copyWith({
    List<ProfileWidget>? widgets,
    String? theme,
    Color? accentColor,
    String? bannerImageUrl,
    DateTime? updatedAt,
    List<DashboardWidget>? desktopLeftSidebar,
    List<DashboardWidget>? desktopRightSidebar,
  }) {
    return ProfileLayout(
      widgets: widgets ?? this.widgets,
      theme: theme ?? this.theme,
      accentColor: accentColor ?? this.accentColor,
      bannerImageUrl: bannerImageUrl ?? this.bannerImageUrl,
      updatedAt: updatedAt ?? this.updatedAt,
      desktopLeftSidebar: desktopLeftSidebar ?? this.desktopLeftSidebar,
      desktopRightSidebar: desktopRightSidebar ?? this.desktopRightSidebar,
    );
  }
}

class ProfileWidgetConstraints {
  static const double maxWidth = 400.0;
  static const double maxHeight = 300.0;
  static const double minSize = 100.0;
  static const double defaultSize = 200.0;

  static Size getWidgetSize(ProfileWidgetType type) {
    switch (type) {
      case ProfileWidgetType.pinnedPosts:
        return const Size(maxWidth, 150.0);
      case ProfileWidgetType.musicWidget:
        return const Size(maxWidth, 120.0);
      case ProfileWidgetType.photoGrid:
        return const Size(maxWidth, 200.0);
      case ProfileWidgetType.socialLinks:
        return const Size(maxWidth, 80.0);
      case ProfileWidgetType.bio:
        return const Size(maxWidth, 120.0);
      case ProfileWidgetType.stats:
        return const Size(maxWidth, 100.0);
      case ProfileWidgetType.quote:
        return const Size(maxWidth, 150.0);
      case ProfileWidgetType.beaconActivity:
        return const Size(maxWidth, 180.0);
      case ProfileWidgetType.customText:
        return const Size(maxWidth, 150.0);
      case ProfileWidgetType.featuredFriends:
        return const Size(maxWidth, 120.0);
      case ProfileWidgetType.featuredGroups:
        return const Size(maxWidth, 120.0);
    }
  }

  static bool isValidSize(Size size) {
    return size.width >= minSize && 
           size.width <= maxWidth && 
           size.height >= minSize && 
           size.height <= maxHeight;
  }
}

class ProfileTheme {
  final String name;
  final Color primaryColor;
  final Color backgroundColor;
  final Color textColor;
  final Color accentColor;
  final String fontFamily;

  const ProfileTheme({
    required this.name,
    required this.primaryColor,
    required this.backgroundColor,
    required this.textColor,
    required this.accentColor,
    required this.fontFamily,
  });

  static const List<ProfileTheme> availableThemes = [
    ProfileTheme(
      name: 'default',
      primaryColor: Colors.blue,
      backgroundColor: Colors.white,
      textColor: Colors.black87,
      accentColor: Colors.blueAccent,
      fontFamily: 'Roboto',
    ),
    ProfileTheme(
      name: 'dark',
      primaryColor: Colors.grey,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
      accentColor: Colors.blueAccent,
      fontFamily: 'Roboto',
    ),
    ProfileTheme(
      name: 'ocean',
      primaryColor: Colors.cyan,
      backgroundColor: Color(0xFFF0F8FF),
      textColor: Colors.black87,
      accentColor: Colors.teal,
      fontFamily: 'Roboto',
    ),
    ProfileTheme(
      name: 'sunset',
      primaryColor: Colors.orange,
      backgroundColor: Color(0xFFFFF3E0),
      textColor: Colors.black87,
      accentColor: Colors.deepOrange,
      fontFamily: 'Roboto',
    ),
    ProfileTheme(
      name: 'forest',
      primaryColor: Colors.green,
      backgroundColor: Color(0xFFF1F8E9),
      textColor: Colors.black87,
      accentColor: Colors.lightGreen,
      fontFamily: 'Roboto',
    ),
    ProfileTheme(
      name: 'royal',
      primaryColor: Colors.purple,
      backgroundColor: Color(0xFFF3E5F5),
      textColor: Colors.black87,
      accentColor: Colors.deepPurple,
      fontFamily: 'Roboto',
    ),
  ];

  static ProfileTheme getThemeByName(String name) {
    return availableThemes.firstWhere(
      (theme) => theme.name == name,
      orElse: () => availableThemes.first,
    );
  }
}
