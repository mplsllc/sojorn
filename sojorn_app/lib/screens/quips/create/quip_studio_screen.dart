import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../compose/video_editor_screen.dart'; // Import the existing editor
/// The "Pro Studio" Stage.
/// Uses the robust sojornVideoEditor which provides trimming and encoding.
class QuipStudioScreen extends ConsumerStatefulWidget {
  final File videoFile;

  const QuipStudioScreen({
    super.key,
    required this.videoFile,
  });

  @override
  ConsumerState<QuipStudioScreen> createState() => _QuipStudioScreenState();
}

class _QuipStudioScreenState extends ConsumerState<QuipStudioScreen> {
  
  @override
  Widget build(BuildContext context) {
    // We use the existing highly functional editor.
    // Ensure sojornVideoEditor returns a SojornMediaResult, which QuipPreviewScreen handles.
    return sojornVideoEditor(
      videoPath: widget.videoFile.path,
    );
  }
}
