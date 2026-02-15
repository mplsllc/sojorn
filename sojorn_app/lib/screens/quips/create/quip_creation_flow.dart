import 'package:flutter/material.dart';
import 'quip_recorder_screen.dart';

/// Entry point wrapper for the Quip Creation Flow.
/// Navigation is now handled linearly starting from [QuipRecorderScreen].
class QuipCreationFlow extends StatelessWidget {
  const QuipCreationFlow({super.key});

  @override
  Widget build(BuildContext context) {
    return const QuipRecorderScreen();
  }
}
