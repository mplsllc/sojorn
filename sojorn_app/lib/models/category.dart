// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

/// Category model matching backend categories table
class Category {
  final String id;
  final String slug;
  final String name;
  final String description;
  final bool defaultOff;
  final String? officialAccountId;
  final DateTime createdAt;

  Category({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.defaultOff,
    this.officialAccountId,
    required this.createdAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled',
      description: json['description'] as String? ?? '',
      defaultOff: (json['default_off'] as bool?) ?? (json['is_sensitive'] as bool?) ?? false,
      officialAccountId: json['official_account_id'] as String?,
      createdAt: json['created_at'] != null 
        ? DateTime.parse(json['created_at'] as String) 
        : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'name': name,
      'description': description,
      'default_off': defaultOff,
      'official_account_id': officialAccountId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// User category settings model
class UserCategorySetting {
  final String userId;
  final String categoryId;
  final bool enabled;

  UserCategorySetting({
    required this.userId,
    required this.categoryId,
    required this.enabled,
  });

  factory UserCategorySetting.fromJson(Map<String, dynamic> json) {
    return UserCategorySetting(
      userId: json['user_id'] as String,
      categoryId: json['category_id'] as String,
      enabled: json['enabled'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'category_id': categoryId,
      'enabled': enabled,
    };
  }
}
