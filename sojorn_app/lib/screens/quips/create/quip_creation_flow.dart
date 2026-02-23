// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

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
