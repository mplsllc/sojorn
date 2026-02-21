// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import '../models/post.dart';

/// Tree node for building threaded conversation structure
class ThreadNode {
  final Post post;
  final List<ThreadNode> children;
  int depth;
  ThreadNode? parent;

  ThreadNode({
    required this.post,
    required this.children,
    required this.depth,
    this.parent,
  });

  /// Build tree structure from flat list of posts
  static ThreadNode buildTree(List<Post> posts) {
    if (posts.isEmpty) {
      throw ArgumentError('Posts list cannot be empty');
    }

    // Create a map of posts by ID for quick lookup
    final postMap = <String, ThreadNode>{};
    
    // Create nodes for all posts
    for (final post in posts) {
      postMap[post.id] = ThreadNode(
        post: post,
        children: [],
        depth: 0, // Will be calculated later
      );
    }

    // Build the tree structure
    ThreadNode? root;
    
    for (final post in posts) {
      final node = postMap[post.id]!;
      
      if (post.chainParentId == null || post.chainParentId!.isEmpty) {
        // This is the root post
        root = node;
        node.depth = 0;
      } else {
        // This is a reply - find its parent
        final parent = postMap[post.chainParentId];
        if (parent != null) {
          parent.children.add(node);
          node.parent = parent;
          node.depth = parent.depth + 1;
        } else {
          // Orphan post - treat as root
          if (root == null) {
            root = node;
            node.depth = 0;
          }
        }
      }
    }

    // Sort children by creation time
    for (final node in postMap.values) {
      node.children.sort((a, b) => a.post.createdAt.compareTo(b.post.createdAt));
    }

    return root ?? postMap.values.first;
  }

  /// Check if this node has any children
  bool get hasChildren => children.isNotEmpty;

  /// Get total number of posts in this subtree
  int get totalCount {
    int count = 1; // Count this post
    for (final child in children) {
      count += child.totalCount;
    }
    return count;
  }

  /// Get total number of descendants (excluding this post)
  int get totalDescendants => totalCount - 1;

  /// Get all posts in this subtree as a flat list (in order)
  List<Post> get allPosts {
    final posts = <Post>[post];
    for (final child in children) {
      posts.addAll(child.allPosts);
    }
    return posts;
  }
}
