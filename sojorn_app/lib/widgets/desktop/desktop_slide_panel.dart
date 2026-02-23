// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';

/// Opens [child] as a right-side slide panel on desktop (≥900px) or a
/// full-screen push on mobile/tablet.
///
/// Use for forms, settings, and creation flows.
void openDesktopSlidePanel(
  BuildContext context, {
  required Widget child,
  double width = 480,
  bool useRootNavigator = true,
}) {
  final isDesktop = MediaQuery.of(context).size.width >= 900;
  if (isDesktop) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black26,
      barrierLabel: 'Close',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final slide =
            CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(slide),
            child: Material(
              elevation: 16,
              child: SafeArea(
                child: SizedBox(
                  width: width,
                  height: double.infinity,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  } else {
    Navigator.of(context, rootNavigator: useRootNavigator).push(
      MaterialPageRoute(builder: (_) => child),
    );
  }
}
