import 'package:flutter/material.dart';
import '../models/post.dart';
import '../theme/tokens.dart';
import '../screens/post/threaded_conversation_screen.dart';

/// Navigation service for opening different feeds based on post type
class FeedNavigationService {
  static void openQuipsFeed(BuildContext context, Post post) {
    // Navigate to Quips feed with the specific video
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => QuipsFeedScreen(
          initialPostId: post.id,
          initialVideoUrl: post.videoUrl,
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

/// Placeholder for QuipsFeedScreen (would be implemented separately)
class QuipsFeedScreen extends StatelessWidget {
  final String? initialPostId;
  final String? initialVideoUrl;

  const QuipsFeedScreen({
    super.key,
    this.initialPostId,
    this.initialVideoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SojornColors.basicBlack,
      appBar: AppBar(
        backgroundColor: SojornColors.basicBlack,
        title: const Text('Quips'),
      ),
      body: Center(
        child: Text(
          'Quips Feed\n(Initial Post: $initialPostId)',
          style: const TextStyle(color: SojornColors.basicWhite),
        ),
      ),
    );
  }
}
