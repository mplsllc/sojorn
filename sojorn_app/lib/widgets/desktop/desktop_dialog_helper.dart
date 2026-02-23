// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../theme/tokens.dart';

/// Opens [child] as a centered dialog on desktop (≥900px) or a full-screen
/// push on mobile/tablet.
///
/// Use for detail views, user lists, and read-focused content.
void openDesktopDialog(
  BuildContext context, {
  required Widget child,
  double width = 700,
  double? maxHeight,
  bool barrierDismissible = true,
}) {
  final isDesktop = MediaQuery.of(context).size.width >= 900;
  if (isDesktop) {
    showDialog(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black38,
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SojornRadii.modal),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: maxHeight ?? MediaQuery.of(context).size.height - 80,
          ),
          child: child,
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => child),
    );
  }
}
