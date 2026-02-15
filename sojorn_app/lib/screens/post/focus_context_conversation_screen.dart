import 'package:flutter/material.dart';
import '../../models/post.dart';
import 'threaded_conversation_screen.dart';

/// Legacy alias for the Dynamic Block thread view.
class FocusContextConversationScreen extends StatelessWidget {
  final String postId;
  final Post? initialPost;

  const FocusContextConversationScreen({
    super.key,
    required this.postId,
    this.initialPost,
  });

  @override
  Widget build(BuildContext context) {
    return ThreadedConversationScreen(
      rootPostId: postId,
      rootPost: initialPost,
    );
  }
}
