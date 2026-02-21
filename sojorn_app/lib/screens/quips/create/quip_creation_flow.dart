// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

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
