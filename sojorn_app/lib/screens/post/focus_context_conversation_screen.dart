// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

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
