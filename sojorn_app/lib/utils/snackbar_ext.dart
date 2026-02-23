// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/desktop/desktop_toast.dart';

/// BuildContext extension for quick, design-system-consistent snackbars.
///
/// On desktop (>= 900px), routes to [DesktopToast] slide-in cards.
/// On mobile, uses standard [ScaffoldMessenger] snackbars.
///
/// Usage:
/// ```dart
/// context.showSuccess('Saved!');
/// context.showError('Something went wrong.');
/// context.showInfo('Loading…');
/// ```
extension SnackbarExt on BuildContext {
  bool get _isDesktop => MediaQuery.of(this).size.width >= 900;

  void showSuccess(String message, {Duration duration = const Duration(seconds: 3)}) {
    if (_isDesktop) {
      DesktopToast.success(this, message);
      return;
    }
    ScaffoldMessenger.of(this).showSnackBar(
      _buildSnackBar(
        message: message,
        backgroundColor: AppTheme.success,
        icon: Icons.check_circle,
        duration: duration,
      ),
    );
  }

  void showError(String message, {Duration duration = const Duration(seconds: 4)}) {
    if (_isDesktop) {
      DesktopToast.error(this, message);
      return;
    }
    ScaffoldMessenger.of(this).showSnackBar(
      _buildSnackBar(
        message: message,
        backgroundColor: AppTheme.error,
        icon: Icons.cancel,
        duration: duration,
      ),
    );
  }

  void showInfo(String message, {Duration duration = const Duration(seconds: 3)}) {
    if (_isDesktop) {
      DesktopToast.info(this, message);
      return;
    }
    ScaffoldMessenger.of(this).showSnackBar(
      _buildSnackBar(
        message: message,
        backgroundColor: AppTheme.info,
        icon: Icons.info,
        duration: duration,
      ),
    );
  }

  void showWarning(String message, {Duration duration = const Duration(seconds: 3)}) {
    if (_isDesktop) {
      DesktopToast.show(this, message: message, icon: Icons.warning, color: AppTheme.warning, duration: duration);
      return;
    }
    ScaffoldMessenger.of(this).showSnackBar(
      _buildSnackBar(
        message: message,
        backgroundColor: AppTheme.warning,
        icon: Icons.warning,
        duration: duration,
      ),
    );
  }
}

SnackBar _buildSnackBar({
  required String message,
  required Color backgroundColor,
  required IconData icon,
  required Duration duration,
}) {
  return SnackBar(
    content: Row(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      ],
    ),
    backgroundColor: backgroundColor,
    duration: duration,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    margin: const EdgeInsets.all(16),
  );
}
