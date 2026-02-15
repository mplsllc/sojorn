/// User search result with minimal info for display
class SearchUser {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String harmonyTier;

  SearchUser({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.harmonyTier = 'new',
  });

  factory SearchUser.fromJson(Map<String, dynamic> json) {
    return SearchUser(
      id: json['id'] as String? ?? '',
      username: (json['username'] as String?) ?? (json['handle'] as String?) ?? 'unknown',
      displayName: json['display_name'] as String? ?? json['displayName'] as String? ?? json['handle'] as String? ?? json['username'] as String? ?? 'Unknown',
      avatarUrl: json['avatar_url'] as String?,
      harmonyTier: json['harmony_tier'] as String? ?? json['harmonyTier'] as String? ?? 'new',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'harmony_tier': harmonyTier,
    };
  }
}

/// Hashtag search result with post count
class SearchTag {
  final String tag;
  final int count;

  SearchTag({
    required this.tag,
    required this.count,
  });

  factory SearchTag.fromJson(Map<String, dynamic> json) {
    return SearchTag(
      tag: json['tag'] as String,
      count: json['count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tag': tag,
      'count': count,
    };
  }

  String get withHash => '#$tag';
}

/// Post search result with minimal info for display
class SearchPost {
  final String id;
  final String body;
  final String authorId;
  final String authorHandle;
  final String authorDisplayName;
  final DateTime createdAt;

  SearchPost({
    required this.id,
    required this.body,
    required this.authorId,
    required this.authorHandle,
    required this.authorDisplayName,
    required this.createdAt,
  });

  factory SearchPost.fromJson(Map<String, dynamic> json) {
    // Handle both flat structure and nested author object structure
    final authorJson = json['author'] as Map<String, dynamic>?;

    return SearchPost(
      id: json['id'] as String,
      body: json['body'] as String,
      authorId: json['author_id'] as String? ?? authorJson?['id'] as String? ?? '',
      authorHandle: json['author_handle'] as String? ?? authorJson?['handle'] as String? ?? 'unknown',
      authorDisplayName: json['author_display_name'] as String? ?? authorJson?['display_name'] as String? ?? 'Unknown',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'body': body,
      'author_id': authorId,
      'author_handle': authorHandle,
      'author_display_name': authorDisplayName,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// Search results model for discovery search
/// Contains users, hashtags, and posts matching the query
class SearchResults {
  final List<SearchUser> users;
  final List<SearchTag> tags;
  final List<SearchPost> posts;

  SearchResults({
    required this.users,
    required this.tags,
    required this.posts,
  });

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    final usersJson = json['users'] as List<dynamic>? ?? [];
    final tagsJson = json['tags'] as List<dynamic>? ?? [];
    final postsJson = json['posts'] as List<dynamic>? ?? [];

    return SearchResults(
      users: usersJson
          .map((u) => SearchUser.fromJson(u as Map<String, dynamic>))
          .toList(),
      tags: tagsJson
          .map((t) => SearchTag.fromJson(t as Map<String, dynamic>))
          .toList(),
      posts: postsJson
          .map((p) => SearchPost.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'users': users.map((u) => u.toJson()).toList(),
      'tags': tags.map((t) => t.toJson()).toList(),
      'posts': posts.map((p) => p.toJson()).toList(),
    };
  }

  bool get isEmpty => users.isEmpty && tags.isEmpty && posts.isEmpty;
  bool get hasResults => users.isNotEmpty || tags.isNotEmpty || posts.isNotEmpty;
}

/// Recent search item (stored locally)
class RecentSearch {
  final String id;
  final String text;
  final DateTime searchedAt;
  final RecentSearchType type;

  RecentSearch({
    required this.id,
    required this.text,
    required this.searchedAt,
    required this.type,
  });

  factory RecentSearch.fromJson(Map<String, dynamic> json) {
    return RecentSearch(
      id: json['id'] as String,
      text: json['text'] as String,
      searchedAt: DateTime.parse(json['searched_at'] as String),
      type: RecentSearchType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RecentSearchType.text,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'searched_at': searchedAt.toIso8601String(),
      'type': type.name,
    };
  }
}

enum RecentSearchType {
  user,
  tag,
  text,
}
