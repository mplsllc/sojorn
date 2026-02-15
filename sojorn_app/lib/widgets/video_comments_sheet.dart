import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/post.dart';
import '../models/thread_node.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/traditional_quips_sheet.dart';

/// Traditional video comments sheet (TikTok/Reddit style)
class VideoCommentsSheet extends StatefulWidget {
  final String postId;
  final int initialCommentCount;
  final VoidCallback? onCommentPosted;

  const VideoCommentsSheet({
    super.key,
    required this.postId,
    this.initialCommentCount = 0,
    this.onCommentPosted,
  });

  @override
  State<VideoCommentsSheet> createState() => _VideoCommentsSheetState();
}

class _VideoCommentsSheetState extends State<VideoCommentsSheet> {
  @override
  Widget build(BuildContext context) {
    return TraditionalQuipsSheet(
      postId: widget.postId,
      initialQuipCount: widget.initialCommentCount,
      onQuipPosted: widget.onCommentPosted,
    );
  }
}
