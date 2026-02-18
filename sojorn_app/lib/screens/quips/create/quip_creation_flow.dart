import 'package:flutter/material.dart';
import 'quip_camera_screen.dart';

/// Entry point wrapper for the Quip Creation Flow.
/// Routes to [QuipCameraScreen] — the new Snapchat-style camera with
/// instant sticker/text decoration and zero encoding wait.
class QuipCreationFlow extends StatelessWidget {
  const QuipCreationFlow({super.key});

  @override
  Widget build(BuildContext context) {
    return const QuipCameraScreen();
  }
}
