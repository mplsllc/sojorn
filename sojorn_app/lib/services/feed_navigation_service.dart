// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../models/post.dart';
import '../screens/post/threaded_conversation_screen.dart';
import '../screens/quips/feed/quips_feed_screen.dart';

/// Navigation service for opening different feeds based on post type
class FeedNavigationService {
  static void openQuipsFeed(BuildContext context, Post post) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => QuipsFeedScreen(
          initialPostId: post.id,
        ),
      ),
    );
  }

  static void openThreadedConversation(BuildContext context, String postId) {
    // Navigate to threaded conversation for regular posts
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => ThreadedConversationScreen(
          rootPostId: postId,
        ),
      ),
    );
  }
}

