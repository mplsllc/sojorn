// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_scaffold.dart';
import 'threaded_conversation_screen.dart';
import '../compose/compose_screen.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  final Post post;

  const PostDetailScreen({
    super.key,
    required this.post,
  });

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return ThreadedConversationScreen(
      rootPostId: widget.post.id,
      rootPost: widget.post,
    );
  }
}
